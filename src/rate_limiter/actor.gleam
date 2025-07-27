//// The inner actor implementation of the RateLimiter. Use this module if you want to use
//// the rate limiter as part of a larger supervision tree.

import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision
import rate_limiter/limit

// FFI to get BEAMs monotonic time.
// We use microseconds because it's a small enough unit for common rate limiting tasks
// (like limiting https requests).
@external(erlang, "ffi", "get_micro_second")
fn get_micro_second() -> Int

// Based on the provided last time a request was made, credits a certain number of tokens
// to the Limit.
fn replenish_tokens(
  limit: limit.Limit,
  last_hit_micro_seconds: Int,
) -> limit.Limit {
  // Monotonic difference since last hit
  let diff_micro_seconds = get_micro_second() - last_hit_micro_seconds

  // Number of tokens to add according to the limit's ratio. Using microseconds here lets us use
  // simple integer division and get a good enough result without worrying about floating point math
  // or big decimals or something.
  let tokens_to_add = diff_micro_seconds / limit.micro_seconds_per_token

  // Make sure not to go over the burst limit. This keeps the available tokens
  // from growing forever.
  limit.Limit(
    ..limit,
    tokens: int.min(limit.tokens + tokens_to_add, limit.max_tokens),
  )
}

pub opaque type Msg {

  // Try to perform a request *immediately*.
  Hit(
    // Responds with either `Ok` or an `Error` containing a description of the limit that
    // was violated.
    reply_with: process.Subject(Result(Nil, String)),
  )

  // Ask how long until n requests can be made.
  // Get back a resposne in micro seconds. If the number is zero,
  // it means a request can be made now.
  Ask(reply_with: process.Subject(Int), n_requests: Int)
}

pub opaque type State {
  State(
    // The set of limits to enforce
    limits: List(limit.Limit),
    // The monotonic time for when the last hit occured in microseconds
    last_hit_micro_seconds: Int,
  )
}

fn new_state() -> State {
  State(limits: [], last_hit_micro_seconds: get_micro_second())
}

fn add_limits(state: State, limits: List(limit.Limit)) -> State {
  State(..state, limits: list.append(state.limits, limits))
}

fn refill_tokens(state: State) -> State {
  State(
    ..state,
    limits: list.map(state.limits, replenish_tokens(
      _,
      state.last_hit_micro_seconds,
    )),
  )
}

// Try to consume a token for a given limit.
fn try_consume_token(limit: limit.Limit) -> Result(limit.Limit, Nil) {
  case limit.tokens > 0 {
    // No tokens available to consume
    False -> Error(Nil)

    // There was a token available
    True -> Ok(limit.Limit(..limit, tokens: limit.tokens - 1))
  }
}

fn handle_msg(state: State, msg: Msg) -> actor.Next(State, Msg) {
  // Before handling any messages, we should use the last recorded hit 
  // time to refill the tokens for each limit
  let state = refill_tokens(state)

  case msg {
    Hit(reply_with:) -> {
      // Now for each limit, we simply check whether a request can be made.
      // If none of the limits trigger a rate limit, we get an updated set of limits
      // to reflect the fact we made a request (i.e. spent a token)
      let res =
        list.try_fold(state.limits, [], fn(updated_limits, limit) {
          case try_consume_token(limit) {
            // Could not consume a token, return an error with the limit
            // that caused the failure.
            Error(Nil) -> Error(limit)

            // Successfully consumed the token, add the updated limit to the 
            // list of limits
            Ok(limit) -> Ok([limit, ..updated_limits])
          }
        })

      case res {
        // Request denied
        Error(limit) -> {
          process.send(reply_with, Error(limit.description))
          actor.continue(state)
        }

        // Request accepted
        Ok(limits) -> {
          process.send(reply_with, Ok(Nil))
          actor.continue(State(..state, limits:))
        }
      }
    }
    Ask(reply_with:, n_requests:) -> {
      // Caluclate the max limit until a request can be made
      let wait =
        list.fold(state.limits, 0, fn(wait_remaining, limit) {
          let cost_of_limit = {
            // A certain number of requests can be made right away by spending existing tokens
            let not_free_requests = n_requests - limit.tokens

            // Each remaining request constitutes a full request, *except* the one for which we're already
            // partially through the waiting period.
            let partial_waiting_period =
              get_micro_second() - state.last_hit_micro_seconds

            case not_free_requests {
              // We have enough tokens to cover all the requests we want to make.
              0 -> 0

              // We're just missing one token, so we just return the partial limit
              1 -> partial_waiting_period

              // We're missing more than one token, so we need to wait the partial waiting period
              // *plus* the full waiting period for the rest of the tokens
              _ ->
                partial_waiting_period
                + { limit.micro_seconds_per_token * { not_free_requests - 1 } }
            }
          }

          int.max(wait_remaining, cost_of_limit)
        })
      process.send(reply_with, wait)
      actor.continue(state)
    }
  }
}

/// Start a new rate limiter actor.
pub fn start(
  limits: List(limit.Limit),
) -> Result(actor.Started(process.Subject(Msg)), actor.StartError) {
  new_state()
  |> add_limits(limits)
  |> actor.new
  |> actor.on_message(handle_msg)
  |> actor.start
}

/// Get a constructor for a rate limiter that can be used as part of a larger supervision tree.
pub fn supervised(
  limits: List(limit.Limit),
) -> supervision.ChildSpecification(process.Subject(Msg)) {
  supervision.worker(fn() { start(limits) })
}

/// This function allows the rate limiter *actor* to be used as a lazy guard.
/// Example:
/// ```gleam
/// use <- rate_limiter.lazy_guard(limiter_actor, fn(limit_description) {
///   // ... Construct the appropriate error. `limit_description` is a text description of the limit that was violated.
/// })
/// // ... Continue with the function
/// ```
pub fn lazy_guard(
  rate_limiter: actor.Started(process.Subject(Msg)),
  timeout_ms: Int,
  or_else: fn(String) -> a,
  do: fn() -> a,
) -> a {
  case process.call(rate_limiter.data, timeout_ms, Hit) {
    // The rate limiter says we can't make a request right now.
    Error(desc) -> or_else(desc)

    // The rate limiter says it's okay to make a request right now
    Ok(Nil) -> do()
  }
}

/// Ask the rate limiter how much time is left before you can make n requests.
/// The response is in *microseconds*.
pub fn ask(
  rate_limiter: actor.Started(process.Subject(Msg)),
  timeout_ms: Int,
  n_requests: Int,
) -> Int {
  process.call(rate_limiter.data, timeout_ms, Ask(_, n_requests:))
}

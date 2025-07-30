//// The inner actor implementation of the RateLimiter. Use this module if you want to use
//// the rate limiter as part of a larger supervision tree.

import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision

// FFI to get BEAMs monotonic time.
@external(erlang, "ffi", "nanosecond")
fn nanosecond() -> Int

const one_second_ns = 1_000_000_000

/// Represents the actual limit on the requests that can be made. We use a token bucket algorithm,
/// and a token refill rate defined in nanoseconds, which is small enough for this packages use cases.
pub type Limit {
  Limit(
    // We store the number of nanoseconds until we generate another token as an integer.
    ns_per_token: Int,
    // The number of action tokens available
    tokens: Int,
    // The max number to refill the tokens too. 
    burst: Int,
    // A description of the rate limit to return when the limit is hit.
    description: String,
  )
}

/// Check whether a limit has been properly configured.
fn is_valid(limit limit: Limit) -> Bool {
  limit.tokens > 0
  && limit.burst >= limit.tokens
  && limit.ns_per_token > 0
  && limit.description != ""
}

// Creates a `Limit` based on a number of hits per number of nanoseconds.
// This helper constructor is private because to be honest, the message loop
// of the actor won't execute quickly enough to be doing rate limiting this
// fine grained.
fn hits_per_ns(
  hits hits: Int,
  ns ns: Int,
  description description: String,
) -> Limit {
  // This will be our base unit for how quickly we replenish tokens.
  // Nanoseconds is small enough that in the event there is a remainder, we round up
  // by one nanosecond to ensure requests are under the limit.
  let ns_per_token = case ns % hits {
    0 -> ns / hits
    _ -> ns / hits + 1
  }

  Limit(
    ns_per_token:,
    description:,
    // We start with a full set of tokens available, and refill up to a max of 
    // the number of hits specified.
    tokens: hits,
    burst: hits,
  )
}

// Our public constructors for various rate limits

/// Creates a limit of `hits` number of requests per second.
pub fn hits_per_second(hits hits: Int) -> Limit {
  hits_per_ns(
    hits:,
    ns: one_second_ns,
    description: int.to_string(hits) <> " requests per second",
  )
}

/// Creates a limit of `hits` number of requests per `seconds` seconds.
pub fn hits_per_seconds(hits hits: Int, seconds secs: Int) -> Limit {
  hits_per_ns(
    hits:,
    ns: one_second_ns * secs,
    description: int.to_string(hits)
      <> " requests per "
      <> int.to_string(secs)
      <> " seconds",
  )
}

/// Creates a limit of `hits` number of requests per minute.
pub fn hits_per_minute(hits hits: Int) -> Limit {
  hits_per_ns(
    hits:,
    ns: one_second_ns * 60,
    description: int.to_string(hits) <> " requests per minute",
  )
}

/// Creates a limit of `hits` number of requests per `minutes` minutes.
pub fn hits_per_minutes(hits hits: Int, minutes mins: Int) -> Limit {
  hits_per_ns(
    hits:,
    ns: one_second_ns * 60 * mins,
    description: int.to_string(hits)
      <> " requests per "
      <> int.to_string(mins)
      <> " minutes",
  )
}

/// Creates a limit of `hits` number of requests per hour.
pub fn hits_per_hour(hits hits: Int) -> Limit {
  hits_per_ns(
    hits:,
    ns: one_second_ns * 60 * 60,
    description: int.to_string(hits) <> " requests per hour",
  )
}

/// Creates a limit of `hits` number of requests per `hours` hours.
pub fn hits_per_hours(hits hits: Int, hours hrs: Int) -> Limit {
  hits_per_ns(
    hits:,
    ns: one_second_ns * 60 * 60 * hrs,
    description: int.to_string(hits)
      <> " requests per "
      <> int.to_string(hrs)
      <> " hours",
  )
}

// Based on the provided last time a request was made, credits a certain number of tokens
// to the Limit.
fn replenish_tokens(
  limit limit: Limit,
  last_hit_ns last_hit_ns: Int,
  curr_time_ns curr_time_ns: Int,
) -> Limit {
  // Number of tokens to add according to the limit's ratio. 
  let tokens_to_add = { curr_time_ns - last_hit_ns } / limit.ns_per_token

  // Make sure not to go over the burst limit. This keeps the available tokens
  // from growing forever.
  Limit(..limit, tokens: int.min(limit.tokens + tokens_to_add, limit.burst))
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
    limits: List(Limit),
    // The monotonic time for when the last hit occured.
    last_hit_ns: Int,
  )
}

fn refill_tokens(state: State, curr_time_ns: Int) -> State {
  State(
    ..state,
    limits: list.map(state.limits, replenish_tokens(
      _,
      curr_time_ns:,
      last_hit_ns: state.last_hit_ns,
    )),
  )
}

// Try to consume a token for a given limit.
fn try_consume_token(limit: Limit) -> Result(Limit, Nil) {
  case limit.tokens > 0 {
    // No tokens available to consume
    False -> Error(Nil)

    // There was a token available
    True -> Ok(Limit(..limit, tokens: limit.tokens - 1))
  }
}

fn handle_msg(state: State, msg: Msg) -> actor.Next(State, Msg) {
  // We do 1 call to get the monotonic time per message.
  let curr_time_ns = nanosecond()

  // Before handling any messages, we should use the last recorded hit
  // time to refill the tokens for each limit
  let state = refill_tokens(state, curr_time_ns)

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
            let partial_waiting_period_ns = nanosecond() - state.last_hit_ns

            case not_free_requests {
              // We have enough tokens to cover all the requests we want to make.
              0 -> 0

              // We're just missing one token, so we just return the partial limit
              1 -> partial_waiting_period_ns

              // We're missing more than one token, so we need to wait the partial waiting period
              // *plus* the full waiting period for the rest of the tokens
              _ ->
                partial_waiting_period_ns
                + { limit.ns_per_token * { not_free_requests - 1 } }
            }
          }

          int.max(wait_remaining, cost_of_limit)
        })
      process.send(reply_with, wait)
      actor.continue(state)
    }
  }
}

pub type RateLimiter =
  actor.Started(process.Subject(Msg))

/// Start a new rate limiter actor.
pub fn start(
  limits: List(Limit),
) -> Result(actor.Started(process.Subject(Msg)), actor.StartError) {
  State(limits:, last_hit_ns: nanosecond())
  |> actor.new
  |> actor.on_message(handle_msg)
  |> actor.start
}

/// Get a constructor for a rate limiter that can be used as part of a larger supervision tree.
pub fn supervised(
  limits: List(Limit),
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
/// The response is in *nanoseconds*.
pub fn ask(
  rate_limiter: actor.Started(process.Subject(Msg)),
  timeout_ms: Int,
  n_requests: Int,
) -> Int {
  process.call(rate_limiter.data, timeout_ms, Ask(_, n_requests:))
}

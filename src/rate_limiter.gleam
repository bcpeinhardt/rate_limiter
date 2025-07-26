//// This package provides a rate limiter for requests. 

import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor

// FFI to get BEAMs monotonic time.
// We use microseconds because it's a small enough unit for common rate limiting tasks
// (like limiting https requests).
@external(erlang, "ffi", "get_micro_second")
fn get_micro_second() -> Int

// A limit is a number of hits per millisecond that are allowed.
pub opaque type Limit {
  Limit(
    // We store the number micro seconds until we generate another token as an integer.
    micro_seconds_per_token: Int,
    // The number of action tokens available
    tokens: Int,
    // The max number to refill the tokens too. 
    max_tokens: Int,
    // A description of the rate limit to return when the limit is hit.
    description: String,
  )
}

fn replenish_tokens(limit: Limit, last_hit_micro_seconds: Int) -> Limit {
  // Monotonic difference since last hit
  let diff_micro_seconds = get_micro_second() - last_hit_micro_seconds

  // Number of tokens to add according to the limit's ratio. Using microseconds here lets us use
  // simple integer division and get a good enough result without worrying about floating point math
  // or big decimals or something.
  let tokens_to_add = diff_micro_seconds / limit.micro_seconds_per_token

  // Make sure not to go over the burst limit. This keeps the available tokens
  // from growing forever.
  Limit(
    ..limit,
    tokens: int.min(limit.tokens + tokens_to_add, limit.max_tokens),
  )
}

// Creates a `Limit` based on a number of hits per number of microseconds.
fn hits_per_microseconds(
  hits hits: Int,
  microseconds microseconds: Int,
  description description: String,
) -> Limit {
  // This will be our base unit for how quickly we replenish tokens.
  // Micro seconds is a small enough unit for the tasks this library is intended
  // for that it's okay to truncate the partial microseconds, but to guarantee we aren't
  // allowing more traffic than asked for, we round up rather than down.
  let micro_seconds_per_token = case microseconds % hits {
    0 -> microseconds / hits
    _ -> microseconds / hits + 1
  }

  Limit(
    micro_seconds_per_token:,
    // We start with a full set of tokens available, and refill up to a max of 
    // the number of hits specified.
    tokens: hits,
    max_tokens: hits,
    description:,
  )
}

const one_second_micro_sec = 1_000_000

// Our public constructors for various rate limits

/// Creates a limit of `hits` number of requests per second.
pub fn per_second(hits hits: Int) -> Limit {
  hits_per_microseconds(
    hits:,
    microseconds: one_second_micro_sec,
    description: int.to_string(hits) <> " requests per second",
  )
}

/// Creates a limit of `hits` number of requests per `seconds` seconds.
pub fn per_seconds(hits hits: Int, seconds secs: Int) -> Limit {
  hits_per_microseconds(
    hits:,
    microseconds: one_second_micro_sec * secs,
    description: int.to_string(hits)
      <> " requests per "
      <> int.to_string(secs)
      <> " seconds",
  )
}

/// Creates a limit of `hits` number of requests per minute.
pub fn per_minute(hits hits: Int) -> Limit {
  hits_per_microseconds(
    hits:,
    microseconds: one_second_micro_sec * 60,
    description: int.to_string(hits) <> " requests per minute",
  )
}

/// Creates a limit of `hits` number of requests per `minutes` minutes.
pub fn per_minutes(hits hits: Int, minutes mins: Int) -> Limit {
  hits_per_microseconds(
    hits:,
    microseconds: one_second_micro_sec * 60 * mins,
    description: int.to_string(hits)
      <> " requests per "
      <> int.to_string(mins)
      <> " minutes",
  )
}

/// Creates a limit of `hits` number of requests per hour.
pub fn per_hour(hits hits: Int) -> Limit {
  hits_per_microseconds(
    hits:,
    microseconds: one_second_micro_sec * 60 * 60,
    description: int.to_string(hits) <> " requests per hour",
  )
}

/// Creates a limit of `hits` number of requests per `hours` hours.
pub fn per_hours(hits hits: Int, hours hrs: Int) -> Limit {
  hits_per_microseconds(
    hits:,
    microseconds: one_second_micro_sec * 60 * 60 * hrs,
    description: int.to_string(hits)
      <> " requests per "
      <> int.to_string(hrs)
      <> " hours",
  )
}

// The rate limiter actor

pub opaque type Msg {
  Hit(
    // Responds with either `Ok` or an `Error` containing a description of the limit that
    // was violated.
    reply_with: process.Subject(Result(Nil, String)),
  )
}

pub opaque type State {
  State(
    // The set of limits to enforce
    limits: List(Limit),
    // The monotonic time for when the last hit occured in microseconds
    last_hit_micro_seconds: Int,
  )
}

fn new_state() -> State {
  State(limits: [], last_hit_micro_seconds: get_micro_second())
}

fn add_limits(state: State, limits: List(Limit)) -> State {
  State(..state, limits: list.append(state.limits, limits))
}

fn handle_msg(state: State, msg: Msg) -> actor.Next(State, Msg) {
  // Before handling any messages, we should use the last recorded hit 
  // time to refill the tokens for each limit
  let state =
    State(
      ..state,
      limits: list.map(state.limits, replenish_tokens(
        _,
        state.last_hit_micro_seconds,
      )),
    )

  case msg {
    Hit(reply_with:) -> {
      // Now for each limit, we simply check whether a request can be made.
      // If none of the limits trigger a rate limit, we get an updated set of limits
      // to reflect the fact we made a request (i.e. spent a token)
      let res =
        list.try_fold(state.limits, [], fn(updated_limits, limit) {
          case limit.tokens {
            // No more tokens, so we can't make a request
            0 -> Error(limit)

            // There was a token available to spend, so keep going
            // and update the limit to reflect spending the token.
            x -> Ok([Limit(..limit, tokens: x - 1), ..updated_limits])
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
  }
}

pub type RateLimiter =
  actor.Started(process.Subject(Msg))

pub fn new_rate_limiter(
  limits: List(Limit),
) -> Result(RateLimiter, actor.StartError) {
  new_state()
  |> add_limits(limits)
  |> actor.new
  |> actor.on_message(handle_msg)
  |> actor.start
}

/// This function allows the rate limiter to be used as a lazy guard.
/// Example:
/// ```gleam
/// use <- rate_limiter.lazy_guard(limiter, fn() {
///   // Construct the appropriate error
/// })
/// 
/// // Continue with the function
/// ```
pub fn lazy_guard(
  rate_limiter: RateLimiter,
  or_else: fn(String) -> a,
  do: fn() -> a,
) -> a {
  case process.call(rate_limiter.data, 1000, Hit) {
    // The rate limiter says we can't make a request right now.
    Error(desc) -> or_else(desc)

    // The rate limiter says it's okay to make a request right now
    Ok(Nil) -> do()
  }
}

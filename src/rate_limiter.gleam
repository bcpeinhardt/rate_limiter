//// This package provides a rate limiter for requests. 

import gleam/erlang/process
import gleam/otp/actor
import gleam/result
import rate_limiter/actor as rate_limiter_actor
import rate_limiter/limit

pub type RateLimitError {
  CouldNotStartRateLimiter(inner: actor.StartError)
}

pub opaque type RateLimiter {
  RateLimiter(inner: actor.Started(process.Subject(rate_limiter_actor.Msg)))
}

/// Start a new rate limiter actor.
pub fn new(limits: List(limit.Limit)) -> Result(RateLimiter, RateLimitError) {
  use rate_limit_actor <- result.try(
    rate_limiter_actor.start(limits)
    |> result.map_error(CouldNotStartRateLimiter),
  )
  Ok(RateLimiter(inner: rate_limit_actor))
}

/// This function allows the rate limiter to be used as a lazy guard.
/// Example:
/// ```gleam
/// use <- rate_limiter.lazy_guard(limiter, fn(limit_description) {
///   // ... Construct the appropriate error. `limit_description` is a text description of the limit that was violated.
/// })
/// // ... Continue with the function
/// ```
pub fn lazy_guard(
  rate_limiter: RateLimiter,
  or_else: fn(String) -> a,
  do: fn() -> a,
) -> a {
  rate_limiter_actor.lazy_guard(rate_limiter.inner, or_else, do)
}

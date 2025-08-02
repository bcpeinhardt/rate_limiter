import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/string
import gleeunit
import rate_limiter

pub fn main() -> Nil {
  gleeunit.main()
}

// This counter will only return a 1 to add if the rate limiter lets it pass
fn limited_counter(limiter: rate_limiter.RateLimiter) -> Int {
  use <- rate_limiter.lazy_guard(limiter, 1000, fn(_) { 0 })
  1
}

// gleeunit test functions end in `_test`
pub fn basic_usage_test() {
  // Set up the rate limiter
  let assert Ok(limiter) =
    rate_limiter.start([
      rate_limiter.hits_per_second(hits: 10),
      rate_limiter.hits_per_minute(hits: 15),
    ])

  // Call limited counter 30 times in a row, and verify
  // the sum of successful counts is 10
  let sum =
    list.range(1, 30)
    |> list.fold(0, fn(acc, _) { acc + limited_counter(limiter) })
  assert sum == 10

  // Wait 2 seconds, then call the rate limiter 30 times again. We should only get
  // 5 more hits because of the 15 hits / minute limit
  process.sleep(1000 * 2)
  let sum2 =
    list.range(1, 30)
    |> list.fold(0, fn(acc, _) { acc + limited_counter(limiter) })
  assert sum2 == 5
}

pub fn a_rate_limit_with_an_invalid_configuration_immediately_fails_test() {
  let assert Error(start_error) =
    rate_limiter.start([rate_limiter.hits_per_second(hits: -10)])
  let assert actor.InitFailed(msg) = start_error
  assert msg |> string.contains("invalid limit")
}

pub fn each_limit_constructor_test() {
  // 10 hits per second.
  // 1 second is 1_000_000 micro seconds
  // That makes 100_000 micros seconds per token w/ a max of 10 tokens.
  let l = rate_limiter.hits_per_second(10)
  assert l.burst == 10
  assert l.tokens == 10
  assert l.ns_per_token == 100_000_000

  // 10 hits per every 2 seconds.
  // 2 seconds is 2_000_000 micro seconds
  // That makes 200_000 micros seconds per token w/ a max of 10 tokens.
  let l = rate_limiter.hits_per_seconds(hits: 10, seconds: 2)
  assert l.burst == 10
  assert l.tokens == 10
  assert l.ns_per_token == 200_000_000

  // 10 hits per minute.
  // 1 minute is 60_000_000 micro seconds
  // That makes 6_000_000 micros seconds per token w/ a max of 10 tokens.
  let l = rate_limiter.hits_per_minute(10)
  assert l.burst == 10
  assert l.tokens == 10
  assert l.ns_per_token == 6_000_000_000

  // 10 hits per 5 minutes.
  // 5 minutes is 300_000_000 micro seconds
  // That makes 30_000_000 micro seconds per token w/ a max of 10 tokens.
  let l = rate_limiter.hits_per_minutes(hits: 10, minutes: 5)
  assert l.burst == 10
  assert l.tokens == 10
  assert l.ns_per_token == 30_000_000_000

  // 61 hits per hour.
  // 1 hour is 3.6 billion micro seconds
  // 59016393.4426 microseconds per hit, we should round up to 59_016_394 to keep our limit guarantee.
  let l = rate_limiter.hits_per_hour(hits: 61)
  assert l.burst == 61
  assert l.tokens == 61
  assert l.ns_per_token == 59_016_393_443

  // 61 hits per 2 hours.
  // 2 hours is 7.2 billion micro seconds
  // 118032786.885 microseconds per hit, we should round up to 118_032_787 to keep our limit guarantee.
  let l = rate_limiter.hits_per_hours(hits: 61, hours: 2)
  assert l.burst == 61
  assert l.tokens == 61
  assert l.ns_per_token == 118_032_786_886
}

pub fn ask_rate_limiter_test() {
  let assert Ok(limiter) =
    rate_limiter.start([
      rate_limiter.hits_per_minute(60),
      rate_limiter.hits_per_hour(100),
    ])

  // No requests yet, should be able to make a request right away
  assert rate_limiter.ask(limiter, 1000, 1) == 0

  // Make 65 requests. The amount of time remaining until I can make a request should be:
  // 1. non-zero
  // 2. definitely less than or equal to 1 second (the token replenish rate for 60 requests / minute)
  list.range(1, 65) |> list.each(fn(_) { limited_counter(limiter) })
  let wait = rate_limiter.ask(limiter, 1000, 1)
  assert wait > 0
  assert wait <= 1_000_000_000
  // microseconds in one second

  // Wait a second so our smaller rate limit replenishes
  process.sleep(1000)

  // Make 40 more requests (total 105)
  // The amount of time remaining until I can make *2* requests should be:
  // 1. non-zero
  // 2. definitely less than 72 seconds, the replenish cost for two tokens at 100 / hour
  // 3. almost certainly more than 36 seconds, the replenish cost for one token at 100 / hour
  list.range(1, 40) |> list.each(fn(_) { limited_counter(limiter) })
  let wait = rate_limiter.ask(limiter, 1000, 2)
  assert wait > 0
  assert wait > 36_000_000_000
  // microseconds in 36 seconds
  assert wait < 72_000_000_000
}

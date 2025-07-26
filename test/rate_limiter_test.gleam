import gleam/erlang/process
import gleam/list
import gleam/result
import gleeunit
import rate_limiter

pub fn main() -> Nil {
  gleeunit.main()
}

// This counter will only return a 1 to add if the rate limiter lets it pass
fn limited_counter(limiter: rate_limiter.RateLimiter) -> Int {
  use <- rate_limiter.lazy_guard(limiter, fn(_) { 0 })
  1
}

// gleeunit test functions end in `_test`
pub fn basic_usage_test() {
  // Set up the rate limiter
  let assert Ok(limiter) =
    rate_limiter.new_rate_limiter([
      rate_limiter.per_second(hits: 10),
      rate_limiter.per_minute(15),
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

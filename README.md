# rate_limiter

[![Package Version](https://img.shields.io/hexpm/v/rate_limiter)](https://hex.pm/packages/rate_limiter)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/rate_limiter/)

```sh
gleam add rate_limiter@1
```

A simple rate limiter for the Erlang target. 
The `rate_limiter` module provides a standalone rate limiter type backed by an actor.
The `rate_limiter/actor` module provides the actor implementation by itself for use in a larger supervision tree.
The `rate_limiter/limit` module provides constructors for different limits.


### Construct a rate limiter
```gleam
let assert Ok(limiter) =
  rate_limiter.new_rate_limiter([
    limit.per_hour(100),
    limit.per_minute(60),
  ])
```

### Enforce a rate_limit
```gleam
// Use the lazy_guard function to check a rate limit before proceeding.
use <- rate_limiter.lazy_guard(limiter, fn(descr) { 
  // Handle hitting the limit. `desc` is a human readable description of the rate limit violated.
  // Example: 15 requests per minute
})
```

Further documentation can be found at <https://hexdocs.pm/rate_limiter>.

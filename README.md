# rate_limiter

[![Package Version](https://img.shields.io/hexpm/v/rate_limiter)](https://hex.pm/packages/rate_limiter)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/rate_limiter/)

```sh
gleam add rate_limiter@1
```

A simple rate limiter actor for the Erlang target. 


### Construct a rate limiter
```gleam
let assert Ok(limiter) =
  rate_limiter.start([
    limit.per_hour(100),
    limit.per_minute(60),
  ])
```

### Enforce a rate limit with `lazy_guard`
```gleam
use <- rate_limiter.lazy_guard(limiter, fn(limit_description) { 
  // Handle hitting the limit. 
  // `limit_description` is a human readable description of the rate limit violated.
  // Example: 15 requests per minute
})
// If you made it here none of the rate limits were triggered, congrats!
```

A word of caution: 

This is a simple actor implementing a single token bucket. It's meant as a building block / primitive.

*DO NOT* funnel all the requests to your web service through this single actor. Please.

You could probably use this package as *part* of a rate limiting setup for an API. For example, if you were doing
session based authentication in wisp, you might set up an ETS table mapping session cookies to their running rate limiters.
That way you're hitting the ETS table for rate limits on a per session basis rather than a per request basis.
(Maybe, not really my area tbh).

Further documentation can be found at <https://hexdocs.pm/rate_limiter>.

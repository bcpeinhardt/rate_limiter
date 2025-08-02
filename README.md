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

This is a simple actor implementing a single token bucket. 

In Beam world, we tend to write a simple web server to handle one request and spin up a million rather than
a super complicated web server to handle a million requests and spinning up only one (bad paraphrasing).

*DO NOT* funnel all the requests to your web service through this single actor. Please.

If you're implementing a token based rate limiter for your wisp backend, you can probably get a long way with a 
middleware to do an ETS lookup.

If you're looking for something more granular or more ephemeral (like *session* based rate limits), this might
be the package for you.

Further documentation can be found at <https://hexdocs.pm/rate_limiter>.

# rate_limiter

[![Package Version](https://img.shields.io/hexpm/v/rate_limiter)](https://hex.pm/packages/rate_limiter)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/rate_limiter/)

```sh
gleam add rate_limiter@1
```

A simple rate limiter for the erlang target. 

```gleam
// Setting up the rate limiter. Depending on how you're using it
// you'll likely pass it around as part of a larger context. This example shows
// setting up the rate limiter for a wisp backend.
pub fn main() {
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  // Set up our rate limiter actor
  let assert Ok(limiter) =
    rate_limiter.new_rate_limiter([
      rate_limiter.per_hour(100),
      rate_limiter.per_minute(60),
    ])

  // Start the Mist web server.
  let assert Ok(_) =
    wisp_mist.handler(handle_request(_, Context(limiter:)), secret_key_base)
    |> mist.new
    |> mist.port(8000)
    |> mist.start

  process.sleep_forever()
}

// The whenever something should be rate limited, use the lazy guard
// function to handle it. Here's a wisp request handler as an example
fn handle_request(req: wisp.Request, ctx: Context) -> wisp.Response {
  use _req <- middleware(req)
  use <- rate_limiter.lazy_guard(ctx.limiter, fn(limit_description) {
    let msg = "rate limit hit for request handler: " <> limit_description
    wisp.log_info(msg)
    wisp.response(429) |> wisp.string_body(msg)
  })
  wisp.ok() |> wisp.string_body("Hello, Joe!")
}
```

Further documentation can be found at <https://hexdocs.pm/rate_limiter>.

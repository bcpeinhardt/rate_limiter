//// This package provides a rate limiter for requests. 

import gleam/bool
import gleam/list
import gleam/int
import gleam/io
import gleam/otp/actor
import gleam/erlang/process

// FFI to get BEAMs monotonic time
@external(erlang, "ffi", "get_ms")
fn get_ms() -> Int

// A limit is a number of hits per millisecond that are allowed.
pub opaque type Limit {
  Limit(hits: Int, duration_ms: Int)
}

// Calculates the number of tokens to replenish given a limit and 
// the number of ms that have passed.
// Hits            Millisecond
// ------------ X ------------- = Hits
// Millisecond
fn tokens_to_replenish(limit: Limit, after_ms: Int) -> Int {
  { limit.hits * after_ms } / limit.duration_ms
}

pub fn per_second(hits hits: Int) -> Limit {
  Limit(hits:, duration_ms: 1000)
}

pub fn per_n_seconds(hits hits: Int, seconds secs: Int) -> Limit {
  Limit(hits:, duration_ms: 1000 * secs)
}

pub fn per_minute(hits hits: Int) -> Limit {
  Limit(hits:, duration_ms: 1000 * 60)
}

pub fn per_n_minutes(hits hits: Int, minutes mins: Int) -> Limit {
  Limit(hits:, duration_ms: 1000 * 60 * mins)
}

pub fn per_hour(hits hits: Int) -> Limit {
  Limit(hits:, duration_ms: 1000 * 60 * 60)
}

// The rate limiter actor

type Msg {
  Hit(reply_with: process.Subject(Bool))
}

type State {
  State(
    // Each `token` is an action that's allowed to be performed. The tokens refill at a consistent rate,
    // allowing for bursts or steady usage.
    tokens: Int,

    // Time in milliseconds since the last call
    ms_since_last_hit: Int,

    // The limit we're actually enforcing
    limit: Limit
  )
}

fn new_state(limit: Limit) -> State {
  State(tokens: 10, ms_since_last_hit: get_ms(), limit:)
}

fn consume_token(state: State) -> State {
  State(..state, tokens: state.tokens - 1)
}

fn replenish_tokens(state: State) -> State {
  // Calculate the number of tokens to refill based on the elapsed time.
  let n = tokens_to_replenish(state.limit, get_ms() - state.ms_since_last_hit)
  State(..state, tokens: state.tokens + n)
}

fn record_hit(state: State) -> State {
  State(..state, ms_since_last_hit: get_ms())
}

fn handle_msg(
  state: State,
  msg: Msg
) -> actor.Next(State, Msg) {
  // Before handling any messages, we should use the last recorded hit 
  // time to determine how many tokens to refill
  let state = replenish_tokens(state)

  case msg {
    Hit(reply_with:) -> {
      case state.tokens == 0 {
        True -> {
          process.send(reply_with, False)
          state |> actor.continue
        }
        False -> {
          process.send(reply_with, True)
          state |> consume_token |> record_hit |> actor.continue
        }
      }
    }
  }
}

type RateLimiter = actor.Started(process.Subject(Msg))

fn new_rate_limiter() -> Result(RateLimiter, actor.StartError) {
  actor.new(new_state(60 |> per_minute)) |> actor.on_message(handle_msg) |> actor.start
}

pub fn main() {
  // Set up our rate limiter
  let assert Ok(rate_limiter) = new_rate_limiter()
  
  // Fire off 15 requests
  list.range(1, 15) |> list.each(fn(i) { 
    let res = process.call(rate_limiter.data, 1000, Hit)
    io.println(int.to_string(i) <> ": " <> bool.to_string(res))
  })

  // Sleep two seconds to let the tokens refill
  process.sleep(2000)

  // Fire off 15 more
  list.range(16, 30) |> list.each(fn(i) { 
    let res = process.call(rate_limiter.data, 1000, Hit)
    io.println(int.to_string(i) <> ": " <> bool.to_string(res))
  })
}



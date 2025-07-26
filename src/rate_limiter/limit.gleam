import gleam/int

const one_second_micro_sec = 1_000_000

/// Represents the actual limit on the requests that can be made. We use a token bucket algorithm,
/// and a token refill rate defined in microseconds, which is small enough for this packages use cases.
pub type Limit {
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

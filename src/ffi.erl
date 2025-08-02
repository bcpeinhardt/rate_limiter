-module(ffi).

-export([nanosecond/0]).

% FFI for erlangs montonic time functionality
nanosecond() ->
    erlang:monotonic_time(nanosecond).




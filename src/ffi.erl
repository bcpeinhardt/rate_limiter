-module(ffi).

-export([nanosecond/0]).

nanosecond() ->
    erlang:monotonic_time(nanosecond).
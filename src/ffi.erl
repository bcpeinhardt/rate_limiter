-module(ffi).

-export([get_ms/0]).

get_ms() ->
    erlang:monotonic_time(millisecond).
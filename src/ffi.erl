-module(ffi).

-export([get_micro_second/0]).

get_micro_second() ->
    erlang:monotonic_time(microsecond).
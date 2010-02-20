-module(ns_bootstrap).

-export([start/0, override_resolver/0]).

start() ->
    ok = application:start(sasl),
    ok = application:start(dist_manager),
    ok = application:start(ns_server).

override_resolver() ->
    inet_db:set_lookup([file, dns]),
    start().
% Copyright (c) 2008, Cliff Moon
% Copyright (c) 2008, Powerset, Inc
% Copyright (c) 2009, NorthScale, Inc
%
% All rights reserved.
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions
% are met:
%
% * Redistributions of source code must retain the above copyright
% notice, this list of conditions and the following disclaimer.
% * Redistributions in binary form must reproduce the above copyright
% notice, this list of conditions and the following disclaimer in the
% documentation and/or other materials provided with the distribution.
% * Neither the name of Powerset, Inc nor the names of its
% contributors may be used to endorse or promote products derived from
% this software without specific prior written permission.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
% FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
% COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
% INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
% ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
% POSSIBILITY OF SUCH DAMAGE.
%
% Original Author: Cliff Moon

-include_lib("eunit/include/eunit.hrl").

-compile(export_all).

all_test_() ->
  {foreach,
    fun() -> test_setup() end,
    fun(V) -> test_teardown(V) end,
  [
    {"test_write_membership_to_disk",
     ?_test(test_write_membership_to_disk())},
    {"test_load_membership_from_disk",
     ?_test(test_load_membership_from_disk())},
    {"test_join_one_node",
     ?_test(test_join_one_node())},
% TODO:
%    {"test_membership_gossip_cluster_collision",
%     ?_test(test_membership_gossip_cluster_collision())},
    {"test_replica_nodes",
     ?_test(test_replica_nodes())},
% TODO:
%    {"test_nodes_for_partition",
%     ?_test(test_nodes_for_partition())},
%    {"test_servers_for_key",
%     ?_test(test_servers_for_key())},
    {"test_partitions_for_node_all",
     ?_test(test_partitions_for_node_all())},
%    {"test_initial_partition_setup",
%     ?_test(test_initial_partition_setup())},
    {"test_recover_from_old_membership_read",
     ?_test(test_recover_from_old_membership_read())},
% TODO:
%    {"test_membership_server_throughput",
%     test_membership_server_throughput_()},
    {"test_find_partition",
     ?_test(test_find_partition())}
  ]}.

test_write_membership_to_disk() ->
  process_flag(trap_exit, true),
  {ok, _} = membership:start_link(node(), [node()]),
  ?debugFmt("~p", [data_file()]),
  {ok, Bin} = file:read_file(data_file()),
  State = binary_to_term(Bin),
  ?assertEqual([node()], State#membership.nodes),
  ?assertEqual(64, length(State#membership.partitions)),
  membership:stop(),
  verify().

test_find_partition() ->
  process_flag(trap_exit, true),
  ?assertEqual(1, find_partition(0, 6)),
  ?assertEqual(1, find_partition(1, 6)),
  ?assertEqual((2 bsl 31) - 67108863, find_partition(2 bsl 31, 6)),
  ?assertEqual((2 bsl 30) - 67108863, find_partition((2 bsl 30)-1, 6)).

test_load_membership_from_disk() ->
  process_flag(trap_exit, true),
  State = create_initial_state(node(), [node()], config:get(),
                               ets:new(partitions, [set, public])),
  NS = State#membership{version=[a,b,c]},
  file:write_file(data_file(), term_to_binary(NS)),
  {ok, _} = membership:start_link(node(), [node()]),
  ?assertEqual([node()], membership:nodes()),
  ?assertEqual(64, length(membership:partitions())),
  MemState = state(),
  ?assertEqual([a,b,c], MemState#membership.version),
  membership:stop(),
  verify().

%-record(membership, {config, partitions, version, nodes, old_partitions}).
test_recover_from_old_membership_read() ->
  process_flag(trap_exit, true),
  P = partitions:create_partitions(6, a, [a, b, c, d, e, f]),
  OldMem = {membership, {config, 1, 2, 3, 4}, P,
            [{a, 1}, {b, 1}], [a, b, c, d, e, f], undefined},
  ok = file:write_file(data_file("a"), term_to_binary(OldMem)),
  {ok, _} = membership:start_link(a, [a, b, c]),
  ?assertEqual(P, membership:partitions()),
  ?assertEqual([a, b, c, d, e, f], membership:nodes()).

test_join_one_node() ->
  process_flag(trap_exit, true),
  mock:expects(sync_manager, load, fun({_, _, P}) -> is_list(P) end, ok),
  mock:expects(storage_manager, load, fun({_, _, P}) -> is_list(P) end, ok),
  {ok, _} = membership:start_link(node(), [node()]),
  membership:join_node(node(), node_a),
  Partitions = membership:partitions(),
  {A, B} = lists:partition(fun({Node,_}) -> Node == node() end, Partitions),
  ?assertEqual(64, length(A) + length(B)),
  membership:stop(),
  verify().

test_membership_gossip_cluster_collision() ->
  process_flag(trap_exit, true),
  mock:expects(sync_manager, load,
               fun({_, _, P}) -> is_list(P) end, ok, 3),
  mock:expects(storage_manager, load,
               fun({_, _, P}) -> is_list(P) end, ok, 3),
  {ok, _} = membership:start_link(mem_a, a, [a]),
  {ok, _} = membership:start_link(mem_b, b, [b]),
  gen_server:cast(mem_a, {gossip_with, mem_b}),
  timer:sleep(10),
  Partitions = gen_server:call(mem_a, partitions),
  {A, B} = lists:partition(fun({Node,_}) -> Node == a end, Partitions),
  ?debugVal({A, B}),
  ?assertEqual(64, length(A) + length(B)),
  ?assert(length(A) > 0),
  ?assert(length(B) > 0),
  membership:stop(mem_a),
  membership:stop(mem_b),
  verify().

test_replica_nodes() ->
  process_flag(trap_exit, true),
  config:set(n, 3),
  {ok, _} = membership:start_link(a, [a, b, c, d, e, f]),
  ?assertEqual([f,a,b], replica_nodes(f)).

test_nodes_for_partition() ->
  process_flag(trap_exit, true),
  config:set(n, 3),
  {ok, _} = membership:start_link(a, [a, b, c, d, e, f]),
  ?assertEqual([d,e,f], nodes_for_partition(1)).

test_servers_for_key() ->
  process_flag(trap_exit, true),
  config:set(n, 3),
  {ok, _} = membership:start_link(a, [a, b, c, d, e, f]),
  % 25110333
  ?assertEqual([{storage_1, d}, {storage_1, e}, {storage_1, f}],
               servers_for_key("key")).

test_initial_partition_setup() ->
  process_flag(trap_exit, true),
  {ok, _} = membership:start_link(a, [a, b, c, d, e, f]),
  Sizes = partitions:sizes([a,b,c,d,e,f], partitions()),
  {value, {c,S}} = lists:keysearch(c, 1, Sizes),
  ?debugVal({Sizes, S}),
  ?assert(S > 0).

test_partitions_for_node_all() ->
  config:set(n, 2),
  {ok, _} = membership:start_link(a, [a, b, c, d, e, f]),
  % 715827883
  Parts = partitions_for_node(a, all),
  PA = partitions_for_node(a, master),
  PF = partitions_for_node(f, master),
  ?debugFmt("Parts ~p", [Parts]),
  ?assertEqual(lists:sort(Parts), lists:sort(PA ++ PF)).

test_partitions_for_node_master() ->
  process_flag(trap_exit, true),
  {ok, _} = membership:start_link(a, [a,b,c,d,e,f]),
  Parts = partitions_for_node(a, master),
  ?assertEqual(10, length(Parts)).

test_membership_server_throughput_() ->
  process_flag(trap_exit, true),
  {timeout, 500, ?_test(test_membership_server_throughput())}.

test_membership_server_throughput() ->
  process_flag(trap_exit, true),
  {ok, _} = membership:start_link(a, [a,b,c,d,e,f]),
  {Keys, _} = misc:fast_acc(fun({List, Str}) ->
      Mod = misc:succ(Str),
      {[Mod|List], Mod}
    end, {[], "aaaaaaaa"}, 10000),
  Start = misc:now_float(),
  lists:foreach(fun(Str) ->
      membership:servers_for_key(Str)
    end, Keys),
  End = misc:now_float(),
  ?debugFmt("membership can do ~p reqs/s", [10000/(End-Start)]).

test_gossip_server() ->
  ok.

test_setup() ->
  process_flag(trap_exit, true),
  config:start_link({config,
                     [{n,1},{r,1},{w,1},{q,6},{directory,priv_dir()}]}),
  ?assertMatch({ok, _}, mock:mock(sync_manager)),
  ?assertMatch({ok, _}, mock:mock(storage_manager)),
  mock:expects(sync_manager, load,
               fun({_, _, P}) -> is_list(P) end, ok),
  mock:expects(storage_manager, load,
               fun({_, _, P}) -> is_list(P) end, ok).

verify() ->
  ok = mock:verify(sync_manager),
  ok = mock:verify(storage_manager).

test_teardown(_) ->
  file:delete(data_file()),
  file:delete(data_file("a")),
  file:delete(data_file("b")),
  membership:stop(),
  mock:stop(sync_manager),
  mock:stop(storage_manager),
  config:stop().

priv_dir() ->
  Dir = filename:join([t:config(priv_dir), "data", "membership"]),
  filelib:ensure_dir(filename:join(Dir, "membership")),
  Dir.

data_file() ->
  filename:join([priv_dir(), atom_to_list(node()) ++ ".bin"]).

data_file(Name) ->
  filename:join([priv_dir(), Name ++ ".bin"]).

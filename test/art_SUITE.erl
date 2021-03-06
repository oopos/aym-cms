%  @copyright 2010-2011 Zuse Institute Berlin
%  @end
%
%   Licensed under the Apache License, Version 2.0 (the "License");
%   you may not use this file except in compliance with the License.
%   You may obtain a copy of the License at
%
%       http://www.apache.org/licenses/LICENSE-2.0
%
%   Unless required by applicable law or agreed to in writing, software
%   distributed under the License is distributed on an "AS IS" BASIS,
%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%   See the License for the specific language governing permissions and
%   limitations under the License.
%%%-------------------------------------------------------------------
%%% File    art_SUITE.erl
%%% @author Maik Lange <MLange@informatik.hu-berlin.de>
%%% @doc    Tests for art module (approximate reconciliation tree).
%%% @end
%%% Created : 11/11/2011 by Maik Lange <MLange@informatik.hu-berlin.de>
%%%-------------------------------------------------------------------
%% @version $Id: $

-module(art_SUITE).

-compile(export_all).

-include("scalaris.hrl").
-include("unittest.hrl").

-define(IIF(C, A, B), case C of
                          true -> A;
                          _ -> B
                      end).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

all() -> [
          performance,
          tester_new,
          tester_lookup
         ].

suite() ->
    [
     {timetrap, {seconds, 20}}
    ].

init_per_suite(Config) ->
    _ = crypto:start(),
    Config.

end_per_suite(_Config) ->
    crypto:stop(),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

performance(_) ->
    
    ToAdd = 2000,
    ExecTimes = 100,
    
    I = intervals:new('[', rt_SUITE:number_to_key(1), rt_SUITE:number_to_key(100000000), ']'),
    {TreeTime, Tree} = 
        util:tc(fun() -> 
                        merkle_tree_builder:build(merkle_tree:new(I), ToAdd, uniform) 
                end, []),
    
    %measure build times
    BT = measure_util:time_avg(
           fun() -> 
                   art:new(Tree) 
           end,
           [], ExecTimes, false),    
    %Output
    ct:pal("ART Performance
            ------------------------
            PARAMETER: AddedItems=~p ; ExecTimes=~p
            TreeTime (ms)= ~p
            ARTBuildTime (ms)= ~p", 
           [ToAdd, ExecTimes, TreeTime / 1000,
            measure_util:print_result(BT, ms)]),
    true.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec prop_new(intervals:key(), intervals:key()) -> boolean().
prop_new(L, L) -> true;
prop_new(L, R) ->
    I = intervals:new('[', L, R, ']'),
    Tree = merkle_tree:new(I),
    Art1 = art:new(Tree),
    Conf1 = art:get_config(Art1),
    Art2 = art:new(Tree, 
                   [{correction_factor, util:proplist_get_value(correction_factor, Conf1) + 1},
                    {inner_bf_fpr, util:proplist_get_value(inner_bf_fpr, Conf1) + 0.1},
                    {leaf_bf_fpr, util:proplist_get_value(leaf_bf_fpr, Conf1) + 0.1}]),
    Conf2 = art:get_config(Art2),
    ?equals(util:proplist_get_value(correction_factor, Conf1) + 1,
            util:proplist_get_value(correction_factor, Conf2)),
    ?equals(util:proplist_get_value(inner_bf_fpr, Conf1) + 0.1,
            util:proplist_get_value(inner_bf_fpr, Conf2)),
    ?equals(util:proplist_get_value(leaf_bf_fpr, Conf1) + 0.1,
            util:proplist_get_value(leaf_bf_fpr, Conf2)),    
    true.

tester_new(_) ->
    tester:test(?MODULE, prop_new, 2, 100).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec prop_lookup(intervals:key(), intervals:key()) -> boolean().
prop_lookup(L, L) -> true;    
prop_lookup(L, R) ->    
    I = intervals:new('[', L, R, ']'),
    Tree = merkle_tree_builder:build(merkle_tree:new(I), 400, uniform),    
    Art = art:new(Tree),
    Found = nodes_in_art(merkle_tree:iterator(Tree), Art, 0),
    ?assert(Found > 0),
    ct:pal("TreeNodes=~p ; Found=~p", [merkle_tree:size(Tree), Found]),
    true.

-spec nodes_in_art(merkle_tree:mt_iter(), art:art(), non_neg_integer()) -> non_neg_integer().
nodes_in_art(Iter, Art, Acc) ->
    case merkle_tree:next(Iter) of
        none -> Acc;
        {Node, NewIter} -> 
            nodes_in_art(NewIter, Art, Acc + ?IIF(art:lookup(Node, Art), 1, 0))
    end.

tester_lookup(_) ->
  tester:test(?MODULE, prop_lookup, 2, 100).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%  Copyright 2007-2009 Konrad-Zuse-Zentrum f�r Informationstechnik Berlin
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
%%% File    : dc-clustering.erl
%%% Author  : Thorsten Schuett <schuett@zib.de>
%%% Description : 
%%%
%%% Created :  26 August 2009 by Thorsten Schuett <schuett@zib.de>
%%%-------------------------------------------------------------------
%% @author Thorsten Schuett <schuett@zib.de>
%% @author Marie Hoffmann <hoffmann@zib.de>
%% @copyright 2009 Konrad-Zuse-Zentrum f�r Informationstechnik Berlin
%% @version $Id$
%% @reference T. Schütt, A. Reinefeld,F. Schintke, M. Hoffmann.
%% Gossip-based Topology Inference for Efficient Overlay Mapping on Data Centers.
%% 9th Int. Conf. on Peer-to-Peer Computing Seattle, Sept. 2009.
-module(dc_clustering).

-author('schuett@zib.de').
-vsn('$Id$ ').

-behaviour(gen_component).

-export([start_link/1]).

-export([on/2, init/1]).

-type(relative_size() :: float()).
-type(centroid() :: {vivaldi:network_coordinate(), relative_size()}).
-type(centroids() :: [centroid()]).

% state of the clustering loop
-type(state() :: {centroids()}).

% accepted messages of cluistering process
-type(message() :: any()).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Message Loop
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% start new clustering shuffle
%% @doc message handler
-spec(on/2 :: (Message::message(), State::state()) -> state()).
on({start_clustering_shuffle}, State) ->
    io:format("~p~n", [State]),
    erlang:send_after(config:read(dc_clustering_interval), self(),
                      {start_clustering_shuffle}),
    case get_local_cyclon_pid() of
        failed ->
            ok;
        CyclonPid ->
            cs_send:send_local(CyclonPid,{get_subset, 1, self()})
    end,
    State;

% ask vivaldi for network coordinate
on({reset_clustering}, State) ->
    erlang:send_after(config:read(dc_clustering_reset_interval), self(), {reset_clustering}),
    cs_send:send_local(get_local_vivaldi_pid(), {query_vivaldi, cs_send:this()}),
    State;

% reset the local state
on({query_vivaldi_response, Coordinate, _Confidence}, _State) ->
    {[Coordinate, 1.0]};

% got random node from cyclon
on({cache, Cache}, {Centroids} = State) ->
    %io:format("~p~n",[Cache]),
    case Cache of
        [] ->
            State;
        [Node] ->
            cs_send:send_to_group_member(node:pidX(Node), dc_clustering, {clustering_shuffle,
                                                                          cs_send:this(),
                                                                          Centroids}),
            State
    end;

% have been ask to shuffle
on({clustering_shuffle, RemoteNode, RemoteCentroids},
   {Centroids}) ->
   %io:format("{shuffle, ~p, ~p}~n", [RemoteCoordinate, RemoteConfidence]),
    cs_send:send(RemoteNode, {clustering_shuffle_reply,
                              cs_send:this(),
                              Centroids}),
    NewCentroids = cluster(Centroids, RemoteCentroids),
    {NewCentroids};

% got shuffle response
on({clustering_shuffle_reply, _RemoteNode, RemoteCentroids},
   {Centroids}) ->
    %io:format("{shuffle_reply, ~p, ~p}~n", [RemoteCoordinate, RemoteConfidence]),
    %vivaldi_latency:measure_latency(RemoteNode, RemoteCoordinate, RemoteConfidence),
    NewCentroids = cluster(Centroids, RemoteCentroids),
    {NewCentroids};

% return my clusters
on({query_clustering, Pid},
   {Centroids} = State) ->
    cs_send:send(Pid,{query_clustering_response, Centroids}),
    State;

on(_, _State) ->
    unknown_event.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Init
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec(init/1 :: ([any()]) -> state()).
init([_InstanceId, []]) ->
    erlang:send_after(config:read(dc_clustering_reset_interval), self(), {reset_clustering}),
    cs_send:send_local(self(),{reset_clustering}),
    cs_send:send_local(self(),{start_clustering_shuffle}),
    {[]}.

%% @spec start_link(term()) -> {ok, pid()}
start_link(InstanceId) ->
    gen_component:start_link(?MODULE, [InstanceId, []], [{register, InstanceId, dc_clustering}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
get_local_cyclon_pid() ->
    InstanceId = erlang:get(instance_id),
    if
        InstanceId == undefined ->
            log:log(error,"[ Node ] ~p", [util:get_stacktrace()]);
        true ->
            ok
    end,
    process_dictionary:lookup_process(InstanceId, cyclon).

get_local_vivaldi_pid() ->
    InstanceId = erlang:get(instance_id),
    if
        InstanceId == undefined ->
            log:log(error,"[ Node ] ~p", [util:get_stacktrace()]);
        true ->
            ok
    end,
    process_dictionary:lookup_process(InstanceId, vivaldi).

-spec(cluster/2 :: (centroids(), centroids()) -> centroids()).
cluster(Centroids, RemoteCentroids) ->
    Centroids ++ RemoteCentroids.
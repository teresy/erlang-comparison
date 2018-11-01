%%%----------------------------------------------------------------------
%%% File    : ejabberd_listener.erl
%%% Author  : Alexey Shchepin <alexey@process-one.net>
%%% Purpose : Manage socket listener
%%% Created : 16 Nov 2002 by Alexey Shchepin <alexey@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2018   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License along
%%% with this program; if not, write to the Free Software Foundation, Inc.,
%%% 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
%%%
%%%----------------------------------------------------------------------

-module(ejabberd_listener).

-behaviour(supervisor).

-behaviour(ejabberd_config).

-author('alexey@process-one.net').

-author('ekhramtsov@process-one.net').

-export([add_listener/3, config_reloaded/0,
	 delete_listener/2, get_certfiles/0, init/1, init/3,
	 opt_type/1, start/3, start_link/0, start_listener/3,
	 start_listeners/0, stop_listener/2, stop_listeners/0,
	 transform_options/1, validate_cfg/1]).

%% Legacy API
-export([parse_listener_portip/2]).

-include("logger.hrl").

-type({transport,
       {type, 42, union, [{atom, 42, tcp}, {atom, 42, udp}]},
       []}).

-type({endpoint,
       {type, 43, tuple,
	[{remote_type, 43,
	  [{atom, 43, inet}, {atom, 43, port_number}, []]},
	 {remote_type, 43,
	  [{atom, 43, inet}, {atom, 43, ip_address}, []]},
	 {type, 43, transport, []}]},
       []}).

-type({listen_opts,
       {type, 44, list,
	[{remote_type, 44,
	  [{atom, 44, proplists}, {atom, 44, property}, []]}]},
       []}).

-type({listener,
       {type, 45, tuple,
	[{type, 45, endpoint, []}, {type, 45, module, []},
	 {type, 45, listen_opts, []}]},
       []}).

- callback ( { { start , 2 } , [ { type , 47 , 'fun' , [ { type , 47 , product , [ { type , 47 , tuple , [ { atom , 47 , gen_tcp } , { remote_type , 47 , [ { atom , 47 , inet } , { atom , 47 , socket } , [ ] ] } ] } , { type , 47 , listen_opts , [ ] } ] } , { type , 48 , union , [ { type , 48 , tuple , [ { atom , 48 , ok } , { type , 48 , pid , [ ] } ] } , { type , 48 , tuple , [ { atom , 48 , error } , { type , 48 , any , [ ] } ] } , { atom , 48 , ignore } ] } ] } ] } ) .


- callback ( { { start_link , 2 } , [ { type , 49 , 'fun' , [ { type , 49 , product , [ { type , 49 , tuple , [ { atom , 49 , gen_tcp } , { remote_type , 49 , [ { atom , 49 , inet } , { atom , 49 , socket } , [ ] ] } ] } , { type , 49 , listen_opts , [ ] } ] } , { type , 50 , union , [ { type , 50 , tuple , [ { atom , 50 , ok } , { type , 50 , pid , [ ] } ] } , { type , 50 , tuple , [ { atom , 50 , error } , { type , 50 , any , [ ] } ] } , { atom , 50 , ignore } ] } ] } ] } ) .


- callback ( { { accept , 1 } , [ { type , 51 , 'fun' , [ { type , 51 , product , [ { type , 51 , pid , [ ] } ] } , { type , 51 , any , [ ] } ] } ] } ) .


- callback ( { { listen_opt_type , 1 } , [ { type , 52 , 'fun' , [ { type , 52 , product , [ { type , 52 , atom , [ ] } ] } , { type , 52 , 'fun' , [ { type , 52 , product , [ { type , 52 , term , [ ] } ] } , { type , 52 , term , [ ] } ] } ] } ] } ) .


- callback ( { { listen_options , 0 } , [ { type , 53 , 'fun' , [ { type , 53 , product , [ ] } , { type , 53 , listen_opts , [ ] } ] } ] } ) .


-optional_callbacks([{listen_opt_type, 1}]).

-define(TCP_SEND_TIMEOUT, 15000).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init(_) ->
    ets:new(?MODULE, [named_table, public]),
    ejabberd_hooks:add(config_reloaded, ?MODULE,
		       config_reloaded, 50),
    Listeners = ejabberd_config:get_option(listen, []),
    {ok,
     {{one_for_one, 10, 1}, listeners_childspec(Listeners)}}.

- spec ( { { listeners_childspec , 1 } , [ { type , 68 , 'fun' , [ { type , 68 , product , [ { type , 68 , list , [ { type , 68 , listener , [ ] } ] } ] } , { type , 68 , list , [ { remote_type , 68 , [ { atom , 68 , supervisor } , { atom , 68 , child_spec } , [ ] ] } ] } ] } ] } ) .


listeners_childspec(Listeners) ->
    [listeners_childspec_1(V1) || V1 <- Listeners].

listeners_childspec_1({EndPoint, Module, Opts}) ->
    ets:insert(?MODULE, {EndPoint, Module, Opts}),
    {EndPoint, {?MODULE, start, [EndPoint, Module, Opts]},
     transient, brutal_kill, worker, [?MODULE]}.

- spec ( { { start_listeners , 0 } , [ { type , 78 , 'fun' , [ { type , 78 , product , [ ] } , { atom , 78 , ok } ] } ] } ) .


start_listeners() ->
    Listeners = ejabberd_config:get_option(listen, []),
    lists:foreach(fun (Spec) ->
			  supervisor:start_child(?MODULE, Spec)
		  end,
		  listeners_childspec(Listeners)).

- spec ( { { start , 3 } , [ { type , 86 , 'fun' , [ { type , 86 , product , [ { type , 86 , endpoint , [ ] } , { type , 86 , module , [ ] } , { type , 86 , listen_opts , [ ] } ] } , { type , 86 , term , [ ] } ] } ] } ) .


start(EndPoint, Module, Opts) ->
    proc_lib:start_link(?MODULE, init,
			[EndPoint, Module, Opts]).

- spec ( { { init , 3 } , [ { type , 90 , 'fun' , [ { type , 90 , product , [ { type , 90 , endpoint , [ ] } , { type , 90 , module , [ ] } , { type , 90 , listen_opts , [ ] } ] } , { atom , 90 , ok } ] } ] } ) .


init(EndPoint, Module, AllOpts) ->
    {ModuleOpts, SockOpts} = split_opts(AllOpts),
    init(EndPoint, Module, ModuleOpts, SockOpts).

- spec ( { { init , 4 } , [ { type , 95 , 'fun' , [ { type , 95 , product , [ { type , 95 , endpoint , [ ] } , { type , 95 , module , [ ] } , { type , 95 , listen_opts , [ ] } , { type , 95 , list , [ { remote_type , 95 , [ { atom , 95 , gen_tcp } , { atom , 95 , option } , [ ] ] } ] } ] } , { atom , 95 , ok } ] } ] } ) .


init({Port, _, udp} = EndPoint, Module, Opts,
     SockOpts) ->
    case gen_udp:open(Port,
		      [binary, {active, false}, {reuseaddr, true} | SockOpts])
	of
      {ok, Socket} ->
	  case inet:sockname(Socket) of
	    {ok, {Addr, Port1}} ->
		proc_lib:init_ack({ok, self()}),
		application:ensure_started(ejabberd),
		?INFO_MSG("Start accepting UDP connections at ~s "
			  "for ~p",
			  [format_endpoint({Port1, Addr, udp}), Module]),
		case erlang:function_exported(Module, udp_init, 2) of
		  false -> udp_recv(Socket, Module, Opts);
		  true ->
		      case catch Module:udp_init(Socket, Opts) of
			{'EXIT', _} = Err ->
			    ?ERROR_MSG("failed to process callback function "
				       "~p:~s(~p, ~p): ~p",
				       [Module, udp_init, Socket, Opts, Err]),
			    udp_recv(Socket, Module, Opts);
			NewOpts -> udp_recv(Socket, Module, NewOpts)
		      end
		end;
	    {error, Reason} = Err ->
		report_socket_error(Reason, EndPoint, Module),
		proc_lib:init_ack(Err)
	  end;
      {error, Reason} = Err ->
	  report_socket_error(Reason, EndPoint, Module),
	  proc_lib:init_ack(Err)
    end;
init({Port, _, tcp} = EndPoint, Module, Opts,
     SockOpts) ->
    case listen_tcp(Port, SockOpts) of
      {ok, ListenSocket} ->
	  case inet:sockname(ListenSocket) of
	    {ok, {Addr, Port1}} ->
		proc_lib:init_ack({ok, self()}),
		application:ensure_started(ejabberd),
		Sup = start_module_sup(Module, Opts),
		?INFO_MSG("Start accepting TCP connections at ~s "
			  "for ~p",
			  [format_endpoint({Port1, Addr, tcp}), Module]),
		case erlang:function_exported(Module, tcp_init, 2) of
		  false -> accept(ListenSocket, Module, Opts, Sup);
		  true ->
		      case catch Module:tcp_init(ListenSocket, Opts) of
			{'EXIT', _} = Err ->
			    ?ERROR_MSG("failed to process callback function "
				       "~p:~s(~p, ~p): ~p",
				       [Module, tcp_init, ListenSocket, Opts,
					Err]),
			    accept(ListenSocket, Module, Opts, Sup);
			NewOpts -> accept(ListenSocket, Module, NewOpts, Sup)
		      end
		end;
	    {error, Reason} = Err ->
		report_socket_error(Reason, EndPoint, Module), Err
	  end;
      {error, Reason} = Err ->
	  report_socket_error(Reason, EndPoint, Module),
	  proc_lib:init_ack(Err)
    end.

- spec ( { { listen_tcp , 2 } , [ { type , 163 , 'fun' , [ { type , 163 , product , [ { remote_type , 163 , [ { atom , 163 , inet } , { atom , 163 , port_number } , [ ] ] } , { type , 163 , list , [ { remote_type , 163 , [ { atom , 163 , gen_tcp } , { atom , 163 , option } , [ ] ] } ] } ] } , { type , 164 , union , [ { type , 164 , tuple , [ { atom , 164 , ok } , { remote_type , 164 , [ { atom , 164 , inet } , { atom , 164 , socket } , [ ] ] } ] } , { type , 164 , tuple , [ { atom , 164 , error } , { type , 164 , union , [ { atom , 164 , system_limit } , { remote_type , 164 , [ { atom , 164 , inet } , { atom , 164 , posix } , [ ] ] } ] } ] } ] } ] } ] } ) .


listen_tcp(Port, SockOpts) ->
    Res = gen_tcp:listen(Port,
			 [binary, {packet, 0}, {active, false},
			  {reuseaddr, true}, {nodelay, true},
			  {send_timeout, ?TCP_SEND_TIMEOUT},
			  {send_timeout_close, true}, {keepalive, true}
			  | SockOpts]),
    case Res of
      {ok, ListenSocket} -> {ok, ListenSocket};
      {error, _} = Err -> Err
    end.

- spec ( { { split_opts , 1 } , [ { type , 182 , 'fun' , [ { type , 182 , product , [ { type , 182 , listen_opts , [ ] } ] } , { type , 182 , tuple , [ { type , 182 , listen_opts , [ ] } , { type , 182 , list , [ { remote_type , 182 , [ { atom , 182 , gen_tcp } , { atom , 182 , option } , [ ] ] } ] } ] } ] } ] } ) .


split_opts(Opts) ->
    lists:foldl(fun (Opt, {ModOpts, SockOpts} = Acc) ->
			case Opt of
			  {ip, _} -> {ModOpts, [Opt | SockOpts]};
			  {backlog, _} -> {ModOpts, [Opt | SockOpts]};
			  {inet, true} -> {ModOpts, [inet | SockOpts]};
			  {inet6, true} -> {ModOpts, [int6 | SockOpts]};
			  {inet, false} -> Acc;
			  {inet6, false} -> Acc;
			  _ -> {[Opt | ModOpts], SockOpts}
			end
		end,
		{[], []}, Opts).

- spec ( { { accept , 4 } , [ { type , 197 , 'fun' , [ { type , 197 , product , [ { remote_type , 197 , [ { atom , 197 , inet } , { atom , 197 , socket } , [ ] ] } , { type , 197 , module , [ ] } , { type , 197 , listen_opts , [ ] } , { type , 197 , atom , [ ] } ] } , { type , 197 , no_return , [ ] } ] } ] } ) .


accept(ListenSocket, Module, Opts, Sup) ->
    Interval = proplists:get_value(accept_interval, Opts,
				   0),
    accept(ListenSocket, Module, Opts, Sup, Interval).

- spec ( { { accept , 5 } , [ { type , 202 , 'fun' , [ { type , 202 , product , [ { remote_type , 202 , [ { atom , 202 , inet } , { atom , 202 , socket } , [ ] ] } , { type , 202 , module , [ ] } , { type , 202 , listen_opts , [ ] } , { type , 202 , atom , [ ] } , { type , 202 , non_neg_integer , [ ] } ] } , { type , 202 , no_return , [ ] } ] } ] } ) .


accept(ListenSocket, Module, Opts, Sup, Interval) ->
    NewInterval = check_rate_limit(Interval),
    case gen_tcp:accept(ListenSocket) of
      {ok, Socket} ->
	  case {inet:sockname(Socket), inet:peername(Socket)} of
	    {{ok, {Addr, Port}}, {ok, {PAddr, PPort}}} ->
		Receiver = case start_connection(Module, Socket, Opts,
						 Sup)
			       of
			     {ok, RecvPid} -> RecvPid;
			     _ -> gen_tcp:close(Socket), none
			   end,
		?INFO_MSG("(~p) Accepted connection ~s:~p -> ~s:~p",
			  [Receiver,
			   ejabberd_config:may_hide_data(inet_parse:ntoa(PAddr)),
			   PPort, inet_parse:ntoa(Addr), Port]);
	    _ -> gen_tcp:close(Socket)
	  end,
	  accept(ListenSocket, Module, Opts, Sup, NewInterval);
      {error, Reason} ->
	  ?ERROR_MSG("(~w) Failed TCP accept: ~s",
		     [ListenSocket, inet:format_error(Reason)]),
	  accept(ListenSocket, Module, Opts, Sup, NewInterval)
    end.

- spec ( { { udp_recv , 3 } , [ { type , 230 , 'fun' , [ { type , 230 , product , [ { remote_type , 230 , [ { atom , 230 , inet } , { atom , 230 , socket } , [ ] ] } , { type , 230 , module , [ ] } , { type , 230 , listen_opts , [ ] } ] } , { type , 230 , no_return , [ ] } ] } ] } ) .


udp_recv(Socket, Module, Opts) ->
    case gen_udp:recv(Socket, 0) of
      {ok, {Addr, Port, Packet}} ->
	  case catch Module:udp_recv(Socket, Addr, Port, Packet,
				     Opts)
	      of
	    {'EXIT', Reason} ->
		?ERROR_MSG("failed to process UDP packet:~n** Source: "
			   "{~p, ~p}~n** Reason: ~p~n** Packet: "
			   "~p",
			   [Addr, Port, Reason, Packet]),
		udp_recv(Socket, Module, Opts);
	    NewOpts -> udp_recv(Socket, Module, NewOpts)
	  end;
      {error, Reason} ->
	  ?ERROR_MSG("unexpected UDP error: ~s",
		     [format_error(Reason)]),
	  throw({error, Reason})
    end.

- spec ( { { start_connection , 4 } , [ { type , 249 , 'fun' , [ { type , 249 , product , [ { type , 249 , module , [ ] } , { remote_type , 249 , [ { atom , 249 , inet } , { atom , 249 , socket } , [ ] ] } , { type , 249 , listen_opts , [ ] } , { type , 249 , atom , [ ] } ] } , { type , 250 , union , [ { type , 250 , tuple , [ { atom , 250 , ok } , { type , 250 , pid , [ ] } ] } , { type , 250 , tuple , [ { atom , 250 , error } , { type , 250 , any , [ ] } ] } , { atom , 250 , ignore } ] } ] } ] } ) .


start_connection(Module, Socket, Opts, Sup) ->
    Res = case Sup of
	    undefined -> Module:start({gen_tcp, Socket}, Opts);
	    _ ->
		supervisor:start_child(Sup, [{gen_tcp, Socket}, Opts])
	  end,
    case Res of
      {ok, Pid} ->
	  case gen_tcp:controlling_process(Socket, Pid) of
	    ok -> Module:accept(Pid), {ok, Pid};
	    Err -> exit(Pid, kill), Err
	  end;
      Err -> Err
    end.

- spec ( { { start_listener , 3 } , [ { type , 270 , 'fun' , [ { type , 270 , product , [ { type , 270 , endpoint , [ ] } , { type , 270 , module , [ ] } , { type , 270 , listen_opts , [ ] } ] } , { type , 271 , union , [ { type , 271 , tuple , [ { atom , 271 , ok } , { type , 271 , pid , [ ] } ] } , { type , 271 , tuple , [ { atom , 271 , error } , { type , 271 , any , [ ] } ] } ] } ] } ] } ) .


start_listener(EndPoint, Module, Opts) ->
    %% It is only required to start the supervisor in some cases.
    %% But it doesn't hurt to attempt to start it for any listener.
    %% So, it's normal (and harmless) that in most cases this
    %% call returns: {error, {already_started, pid()}}
    case start_listener_sup(EndPoint, Module, Opts) of
      {ok, _Pid} = R -> R;
      {error,
       {{'EXIT', {undef, [{M, _F, _A} | _]}}, _} = Error} ->
	  ?ERROR_MSG("Error starting the ejabberd listener: "
		     "~p.~nIt could not be loaded or is not "
		     "an ejabberd listener.~nError: ~p~n",
		     [Module, Error]),
	  {error, {module_not_available, M}};
      {error, {already_started, Pid}} -> {ok, Pid};
      {error, Error} -> {error, Error}
    end.

- spec ( { { start_module_sup , 2 } , [ { type , 290 , 'fun' , [ { type , 290 , product , [ { type , 290 , module , [ ] } , { type , 290 , list , [ { remote_type , 290 , [ { atom , 290 , proplists } , { atom , 290 , property } , [ ] ] } ] } ] } , { type , 290 , atom , [ ] } ] } ] } ) .


start_module_sup(Module, Opts) ->
    case proplists:get_value(supervisor, Opts, true) of
      true ->
	  Proc = list_to_atom(atom_to_list(Module) ++ "_sup"),
	  ChildSpec = {Proc,
		       {ejabberd_tmp_sup, start_link, [Proc, Module]},
		       permanent, infinity, supervisor, [ejabberd_tmp_sup]},
	  supervisor:start_child(ejabberd_sup, ChildSpec),
	  Proc;
      false -> undefined
    end.

- spec ( { { start_listener_sup , 3 } , [ { type , 306 , 'fun' , [ { type , 306 , product , [ { type , 306 , endpoint , [ ] } , { type , 306 , module , [ ] } , { type , 306 , listen_opts , [ ] } ] } , { type , 307 , union , [ { type , 307 , tuple , [ { atom , 307 , ok } , { type , 307 , pid , [ ] } ] } , { type , 307 , tuple , [ { atom , 307 , error } , { type , 307 , any , [ ] } ] } ] } ] } ] } ) .


start_listener_sup(EndPoint, Module, Opts) ->
    ChildSpec = {EndPoint,
		 {?MODULE, start, [EndPoint, Module, Opts]}, transient,
		 brutal_kill, worker, [?MODULE]},
    supervisor:start_child(?MODULE, ChildSpec).

- spec ( { { stop_listeners , 0 } , [ { type , 317 , 'fun' , [ { type , 317 , product , [ ] } , { atom , 317 , ok } ] } ] } ) .


stop_listeners() ->
    Ports = ejabberd_config:get_option(listen, []),
    lists:foreach(fun ({PortIpNetp, Module, _Opts}) ->
			  delete_listener(PortIpNetp, Module)
		  end,
		  Ports).

- spec ( { { stop_listener , 2 } , [ { type , 326 , 'fun' , [ { type , 326 , product , [ { type , 326 , endpoint , [ ] } , { type , 326 , module , [ ] } ] } , { type , 326 , union , [ { atom , 326 , ok } , { type , 326 , tuple , [ { atom , 326 , error } , { type , 326 , any , [ ] } ] } ] } ] } ] } ) .


stop_listener({_, _, Transport} = EndPoint, Module) ->
    case supervisor:terminate_child(?MODULE, EndPoint) of
      ok ->
	  ?INFO_MSG("Stop accepting ~s connections at ~s "
		    "for ~p",
		    [case Transport of
		       udp -> "UDP";
		       tcp -> "TCP"
		     end,
		     format_endpoint(EndPoint), Module]),
	  ets:delete(?MODULE, EndPoint),
	  supervisor:delete_child(?MODULE, EndPoint);
      Err -> Err
    end.

- spec ( { { add_listener , 3 } , [ { type , 339 , 'fun' , [ { type , 339 , product , [ { type , 339 , endpoint , [ ] } , { type , 339 , module , [ ] } , { type , 339 , listen_opts , [ ] } ] } , { type , 339 , union , [ { atom , 339 , ok } , { type , 339 , tuple , [ { atom , 339 , error } , { type , 339 , any , [ ] } ] } ] } ] } ] } ) .


add_listener(EndPoint, Module, Opts) ->
    case start_listener(EndPoint, Module, Opts) of
      {ok, _Pid} -> ok;
      {error, {already_started, _Pid}} ->
	  {error, {already_started, EndPoint}};
      {error, Error} -> {error, Error}
    end.

- spec ( { { delete_listener , 2 } , [ { type , 350 , 'fun' , [ { type , 350 , product , [ { type , 350 , endpoint , [ ] } , { type , 350 , module , [ ] } ] } , { type , 350 , union , [ { atom , 350 , ok } , { type , 350 , tuple , [ { atom , 350 , error } , { type , 350 , any , [ ] } ] } ] } ] } ] } ) .


delete_listener(EndPoint, Module) ->
    stop_listener(EndPoint, Module).

- spec ( { { config_reloaded , 0 } , [ { type , 354 , 'fun' , [ { type , 354 , product , [ ] } , { atom , 354 , ok } ] } ] } ) .


config_reloaded() ->
    New = ejabberd_config:get_option(listen, []),
    Old = ets:tab2list(?MODULE),
    lists:foreach(fun ({EndPoint, Module, _Opts}) ->
			  case lists:keyfind(EndPoint, 1, New) of
			    false -> stop_listener(EndPoint, Module);
			    _ -> ok
			  end
		  end,
		  Old),
    lists:foreach(fun ({EndPoint, Module, Opts}) ->
			  case lists:keyfind(EndPoint, 1, Old) of
			    {_, Module, Opts} -> ok;
			    {_, OldModule, _} ->
				stop_listener(EndPoint, OldModule),
				ets:insert(?MODULE, {EndPoint, Module, Opts}),
				start_listener(EndPoint, Module, Opts);
			    false ->
				ets:insert(?MODULE, {EndPoint, Module, Opts}),
				start_listener(EndPoint, Module, Opts)
			  end
		  end,
		  New).

- spec ( { { get_certfiles , 0 } , [ { type , 382 , 'fun' , [ { type , 382 , product , [ ] } , { type , 382 , list , [ { type , 382 , binary , [ ] } ] } ] } ] } ) .


get_certfiles() ->
    lists:filtermap(fun ({_, _, Opts}) ->
			    case proplists:get_value(certfile, Opts) of
			      undefined -> false;
			      Cert -> {true, Cert}
			    end
		    end,
		    ets:tab2list(?MODULE)).

- spec ( { { report_socket_error , 3 } , [ { type , 392 , 'fun' , [ { type , 392 , product , [ { remote_type , 392 , [ { atom , 392 , inet } , { atom , 392 , posix } , [ ] ] } , { type , 392 , endpoint , [ ] } , { type , 392 , module , [ ] } ] } , { atom , 392 , ok } ] } ] } ) .


report_socket_error(Reason, EndPoint, Module) ->
    ?ERROR_MSG("Failed to open socket at ~s for ~s: ~s",
	       [format_endpoint(EndPoint), Module,
		format_error(Reason)]).

- spec ( { { format_error , 1 } , [ { type , 397 , 'fun' , [ { type , 397 , product , [ { remote_type , 397 , [ { atom , 397 , inet } , { atom , 397 , posix } , [ ] ] } ] } , { type , 397 , string , [ ] } ] } ] } ) .


format_error(Reason) ->
    case inet:format_error(Reason) of
      "unknown POSIX error" -> atom_to_list(Reason);
      ReasonStr -> ReasonStr
    end.

- spec ( { { format_endpoint , 1 } , [ { type , 406 , 'fun' , [ { type , 406 , product , [ { type , 406 , endpoint , [ ] } ] } , { type , 406 , string , [ ] } ] } ] } ) .


format_endpoint({Port, IP, _Transport}) ->
    IPStr = case tuple_size(IP) of
	      4 -> inet:ntoa(IP);
	      8 -> "[" ++ inet:ntoa(IP) ++ "]"
	    end,
    IPStr ++ ":" ++ integer_to_list(Port).

- spec ( { { check_rate_limit , 1 } , [ { type , 414 , 'fun' , [ { type , 414 , product , [ { type , 414 , non_neg_integer , [ ] } ] } , { type , 414 , non_neg_integer , [ ] } ] } ] } ) .


check_rate_limit(Interval) ->
    NewInterval = receive
		    {rate_limit, AcceptInterval} -> AcceptInterval
		    after 0 -> Interval
		  end,
    case NewInterval of
      0 -> ok;
      Ms when is_integer(Ms) -> timer:sleep(Ms);
      {linear, I1, T1, T2, I2} ->
	  {MSec, Sec, _USec} = os:timestamp(),
	  TS = MSec * 1000000 + Sec,
	  I = if TS =< T1 -> I1;
		 TS >= T1 + T2 -> I2;
		 true -> round((I2 - I1) * (TS - T1) / T2 + I1)
	      end,
	  timer:sleep(I)
    end,
    NewInterval.

transform_option({{Port, IP, Transport}, Mod, Opts}) ->
    IPStr = if is_tuple(IP) ->
		   list_to_binary(inet_parse:ntoa(IP));
	       true -> IP
	    end,
    Opts1 = [transform_option_1(V1, IP) || V1 <- Opts],
    Opts2 = lists:foldl(fun (Opt, Acc) ->
				try Mod:transform_listen_option(Opt, Acc) catch
				  error:undef -> [Opt | Acc]
				end
			end,
			[], Opts1),
    TransportOpt = if Transport == tcp -> [];
		      true -> [{transport, Transport}]
		   end,
    IPOpt = if IPStr == <<"0.0.0.0">> -> [];
	       true -> [{ip, IPStr}]
	    end,
    IPOpt ++
      TransportOpt ++ [{port, Port}, {module, Mod} | Opts2];
transform_option({{Port, Transport}, Mod, Opts})
    when Transport == tcp orelse Transport == udp ->
    transform_option({{Port, all_zero_ip(Opts), Transport},
		      Mod, Opts});
transform_option({{Port, IP}, Mod, Opts}) ->
    transform_option({{Port, IP, tcp}, Mod, Opts});
transform_option({Port, Mod, Opts}) ->
    transform_option({{Port, all_zero_ip(Opts), tcp}, Mod,
		      Opts});
transform_option(Opt) -> Opt.

transform_option_1({ip, IPT}, IP) when is_tuple(IPT) ->
    {ip, list_to_binary(inet_parse:ntoa(IP))};
transform_option_1(ssl, IP) -> {tls, true};
transform_option_1(A, IP) when is_atom(A) -> {A, true};
transform_option_1(Opt, IP) -> Opt.

transform_options(Opts) ->
    lists:foldl(fun transform_options/2, [], Opts).

transform_options({listen, LOpts}, Opts) ->
    [{listen, [transform_option(V1) || V1 <- LOpts]}
     | Opts];
transform_options(Opt, Opts) -> [Opt | Opts].

- spec ( { { validate_cfg , 1 } , [ { type , 486 , 'fun' , [ { type , 486 , product , [ { type , 486 , list , [ ] } ] } , { type , 486 , list , [ { type , 486 , listener , [ ] } ] } ] } ] } ) .


validate_cfg(Listeners) ->
    Listeners1 = lists:map(fun validate_opts/1, Listeners),
    Listeners2 = lists:keysort(1, Listeners1),
    check_overlapping_listeners(Listeners2).

- spec ( { { validate_module , 1 } , [ { type , 492 , 'fun' , [ { type , 492 , product , [ { type , 492 , module , [ ] } ] } , { atom , 492 , ok } ] } ] } ) .


validate_module(Mod) ->
    case code:ensure_loaded(Mod) of
      {module, Mod} ->
	  lists:foreach(fun ({Fun, Arity}) ->
				case erlang:function_exported(Mod, Fun, Arity)
				    of
				  true -> ok;
				  false ->
				      ?ERROR_MSG("Failed to load listening module ~s, "
						 "because it doesn't export ~s/~B callback. "
						 "The module is either not a listening "
						 "module or it is a third-party module "
						 "which requires update",
						 [Mod, Fun, Arity]),
				      erlang:error(badarg)
				end
			end,
			[{start, 2}, {start_link, 2}, {accept, 1},
			 {listen_options, 0}]);
      _ ->
	  ?ERROR_MSG("Failed to load unknown listening module "
		     "~s: make sure there is no typo and ~s.beam "
		     "exists inside either ~s or ~s directory",
		     [Mod, Mod, filename:dirname(code:which(?MODULE)),
		      ext_mod:modules_dir()]),
	  erlang:error(badarg)
    end.

- spec ( { { validate_opts , 1 } , [ { type , 521 , 'fun' , [ { type , 521 , product , [ { type , 521 , listen_opts , [ ] } ] } , { type , 521 , listener , [ ] } ] } ] } ) .


validate_opts(Opts) ->
    case lists:keyfind(module, 1, Opts) of
      {_, Mod} ->
	  validate_module(Mod),
	  Opts1 = validate_opts(Mod, Opts),
	  {Opts2, Opts3} = lists:partition(fun ({port, _}) ->
						   true;
					       ({transport, _}) -> true;
					       ({module, _}) -> true;
					       (_) -> false
					   end,
					   Opts1),
	  Port = proplists:get_value(port, Opts2),
	  Transport = proplists:get_value(transport, Opts2, tcp),
	  IP = proplists:get_value(ip, Opts3, all_zero_ip(Opts3)),
	  {{Port, IP, Transport}, Mod, Opts3};
      false ->
	  ?ERROR_MSG("Missing required listening option: module",
		     []),
	  erlang:error(badarg)
    end.

- spec ( { { validate_opts , 2 } , [ { type , 542 , 'fun' , [ { type , 542 , product , [ { type , 542 , module , [ ] } , { type , 542 , listen_opts , [ ] } ] } , { type , 542 , listen_opts , [ ] } ] } ] } ) .


validate_opts(Mod, Opts) ->
    Defaults = listen_options() ++ Mod:listen_options(),
    {Opts1, Defaults1} = lists:mapfoldl(fun ({Opt, Val} =
						 OptVal,
					     Defs) ->
						case proplists:is_defined(Opt,
									  Defaults)
						    of
						  true ->
						      NewOptVal = case
								    lists:member(OptVal,
										 Defaults)
								      of
								    true -> [];
								    false ->
									[validate_module_opt(Mod,
											     Opt,
											     Val)]
								  end,
						      {NewOptVal,
						       proplists:delete(Opt,
									Defs)};
						  false ->
						      ?ERROR_MSG("Unknown listening option '~s' of module "
								 "~s; available options are: ~s",
								 [Opt, Mod,
								  misc:join_atoms(proplists:get_keys(Defaults),
										  <<", ">>)]),
						      erlang:error(badarg)
						end
					end,
					Defaults, Opts),
    case [V1 || V1 <- Defaults1, fun is_atom/1(V1)] of
      [] -> lists:flatten(Opts1);
      MissingRequiredOpts ->
	  ?ERROR_MSG("Missing required listening option(s): ~s",
		     [misc:join_atoms(MissingRequiredOpts, <<", ">>)]),
	  erlang:error(badarg)
    end.

- spec ( { { validate_module_opt , 3 } , [ { type , 574 , 'fun' , [ { type , 574 , product , [ { type , 574 , module , [ ] } , { type , 574 , atom , [ ] } , { type , 574 , any , [ ] } ] } , { type , 574 , tuple , [ { type , 574 , atom , [ ] } , { type , 574 , any , [ ] } ] } ] } ] } ) .


validate_module_opt(Module, Opt, Val) ->
    VFun = try Module:listen_opt_type(Opt) catch
	     _:_ -> listen_opt_type(Opt)
	   end,
    try {Opt, VFun(Val)} catch
      _:R when R /= undef ->
	  ?ERROR_MSG("Invalid value of listening option ~s: ~s",
		     [Opt, misc:format_val({yaml, Val})]),
	  erlang:error(badarg)
    end.

- spec ( { { all_zero_ip , 1 } , [ { type , 586 , 'fun' , [ { type , 586 , product , [ { type , 586 , listen_opts , [ ] } ] } , { remote_type , 586 , [ { atom , 586 , inet } , { atom , 586 , ip_address } , [ ] ] } ] } ] } ) .


all_zero_ip(Opts) ->
    case proplists:get_bool(inet6, Opts) of
      true -> {0, 0, 0, 0, 0, 0, 0, 0};
      false -> {0, 0, 0, 0}
    end.

- spec ( { { check_overlapping_listeners , 1 } , [ { type , 593 , 'fun' , [ { type , 593 , product , [ { type , 593 , list , [ { type , 593 , listener , [ ] } ] } ] } , { type , 593 , list , [ { type , 593 , listener , [ ] } ] } ] } ] } ) .


check_overlapping_listeners(Listeners) ->
    lists:foldl(fun ({{Port, IP, Transport} = Key, _, _},
		     Acc) ->
			case lists:member(Key, Acc) of
			  true ->
			      ?ERROR_MSG("Overlapping listeners found at ~s",
					 [format_endpoint(Key)]),
			      erlang:error(badarg);
			  false ->
			      ZeroIP = case size(IP) of
					 8 -> {0, 0, 0, 0, 0, 0, 0, 0};
					 4 -> {0, 0, 0, 0}
				       end,
			      Key1 = {Port, ZeroIP, Transport},
			      case lists:member(Key1, Acc) of
				true ->
				    ?ERROR_MSG("Overlapping listeners found at ~s and ~s",
					       [format_endpoint(Key),
						format_endpoint(Key1)]),
				    erlang:error(badarg);
				false -> [Key | Acc]
			      end
			end
		end,
		[], Listeners),
    Listeners.

listen_opt_type(port) ->
    fun (I) when is_integer(I), I > 0, I < 65536 -> I end;
listen_opt_type(module) ->
    fun (A) when is_atom(A) -> A end;
listen_opt_type(ip) ->
    fun (S) ->
	    {ok, Addr} = inet_parse:address(binary_to_list(S)), Addr
    end;
listen_opt_type(transport) ->
    fun (tcp) -> tcp;
	(udp) -> udp
    end;
listen_opt_type(accept_interval) ->
    fun (I) when is_integer(I), I >= 0 -> I end;
listen_opt_type(backlog) ->
    fun (I) when is_integer(I), I >= 0 -> I end;
listen_opt_type(inet) ->
    fun (B) when is_boolean(B) -> B end;
listen_opt_type(inet6) ->
    fun (B) when is_boolean(B) -> B end;
listen_opt_type(supervisor) ->
    fun (B) when is_boolean(B) -> B end;
listen_opt_type(certfile) ->
    fun (S) ->
	    {ok, File} = ejabberd_pkix:add_certfile(S), File
    end;
listen_opt_type(ciphers) -> fun iolist_to_binary/1;
listen_opt_type(dhfile) -> fun misc:try_read_file/1;
listen_opt_type(cafile) ->
    fun ejabberd_pkix:try_certfile/1;
listen_opt_type(protocol_options) ->
    fun (Options) -> str:join(Options, <<"|">>) end;
listen_opt_type(tls_compression) ->
    fun (B) when is_boolean(B) -> B end;
listen_opt_type(tls) ->
    fun (B) when is_boolean(B) -> B end;
listen_opt_type(max_stanza_size) ->
    fun (I) when is_integer(I), I > 0 -> I;
	(unlimited) -> infinity;
	(infinity) -> infinity
    end;
listen_opt_type(max_fsm_queue) ->
    fun (I) when is_integer(I), I > 0 -> I end;
listen_opt_type(shaper) ->
    fun acl:shaper_rules_validator/1;
listen_opt_type(access) ->
    fun acl:access_rules_validator/1.

listen_options() ->
    [module, port, {transport, tcp}, {ip, <<"0.0.0.0">>},
     {inet, true}, {inet6, false}, {accept_interval, 0},
     {backlog, 5}, {supervisor, true}].

opt_type(listen) -> fun validate_cfg/1;
opt_type(_) -> [listen].

%%%----------------------------------------------------------------------
%%% Some legacy code used by ejabberd_web_admin only
%%%----------------------------------------------------------------------
parse_listener_portip(PortIP, Opts) ->
    {IPOpt, Opts2} = strip_ip_option(Opts),
    {IPVOpt, OptsClean} = case proplists:get_bool(inet6,
						  Opts2)
			      of
			    true -> {inet6, proplists:delete(inet6, Opts2)};
			    false -> {inet, Opts2}
			  end,
    {Port, IPT, Proto} = case add_proto(PortIP, Opts) of
			   {P, Prot} ->
			       T = get_ip_tuple(IPOpt, IPVOpt), {P, T, Prot};
			   {P, T, Prot} when is_integer(P) and is_tuple(T) ->
			       {P, T, Prot};
			   {P, S, Prot} when is_integer(P) and is_binary(S) ->
			       {ok, T} = inet_parse:address(binary_to_list(S)),
			       {P, T, Prot}
			 end,
    IPV = case tuple_size(IPT) of
	    4 -> inet;
	    8 -> inet6
	  end,
    {Port, IPT, IPV, Proto, OptsClean}.

add_proto(Port, Opts) when is_integer(Port) ->
    {Port, get_proto(Opts)};
add_proto({Port, Proto}, _Opts) when is_atom(Proto) ->
    {Port, normalize_proto(Proto)};
add_proto({Port, Addr}, Opts) ->
    {Port, Addr, get_proto(Opts)};
add_proto({Port, Addr, Proto}, _Opts) ->
    {Port, Addr, normalize_proto(Proto)}.

strip_ip_option(Opts) ->
    {IPL, OptsNoIP} = lists:partition(fun ({ip, _}) -> true;
					  (_) -> false
				      end,
				      Opts),
    case IPL of
      %% Only the first ip option is considered
      [{ip, T1} | _] -> {T1, OptsNoIP};
      [] -> {no_ip_option, OptsNoIP}
    end.

get_ip_tuple(no_ip_option, inet) -> {0, 0, 0, 0};
get_ip_tuple(no_ip_option, inet6) ->
    {0, 0, 0, 0, 0, 0, 0, 0};
get_ip_tuple(IPOpt, _IPVOpt) -> IPOpt.

get_proto(Opts) ->
    case proplists:get_value(proto, Opts) of
      undefined -> tcp;
      Proto -> normalize_proto(Proto)
    end.

normalize_proto(udp) -> udp;
normalize_proto(_) -> tcp.

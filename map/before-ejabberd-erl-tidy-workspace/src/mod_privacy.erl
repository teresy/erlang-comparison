%%%----------------------------------------------------------------------
%%% File    : mod_privacy.erl
%%% Author  : Alexey Shchepin <alexey@process-one.net>
%%% Purpose : jabber:iq:privacy support
%%% Created : 21 Jul 2003 by Alexey Shchepin <alexey@process-one.net>
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

-module(mod_privacy).

-author('alexey@process-one.net').

-protocol({xep, 16, '1.6'}).

-behaviour(gen_mod).

-export([c2s_copy_session/2, check_packet/4, depends/2,
	 disco_features/5, encode_list_item/1, export/1,
	 get_user_list/3, get_user_lists/2, import/5,
	 import_info/0, import_start/2, import_stop/2,
	 mod_opt_type/1, mod_options/1, process_iq/1,
	 push_list_update/2, reload/3, remove_user/2,
	 set_default_list/3, set_list/1, set_list/4, start/2,
	 stop/1, user_receive_packet/1, user_send_packet/1]).

-include("logger.hrl").

-include("xmpp.hrl").

-include("mod_privacy.hrl").

-define(PRIVACY_CACHE, privacy_cache).

-define(PRIVACY_LIST_CACHE, privacy_list_cache).

-type({c2s_state,
       {remote_type, 50,
	[{atom, 50, ejabberd_c2s}, {atom, 50, state}, []]},
       []}).

- callback ( { { init , 2 } , [ { type , 51 , 'fun' , [ { type , 51 , product , [ { type , 51 , binary , [ ] } , { remote_type , 51 , [ { atom , 51 , gen_mod } , { atom , 51 , opts } , [ ] ] } ] } , { type , 51 , any , [ ] } ] } ] } ) .


- callback ( { { import , 1 } , [ { type , 52 , 'fun' , [ { type , 52 , product , [ { type , 52 , record , [ { atom , 52 , privacy } ] } ] } , { atom , 52 , ok } ] } ] } ) .


- callback ( { { set_default , 3 } , [ { type , 53 , 'fun' , [ { type , 53 , product , [ { type , 53 , binary , [ ] } , { type , 53 , binary , [ ] } , { type , 53 , binary , [ ] } ] } , { type , 54 , union , [ { atom , 54 , ok } , { type , 54 , tuple , [ { atom , 54 , error } , { type , 54 , union , [ { atom , 54 , notfound } , { type , 54 , any , [ ] } ] } ] } ] } ] } ] } ) .


- callback ( { { unset_default , 2 } , [ { type , 55 , 'fun' , [ { type , 55 , product , [ { type , 55 , binary , [ ] } , { type , 55 , binary , [ ] } ] } , { type , 55 , union , [ { atom , 55 , ok } , { type , 55 , tuple , [ { atom , 55 , error } , { type , 55 , any , [ ] } ] } ] } ] } ] } ) .


- callback ( { { remove_list , 3 } , [ { type , 56 , 'fun' , [ { type , 56 , product , [ { type , 56 , binary , [ ] } , { type , 56 , binary , [ ] } , { type , 56 , binary , [ ] } ] } , { type , 57 , union , [ { atom , 57 , ok } , { type , 57 , tuple , [ { atom , 57 , error } , { type , 57 , union , [ { atom , 57 , notfound } , { atom , 57 , conflict } , { type , 57 , any , [ ] } ] } ] } ] } ] } ] } ) .


- callback ( { { remove_lists , 2 } , [ { type , 58 , 'fun' , [ { type , 58 , product , [ { type , 58 , binary , [ ] } , { type , 58 , binary , [ ] } ] } , { type , 58 , union , [ { atom , 58 , ok } , { type , 58 , tuple , [ { atom , 58 , error } , { type , 58 , any , [ ] } ] } ] } ] } ] } ) .


- callback ( { { set_lists , 1 } , [ { type , 59 , 'fun' , [ { type , 59 , product , [ { type , 59 , record , [ { atom , 59 , privacy } ] } ] } , { type , 59 , union , [ { atom , 59 , ok } , { type , 59 , tuple , [ { atom , 59 , error } , { type , 59 , any , [ ] } ] } ] } ] } ] } ) .


- callback ( { { set_list , 4 } , [ { type , 60 , 'fun' , [ { type , 60 , product , [ { type , 60 , binary , [ ] } , { type , 60 , binary , [ ] } , { type , 60 , binary , [ ] } , { type , 60 , listitem , [ ] } ] } , { type , 61 , union , [ { atom , 61 , ok } , { type , 61 , tuple , [ { atom , 61 , error } , { type , 61 , any , [ ] } ] } ] } ] } ] } ) .


- callback ( { { get_list , 3 } , [ { type , 62 , 'fun' , [ { type , 62 , product , [ { type , 62 , binary , [ ] } , { type , 62 , binary , [ ] } , { type , 62 , union , [ { type , 62 , binary , [ ] } , { atom , 62 , default } ] } ] } , { type , 63 , union , [ { type , 63 , tuple , [ { atom , 63 , ok } , { type , 63 , tuple , [ { type , 63 , binary , [ ] } , { type , 63 , list , [ { type , 63 , listitem , [ ] } ] } ] } ] } , { atom , 63 , error } , { type , 63 , tuple , [ { atom , 63 , error } , { type , 63 , any , [ ] } ] } ] } ] } ] } ) .


- callback ( { { get_lists , 2 } , [ { type , 64 , 'fun' , [ { type , 64 , product , [ { type , 64 , binary , [ ] } , { type , 64 , binary , [ ] } ] } , { type , 65 , union , [ { type , 65 , tuple , [ { atom , 65 , ok } , { type , 65 , record , [ { atom , 65 , privacy } ] } ] } , { atom , 65 , error } , { type , 65 , tuple , [ { atom , 65 , error } , { type , 65 , any , [ ] } ] } ] } ] } ] } ) .


- callback ( { { use_cache , 1 } , [ { type , 66 , 'fun' , [ { type , 66 , product , [ { type , 66 , binary , [ ] } ] } , { type , 66 , boolean , [ ] } ] } ] } ) .


- callback ( { { cache_nodes , 1 } , [ { type , 67 , 'fun' , [ { type , 67 , product , [ { type , 67 , binary , [ ] } ] } , { type , 67 , list , [ { type , 67 , node , [ ] } ] } ] } ] } ) .


-optional_callbacks([{use_cache, 1}, {cache_nodes, 1}]).

start(Host, Opts) ->
    Mod = gen_mod:db_mod(Host, Opts, ?MODULE),
    Mod:init(Host, Opts),
    init_cache(Mod, Host, Opts),
    ejabberd_hooks:add(disco_local_features, Host, ?MODULE,
		       disco_features, 50),
    ejabberd_hooks:add(c2s_copy_session, Host, ?MODULE,
		       c2s_copy_session, 50),
    ejabberd_hooks:add(user_send_packet, Host, ?MODULE,
		       user_send_packet, 50),
    ejabberd_hooks:add(user_receive_packet, Host, ?MODULE,
		       user_receive_packet, 50),
    ejabberd_hooks:add(privacy_check_packet, Host, ?MODULE,
		       check_packet, 50),
    ejabberd_hooks:add(remove_user, Host, ?MODULE,
		       remove_user, 50),
    gen_iq_handler:add_iq_handler(ejabberd_sm, Host,
				  ?NS_PRIVACY, ?MODULE, process_iq).

stop(Host) ->
    ejabberd_hooks:delete(disco_local_features, Host,
			  ?MODULE, disco_features, 50),
    ejabberd_hooks:delete(c2s_copy_session, Host, ?MODULE,
			  c2s_copy_session, 50),
    ejabberd_hooks:delete(user_send_packet, Host, ?MODULE,
			  user_send_packet, 50),
    ejabberd_hooks:delete(user_receive_packet, Host,
			  ?MODULE, user_receive_packet, 50),
    ejabberd_hooks:delete(privacy_check_packet, Host,
			  ?MODULE, check_packet, 50),
    ejabberd_hooks:delete(remove_user, Host, ?MODULE,
			  remove_user, 50),
    gen_iq_handler:remove_iq_handler(ejabberd_sm, Host,
				     ?NS_PRIVACY).

reload(Host, NewOpts, OldOpts) ->
    NewMod = gen_mod:db_mod(Host, NewOpts, ?MODULE),
    OldMod = gen_mod:db_mod(Host, OldOpts, ?MODULE),
    if NewMod /= OldMod -> NewMod:init(Host, NewOpts);
       true -> ok
    end,
    init_cache(NewMod, Host, NewOpts).

- spec ( { { disco_features , 5 } , [ { type , 116 , 'fun' , [ { type , 116 , product , [ { type , 116 , union , [ { type , 116 , tuple , [ { atom , 116 , error } , { type , 116 , stanza_error , [ ] } ] } , { type , 116 , tuple , [ { atom , 116 , result } , { type , 116 , list , [ { type , 116 , binary , [ ] } ] } ] } , { atom , 116 , empty } ] } , { type , 117 , jid , [ ] } , { type , 117 , jid , [ ] } , { type , 117 , binary , [ ] } , { type , 117 , binary , [ ] } ] } , { type , 118 , union , [ { type , 118 , tuple , [ { atom , 118 , error } , { type , 118 , stanza_error , [ ] } ] } , { type , 118 , tuple , [ { atom , 118 , result } , { type , 118 , list , [ { type , 118 , binary , [ ] } ] } ] } ] } ] } ] } ) .


disco_features({error, Err}, _From, _To, _Node,
	       _Lang) ->
    {error, Err};
disco_features(empty, _From, _To, <<"">>, _Lang) ->
    {result, [?NS_PRIVACY]};
disco_features({result, Feats}, _From, _To, <<"">>,
	       _Lang) ->
    {result, [?NS_PRIVACY | Feats]};
disco_features(Acc, _From, _To, _Node, _Lang) -> Acc.

- spec ( { { process_iq , 1 } , [ { type , 128 , 'fun' , [ { type , 128 , product , [ { type , 128 , iq , [ ] } ] } , { type , 128 , iq , [ ] } ] } ] } ) .


process_iq(#iq{type = Type,
	       from = #jid{luser = U, lserver = S},
	       to = #jid{luser = U, lserver = S}} =
	       IQ) ->
    case Type of
      get -> process_iq_get(IQ);
      set -> process_iq_set(IQ)
    end;
process_iq(#iq{lang = Lang} = IQ) ->
    Txt = <<"Query to another users is forbidden">>,
    xmpp:make_error(IQ, xmpp:err_forbidden(Txt, Lang)).

- spec ( { { process_iq_get , 1 } , [ { type , 140 , 'fun' , [ { type , 140 , product , [ { type , 140 , iq , [ ] } ] } , { type , 140 , iq , [ ] } ] } ] } ) .


process_iq_get(#iq{lang = Lang,
		   sub_els =
		       [#privacy_query{default = Default, active = Active}]} =
		   IQ)
    when Default /= undefined; Active /= undefined ->
    Txt = <<"Only <list/> element is allowed in this "
	    "query">>,
    xmpp:make_error(IQ, xmpp:err_bad_request(Txt, Lang));
process_iq_get(#iq{lang = Lang,
		   sub_els = [#privacy_query{lists = Lists}]} =
		   IQ) ->
    case Lists of
      [] -> process_lists_get(IQ);
      [#privacy_list{name = ListName}] ->
	  process_list_get(IQ, ListName);
      _ ->
	  Txt = <<"Too many <list/> elements">>,
	  xmpp:make_error(IQ, xmpp:err_bad_request(Txt, Lang))
    end;
process_iq_get(#iq{lang = Lang} = IQ) ->
    Txt = <<"No module is handling this query">>,
    xmpp:make_error(IQ,
		    xmpp:err_service_unavailable(Txt, Lang)).

- spec ( { { process_lists_get , 1 } , [ { type , 162 , 'fun' , [ { type , 162 , product , [ { type , 162 , iq , [ ] } ] } , { type , 162 , iq , [ ] } ] } ] } ) .


process_lists_get(#iq{from =
			  #jid{luser = LUser, lserver = LServer},
		      lang = Lang} =
		      IQ) ->
    case get_user_lists(LUser, LServer) of
      {ok, #privacy{default = Default, lists = Lists}} ->
	  Active = xmpp:get_meta(IQ, privacy_active_list, none),
	  xmpp:make_iq_result(IQ,
			      #privacy_query{active = Active, default = Default,
					     lists =
						 [#privacy_list{name = Name}
						  || {Name, _} <- Lists]});
      error ->
	  xmpp:make_iq_result(IQ,
			      #privacy_query{active = none, default = none});
      {error, _} ->
	  Txt = <<"Database failure">>,
	  xmpp:make_error(IQ,
			  xmpp:err_internal_server_error(Txt, Lang))
    end.

- spec ( { { process_list_get , 2 } , [ { type , 181 , 'fun' , [ { type , 181 , product , [ { type , 181 , iq , [ ] } , { type , 181 , binary , [ ] } ] } , { type , 181 , iq , [ ] } ] } ] } ) .


process_list_get(#iq{from =
			 #jid{luser = LUser, lserver = LServer},
		     lang = Lang} =
		     IQ,
		 Name) ->
    case get_user_list(LUser, LServer, Name) of
      {ok, {_, List}} ->
	  Items = [encode_list_item(V1) || V1 <- List],
	  xmpp:make_iq_result(IQ,
			      #privacy_query{lists =
						 [#privacy_list{name = Name,
								items =
								    Items}]});
      error ->
	  Txt = <<"No privacy list with this name found">>,
	  xmpp:make_error(IQ, xmpp:err_item_not_found(Txt, Lang));
      {error, _} ->
	  Txt = <<"Database failure">>,
	  xmpp:make_error(IQ,
			  xmpp:err_internal_server_error(Txt, Lang))
    end.

- spec ( { { encode_list_item , 1 } , [ { type , 199 , 'fun' , [ { type , 199 , product , [ { type , 199 , listitem , [ ] } ] } , { type , 199 , privacy_item , [ ] } ] } ] } ) .


encode_list_item(#listitem{action = Action,
			   order = Order, type = Type, match_all = MatchAll,
			   match_iq = MatchIQ, match_message = MatchMessage,
			   match_presence_in = MatchPresenceIn,
			   match_presence_out = MatchPresenceOut,
			   value = Value}) ->
    Item = #privacy_item{action = Action, order = Order,
			 type =
			     case Type of
			       none -> undefined;
			       Type -> Type
			     end,
			 value = encode_value(Type, Value)},
    case MatchAll of
      true -> Item;
      false ->
	  Item#privacy_item{message = MatchMessage, iq = MatchIQ,
			    presence_in = MatchPresenceIn,
			    presence_out = MatchPresenceOut}
    end.

- spec ( { { encode_value , 2 } , [ { type , 226 , 'fun' , [ { type , 226 , product , [ { type , 226 , listitem_type , [ ] } , { type , 226 , listitem_value , [ ] } ] } , { type , 226 , binary , [ ] } ] } ] } ) .


encode_value(Type, Val) ->
    case Type of
      jid -> jid:encode(Val);
      group -> Val;
      subscription ->
	  case Val of
	    both -> <<"both">>;
	    to -> <<"to">>;
	    from -> <<"from">>;
	    none -> <<"none">>
	  end;
      none -> <<"">>
    end.

- spec ( { { decode_value , 2 } , [ { type , 241 , 'fun' , [ { type , 241 , product , [ { type , 241 , union , [ { atom , 241 , jid } , { atom , 241 , subscription } , { atom , 241 , group } , { atom , 241 , undefined } ] } , { type , 241 , binary , [ ] } ] } , { type , 242 , listitem_value , [ ] } ] } ] } ) .


decode_value(Type, Value) ->
    case Type of
      jid -> jid:tolower(jid:decode(Value));
      subscription ->
	  case Value of
	    <<"from">> -> from;
	    <<"to">> -> to;
	    <<"both">> -> both;
	    <<"none">> -> none
	  end;
      group when Value /= <<"">> -> Value;
      undefined -> none
    end.

- spec ( { { process_iq_set , 1 } , [ { type , 257 , 'fun' , [ { type , 257 , product , [ { type , 257 , iq , [ ] } ] } , { type , 257 , iq , [ ] } ] } ] } ) .


process_iq_set(#iq{lang = Lang,
		   sub_els =
		       [#privacy_query{default = Default, active = Active,
				       lists = Lists}]} =
		   IQ) ->
    case Lists of
      [#privacy_list{items = Items, name = ListName}]
	  when Default == undefined, Active == undefined ->
	  process_lists_set(IQ, ListName, Items);
      [] when Default == undefined, Active /= undefined ->
	  process_active_set(IQ, Active);
      [] when Active == undefined, Default /= undefined ->
	  process_default_set(IQ, Default);
      _ ->
	  Txt = <<"The stanza MUST contain only one <active/> "
		  "element, one <default/> element, or "
		  "one <list/> element">>,
	  xmpp:make_error(IQ, xmpp:err_bad_request(Txt, Lang))
    end;
process_iq_set(#iq{lang = Lang} = IQ) ->
    Txt = <<"No module is handling this query">>,
    xmpp:make_error(IQ,
		    xmpp:err_service_unavailable(Txt, Lang)).

- spec ( { { process_default_set , 2 } , [ { type , 279 , 'fun' , [ { type , 279 , product , [ { type , 279 , iq , [ ] } , { type , 279 , union , [ { atom , 279 , none } , { type , 279 , binary , [ ] } ] } ] } , { type , 279 , iq , [ ] } ] } ] } ) .


process_default_set(#iq{from =
			    #jid{luser = LUser, lserver = LServer},
			lang = Lang} =
			IQ,
		    Value) ->
    case set_default_list(LUser, LServer, Value) of
      ok -> xmpp:make_iq_result(IQ);
      {error, notfound} ->
	  Txt = <<"No privacy list with this name found">>,
	  xmpp:make_error(IQ, xmpp:err_item_not_found(Txt, Lang));
      {error, _} ->
	  Txt = <<"Database failure">>,
	  xmpp:make_error(IQ,
			  xmpp:err_internal_server_error(Txt, Lang))
    end.

- spec ( { { process_active_set , 2 } , [ { type , 293 , 'fun' , [ { type , 293 , product , [ { var , 293 , 'IQ' } , { type , 293 , union , [ { atom , 293 , none } , { type , 293 , binary , [ ] } ] } ] } , { var , 293 , 'IQ' } ] } ] } ) .


process_active_set(IQ, none) ->
    xmpp:make_iq_result(xmpp:put_meta(IQ,
				      privacy_active_list, none));
process_active_set(#iq{from =
			   #jid{luser = LUser, lserver = LServer},
		       lang = Lang} =
		       IQ,
		   Name) ->
    case get_user_list(LUser, LServer, Name) of
      {ok, _} ->
	  xmpp:make_iq_result(xmpp:put_meta(IQ,
					    privacy_active_list, Name));
      error ->
	  Txt = <<"No privacy list with this name found">>,
	  xmpp:make_error(IQ, xmpp:err_item_not_found(Txt, Lang));
      {error, _} ->
	  Txt = <<"Database failure">>,
	  xmpp:make_error(IQ,
			  xmpp:err_internal_server_error(Txt, Lang))
    end.

- spec ( { { set_list , 1 } , [ { type , 309 , 'fun' , [ { type , 309 , product , [ { type , 309 , privacy , [ ] } ] } , { type , 309 , union , [ { atom , 309 , ok } , { type , 309 , tuple , [ { atom , 309 , error } , { type , 309 , any , [ ] } ] } ] } ] } ] } ) .


set_list(#privacy{us = {LUser, LServer},
		  lists = Lists} =
	     Privacy) ->
    Mod = gen_mod:db_mod(LServer, ?MODULE),
    case Mod:set_lists(Privacy) of
      ok ->
	  Names = [Name || {Name, _} <- Lists],
	  delete_cache(Mod, LUser, LServer, Names);
      {error, _} = Err -> Err
    end.

- spec ( { { process_lists_set , 3 } , [ { type , 320 , 'fun' , [ { type , 320 , product , [ { type , 320 , iq , [ ] } , { type , 320 , binary , [ ] } , { type , 320 , list , [ { type , 320 , privacy_item , [ ] } ] } ] } , { type , 320 , iq , [ ] } ] } ] } ) .


process_lists_set(#iq{from =
			  #jid{luser = LUser, lserver = LServer},
		      lang = Lang} =
		      IQ,
		  Name, []) ->
    case xmpp:get_meta(IQ, privacy_active_list, none) of
      Name ->
	  Txt = <<"Cannot remove active list">>,
	  xmpp:make_error(IQ, xmpp:err_conflict(Txt, Lang));
      _ ->
	  case remove_list(LUser, LServer, Name) of
	    ok -> xmpp:make_iq_result(IQ);
	    {error, conflict} ->
		Txt = <<"Cannot remove default list">>,
		xmpp:make_error(IQ, xmpp:err_conflict(Txt, Lang));
	    {error, notfound} ->
		Txt = <<"No privacy list with this name found">>,
		xmpp:make_error(IQ, xmpp:err_item_not_found(Txt, Lang));
	    {error, _} ->
		Txt = <<"Database failure">>,
		Err = xmpp:err_internal_server_error(Txt, Lang),
		xmpp:make_error(IQ, Err)
	  end
    end;
process_lists_set(#iq{from =
			  #jid{luser = LUser, lserver = LServer} = From,
		      lang = Lang} =
		      IQ,
		  Name, Items) ->
    case catch [decode_item(V1) || V1 <- Items] of
      {error, Why} ->
	  Txt = xmpp:io_format_error(Why),
	  xmpp:make_error(IQ, xmpp:err_bad_request(Txt, Lang));
      List ->
	  case set_list(LUser, LServer, Name, List) of
	    ok ->
		push_list_update(From, Name), xmpp:make_iq_result(IQ);
	    {error, _} ->
		Txt = <<"Database failure">>,
		xmpp:make_error(IQ,
				xmpp:err_internal_server_error(Txt, Lang))
	  end
    end.

- spec ( { { push_list_update , 2 } , [ { type , 360 , 'fun' , [ { type , 360 , product , [ { type , 360 , jid , [ ] } , { type , 360 , binary , [ ] } ] } , { atom , 360 , ok } ] } ] } ) .


push_list_update(From, Name) ->
    BareFrom = jid:remove_resource(From),
    lists:foreach(fun (R) ->
			  To = jid:replace_resource(From, R),
			  IQ = #iq{type = set, from = BareFrom, to = To,
				   id =
				       <<"push",
					 (p1_rand:get_string())/binary>>,
				   sub_els =
				       [#privacy_query{lists =
							   [#privacy_list{name =
									      Name}]}]},
			  ejabberd_router:route(IQ)
		  end,
		  ejabberd_sm:get_user_resources(From#jid.luser,
						 From#jid.lserver)).

- spec ( { { decode_item , 1 } , [ { type , 373 , 'fun' , [ { type , 373 , product , [ { type , 373 , privacy_item , [ ] } ] } , { type , 373 , listitem , [ ] } ] } ] } ) .


decode_item(#privacy_item{order = Order,
			  action = Action, type = T, value = V,
			  message = MatchMessage, iq = MatchIQ,
			  presence_in = MatchPresenceIn,
			  presence_out = MatchPresenceOut}) ->
    Value = try decode_value(T, V) catch
	      _:_ ->
		  throw({error,
			 {bad_attr_value, <<"value">>, <<"item">>,
			  ?NS_PRIVACY}})
	    end,
    Type = case T of
	     undefined -> none;
	     _ -> T
	   end,
    ListItem = #listitem{order = Order, action = Action,
			 type = Type, value = Value},
    if not
	 (MatchMessage or MatchIQ or MatchPresenceIn or
	    MatchPresenceOut) ->
	   ListItem#listitem{match_all = true};
       true ->
	   ListItem#listitem{match_iq = MatchIQ,
			     match_message = MatchMessage,
			     match_presence_in = MatchPresenceIn,
			     match_presence_out = MatchPresenceOut}
    end.

- spec ( { { c2s_copy_session , 2 } , [ { type , 404 , 'fun' , [ { type , 404 , product , [ { type , 404 , c2s_state , [ ] } , { type , 404 , c2s_state , [ ] } ] } , { type , 404 , c2s_state , [ ] } ] } ] } ) .


c2s_copy_session ( State , # { privacy_active_list : = List } ) -> State # { privacy_active_list = > List } ; c2s_copy_session ( State , _ ) -> State .


- spec ( { { user_send_packet , 1 } , [ { type , 410 , 'fun' , [ { type , 410 , product , [ { type , 410 , tuple , [ { type , 410 , stanza , [ ] } , { type , 410 , c2s_state , [ ] } ] } ] } , { type , 410 , tuple , [ { type , 410 , stanza , [ ] } , { type , 410 , c2s_state , [ ] } ] } ] } ] } ) .


user_send_packet ( { # iq { type = Type , to = # jid { luser = U , lserver = S , lresource = << "" >> } , from = # jid { luser = U , lserver = S } , sub_els = [ _ ] } = IQ , # { privacy_active_list : = Name } = State } ) when Type == get ; Type == set -> NewIQ = case xmpp : has_subtag ( IQ , # privacy_query { } ) of true -> xmpp : put_meta ( IQ , privacy_active_list , Name ) ; false -> IQ end , { NewIQ , State } ; user_send_packet ( Acc ) -> Acc .


- spec ( { { user_receive_packet , 1 } , [ { type , 425 , 'fun' , [ { type , 425 , product , [ { type , 425 , tuple , [ { type , 425 , stanza , [ ] } , { type , 425 , c2s_state , [ ] } ] } ] } , { type , 425 , tuple , [ { type , 425 , stanza , [ ] } , { type , 425 , c2s_state , [ ] } ] } ] } ] } ) .


user_receive_packet ( { # iq { type = result , meta = # { privacy_active_list : = Name } } = IQ , State } ) -> { IQ , State # { privacy_active_list = > Name } } ; user_receive_packet ( Acc ) -> Acc .


- spec ( { { set_list , 4 } , [ { type , 432 , 'fun' , [ { type , 432 , product , [ { type , 432 , binary , [ ] } , { type , 432 , binary , [ ] } , { type , 432 , binary , [ ] } , { type , 432 , list , [ { type , 432 , listitem , [ ] } ] } ] } , { type , 432 , union , [ { atom , 432 , ok } , { type , 432 , tuple , [ { atom , 432 , error } , { type , 432 , any , [ ] } ] } ] } ] } ] } ) .


set_list(LUser, LServer, Name, List) ->
    Mod = gen_mod:db_mod(LServer, ?MODULE),
    case Mod:set_list(LUser, LServer, Name, List) of
      ok -> delete_cache(Mod, LUser, LServer, [Name]);
      {error, _} = Err -> Err
    end.

- spec ( { { remove_list , 3 } , [ { type , 442 , 'fun' , [ { type , 442 , product , [ { type , 442 , binary , [ ] } , { type , 442 , binary , [ ] } , { type , 442 , binary , [ ] } ] } , { type , 443 , union , [ { atom , 443 , ok } , { type , 443 , tuple , [ { atom , 443 , error } , { type , 443 , union , [ { atom , 443 , conflict } , { atom , 443 , notfound } , { type , 443 , any , [ ] } ] } ] } ] } ] } ] } ) .


remove_list(LUser, LServer, Name) ->
    Mod = gen_mod:db_mod(LServer, ?MODULE),
    case Mod:remove_list(LUser, LServer, Name) of
      ok -> delete_cache(Mod, LUser, LServer, [Name]);
      Err -> Err
    end.

- spec ( { { get_user_lists , 2 } , [ { type , 453 , 'fun' , [ { type , 453 , product , [ { type , 453 , binary , [ ] } , { type , 453 , binary , [ ] } ] } , { type , 453 , union , [ { type , 453 , tuple , [ { atom , 453 , ok } , { type , 453 , privacy , [ ] } ] } , { atom , 453 , error } , { type , 453 , tuple , [ { atom , 453 , error } , { type , 453 , any , [ ] } ] } ] } ] } ] } ) .


get_user_lists(User, Server) ->
    LUser = jid:nodeprep(User),
    LServer = jid:nameprep(Server),
    Mod = gen_mod:db_mod(LServer, ?MODULE),
    case use_cache(Mod, LServer) of
      true ->
	  ets_cache:lookup(?PRIVACY_CACHE, {LUser, LServer},
			   fun () -> Mod:get_lists(LUser, LServer) end);
      false -> Mod:get_lists(LUser, LServer)
    end.

- spec ( { { get_user_list , 3 } , [ { type , 467 , 'fun' , [ { type , 467 , product , [ { type , 467 , binary , [ ] } , { type , 467 , binary , [ ] } , { type , 467 , union , [ { type , 467 , binary , [ ] } , { atom , 467 , default } ] } ] } , { type , 468 , union , [ { type , 468 , tuple , [ { atom , 468 , ok } , { type , 468 , tuple , [ { type , 468 , binary , [ ] } , { type , 468 , list , [ { type , 468 , listitem , [ ] } ] } ] } ] } , { atom , 468 , error } , { type , 468 , tuple , [ { atom , 468 , error } , { type , 468 , any , [ ] } ] } ] } ] } ] } ) .


get_user_list(LUser, LServer, Name) ->
    Mod = gen_mod:db_mod(LServer, ?MODULE),
    case use_cache(Mod, LServer) of
      true ->
	  ets_cache:lookup(?PRIVACY_LIST_CACHE,
			   {LUser, LServer, Name},
			   fun () ->
				   case ets_cache:lookup(?PRIVACY_CACHE,
							 {LUser, LServer})
				       of
				     {ok, Privacy} ->
					 get_list_by_name(Privacy, Name);
				     error -> Mod:get_list(LUser, LServer, Name)
				   end
			   end);
      false -> Mod:get_list(LUser, LServer, Name)
    end.

- spec ( { { get_list_by_name , 2 } , [ { type , 488 , 'fun' , [ { type , 488 , product , [ { type , 488 , record , [ { atom , 488 , privacy } ] } , { type , 488 , union , [ { type , 488 , binary , [ ] } , { atom , 488 , default } ] } ] } , { type , 489 , union , [ { type , 489 , tuple , [ { atom , 489 , ok } , { type , 489 , tuple , [ { type , 489 , binary , [ ] } , { type , 489 , list , [ { type , 489 , listitem , [ ] } ] } ] } ] } , { atom , 489 , error } ] } ] } ] } ) .


get_list_by_name(#privacy{default = Default} = Privacy,
		 default) ->
    get_list_by_name(Privacy, Default);
get_list_by_name(#privacy{lists = Lists}, Name) ->
    case lists:keyfind(Name, 1, Lists) of
      {_, List} -> {ok, {Name, List}};
      false -> error
    end.

- spec ( { { set_default_list , 3 } , [ { type , 498 , 'fun' , [ { type , 498 , product , [ { type , 498 , binary , [ ] } , { type , 498 , binary , [ ] } , { type , 498 , union , [ { type , 498 , binary , [ ] } , { atom , 498 , none } ] } ] } , { type , 499 , union , [ { atom , 499 , ok } , { type , 499 , tuple , [ { atom , 499 , error } , { type , 499 , union , [ { atom , 499 , notfound } , { type , 499 , any , [ ] } ] } ] } ] } ] } ] } ) .


set_default_list(LUser, LServer, Name) ->
    Mod = gen_mod:db_mod(LServer, ?MODULE),
    Res = case Name of
	    none -> Mod:unset_default(LUser, LServer);
	    _ -> Mod:set_default(LUser, LServer, Name)
	  end,
    case Res of
      ok -> delete_cache(Mod, LUser, LServer, []);
      Err -> Err
    end.

- spec ( { { check_packet , 4 } , [ { type , 513 , 'fun' , [ { type , 513 , product , [ { type , 513 , union , [ { atom , 513 , allow } , { atom , 513 , deny } ] } , { type , 513 , union , [ { type , 513 , c2s_state , [ ] } , { type , 513 , jid , [ ] } ] } , { type , 513 , stanza , [ ] } , { type , 513 , union , [ { atom , 513 , in } , { atom , 513 , out } ] } ] } , { type , 513 , union , [ { atom , 513 , allow } , { atom , 513 , deny } ] } ] } ] } ) .


check_packet ( Acc , # { jid : = JID } = State , Packet , Dir ) -> case maps : get ( privacy_active_list , State , none ) of none -> check_packet ( Acc , JID , Packet , Dir ) ; ListName -> # jid { luser = LUser , lserver = LServer } = JID , case get_user_list ( LUser , LServer , ListName ) of { ok , { _ , List } } -> do_check_packet ( JID , List , Packet , Dir ) ; _ -> ? DEBUG ( "Non-existing active list '~s' is set " "for user '~s'" , [ ListName , jid : encode ( JID ) ] ) , check_packet ( Acc , JID , Packet , Dir ) end end ; check_packet ( _ , JID , Packet , Dir ) -> # jid { luser = LUser , lserver = LServer } = JID , case get_user_list ( LUser , LServer , default ) of { ok , { _ , List } } -> do_check_packet ( JID , List , Packet , Dir ) ; _ -> allow end .


%% From is the sender, To is the destination.
%% If Dir = out, User@Server is the sender account (From).
%% If Dir = in, User@Server is the destination account (To).
- spec ( { { do_check_packet , 4 } , [ { type , 541 , 'fun' , [ { type , 541 , product , [ { type , 541 , jid , [ ] } , { type , 541 , list , [ { type , 541 , listitem , [ ] } ] } , { type , 541 , stanza , [ ] } , { type , 541 , union , [ { atom , 541 , in } , { atom , 541 , out } ] } ] } , { type , 541 , union , [ { atom , 541 , allow } , { atom , 541 , deny } ] } ] } ] } ) .


do_check_packet(_, [], _, _) -> allow;
do_check_packet(#jid{luser = LUser, lserver = LServer},
		List, Packet, Dir) ->
    From = xmpp:get_from(Packet),
    To = xmpp:get_to(Packet),
    case {From, To} of
      {#jid{luser = <<"">>, lserver = LServer},
       #jid{lserver = LServer}}
	  when Dir == in ->
	  %% Allow any packets from local server
	  allow;
      {#jid{lserver = LServer},
       #jid{luser = <<"">>, lserver = LServer}}
	  when Dir == out ->
	  %% Allow any packets to local server
	  allow;
      {#jid{luser = LUser, lserver = LServer,
	    lresource = <<"">>},
       #jid{luser = LUser, lserver = LServer}}
	  when Dir == in ->
	  %% Allow incoming packets from user's bare jid to his full jid
	  allow;
      {#jid{luser = LUser, lserver = LServer},
       #jid{luser = LUser, lserver = LServer,
	    lresource = <<"">>}}
	  when Dir == out ->
	  %% Allow outgoing packets from user's full jid to his bare JID
	  allow;
      _ ->
	  PType = case Packet of
		    #message{} -> message;
		    #iq{} -> iq;
		    #presence{type = available} -> presence;
		    #presence{type = unavailable} -> presence;
		    _ -> other
		  end,
	  PType2 = case {PType, Dir} of
		     {message, in} -> message;
		     {iq, in} -> iq;
		     {presence, in} -> presence_in;
		     {presence, out} -> presence_out;
		     {_, _} -> other
		   end,
	  LJID = case Dir of
		   in -> jid:tolower(From);
		   out -> jid:tolower(To)
		 end,
	  {Subscription, _Ask, Groups} =
	      ejabberd_hooks:run_fold(roster_get_jid_info, LServer,
				      {none, none, []}, [LUser, LServer, LJID]),
	  check_packet_aux(List, PType2, LJID, Subscription,
			   Groups)
    end.

- spec ( { { check_packet_aux , 5 } , [ { type , 590 , 'fun' , [ { type , 590 , product , [ { type , 590 , list , [ { type , 590 , listitem , [ ] } ] } , { type , 591 , union , [ { atom , 591 , message } , { atom , 591 , iq } , { atom , 591 , presence_in } , { atom , 591 , presence_out } , { atom , 591 , other } ] } , { type , 592 , ljid , [ ] } , { type , 592 , union , [ { atom , 592 , none } , { atom , 592 , both } , { atom , 592 , from } , { atom , 592 , to } ] } , { type , 592 , list , [ { type , 592 , binary , [ ] } ] } ] } , { type , 593 , union , [ { atom , 593 , allow } , { atom , 593 , deny } ] } ] } ] } ) .


%% Ptype = mesage | iq | presence_in | presence_out | other
check_packet_aux([], _PType, _JID, _Subscription,
		 _Groups) ->
    allow;
check_packet_aux([Item | List], PType, JID,
		 Subscription, Groups) ->
    #listitem{type = Type, value = Value, action = Action} =
	Item,
    case is_ptype_match(Item, PType) of
      true ->
	  case is_type_match(Type, Value, JID, Subscription,
			     Groups)
	      of
	    true -> Action;
	    false ->
		check_packet_aux(List, PType, JID, Subscription, Groups)
	  end;
      false ->
	  check_packet_aux(List, PType, JID, Subscription, Groups)
    end.

- spec ( { { is_ptype_match , 2 } , [ { type , 613 , 'fun' , [ { type , 613 , product , [ { type , 613 , listitem , [ ] } , { type , 614 , union , [ { atom , 614 , message } , { atom , 614 , iq } , { atom , 614 , presence_in } , { atom , 614 , presence_out } , { atom , 614 , other } ] } ] } , { type , 615 , boolean , [ ] } ] } ] } ) .


is_ptype_match(Item, PType) ->
    case Item#listitem.match_all of
      true -> true;
      false ->
	  case PType of
	    message -> Item#listitem.match_message;
	    iq -> Item#listitem.match_iq;
	    presence_in -> Item#listitem.match_presence_in;
	    presence_out -> Item#listitem.match_presence_out;
	    other -> false
	  end
    end.

- spec ( { { is_type_match , 5 } , [ { type , 629 , 'fun' , [ { type , 629 , product , [ { type , 629 , union , [ { atom , 629 , none } , { atom , 629 , jid } , { atom , 629 , subscription } , { atom , 629 , group } ] } , { type , 629 , listitem_value , [ ] } , { type , 630 , ljid , [ ] } , { type , 630 , union , [ { atom , 630 , none } , { atom , 630 , both } , { atom , 630 , from } , { atom , 630 , to } ] } , { type , 630 , list , [ { type , 630 , binary , [ ] } ] } ] } , { type , 630 , boolean , [ ] } ] } ] } ) .


is_type_match(none, _Value, _JID, _Subscription,
	      _Groups) ->
    true;
is_type_match(jid, Value, JID, _Subscription,
	      _Groups) ->
    case Value of
      {<<"">>, Server, <<"">>} ->
	  case JID of
	    {_, Server, _} -> true;
	    _ -> false
	  end;
      {User, Server, <<"">>} ->
	  case JID of
	    {User, Server, _} -> true;
	    _ -> false
	  end;
      {<<"">>, Server, Resource} ->
	  case JID of
	    {_, Server, Resource} -> true;
	    _ -> false
	  end;
      _ -> Value == JID
    end;
is_type_match(subscription, Value, _JID, Subscription,
	      _Groups) ->
    Value == Subscription;
is_type_match(group, Group, _JID, _Subscription,
	      Groups) ->
    lists:member(Group, Groups).

- spec ( { { remove_user , 2 } , [ { type , 657 , 'fun' , [ { type , 657 , product , [ { type , 657 , binary , [ ] } , { type , 657 , binary , [ ] } ] } , { atom , 657 , ok } ] } ] } ) .


remove_user(User, Server) ->
    LUser = jid:nodeprep(User),
    LServer = jid:nameprep(Server),
    Privacy = get_user_lists(LUser, LServer),
    Mod = gen_mod:db_mod(LServer, ?MODULE),
    Mod:remove_lists(LUser, LServer),
    case Privacy of
      {ok, #privacy{lists = Lists}} ->
	  Names = [Name || {Name, _} <- Lists],
	  delete_cache(Mod, LUser, LServer, Names);
      _ -> ok
    end.

- spec ( { { init_cache , 3 } , [ { type , 672 , 'fun' , [ { type , 672 , product , [ { type , 672 , module , [ ] } , { type , 672 , binary , [ ] } , { remote_type , 672 , [ { atom , 672 , gen_mod } , { atom , 672 , opts } , [ ] ] } ] } , { atom , 672 , ok } ] } ] } ) .


init_cache(Mod, Host, Opts) ->
    case use_cache(Mod, Host) of
      true ->
	  CacheOpts = cache_opts(Opts),
	  ets_cache:new(?PRIVACY_CACHE, CacheOpts),
	  ets_cache:new(?PRIVACY_LIST_CACHE, CacheOpts);
      false ->
	  ets_cache:delete(?PRIVACY_CACHE),
	  ets_cache:delete(?PRIVACY_LIST_CACHE)
    end.

- spec ( { { cache_opts , 1 } , [ { type , 684 , 'fun' , [ { type , 684 , product , [ { remote_type , 684 , [ { atom , 684 , gen_mod } , { atom , 684 , opts } , [ ] ] } ] } , { type , 684 , list , [ { remote_type , 684 , [ { atom , 684 , proplists } , { atom , 684 , property } , [ ] ] } ] } ] } ] } ) .


cache_opts(Opts) ->
    MaxSize = gen_mod:get_opt(cache_size, Opts),
    CacheMissed = gen_mod:get_opt(cache_missed, Opts),
    LifeTime = case gen_mod:get_opt(cache_life_time, Opts)
		   of
		 infinity -> infinity;
		 I -> timer:seconds(I)
	       end,
    [{max_size, MaxSize}, {cache_missed, CacheMissed},
     {life_time, LifeTime}].

- spec ( { { use_cache , 2 } , [ { type , 694 , 'fun' , [ { type , 694 , product , [ { type , 694 , module , [ ] } , { type , 694 , binary , [ ] } ] } , { type , 694 , boolean , [ ] } ] } ] } ) .


use_cache(Mod, Host) ->
    case erlang:function_exported(Mod, use_cache, 1) of
      true -> Mod:use_cache(Host);
      false ->
	  gen_mod:get_module_opt(Host, ?MODULE, use_cache)
    end.

- spec ( { { cache_nodes , 2 } , [ { type , 701 , 'fun' , [ { type , 701 , product , [ { type , 701 , module , [ ] } , { type , 701 , binary , [ ] } ] } , { type , 701 , list , [ { type , 701 , node , [ ] } ] } ] } ] } ) .


cache_nodes(Mod, Host) ->
    case erlang:function_exported(Mod, cache_nodes, 1) of
      true -> Mod:cache_nodes(Host);
      false -> ejabberd_cluster:get_nodes()
    end.

- spec ( { { delete_cache , 4 } , [ { type , 708 , 'fun' , [ { type , 708 , product , [ { type , 708 , module , [ ] } , { type , 708 , binary , [ ] } , { type , 708 , binary , [ ] } , { type , 708 , list , [ { type , 708 , binary , [ ] } ] } ] } , { atom , 708 , ok } ] } ] } ) .


delete_cache(Mod, LUser, LServer, Names) ->
    case use_cache(Mod, LServer) of
      true ->
	  Nodes = cache_nodes(Mod, LServer),
	  ets_cache:delete(?PRIVACY_CACHE, {LUser, LServer},
			   Nodes),
	  lists:foreach(fun (Name) ->
				ets_cache:delete(?PRIVACY_LIST_CACHE,
						 {LUser, LServer, Name}, Nodes)
			end,
			[default | Names]);
      false -> ok
    end.

numeric_to_binary(<<0, 0, _/binary>>) -> <<"0">>;
numeric_to_binary(<<0, _, _:6/binary, T/binary>>) ->
    Res = lists:foldl(fun (X, Sum) -> Sum * 10000 + X end,
		      0, [X || <<X:16>> <= T]),
    integer_to_binary(Res).

bool_to_binary(<<0>>) -> <<"0">>;
bool_to_binary(<<1>>) -> <<"1">>.

prepare_list_data(mysql, [ID | Row]) ->
    [binary_to_integer(ID) | Row];
prepare_list_data(pgsql,
		  [<<ID:64>>, SType, SValue, SAction, SOrder, SMatchAll,
		   SMatchIQ, SMatchMessage, SMatchPresenceIn,
		   SMatchPresenceOut]) ->
    [ID, SType, SValue, SAction, numeric_to_binary(SOrder),
     bool_to_binary(SMatchAll), bool_to_binary(SMatchIQ),
     bool_to_binary(SMatchMessage),
     bool_to_binary(SMatchPresenceIn),
     bool_to_binary(SMatchPresenceOut)].

prepare_id(mysql, ID) -> binary_to_integer(ID);
prepare_id(pgsql, <<ID:32>>) -> ID.

import_info() ->
    [{<<"privacy_default_list">>, 2},
     {<<"privacy_list_data">>, 10}, {<<"privacy_list">>, 4}].

import_start(LServer, DBType) ->
    ets:new(privacy_default_list_tmp,
	    [private, named_table]),
    ets:new(privacy_list_data_tmp,
	    [private, named_table, bag]),
    ets:new(privacy_list_tmp,
	    [private, named_table, bag, {keypos, #privacy.us}]),
    Mod = gen_mod:db_mod(DBType, ?MODULE),
    Mod:init(LServer, []).

import(LServer, {sql, _}, _DBType,
       <<"privacy_default_list">>, [LUser, Name]) ->
    US = {LUser, LServer},
    ets:insert(privacy_default_list_tmp, {US, Name}),
    ok;
import(LServer, {sql, SQLType}, _DBType,
       <<"privacy_list_data">>, Row1) ->
    [ID | Row] = prepare_list_data(SQLType, Row1),
    case mod_privacy_sql:raw_to_item(Row) of
      [Item] ->
	  IS = {ID, LServer},
	  ets:insert(privacy_list_data_tmp, {IS, Item}),
	  ok;
      [] -> ok
    end;
import(LServer, {sql, SQLType}, _DBType,
       <<"privacy_list">>, [LUser, Name, ID, _TimeStamp]) ->
    US = {LUser, LServer},
    IS = {prepare_id(SQLType, ID), LServer},
    Default = case ets:lookup(privacy_default_list_tmp, US)
		  of
		[{_, Name}] -> Name;
		_ -> none
	      end,
    case [Item
	  || {_, Item} <- ets:lookup(privacy_list_data_tmp, IS)]
	of
      [_ | _] = Items ->
	  Privacy = #privacy{us = {LUser, LServer},
			     default = Default, lists = [{Name, Items}]},
	  ets:insert(privacy_list_tmp, Privacy),
	  ets:delete(privacy_list_data_tmp, IS),
	  ok;
      _ -> ok
    end.

import_stop(_LServer, DBType) ->
    import_next(DBType, ets:first(privacy_list_tmp)),
    ets:delete(privacy_default_list_tmp),
    ets:delete(privacy_list_data_tmp),
    ets:delete(privacy_list_tmp),
    ok.

import_next(_DBType, '$end_of_table') -> ok;
import_next(DBType, US) ->
    [P | _] = Ps = ets:lookup(privacy_list_tmp, US),
    Lists = lists:flatmap(fun (#privacy{lists = Lists}) ->
				  Lists
			  end,
			  Ps),
    Privacy = P#privacy{lists = Lists},
    Mod = gen_mod:db_mod(DBType, ?MODULE),
    Mod:import(Privacy),
    import_next(DBType, ets:next(privacy_list_tmp, US)).

export(LServer) ->
    Mod = gen_mod:db_mod(LServer, ?MODULE),
    Mod:export(LServer).

depends(_Host, _Opts) -> [].

mod_opt_type(db_type) ->
    fun (T) -> ejabberd_config:v_db(?MODULE, T) end;
mod_opt_type(O)
    when O == cache_life_time; O == cache_size ->
    fun (I) when is_integer(I), I > 0 -> I;
	(infinity) -> infinity
    end;
mod_opt_type(O)
    when O == use_cache; O == cache_missed ->
    fun (B) when is_boolean(B) -> B end.

mod_options(Host) ->
    [{db_type, ejabberd_config:default_db(Host, ?MODULE)},
     {use_cache, ejabberd_config:use_cache(Host)},
     {cache_size, ejabberd_config:cache_size(Host)},
     {cache_missed, ejabberd_config:cache_missed(Host)},
     {cache_life_time,
      ejabberd_config:cache_life_time(Host)}].

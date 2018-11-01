%%%----------------------------------------------------------------------
%%% File    : mod_pubsub.erl
%%% Author  : Christophe Romain <christophe.romain@process-one.net>
%%% Purpose : Publish Subscribe service (XEP-0060)
%%% Created :  1 Dec 2007 by Christophe Romain <christophe.romain@process-one.net>
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

%%% Support for subscription-options and multi-subscribe features was
%%% added by Brian Cully (bjc AT kublai.com). Subscriptions and options are
%%% stored in the pubsub_subscription table, with a link to them provided
%%% by the subscriptions field of pubsub_state. For information on
%%% subscription-options and mulit-subscribe see XEP-0060 sections 6.1.6,
%%% 6.2.3.1, 6.2.3.5, and 6.3. For information on subscription leases see
%%% XEP-0060 section 12.18.

-module(mod_pubsub).

-behaviour(gen_mod).

-behaviour(gen_server).

-author('christophe.romain@process-one.net').

-protocol({xep, 60, '1.14'}).

-protocol({xep, 163, '1.2'}).

-protocol({xep, 248, '0.2'}).

-include("logger.hrl").

-include("xmpp.hrl").

-include("pubsub.hrl").

-include("mod_roster.hrl").

-include("translate.hrl").

-define(STDTREE, <<"tree">>).

-define(STDNODE, <<"flat">>).

-define(PEPNODE, <<"pep">>).

%% exports for hooks
-export([c2s_handle_info/2, caps_add/3, caps_update/3,
	 disco_local_features/5, disco_local_identity/5,
	 disco_local_items/5, disco_sm_features/5,
	 disco_sm_identity/5, disco_sm_items/5,
	 in_subscription/2, on_self_presence/1,
	 on_user_offline/2, out_subscription/1, presence_probe/3,
	 remove_user/2]).

%% exported iq handlers
-export([iq_sm/1, process_commands/1,
	 process_disco_info/1, process_disco_items/1,
	 process_pubsub/1, process_pubsub_owner/1,
	 process_vcard/1]).

%% exports for console debug manual use
-export([create_node/5, create_node/7, delete_item/4,
	 delete_item/5, delete_node/3, get_cached_item/2,
	 get_configure/5, get_item/3, get_items/2, node_action/4,
	 node_call/4, publish_item/6, send_items/7,
	 set_configure/5, subscribe_node/5, tree_action/3,
	 unsubscribe_node/5]).

%% general helpers for plugins
-export([config/3, extended_error/2, host/1, plugin/2,
	 plugins/1, serverhost/1, service_jid/1, tree/1,
	 tree/2]).

%% pubsub#errors
-export([err_closed_node/0,
	 err_configuration_required/0, err_invalid_jid/0,
	 err_invalid_options/0, err_invalid_payload/0,
	 err_invalid_subid/0, err_item_forbidden/0,
	 err_item_required/0, err_jid_required/0,
	 err_max_items_exceeded/0, err_max_nodes_exceeded/0,
	 err_nodeid_required/0, err_not_in_roster_group/0,
	 err_not_subscribed/0, err_payload_required/0,
	 err_payload_too_big/0, err_pending_subscription/0,
	 err_precondition_not_met/0,
	 err_presence_subscription_required/0,
	 err_subid_required/0, err_too_many_subscriptions/0,
	 err_unsupported/1, err_unsupported_access_model/0]).

%% API and gen_server callbacks
-export([code_change/3, depends/2, handle_call/3,
	 handle_cast/2, handle_info/2, init/1, mod_opt_type/1,
	 mod_options/1, start/2, stop/1, terminate/2]).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------

-export_type([{host, 0}, {hostPubsub, 0}, {hostPEP, 0},
	      {nodeIdx, 0}, {nodeId, 0}, {itemId, 0}, {subId, 0},
	      {payload, 0}, {nodeOption, 0}, {nodeOptions, 0},
	      {subOption, 0}, {subOptions, 0}, {pubOption, 0},
	      {pubOptions, 0}, {affiliation, 0}, {subscription, 0},
	      {accessModel, 0}, {publishModel, 0}]).

        %%

        %%

        %%

%% -type payload() defined here because the -type xmlel() is not accessible
%% from pubsub.hrl
-type({payload,
       {type, 129, union,
	[{type, 129, nil, []},
	 {type, 129, nonempty_list, [{type, 129, xmlel, []}]}]},
       []}).

-export_type([{pubsubNode, 0}, {pubsubState, 0},
	      {pubsubItem, 0}, {pubsubSubscription, 0},
	      {pubsubLastItem, 0}]).

-type({pubsubNode,
       {type, 140, record,
	[{atom, 140, pubsub_node},
	 {type, 141, field_type,
	  [{atom, 141, nodeid},
	   {type, 141, tuple,
	    [{ann_type, 141,
	      [{var, 141, 'Host'},
	       {remote_type, 141,
		[{atom, 141, mod_pubsub}, {atom, 141, host}, []]}]},
	     {ann_type, 141,
	      [{var, 141, 'Node'},
	       {remote_type, 141,
		[{atom, 141, mod_pubsub}, {atom, 141, nodeId},
		 []]}]}]}]},
	 {type, 142, field_type,
	  [{atom, 142, id},
	   {ann_type, 142,
	    [{var, 142, 'Nidx'},
	     {remote_type, 142,
	      [{atom, 142, mod_pubsub}, {atom, 142, nodeIdx},
	       []]}]}]},
	 {type, 143, field_type,
	  [{atom, 143, parents},
	   {type, 143, list,
	    [{ann_type, 143,
	      [{var, 143, 'Node'},
	       {remote_type, 143,
		[{atom, 143, mod_pubsub}, {atom, 143, nodeId},
		 []]}]}]}]},
	 {type, 144, field_type,
	  [{atom, 144, type},
	   {ann_type, 144,
	    [{var, 144, 'Type'}, {type, 144, binary, []}]}]},
	 {type, 145, field_type,
	  [{atom, 145, owners},
	   {type, 145, nonempty_list,
	    [{ann_type, 145,
	      [{var, 145, 'Owner'}, {type, 145, ljid, []}]}]}]},
	 {type, 146, field_type,
	  [{atom, 146, options},
	   {ann_type, 146,
	    [{var, 146, 'Opts'},
	     {remote_type, 146,
	      [{atom, 146, mod_pubsub}, {atom, 146, nodeOptions},
	       []]}]}]}]},
       []}).

-type({pubsubState,
       {type, 151, record,
	[{atom, 151, pubsub_state},
	 {type, 152, field_type,
	  [{atom, 152, stateid},
	   {type, 152, tuple,
	    [{ann_type, 152,
	      [{var, 152, 'Entity'}, {type, 152, ljid, []}]},
	     {ann_type, 152,
	      [{var, 152, 'Nidx'},
	       {remote_type, 152,
		[{atom, 152, mod_pubsub}, {atom, 152, nodeIdx},
		 []]}]}]}]},
	 {type, 153, field_type,
	  [{atom, 153, nodeidx},
	   {ann_type, 153,
	    [{var, 153, 'Nidx'},
	     {remote_type, 153,
	      [{atom, 153, mod_pubsub}, {atom, 153, nodeIdx},
	       []]}]}]},
	 {type, 154, field_type,
	  [{atom, 154, items},
	   {type, 154, list,
	    [{ann_type, 154,
	      [{var, 154, 'ItemId'},
	       {remote_type, 154,
		[{atom, 154, mod_pubsub}, {atom, 154, itemId},
		 []]}]}]}]},
	 {type, 155, field_type,
	  [{atom, 155, affiliation},
	   {ann_type, 155,
	    [{var, 155, 'Affs'},
	     {remote_type, 155,
	      [{atom, 155, mod_pubsub}, {atom, 155, affiliation},
	       []]}]}]},
	 {type, 156, field_type,
	  [{atom, 156, subscriptions},
	   {type, 156, list,
	    [{type, 156, tuple,
	      [{ann_type, 156,
		[{var, 156, 'Sub'},
		 {remote_type, 156,
		  [{atom, 156, mod_pubsub}, {atom, 156, subscription},
		   []]}]},
	       {ann_type, 156,
		[{var, 156, 'SubId'},
		 {remote_type, 156,
		  [{atom, 156, mod_pubsub}, {atom, 156, subId},
		   []]}]}]}]}]}]},
       []}).

-type({pubsubItem,
       {type, 161, record,
	[{atom, 161, pubsub_item},
	 {type, 162, field_type,
	  [{atom, 162, itemid},
	   {type, 162, tuple,
	    [{ann_type, 162,
	      [{var, 162, 'ItemId'},
	       {remote_type, 162,
		[{atom, 162, mod_pubsub}, {atom, 162, itemId}, []]}]},
	     {ann_type, 162,
	      [{var, 162, 'Nidx'},
	       {remote_type, 162,
		[{atom, 162, mod_pubsub}, {atom, 162, nodeIdx},
		 []]}]}]}]},
	 {type, 163, field_type,
	  [{atom, 163, nodeidx},
	   {ann_type, 163,
	    [{var, 163, 'Nidx'},
	     {remote_type, 163,
	      [{atom, 163, mod_pubsub}, {atom, 163, nodeIdx},
	       []]}]}]},
	 {type, 164, field_type,
	  [{atom, 164, creation},
	   {type, 164, tuple,
	    [{remote_type, 164,
	      [{atom, 164, erlang}, {atom, 164, timestamp}, []]},
	     {type, 164, ljid, []}]}]},
	 {type, 165, field_type,
	  [{atom, 165, modification},
	   {type, 165, tuple,
	    [{remote_type, 165,
	      [{atom, 165, erlang}, {atom, 165, timestamp}, []]},
	     {type, 165, ljid, []}]}]},
	 {type, 166, field_type,
	  [{atom, 166, payload},
	   {remote_type, 166,
	    [{atom, 166, mod_pubsub}, {atom, 166, payload},
	     []]}]}]},
       []}).

-type({pubsubSubscription,
       {type, 171, record,
	[{atom, 171, pubsub_subscription},
	 {type, 172, field_type,
	  [{atom, 172, subid},
	   {ann_type, 172,
	    [{var, 172, 'SubId'},
	     {remote_type, 172,
	      [{atom, 172, mod_pubsub}, {atom, 172, subId}, []]}]}]},
	 {type, 173, field_type,
	  [{atom, 173, options},
	   {type, 173, union,
	    [{type, 173, nil, []},
	     {remote_type, 173,
	      [{atom, 173, mod_pubsub}, {atom, 173, subOptions},
	       []]}]}]}]},
       []}).

-type({pubsubLastItem,
       {type, 178, record,
	[{atom, 178, pubsub_last_item},
	 {type, 179, field_type,
	  [{atom, 179, nodeid},
	   {type, 179, tuple,
	    [{type, 179, binary, []},
	     {remote_type, 179,
	      [{atom, 179, mod_pubsub}, {atom, 179, nodeIdx},
	       []]}]}]},
	 {type, 180, field_type,
	  [{atom, 180, itemid},
	   {remote_type, 180,
	    [{atom, 180, mod_pubsub}, {atom, 180, itemId}, []]}]},
	 {type, 181, field_type,
	  [{atom, 181, creation},
	   {type, 181, tuple,
	    [{remote_type, 181,
	      [{atom, 181, erlang}, {atom, 181, timestamp}, []]},
	     {type, 181, ljid, []}]}]},
	 {type, 182, field_type,
	  [{atom, 182, payload},
	   {remote_type, 182,
	    [{atom, 182, mod_pubsub}, {atom, 182, payload},
	     []]}]}]},
       []}).

-record(state,
	{server_host, hosts, access, pep_mapping = [],
	 ignore_pep_from_offline = true, last_item_cache = false,
	 max_items_node = ?MAXITEMS,
	 max_subscriptions_node = undefined,
	 default_node_config = [],
	 nodetree = <<"nodetree_", (?STDTREE)/binary>>,
	 plugins = [?STDNODE], db_type}).

-type({state,
       {type, 203, record,
	[{atom, 203, state},
	 {type, 204, field_type,
	  [{atom, 204, server_host}, {type, 204, binary, []}]},
	 {type, 205, field_type,
	  [{atom, 205, hosts},
	   {type, 205, list,
	    [{remote_type, 205,
	      [{atom, 205, mod_pubsub}, {atom, 205, hostPubsub},
	       []]}]}]},
	 {type, 206, field_type,
	  [{atom, 206, access}, {type, 206, atom, []}]},
	 {type, 207, field_type,
	  [{atom, 207, pep_mapping},
	   {type, 207, list,
	    [{type, 207, tuple,
	      [{type, 207, binary, []}, {type, 207, binary, []}]}]}]},
	 {type, 208, field_type,
	  [{atom, 208, ignore_pep_from_offline},
	   {type, 208, boolean, []}]},
	 {type, 209, field_type,
	  [{atom, 209, last_item_cache},
	   {type, 209, boolean, []}]},
	 {type, 210, field_type,
	  [{atom, 210, max_items_node},
	   {type, 210, non_neg_integer, []}]},
	 {type, 211, field_type,
	  [{atom, 211, max_subscriptions_node},
	   {type, 211, union,
	    [{type, 211, non_neg_integer, []},
	     {atom, 211, undefined}]}]},
	 {type, 212, field_type,
	  [{atom, 212, default_node_config},
	   {type, 212, list,
	    [{type, 212, tuple,
	      [{type, 212, atom, []},
	       {type, 212, union,
		[{type, 212, binary, []}, {type, 212, boolean, []},
		 {type, 212, integer, []}, {type, 212, atom, []}]}]}]}]},
	 {type, 213, field_type,
	  [{atom, 213, nodetree}, {type, 213, binary, []}]},
	 {type, 214, field_type,
	  [{atom, 214, plugins},
	   {type, 214, nonempty_list, [{type, 214, binary, []}]}]},
	 {type, 215, field_type,
	  [{atom, 215, db_type}, {type, 215, atom, []}]}]},
       []}).

start(Host, Opts) ->
    gen_mod:start_child(?MODULE, Host, Opts).

stop(Host) -> gen_mod:stop_child(?MODULE, Host).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
- spec ( { { init , 1 } , [ { type , 238 , 'fun' , [ { type , 238 , product , [ { type , 238 , nonempty_list , [ { type , 238 , union , [ { type , 238 , binary , [ ] } , { type , 238 , list , [ { type , 238 , tuple , [ { var , 238 , '_' } , { var , 238 , '_' } ] } ] } ] } ] } ] } , { type , 238 , tuple , [ { atom , 238 , ok } , { type , 238 , state , [ ] } ] } ] } ] } ) .


init([ServerHost, Opts]) ->
    process_flag(trap_exit, true),
    ?DEBUG("pubsub init ~p ~p", [ServerHost, Opts]),
    Hosts = gen_mod:get_opt_hosts(ServerHost, Opts),
    Access = gen_mod:get_opt(access_createnode, Opts),
    PepOffline = gen_mod:get_opt(ignore_pep_from_offline,
				 Opts),
    LastItemCache = gen_mod:get_opt(last_item_cache, Opts),
    MaxItemsNode = gen_mod:get_opt(max_items_node, Opts),
    MaxSubsNode = gen_mod:get_opt(max_subscriptions_node,
				  Opts),
    ejabberd_mnesia:create(?MODULE, pubsub_last_item,
			   [{ram_copies, [node()]},
			    {attributes,
			     record_info(fields, pubsub_last_item)}]),
    AllPlugins = lists:flatmap(fun (Host) ->
				       ejabberd_router:register_route(Host,
								      ServerHost),
				       case gen_mod:get_module_opt(ServerHost,
								   ?MODULE,
								   db_type)
					   of
					 mnesia ->
					     pubsub_index:init(Host, ServerHost,
							       Opts);
					 _ -> ok
				       end,
				       {Plugins, NodeTree, PepMapping} =
					   init_plugins(Host, ServerHost, Opts),
				       DefaultModule = plugin(Host,
							      hd(Plugins)),
				       DefaultNodeCfg =
					   merge_config([gen_mod:get_opt(default_node_config,
									 Opts),
							 DefaultModule:options()]),
				       lists:foreach(fun (H) ->
							     T =
								 gen_mod:get_module_proc(H,
											 config),
							     try ets:new(T,
									 [set,
									  named_table]),
								 ets:insert(T,
									    {nodetree,
									     NodeTree}),
								 ets:insert(T,
									    {plugins,
									     Plugins}),
								 ets:insert(T,
									    {last_item_cache,
									     LastItemCache}),
								 ets:insert(T,
									    {max_items_node,
									     MaxItemsNode}),
								 ets:insert(T,
									    {max_subscriptions_node,
									     MaxSubsNode}),
								 ets:insert(T,
									    {default_node_config,
									     DefaultNodeCfg}),
								 ets:insert(T,
									    {pep_mapping,
									     PepMapping}),
								 ets:insert(T,
									    {ignore_pep_from_offline,
									     PepOffline}),
								 ets:insert(T,
									    {host,
									     Host}),
								 ets:insert(T,
									    {access,
									     Access})
							     catch
							       error:badarg
								   when H ==
									  ServerHost ->
								   ok
							     end
						     end,
						     [Host, ServerHost]),
				       gen_iq_handler:add_iq_handler(ejabberd_local,
								     Host,
								     ?NS_DISCO_INFO,
								     ?MODULE,
								     process_disco_info),
				       gen_iq_handler:add_iq_handler(ejabberd_local,
								     Host,
								     ?NS_DISCO_ITEMS,
								     ?MODULE,
								     process_disco_items),
				       gen_iq_handler:add_iq_handler(ejabberd_local,
								     Host,
								     ?NS_PUBSUB,
								     ?MODULE,
								     process_pubsub),
				       gen_iq_handler:add_iq_handler(ejabberd_local,
								     Host,
								     ?NS_PUBSUB_OWNER,
								     ?MODULE,
								     process_pubsub_owner),
				       gen_iq_handler:add_iq_handler(ejabberd_local,
								     Host,
								     ?NS_VCARD,
								     ?MODULE,
								     process_vcard),
				       gen_iq_handler:add_iq_handler(ejabberd_local,
								     Host,
								     ?NS_COMMANDS,
								     ?MODULE,
								     process_commands),
				       Plugins
			       end,
			       Hosts),
    ejabberd_hooks:add(c2s_self_presence, ServerHost,
		       ?MODULE, on_self_presence, 75),
    ejabberd_hooks:add(c2s_terminated, ServerHost, ?MODULE,
		       on_user_offline, 75),
    ejabberd_hooks:add(disco_local_identity, ServerHost,
		       ?MODULE, disco_local_identity, 75),
    ejabberd_hooks:add(disco_local_features, ServerHost,
		       ?MODULE, disco_local_features, 75),
    ejabberd_hooks:add(disco_local_items, ServerHost,
		       ?MODULE, disco_local_items, 75),
    ejabberd_hooks:add(presence_probe_hook, ServerHost,
		       ?MODULE, presence_probe, 80),
    ejabberd_hooks:add(roster_in_subscription, ServerHost,
		       ?MODULE, in_subscription, 50),
    ejabberd_hooks:add(roster_out_subscription, ServerHost,
		       ?MODULE, out_subscription, 50),
    ejabberd_hooks:add(remove_user, ServerHost, ?MODULE,
		       remove_user, 50),
    ejabberd_hooks:add(c2s_handle_info, ServerHost, ?MODULE,
		       c2s_handle_info, 50),
    case lists:member(?PEPNODE, AllPlugins) of
      true ->
	  ejabberd_hooks:add(caps_add, ServerHost, ?MODULE,
			     caps_add, 80),
	  ejabberd_hooks:add(caps_update, ServerHost, ?MODULE,
			     caps_update, 80),
	  ejabberd_hooks:add(disco_sm_identity, ServerHost,
			     ?MODULE, disco_sm_identity, 75),
	  ejabberd_hooks:add(disco_sm_features, ServerHost,
			     ?MODULE, disco_sm_features, 75),
	  ejabberd_hooks:add(disco_sm_items, ServerHost, ?MODULE,
			     disco_sm_items, 75),
	  gen_iq_handler:add_iq_handler(ejabberd_sm, ServerHost,
					?NS_PUBSUB, ?MODULE, iq_sm),
	  gen_iq_handler:add_iq_handler(ejabberd_sm, ServerHost,
					?NS_PUBSUB_OWNER, ?MODULE, iq_sm);
      false -> ok
    end,
    NodeTree = config(ServerHost, nodetree),
    Plugins = config(ServerHost, plugins),
    PepMapping = config(ServerHost, pep_mapping),
    DBType = gen_mod:get_module_opt(ServerHost, ?MODULE,
				    db_type),
    {ok,
     #state{hosts = Hosts, server_host = ServerHost,
	    access = Access, pep_mapping = PepMapping,
	    ignore_pep_from_offline = PepOffline,
	    last_item_cache = LastItemCache,
	    max_items_node = MaxItemsNode, nodetree = NodeTree,
	    plugins = Plugins, db_type = DBType}}.

depends(ServerHost, Opts0) ->
    Opts = Opts0 ++ mod_options(ServerHost),
    [Host | _] = gen_mod:get_opt_hosts(ServerHost, Opts),
    Plugins = gen_mod:get_opt(plugins, Opts),
    lists:flatmap(fun (Name) ->
			  Plugin = plugin(ServerHost, Name),
			  try Plugin:depends(Host, ServerHost, Opts) catch
			    _:undef -> []
			  end
		  end,
		  Plugins).

%% @doc Call the init/1 function for each plugin declared in the config file.
%% The default plugin module is implicit.
%% <p>The Erlang code for the plugin is located in a module called
%% <em>node_plugin</em>. The 'node_' prefix is mandatory.</p>
%% <p>See {@link node_hometree:init/1} for an example implementation.</p>
init_plugins(Host, ServerHost, Opts) ->
    TreePlugin = tree(Host,
		      gen_mod:get_opt(nodetree, Opts)),
    ?DEBUG("** tree plugin is ~p", [TreePlugin]),
    TreePlugin:init(Host, ServerHost, Opts),
    Plugins = gen_mod:get_opt(plugins, Opts),
    PepMapping = gen_mod:get_opt(pep_mapping, Opts),
    ?DEBUG("** PEP Mapping : ~p~n", [PepMapping]),
    PluginsOK = lists:foldl(fun (Name, Acc) ->
				    Plugin = plugin(Host, Name),
				    Plugin:init(Host, ServerHost, Opts),
				    ?DEBUG("** init ~s plugin", [Name]),
				    [Name | Acc]
			    end,
			    [], Plugins),
    {lists:reverse(PluginsOK), TreePlugin, PepMapping}.

terminate_plugins(Host, ServerHost, Plugins,
		  TreePlugin) ->
    lists:foreach(fun (Name) ->
			  ?DEBUG("** terminate ~s plugin", [Name]),
			  Plugin = plugin(Host, Name),
			  Plugin:terminate(Host, ServerHost)
		  end,
		  Plugins),
    TreePlugin:terminate(Host, ServerHost),
    ok.

%% -------
%% disco hooks handling functions
%%

- spec ( { { disco_local_identity , 5 } , [ { type , 397 , 'fun' , [ { type , 397 , product , [ { type , 397 , list , [ { type , 397 , identity , [ ] } ] } , { type , 397 , jid , [ ] } , { type , 397 , jid , [ ] } , { type , 398 , binary , [ ] } , { type , 398 , binary , [ ] } ] } , { type , 398 , list , [ { type , 398 , identity , [ ] } ] } ] } ] } ) .


disco_local_identity(Acc, _From, To, <<>>, _Lang) ->
    case lists:member(?PEPNODE,
		      plugins(host(To#jid.lserver)))
	of
      true ->
	  [#identity{category = <<"pubsub">>, type = <<"pep">>}
	   | Acc];
      false -> Acc
    end;
disco_local_identity(Acc, _From, _To, _Node, _Lang) ->
    Acc.

- spec ( { { disco_local_features , 5 } , [ { type , 409 , 'fun' , [ { type , 409 , product , [ { type , 409 , union , [ { type , 409 , tuple , [ { atom , 409 , error } , { type , 409 , stanza_error , [ ] } ] } , { type , 409 , tuple , [ { atom , 409 , result } , { type , 409 , list , [ { type , 409 , binary , [ ] } ] } ] } , { atom , 409 , empty } ] } , { type , 410 , jid , [ ] } , { type , 410 , jid , [ ] } , { type , 410 , binary , [ ] } , { type , 410 , binary , [ ] } ] } , { type , 411 , union , [ { type , 411 , tuple , [ { atom , 411 , error } , { type , 411 , stanza_error , [ ] } ] } , { type , 411 , tuple , [ { atom , 411 , result } , { type , 411 , list , [ { type , 411 , binary , [ ] } ] } ] } , { atom , 411 , empty } ] } ] } ] } ) .


disco_local_features(Acc, _From, To, <<>>, _Lang) ->
    Host = host(To#jid.lserver),
    Feats = case Acc of
	      {result, I} -> I;
	      _ -> []
	    end,
    {result,
     Feats ++
       [?NS_PUBSUB | [feature(F)
		      || F <- features(Host, <<>>)]]};
disco_local_features(Acc, _From, _To, _Node, _Lang) ->
    Acc.

- spec ( { { disco_local_items , 5 } , [ { type , 422 , 'fun' , [ { type , 422 , product , [ { type , 422 , union , [ { type , 422 , tuple , [ { atom , 422 , error } , { type , 422 , stanza_error , [ ] } ] } , { type , 422 , tuple , [ { atom , 422 , result } , { type , 422 , list , [ { type , 422 , disco_item , [ ] } ] } ] } , { atom , 422 , empty } ] } , { type , 423 , jid , [ ] } , { type , 423 , jid , [ ] } , { type , 423 , binary , [ ] } , { type , 423 , binary , [ ] } ] } , { type , 424 , union , [ { type , 424 , tuple , [ { atom , 424 , error } , { type , 424 , stanza_error , [ ] } ] } , { type , 424 , tuple , [ { atom , 424 , result } , { type , 424 , list , [ { type , 424 , disco_item , [ ] } ] } ] } , { atom , 424 , empty } ] } ] } ] } ) .


disco_local_items(Acc, _From, _To, <<>>, _Lang) -> Acc;
disco_local_items(Acc, _From, _To, _Node, _Lang) -> Acc.

- spec ( { { disco_sm_identity , 5 } , [ { type , 428 , 'fun' , [ { type , 428 , product , [ { type , 428 , list , [ { type , 428 , identity , [ ] } ] } , { type , 428 , jid , [ ] } , { type , 428 , jid , [ ] } , { type , 429 , binary , [ ] } , { type , 429 , binary , [ ] } ] } , { type , 429 , list , [ { type , 429 , identity , [ ] } ] } ] } ] } ) .


disco_sm_identity(Acc, From, To, Node, _Lang) ->
    disco_identity(jid:tolower(jid:remove_resource(To)),
		   Node, From)
      ++ Acc.

- spec ( { { disco_identity , 3 } , [ { type , 434 , 'fun' , [ { type , 434 , product , [ { type , 434 , binary , [ ] } , { type , 434 , binary , [ ] } , { type , 434 , jid , [ ] } ] } , { type , 434 , list , [ { type , 434 , identity , [ ] } ] } ] } ] } ) .


disco_identity(_Host, <<>>, _From) ->
    [#identity{category = <<"pubsub">>, type = <<"pep">>}];
disco_identity(Host, Node, From) ->
    Action = fun (#pubsub_node{id = Nidx, type = Type,
			       options = Options, owners = O}) ->
		     Owners = node_owners_call(Host, Type, Nidx, O),
		     case get_allowed_items_call(Host, Nidx, From, Type,
						 Options, Owners)
			 of
		       {result, _} ->
			   {result,
			    [#identity{category = <<"pubsub">>,
				       type = <<"pep">>},
			     #identity{category = <<"pubsub">>,
				       type = <<"leaf">>,
				       name =
					   get_option(Options, title, <<>>)}]};
		       _ -> {result, []}
		     end
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_, Result}} -> Result;
      _ -> []
    end.

- spec ( { { disco_sm_features , 5 } , [ { type , 457 , 'fun' , [ { type , 457 , product , [ { type , 457 , union , [ { type , 457 , tuple , [ { atom , 457 , error } , { type , 457 , stanza_error , [ ] } ] } , { type , 457 , tuple , [ { atom , 457 , result } , { type , 457 , list , [ { type , 457 , binary , [ ] } ] } ] } , { atom , 457 , empty } ] } , { type , 458 , jid , [ ] } , { type , 458 , jid , [ ] } , { type , 458 , binary , [ ] } , { type , 458 , binary , [ ] } ] } , { type , 459 , union , [ { type , 459 , tuple , [ { atom , 459 , error } , { type , 459 , stanza_error , [ ] } ] } , { type , 459 , tuple , [ { atom , 459 , result } , { type , 459 , list , [ { type , 459 , binary , [ ] } ] } ] } ] } ] } ] } ) .


disco_sm_features(empty, From, To, Node, Lang) ->
    disco_sm_features({result, []}, From, To, Node, Lang);
disco_sm_features({result, OtherFeatures} = _Acc, From,
		  To, Node, _Lang) ->
    {result,
     OtherFeatures ++
       disco_features(jid:tolower(jid:remove_resource(To)),
		      Node, From)};
disco_sm_features(Acc, _From, _To, _Node, _Lang) -> Acc.

- spec ( { { disco_features , 3 } , [ { type , 468 , 'fun' , [ { type , 468 , product , [ { type , 468 , ljid , [ ] } , { type , 468 , binary , [ ] } , { type , 468 , jid , [ ] } ] } , { type , 468 , list , [ { type , 468 , binary , [ ] } ] } ] } ] } ) .


disco_features(Host, <<>>, _From) ->
    [?NS_PUBSUB | [feature(F)
		   || F <- plugin_features(Host, <<"pep">>)]];
disco_features(Host, Node, From) ->
    Action = fun (#pubsub_node{id = Nidx, type = Type,
			       options = Options, owners = O}) ->
		     Owners = node_owners_call(Host, Type, Nidx, O),
		     case get_allowed_items_call(Host, Nidx, From, Type,
						 Options, Owners)
			 of
		       {result, _} ->
			   {result,
			    [?NS_PUBSUB | [feature(F)
					   || F
						  <- plugin_features(Host,
								     <<"pep">>)]]};
		       _ -> {result, []}
		     end
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_, Result}} -> Result;
      _ -> []
    end.

- spec ( { { disco_sm_items , 5 } , [ { type , 490 , 'fun' , [ { type , 490 , product , [ { type , 490 , union , [ { type , 490 , tuple , [ { atom , 490 , error } , { type , 490 , stanza_error , [ ] } ] } , { type , 490 , tuple , [ { atom , 490 , result } , { type , 490 , list , [ { type , 490 , disco_item , [ ] } ] } ] } , { atom , 490 , empty } ] } , { type , 491 , jid , [ ] } , { type , 491 , jid , [ ] } , { type , 491 , binary , [ ] } , { type , 491 , binary , [ ] } ] } , { type , 492 , union , [ { type , 492 , tuple , [ { atom , 492 , error } , { type , 492 , stanza_error , [ ] } ] } , { type , 492 , tuple , [ { atom , 492 , result } , { type , 492 , list , [ { type , 492 , disco_item , [ ] } ] } ] } ] } ] } ] } ) .


disco_sm_items(empty, From, To, Node, Lang) ->
    disco_sm_items({result, []}, From, To, Node, Lang);
disco_sm_items({result, OtherItems}, From, To, Node,
	       _Lang) ->
    {result,
     lists:usort(OtherItems ++
		   disco_items(jid:tolower(jid:remove_resource(To)), Node,
			       From))};
disco_sm_items(Acc, _From, _To, _Node, _Lang) -> Acc.

- spec ( { { disco_items , 3 } , [ { type , 500 , 'fun' , [ { type , 500 , product , [ { type , 500 , ljid , [ ] } , { type , 500 , binary , [ ] } , { type , 500 , jid , [ ] } ] } , { type , 500 , list , [ { type , 500 , disco_item , [ ] } ] } ] } ] } ) .


disco_items(Host, <<>>, From) ->
    Action = fun (#pubsub_node{nodeid = {_, Node},
			       options = Options, type = Type, id = Nidx,
			       owners = O},
		  Acc) ->
		     Owners = node_owners_call(Host, Type, Nidx, O),
		     case get_allowed_items_call(Host, Nidx, From, Type,
						 Options, Owners)
			 of
		       {result, _} ->
			   [#disco_item{node = Node, jid = jid:make(Host),
					name = get_option(Options, title, <<>>)}
			    | Acc];
		       _ -> Acc
		     end
	     end,
    NodeBloc = fun () ->
		       {result,
			lists:foldl(Action, [],
				    tree_call(Host, get_nodes, [Host]))}
	       end,
    case transaction(Host, NodeBloc, sync_dirty) of
      {result, Items} -> Items;
      _ -> []
    end;
disco_items(Host, Node, From) ->
    Action = fun (#pubsub_node{id = Nidx, type = Type,
			       options = Options, owners = O}) ->
		     Owners = node_owners_call(Host, Type, Nidx, O),
		     case get_allowed_items_call(Host, Nidx, From, Type,
						 Options, Owners)
			 of
		       {result, Items} ->
			   {result,
			    [#disco_item{jid = jid:make(Host), name = ItemId}
			     || #pubsub_item{itemid = {ItemId, _}} <- Items]};
		       _ -> {result, []}
		     end
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_, Result}} -> Result;
      _ -> []
    end.

%% -------
%% presence and session hooks handling functions
%%

- spec ( { { caps_add , 3 } , [ { type , 548 , 'fun' , [ { type , 548 , product , [ { type , 548 , jid , [ ] } , { type , 548 , jid , [ ] } , { type , 548 , list , [ { type , 548 , binary , [ ] } ] } ] } , { atom , 548 , ok } ] } ] } ) .


caps_add(JID, JID, _Features) ->
    %% Send the owner his last PEP items.
    send_last_pep(JID, JID);
caps_add(#jid{lserver = S1} = From,
	 #jid{lserver = S2} = To, _Features)
    when S1 =/= S2 ->
    %% When a remote contact goes online while the local user is offline, the
    %% remote contact won't receive last items from the local user even if
    %% ignore_pep_from_offline is set to false. To work around this issue a bit,
    %% we'll also send the last items to remote contacts when the local user
    %% connects. That's the reason to use the caps_add hook instead of the
    %% presence_probe_hook for remote contacts: The latter is only called when a
    %% contact becomes available; the former is also executed when the local
    %% user goes online (because that triggers the contact to send a presence
    %% packet with CAPS).
    send_last_pep(To, From);
caps_add(_From, _To, _Feature) -> ok.

- spec ( { { caps_update , 3 } , [ { type , 567 , 'fun' , [ { type , 567 , product , [ { type , 567 , jid , [ ] } , { type , 567 , jid , [ ] } , { type , 567 , list , [ { type , 567 , binary , [ ] } ] } ] } , { atom , 567 , ok } ] } ] } ) .


caps_update(From, To, _Features) ->
    send_last_pep(To, From).

- spec ( { { presence_probe , 3 } , [ { type , 571 , 'fun' , [ { type , 571 , product , [ { type , 571 , jid , [ ] } , { type , 571 , jid , [ ] } , { type , 571 , pid , [ ] } ] } , { atom , 571 , ok } ] } ] } ) .


presence_probe(#jid{luser = U, lserver = S},
	       #jid{luser = U, lserver = S}, _Pid) ->
    %% ignore presence_probe from my other ressources
    ok;
presence_probe(#jid{lserver = S} = From,
	       #jid{lserver = S} = To, _Pid) ->
    send_last_pep(To, From);
presence_probe(_From, _To, _Pid) ->
    %% ignore presence_probe from remote contacts, those are handled via caps_add
    ok.

- spec ( { { on_self_presence , 1 } , [ { type , 581 , 'fun' , [ { type , 581 , product , [ { type , 581 , tuple , [ { type , 581 , presence , [ ] } , { remote_type , 581 , [ { atom , 581 , ejabberd_c2s } , { atom , 581 , state } , [ ] ] } ] } ] } , { type , 582 , tuple , [ { type , 582 , presence , [ ] } , { remote_type , 582 , [ { atom , 582 , ejabberd_c2s } , { atom , 582 , state } , [ ] ] } ] } ] } ] } ) .


on_self_presence ( { _ , # { pres_last : = _ } } = Acc ) -> Acc ; on_self_presence ( { # presence { type = available } , # { jid : = JID } } = Acc ) -> send_last_items ( JID ) , Acc ; on_self_presence ( Acc ) -> Acc .


 % Just a presence update.

- spec ( { { on_user_offline , 2 } , [ { type , 591 , 'fun' , [ { type , 591 , product , [ { remote_type , 591 , [ { atom , 591 , ejabberd_c2s } , { atom , 591 , state } , [ ] ] } , { type , 591 , atom , [ ] } ] } , { remote_type , 591 , [ { atom , 591 , ejabberd_c2s } , { atom , 591 , state } , [ ] ] } ] } ] } ) .


on_user_offline ( # { jid : = JID } = C2SState , _Reason ) -> purge_offline ( jid : tolower ( JID ) ) , C2SState ; on_user_offline ( C2SState , _Reason ) -> C2SState .


%% -------
%% subscription hooks handling functions
%%

- spec ( { { out_subscription , 1 } , [ { type , 602 , 'fun' , [ { type , 602 , product , [ { type , 602 , presence , [ ] } ] } , { type , 602 , any , [ ] } ] } ] } ) .


out_subscription(#presence{type = subscribed,
			   from = From, to = To}) ->
    send_last_pep(jid:remove_resource(From), To);
out_subscription(_) -> ok.

- spec ( { { in_subscription , 2 } , [ { type , 608 , 'fun' , [ { type , 608 , product , [ { type , 608 , boolean , [ ] } , { type , 608 , presence , [ ] } ] } , { atom , 608 , true } ] } ] } ) .


in_subscription(_,
		#presence{to = To, from = Owner,
			  type = unsubscribed}) ->
    unsubscribe_user(jid:remove_resource(To), Owner), true;
in_subscription(_, _) -> true.

unsubscribe_user(Entity, Owner) ->
    spawn(fun () ->
		  [unsubscribe_user(ServerHost, Entity, Owner)
		   || ServerHost
			  <- lists:usort(lists:foldl(fun (UserHost, Acc) ->
							     case
							       gen_mod:is_loaded(UserHost,
										 mod_pubsub)
								 of
							       true ->
								   [UserHost
								    | Acc];
							       false -> Acc
							     end
						     end,
						     [],
						     [Entity#jid.lserver,
						      Owner#jid.lserver]))]
	  end).

unsubscribe_user(Host, Entity, Owner) ->
    BJID = jid:tolower(jid:remove_resource(Owner)),
    lists:foreach(fun (PType) ->
			  {result, Subs} = node_action(Host, PType,
						       get_entity_subscriptions,
						       [Host, Entity]),
			  lists:foreach(fun ({#pubsub_node{options = Options,
							   owners = O,
							   id = Nidx},
					      subscribed, _, JID}) ->
						Unsubscribe =
						    match_option(Options,
								 access_model,
								 presence)
						      andalso
						      lists:member(BJID,
								   node_owners_action(Host,
										      PType,
										      Nidx,
										      O)),
						case Unsubscribe of
						  true ->
						      node_action(Host, PType,
								  unsubscribe_node,
								  [Nidx, Entity,
								   JID, all]);
						  false -> ok
						end;
					    (_) -> ok
					end,
					Subs)
		  end,
		  plugins(Host)).

%% -------
%% user remove hook handling function
%%

- spec ( { { remove_user , 2 } , [ { type , 657 , 'fun' , [ { type , 657 , product , [ { type , 657 , binary , [ ] } , { type , 657 , binary , [ ] } ] } , { atom , 657 , ok } ] } ] } ) .


remove_user(User, Server) ->
    LUser = jid:nodeprep(User),
    LServer = jid:nameprep(Server),
    Entity = jid:make(LUser, LServer),
    Host = host(LServer),
    HomeTreeBase = <<"/home/", LServer/binary, "/",
		     LUser/binary>>,
    spawn(fun () ->
		  lists:foreach(fun (PType) ->
					{result, Subs} = node_action(Host,
								     PType,
								     get_entity_subscriptions,
								     [Host,
								      Entity]),
					lists:foreach(fun ({#pubsub_node{id =
									     Nidx},
							    _, _, JID}) ->
							      node_action(Host,
									  PType,
									  unsubscribe_node,
									  [Nidx,
									   Entity,
									   JID,
									   all]);
							  (_) -> ok
						      end,
						      Subs),
					{result, Affs} = node_action(Host,
								     PType,
								     get_entity_affiliations,
								     [Host,
								      Entity]),
					lists:foreach(fun ({#pubsub_node{nodeid
									     =
									     {H,
									      N},
									 parents
									     =
									     []},
							    owner}) ->
							      delete_node(H, N,
									  Entity);
							  ({#pubsub_node{nodeid
									     =
									     {H,
									      N},
									 type =
									     Type},
							    owner})
							      when N ==
								     HomeTreeBase,
								   Type ==
								     <<"hometree">> ->
							      delete_node(H, N,
									  Entity);
							  ({#pubsub_node{id =
									     Nidx},
							    _}) ->
							      {result, State} =
								  node_action(Host,
									      PType,
									      get_state,
									      [Nidx,
									       jid:tolower(Entity)]),
							      ItemIds =
								  State#pubsub_state.items,
							      node_action(Host,
									  PType,
									  remove_extra_items,
									  [Nidx,
									   0,
									   ItemIds]),
							      node_action(Host,
									  PType,
									  set_affiliation,
									  [Nidx,
									   Entity,
									   none])
						      end,
						      Affs)
				end,
				plugins(Host))
	  end),
    ok.

handle_call(server_host, _From, State) ->
    {reply, State#state.server_host, State};
handle_call(plugins, _From, State) ->
    {reply, State#state.plugins, State};
handle_call(pep_mapping, _From, State) ->
    {reply, State#state.pep_mapping, State};
handle_call(nodetree, _From, State) ->
    {reply, State#state.nodetree, State};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
%% @private
handle_cast(_Msg, State) -> {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
%% @private
handle_info({route, #iq{to = To} = IQ}, State)
    when To#jid.lresource == <<"">> ->
    ejabberd_router:process_iq(IQ), {noreply, State};
handle_info({route, Packet}, State) ->
    To = xmpp:get_to(Packet),
    case catch do_route(To#jid.lserver, Packet) of
      {'EXIT', Reason} -> ?ERROR_MSG("~p", [Reason]);
      _ -> ok
    end,
    {noreply, State};
handle_info(_Info, State) -> {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
%% @private
terminate(_Reason,
	  #state{hosts = Hosts, server_host = ServerHost,
		 nodetree = TreePlugin, plugins = Plugins}) ->
    case lists:member(?PEPNODE, Plugins) of
      true ->
	  ejabberd_hooks:delete(caps_add, ServerHost, ?MODULE,
				caps_add, 80),
	  ejabberd_hooks:delete(caps_update, ServerHost, ?MODULE,
				caps_update, 80),
	  ejabberd_hooks:delete(disco_sm_identity, ServerHost,
				?MODULE, disco_sm_identity, 75),
	  ejabberd_hooks:delete(disco_sm_features, ServerHost,
				?MODULE, disco_sm_features, 75),
	  ejabberd_hooks:delete(disco_sm_items, ServerHost,
				?MODULE, disco_sm_items, 75),
	  gen_iq_handler:remove_iq_handler(ejabberd_sm,
					   ServerHost, ?NS_PUBSUB),
	  gen_iq_handler:remove_iq_handler(ejabberd_sm,
					   ServerHost, ?NS_PUBSUB_OWNER);
      false -> ok
    end,
    ejabberd_hooks:delete(c2s_self_presence, ServerHost,
			  ?MODULE, on_self_presence, 75),
    ejabberd_hooks:delete(c2s_terminated, ServerHost,
			  ?MODULE, on_user_offline, 75),
    ejabberd_hooks:delete(disco_local_identity, ServerHost,
			  ?MODULE, disco_local_identity, 75),
    ejabberd_hooks:delete(disco_local_features, ServerHost,
			  ?MODULE, disco_local_features, 75),
    ejabberd_hooks:delete(disco_local_items, ServerHost,
			  ?MODULE, disco_local_items, 75),
    ejabberd_hooks:delete(presence_probe_hook, ServerHost,
			  ?MODULE, presence_probe, 80),
    ejabberd_hooks:delete(roster_in_subscription,
			  ServerHost, ?MODULE, in_subscription, 50),
    ejabberd_hooks:delete(roster_out_subscription,
			  ServerHost, ?MODULE, out_subscription, 50),
    ejabberd_hooks:delete(remove_user, ServerHost, ?MODULE,
			  remove_user, 50),
    ejabberd_hooks:delete(c2s_handle_info, ServerHost,
			  ?MODULE, c2s_handle_info, 50),
    lists:foreach(fun (Host) ->
			  gen_iq_handler:remove_iq_handler(ejabberd_local, Host,
							   ?NS_DISCO_INFO),
			  gen_iq_handler:remove_iq_handler(ejabberd_local, Host,
							   ?NS_DISCO_ITEMS),
			  gen_iq_handler:remove_iq_handler(ejabberd_local, Host,
							   ?NS_PUBSUB),
			  gen_iq_handler:remove_iq_handler(ejabberd_local, Host,
							   ?NS_PUBSUB_OWNER),
			  gen_iq_handler:remove_iq_handler(ejabberd_local, Host,
							   ?NS_VCARD),
			  gen_iq_handler:remove_iq_handler(ejabberd_local, Host,
							   ?NS_COMMANDS),
			  terminate_plugins(Host, ServerHost, Plugins,
					    TreePlugin),
			  ejabberd_router:unregister_route(Host)
		  end,
		  Hosts).

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
%% @private
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
- spec ( { { process_disco_info , 1 } , [ { type , 817 , 'fun' , [ { type , 817 , product , [ { type , 817 , iq , [ ] } ] } , { type , 817 , iq , [ ] } ] } ] } ) .


process_disco_info(#iq{type = set, lang = Lang} = IQ) ->
    Txt = <<"Value 'set' of 'type' attribute is not "
	    "allowed">>,
    xmpp:make_error(IQ, xmpp:err_not_allowed(Txt, Lang));
process_disco_info(#iq{from = From, to = To,
		       lang = Lang, type = get,
		       sub_els = [#disco_info{node = Node}]} =
		       IQ) ->
    Host = To#jid.lserver,
    ServerHost = ejabberd_router:host_of_route(Host),
    Info = ejabberd_hooks:run_fold(disco_info, ServerHost,
				   [], [ServerHost, ?MODULE, <<>>, <<>>]),
    case iq_disco_info(ServerHost, Host, Node, From, Lang)
	of
      {result, IQRes} ->
	  XData = IQRes#disco_info.xdata ++ Info,
	  xmpp:make_iq_result(IQ,
			      IQRes#disco_info{node = Node, xdata = XData});
      {error, Error} -> xmpp:make_error(IQ, Error)
    end.

- spec ( { { process_disco_items , 1 } , [ { type , 836 , 'fun' , [ { type , 836 , product , [ { type , 836 , iq , [ ] } ] } , { type , 836 , iq , [ ] } ] } ] } ) .


process_disco_items(#iq{type = set, lang = Lang} =
			IQ) ->
    Txt = <<"Value 'set' of 'type' attribute is not "
	    "allowed">>,
    xmpp:make_error(IQ, xmpp:err_not_allowed(Txt, Lang));
process_disco_items(#iq{type = get, from = From,
			to = To,
			sub_els = [#disco_items{node = Node} = SubEl]} =
			IQ) ->
    Host = To#jid.lserver,
    case iq_disco_items(Host, Node, From,
			SubEl#disco_items.rsm)
	of
      {result, IQRes} ->
	  xmpp:make_iq_result(IQ, IQRes#disco_items{node = Node});
      {error, Error} -> xmpp:make_error(IQ, Error)
    end.

- spec ( { { process_pubsub , 1 } , [ { type , 850 , 'fun' , [ { type , 850 , product , [ { type , 850 , iq , [ ] } ] } , { type , 850 , iq , [ ] } ] } ] } ) .


process_pubsub(#iq{to = To} = IQ) ->
    Host = To#jid.lserver,
    ServerHost = ejabberd_router:host_of_route(Host),
    Access = config(ServerHost, access),
    case iq_pubsub(Host, Access, IQ) of
      {result, IQRes} -> xmpp:make_iq_result(IQ, IQRes);
      {error, Error} -> xmpp:make_error(IQ, Error)
    end.

- spec ( { { process_pubsub_owner , 1 } , [ { type , 862 , 'fun' , [ { type , 862 , product , [ { type , 862 , iq , [ ] } ] } , { type , 862 , iq , [ ] } ] } ] } ) .


process_pubsub_owner(#iq{to = To} = IQ) ->
    Host = To#jid.lserver,
    case iq_pubsub_owner(Host, IQ) of
      {result, IQRes} -> xmpp:make_iq_result(IQ, IQRes);
      {error, Error} -> xmpp:make_error(IQ, Error)
    end.

- spec ( { { process_vcard , 1 } , [ { type , 872 , 'fun' , [ { type , 872 , product , [ { type , 872 , iq , [ ] } ] } , { type , 872 , iq , [ ] } ] } ] } ) .


process_vcard(#iq{type = get, lang = Lang} = IQ) ->
    xmpp:make_iq_result(IQ, iq_get_vcard(Lang));
process_vcard(#iq{type = set, lang = Lang} = IQ) ->
    Txt = <<"Value 'set' of 'type' attribute is not "
	    "allowed">>,
    xmpp:make_error(IQ, xmpp:err_not_allowed(Txt, Lang)).

- spec ( { { process_commands , 1 } , [ { type , 879 , 'fun' , [ { type , 879 , product , [ { type , 879 , iq , [ ] } ] } , { type , 879 , iq , [ ] } ] } ] } ) .


process_commands(#iq{type = set, to = To, from = From,
		     sub_els = [#adhoc_command{} = Request]} =
		     IQ) ->
    Host = To#jid.lserver,
    ServerHost = ejabberd_router:host_of_route(Host),
    Plugins = config(ServerHost, plugins),
    Access = config(ServerHost, access),
    case adhoc_request(Host, ServerHost, From, Request,
		       Access, Plugins)
	of
      {error, Error} -> xmpp:make_error(IQ, Error);
      Response ->
	  xmpp:make_iq_result(IQ,
			      xmpp_util:make_adhoc_response(Request, Response))
    end;
process_commands(#iq{type = get, lang = Lang} = IQ) ->
    Txt = <<"Value 'get' of 'type' attribute is not "
	    "allowed">>,
    xmpp:make_error(IQ, xmpp:err_not_allowed(Txt, Lang)).

- spec ( { { do_route , 2 } , [ { type , 897 , 'fun' , [ { type , 897 , product , [ { type , 897 , binary , [ ] } , { type , 897 , stanza , [ ] } ] } , { atom , 897 , ok } ] } ] } ) .


do_route(Host, Packet) ->
    To = xmpp:get_to(Packet),
    case To of
      #jid{luser = <<>>, lresource = <<>>} ->
	  case Packet of
	    #message{type = T} when T /= error ->
		case find_authorization_response(Packet) of
		  undefined -> ok;
		  {error, Err} ->
		      ejabberd_router:route_error(Packet, Err);
		  AuthResponse ->
		      handle_authorization_response(Host, Packet,
						    AuthResponse)
		end;
	    _ ->
		Err = xmpp:err_service_unavailable(),
		ejabberd_router:route_error(Packet, Err)
	  end;
      _ ->
	  Err = xmpp:err_item_not_found(),
	  ejabberd_router:route_error(Packet, Err)
    end.

- spec ( { { command_disco_info , 3 } , [ { type , 922 , 'fun' , [ { type , 922 , product , [ { type , 922 , binary , [ ] } , { type , 922 , binary , [ ] } , { type , 922 , jid , [ ] } ] } , { type , 922 , tuple , [ { atom , 922 , result } , { type , 922 , disco_info , [ ] } ] } ] } ] } ) .


command_disco_info(_Host, ?NS_COMMANDS, _From) ->
    {result,
     #disco_info{identities =
		     [#identity{category = <<"automation">>,
				type = <<"command-list">>}]}};
command_disco_info(_Host, ?NS_PUBSUB_GET_PENDING,
		   _From) ->
    {result,
     #disco_info{identities =
		     [#identity{category = <<"automation">>,
				type = <<"command-node">>}],
		 features = [?NS_COMMANDS]}}.

- spec ( { { node_disco_info , 3 } , [ { type , 931 , 'fun' , [ { type , 931 , product , [ { type , 931 , binary , [ ] } , { type , 931 , binary , [ ] } , { type , 931 , jid , [ ] } ] } , { type , 931 , union , [ { type , 931 , tuple , [ { atom , 931 , result } , { type , 931 , disco_info , [ ] } ] } , { type , 932 , tuple , [ { atom , 932 , error } , { type , 932 , stanza_error , [ ] } ] } ] } ] } ] } ) .


node_disco_info(Host, Node, From) ->
    node_disco_info(Host, Node, From, true, true).

- spec ( { { node_disco_info , 5 } , [ { type , 936 , 'fun' , [ { type , 936 , product , [ { type , 936 , binary , [ ] } , { type , 936 , binary , [ ] } , { type , 936 , jid , [ ] } , { type , 936 , boolean , [ ] } , { type , 936 , boolean , [ ] } ] } , { type , 937 , union , [ { type , 937 , tuple , [ { atom , 937 , result } , { type , 937 , disco_info , [ ] } ] } , { type , 937 , tuple , [ { atom , 937 , error } , { type , 937 , stanza_error , [ ] } ] } ] } ] } ] } ) .


node_disco_info(Host, Node, _From, _Identity,
		_Features) ->
    Action = fun (#pubsub_node{id = Nidx, type = Type,
			       options = Options}) ->
		     NodeType = case get_option(Options, node_type) of
				  collection -> <<"collection">>;
				  _ -> <<"leaf">>
				end,
		     Affs = case node_call(Host, Type, get_node_affiliations,
					   [Nidx])
				of
			      {result, As} -> As;
			      _ -> []
			    end,
		     Subs = case node_call(Host, Type,
					   get_node_subscriptions, [Nidx])
				of
			      {result, Ss} -> Ss;
			      _ -> []
			    end,
		     Meta = [{title, get_option(Options, title, <<>>)},
			     {description,
			      get_option(Options, description, <<>>)},
			     {owner,
			      [jid:make(LJID)
			       || {LJID, Aff} <- Affs, Aff =:= owner]},
			     {publisher,
			      [jid:make(LJID)
			       || {LJID, Aff} <- Affs, Aff =:= publisher]},
			     {num_subscribers, length(Subs)}],
		     XData = #xdata{type = result,
				    fields = pubsub_meta_data:encode(Meta)},
		     Is = [#identity{category = <<"pubsub">>,
				     type = NodeType}],
		     Fs = [?NS_PUBSUB | [feature(F)
					 || F <- plugin_features(Host, Type)]],
		     {result,
		      #disco_info{identities = Is, features = Fs,
				  xdata = [XData]}}
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_, Result}} -> {result, Result};
      Other -> Other
    end.

- spec ( { { iq_disco_info , 5 } , [ { type , 969 , 'fun' , [ { type , 969 , product , [ { type , 969 , binary , [ ] } , { type , 969 , binary , [ ] } , { type , 969 , binary , [ ] } , { type , 969 , jid , [ ] } , { type , 969 , binary , [ ] } ] } , { type , 970 , union , [ { type , 970 , tuple , [ { atom , 970 , result } , { type , 970 , disco_info , [ ] } ] } , { type , 970 , tuple , [ { atom , 970 , error } , { type , 970 , stanza_error , [ ] } ] } ] } ] } ] } ) .


iq_disco_info(ServerHost, Host, SNode, From, Lang) ->
    [Node | _] = case SNode of
		   <<>> -> [<<>>];
		   _ -> str:tokens(SNode, <<"!">>)
		 end,
    case Node of
      <<>> ->
	  Name = gen_mod:get_module_opt(ServerHost, ?MODULE,
					name),
	  {result,
	   #disco_info{identities =
			   [#identity{category = <<"pubsub">>,
				      type = <<"service">>,
				      name = translate:translate(Lang, Name)}],
		       features =
			   [?NS_DISCO_INFO, ?NS_DISCO_ITEMS, ?NS_PUBSUB,
			    ?NS_COMMANDS, ?NS_VCARD
			    | [feature(F) || F <- features(Host, Node)]]}};
      ?NS_COMMANDS -> command_disco_info(Host, Node, From);
      ?NS_PUBSUB_GET_PENDING ->
	  command_disco_info(Host, Node, From);
      _ -> node_disco_info(Host, Node, From)
    end.

- spec ( { { iq_disco_items , 4 } , [ { type , 999 , 'fun' , [ { type , 999 , product , [ { type , 999 , host , [ ] } , { type , 999 , binary , [ ] } , { type , 999 , jid , [ ] } , { type , 999 , union , [ { atom , 999 , undefined } , { type , 999 , rsm_set , [ ] } ] } ] } , { type , 1000 , union , [ { type , 1000 , tuple , [ { atom , 1000 , result } , { type , 1000 , disco_items , [ ] } ] } , { type , 1000 , tuple , [ { atom , 1000 , error } , { type , 1000 , stanza_error , [ ] } ] } ] } ] } ] } ) .


iq_disco_items(Host, <<>>, From, _RSM) ->
    Items = [iq_disco_items_1(V1, Host)
	     || V1
		    <- tree_action(Host, get_subnodes, [Host, <<>>, From])],
    {result, #disco_items{items = Items}};
iq_disco_items(Host, ?NS_COMMANDS, _From, _RSM) ->
    {result,
     #disco_items{items =
		      [#disco_item{jid = jid:make(Host),
				   node = ?NS_PUBSUB_GET_PENDING,
				   name = <<"Get Pending">>}]}};
iq_disco_items(_Host, ?NS_PUBSUB_GET_PENDING, _From,
	       _RSM) ->
    {result, #disco_items{}};
iq_disco_items(Host, Item, From, RSM) ->
    case str:tokens(Item, <<"!">>) of
      [_Node, _ItemId] -> {result, #disco_items{}};
      [Node] ->
	  Action = fun (#pubsub_node{id = Nidx, type = Type,
				     options = Options, owners = O}) ->
			   Owners = node_owners_call(Host, Type, Nidx, O),
			   {NodeItems, RsmOut} = case
						   get_allowed_items_call(Host,
									  Nidx,
									  From,
									  Type,
									  Options,
									  Owners,
									  RSM)
						     of
						   {result, R} -> R;
						   _ -> {[], undefined}
						 end,
			   Nodes = [iq_disco_items_2(V2, Host)
				    || V2
					   <- tree_call(Host, get_subnodes,
							[Host, Node, From])],
			   Items = [iq_disco_items_1(V3, Host, Node, Type)
				    || V3 <- NodeItems],
			   {result,
			    #disco_items{items = Nodes ++ Items, rsm = RsmOut}}
		   end,
	  case transaction(Host, Node, Action, sync_dirty) of
	    {result, {_, Result}} -> {result, Result};
	    Other -> Other
	  end
    end.

iq_disco_items_1(#pubsub_node{nodeid = {_, SubNode},
			      options = Options},
		 Host) ->
    case get_option(Options, title) of
      false ->
	  #disco_item{jid = jid:make(Host), node = SubNode};
      Title ->
	  #disco_item{jid = jid:make(Host), name = Title,
		      node = SubNode}
    end.

iq_disco_items_2(#pubsub_node{nodeid = {_, SubNode},
			      options = SubOptions},
		 Host) ->
    case get_option(SubOptions, title) of
      false ->
	  #disco_item{jid = jid:make(Host), node = SubNode};
      Title ->
	  #disco_item{jid = jid:make(Host), name = Title,
		      node = SubNode}
    end.

iq_disco_items_1(#pubsub_item{itemid = {RN, _}}, Host,
		 Node, Type) ->
    {result, Name} = node_call(Host, Type, get_item_name,
			       [Host, Node, RN]),
    #disco_item{jid = jid:make(Host), name = Name}.

- spec ( { { iq_sm , 1 } , [ { type , 1063 , 'fun' , [ { type , 1063 , product , [ { type , 1063 , iq , [ ] } ] } , { type , 1063 , iq , [ ] } ] } ] } ) .


iq_sm(#iq{to = To, sub_els = [SubEl]} = IQ) ->
    LOwner = jid:tolower(jid:remove_resource(To)),
    Res = case xmpp:get_ns(SubEl) of
	    ?NS_PUBSUB -> iq_pubsub(LOwner, all, IQ);
	    ?NS_PUBSUB_OWNER -> iq_pubsub_owner(LOwner, IQ)
	  end,
    case Res of
      {result, IQRes} -> xmpp:make_iq_result(IQ, IQRes);
      {error, Error} -> xmpp:make_error(IQ, Error)
    end.

- spec ( { { iq_get_vcard , 1 } , [ { type , 1079 , 'fun' , [ { type , 1079 , product , [ { type , 1079 , binary , [ ] } ] } , { type , 1079 , vcard_temp , [ ] } ] } ] } ) .


iq_get_vcard(Lang) ->
    Desc = misc:get_descr(Lang,
			  ?T("ejabberd Publish-Subscribe module")),
    #vcard_temp{fn = <<"ejabberd/mod_pubsub">>,
		url = ejabberd_config:get_uri(), desc = Desc}.

- spec ( { { iq_pubsub , 3 } , [ { type , 1086 , 'fun' , [ { type , 1086 , product , [ { type , 1086 , union , [ { type , 1086 , binary , [ ] } , { type , 1086 , ljid , [ ] } ] } , { type , 1086 , atom , [ ] } , { type , 1086 , iq , [ ] } ] } , { type , 1087 , union , [ { type , 1087 , tuple , [ { atom , 1087 , result } , { type , 1087 , pubsub , [ ] } ] } , { type , 1087 , tuple , [ { atom , 1087 , error } , { type , 1087 , stanza_error , [ ] } ] } ] } ] } ] } ) .


iq_pubsub(Host, Access,
	  #iq{from = From, type = IQType, lang = Lang,
	      sub_els = [SubEl]}) ->
    case {IQType, SubEl} of
      {set,
       #pubsub{create = Node, configure = Configure,
	       _ = undefined}}
	  when is_binary(Node) ->
	  ServerHost = serverhost(Host),
	  Plugins = config(ServerHost, plugins),
	  Config = case Configure of
		     {_, XData} -> decode_node_config(XData, Host, Lang);
		     undefined -> []
		   end,
	  Type = hd(Plugins),
	  case Config of
	    {error, _} = Err -> Err;
	    _ ->
		create_node(Host, ServerHost, Node, From, Type, Access,
			    Config)
	  end;
      {set,
       #pubsub{publish =
		   #ps_publish{node = Node, items = Items},
	       publish_options = XData, configure = _,
	       _ = undefined}} ->
	  ServerHost = serverhost(Host),
	  case Items of
	    [#ps_item{id = ItemId, sub_els = Payload}] ->
		case decode_publish_options(XData, Lang) of
		  {error, _} = Err -> Err;
		  PubOpts ->
		      publish_item(Host, ServerHost, Node, From, ItemId,
				   Payload, PubOpts, Access)
		end;
	    [] ->
		publish_item(Host, ServerHost, Node, From, <<>>, [], [],
			     Access);
	    _ ->
		{error,
		 extended_error(xmpp:err_bad_request(),
				err_invalid_payload())}
	  end;
      {set,
       #pubsub{retract =
		   #ps_retract{node = Node, notify = Notify,
			       items = Items},
	       _ = undefined}} ->
	  case Items of
	    [#ps_item{id = ItemId}] ->
		if ItemId /= <<>> ->
		       delete_item(Host, Node, From, ItemId, Notify);
		   true ->
		       {error,
			extended_error(xmpp:err_bad_request(),
				       err_item_required())}
		end;
	    [] ->
		{error,
		 extended_error(xmpp:err_bad_request(),
				err_item_required())};
	    _ ->
		{error,
		 extended_error(xmpp:err_bad_request(),
				err_invalid_payload())}
	  end;
      {set,
       #pubsub{subscribe =
		   #ps_subscribe{node = Node, jid = JID},
	       options = Options, _ = undefined}} ->
	  Config = case Options of
		     #ps_options{xdata = XData, jid = undefined,
				 node = <<>>} ->
			 decode_subscribe_options(XData, Lang);
		     #ps_options{xdata = _XData, jid = #jid{}} ->
			 Txt = <<"Attribute 'jid' is not allowed here">>,
			 {error, xmpp:err_bad_request(Txt, Lang)};
		     #ps_options{xdata = _XData} ->
			 Txt = <<"Attribute 'node' is not allowed here">>,
			 {error, xmpp:err_bad_request(Txt, Lang)};
		     _ -> []
		   end,
	  case Config of
	    {error, _} = Err -> Err;
	    _ -> subscribe_node(Host, Node, From, JID, Config)
	  end;
      {set,
       #pubsub{unsubscribe =
		   #ps_unsubscribe{node = Node, jid = JID, subid = SubId},
	       _ = undefined}} ->
	  unsubscribe_node(Host, Node, From, JID, SubId);
      {get,
       #pubsub{items =
		   #ps_items{node = Node, max_items = MaxItems,
			     subid = SubId, items = Items},
	       rsm = RSM, _ = undefined}} ->
	  ItemIds = [ItemId
		     || #ps_item{id = ItemId} <- Items, ItemId /= <<>>],
	  get_items(Host, Node, From, SubId, MaxItems, ItemIds,
		    RSM);
      {get,
       #pubsub{subscriptions = {Node, _}, _ = undefined}} ->
	  Plugins = config(serverhost(Host), plugins),
	  get_subscriptions(Host, Node, From, Plugins);
      {get,
       #pubsub{affiliations = {Node, _}, _ = undefined}} ->
	  Plugins = config(serverhost(Host), plugins),
	  get_affiliations(Host, Node, From, Plugins);
      {_,
       #pubsub{options = #ps_options{jid = undefined},
	       _ = undefined}} ->
	  {error,
	   extended_error(xmpp:err_bad_request(),
			  err_jid_required())};
      {_,
       #pubsub{options = #ps_options{node = <<>>},
	       _ = undefined}} ->
	  {error,
	   extended_error(xmpp:err_bad_request(),
			  err_nodeid_required())};
      {get,
       #pubsub{options =
		   #ps_options{node = Node, subid = SubId, jid = JID},
	       _ = undefined}} ->
	  get_options(Host, Node, JID, SubId, Lang);
      {set,
       #pubsub{options =
		   #ps_options{node = Node, subid = SubId, jid = JID,
			       xdata = XData},
	       _ = undefined}} ->
	  case decode_subscribe_options(XData, Lang) of
	    {error, _} = Err -> Err;
	    Config -> set_options(Host, Node, JID, SubId, Config)
	  end;
      {set, #pubsub{}} -> {error, xmpp:err_bad_request()};
      _ -> {error, xmpp:err_feature_not_implemented()}
    end.

- spec ( { { iq_pubsub_owner , 2 } , [ { type , 1196 , 'fun' , [ { type , 1196 , product , [ { type , 1196 , union , [ { type , 1196 , binary , [ ] } , { type , 1196 , ljid , [ ] } ] } , { type , 1196 , iq , [ ] } ] } , { type , 1196 , union , [ { type , 1196 , tuple , [ { atom , 1196 , result } , { type , 1196 , union , [ { type , 1196 , pubsub_owner , [ ] } , { atom , 1196 , undefined } ] } ] } , { type , 1197 , tuple , [ { atom , 1197 , error } , { type , 1197 , stanza_error , [ ] } ] } ] } ] } ] } ) .


iq_pubsub_owner(Host,
		#iq{type = IQType, from = From, lang = Lang,
		    sub_els = [SubEl]}) ->
    case {IQType, SubEl} of
      {get,
       #pubsub_owner{configure = {Node, undefined},
		     _ = undefined}} ->
	  ServerHost = serverhost(Host),
	  get_configure(Host, ServerHost, Node, From, Lang);
      {set,
       #pubsub_owner{configure = {Node, XData},
		     _ = undefined}} ->
	  case XData of
	    undefined ->
		{error,
		 xmpp:err_bad_request(<<"No data form found">>, Lang)};
	    #xdata{type = cancel} -> {result, #pubsub_owner{}};
	    #xdata{type = submit} ->
		case decode_node_config(XData, Host, Lang) of
		  {error, _} = Err -> Err;
		  Config -> set_configure(Host, Node, From, Config, Lang)
		end;
	    #xdata{} ->
		{error,
		 xmpp:err_bad_request(<<"Incorrect data form">>, Lang)}
	  end;
      {get,
       #pubsub_owner{default = {Node, undefined},
		     _ = undefined}} ->
	  get_default(Host, Node, From, Lang);
      {set,
       #pubsub_owner{delete = {Node, _}, _ = undefined}} ->
	  delete_node(Host, Node, From);
      {set, #pubsub_owner{purge = Node, _ = undefined}}
	  when Node /= undefined ->
	  purge_node(Host, Node, From);
      {get,
       #pubsub_owner{subscriptions = {Node, []},
		     _ = undefined}} ->
	  get_subscriptions(Host, Node, From);
      {set,
       #pubsub_owner{subscriptions = {Node, Subs},
		     _ = undefined}} ->
	  set_subscriptions(Host, Node, From, Subs);
      {get,
       #pubsub_owner{affiliations = {Node, []},
		     _ = undefined}} ->
	  get_affiliations(Host, Node, From);
      {set,
       #pubsub_owner{affiliations = {Node, Affs},
		     _ = undefined}} ->
	  set_affiliations(Host, Node, From, Affs);
      {_, #pubsub_owner{}} -> {error, xmpp:err_bad_request()};
      _ -> {error, xmpp:err_feature_not_implemented()}
    end.

- spec ( { { adhoc_request , 6 } , [ { type , 1240 , 'fun' , [ { type , 1240 , product , [ { type , 1240 , binary , [ ] } , { type , 1240 , binary , [ ] } , { type , 1240 , jid , [ ] } , { type , 1240 , adhoc_command , [ ] } , { type , 1241 , atom , [ ] } , { type , 1241 , list , [ { type , 1241 , binary , [ ] } ] } ] } , { type , 1241 , union , [ { type , 1241 , adhoc_command , [ ] } , { type , 1241 , tuple , [ { atom , 1241 , error } , { type , 1241 , stanza_error , [ ] } ] } ] } ] } ] } ) .


adhoc_request(Host, _ServerHost, Owner,
	      #adhoc_command{node = ?NS_PUBSUB_GET_PENDING,
			     lang = Lang, action = execute, xdata = undefined},
	      _Access, Plugins) ->
    send_pending_node_form(Host, Owner, Lang, Plugins);
adhoc_request(Host, _ServerHost, Owner,
	      #adhoc_command{node = ?NS_PUBSUB_GET_PENDING,
			     lang = Lang, action = execute,
			     xdata = #xdata{} = XData} =
		  Request,
	      _Access, _Plugins) ->
    case decode_get_pending(XData, Lang) of
      {error, _} = Err -> Err;
      Config ->
	  Node = proplists:get_value(node, Config),
	  case send_pending_auth_events(Host, Node, Owner, Lang)
	      of
	    ok ->
		xmpp_util:make_adhoc_response(Request,
					      #adhoc_command{action =
								 completed});
	    Err -> Err
	  end
    end;
adhoc_request(_Host, _ServerHost, _Owner,
	      #adhoc_command{action = cancel}, _Access, _Plugins) ->
    #adhoc_command{status = canceled};
adhoc_request(_Host, _ServerHost, _Owner, Other,
	      _Access, _Plugins) ->
    ?DEBUG("Couldn't process ad hoc command:~n~p", [Other]),
    {error, xmpp:err_item_not_found()}.

- spec ( { { send_pending_node_form , 4 } , [ { type , 1271 , 'fun' , [ { type , 1271 , product , [ { type , 1271 , binary , [ ] } , { type , 1271 , jid , [ ] } , { type , 1271 , binary , [ ] } , { type , 1272 , list , [ { type , 1272 , binary , [ ] } ] } ] } , { type , 1272 , union , [ { type , 1272 , adhoc_command , [ ] } , { type , 1272 , tuple , [ { atom , 1272 , error } , { type , 1272 , stanza_error , [ ] } ] } ] } ] } ] } ) .


send_pending_node_form(Host, Owner, Lang, Plugins) ->
    Filter = fun (Type) ->
		     lists:member(<<"get-pending">>,
				  plugin_features(Host, Type))
	     end,
    case lists:filter(Filter, Plugins) of
      [] ->
	  Err = extended_error(xmpp:err_feature_not_implemented(),
			       err_unsupported('get-pending')),
	  {error, Err};
      Ps ->
	  case get_pending_nodes(Host, Owner, Ps) of
	    {ok, Nodes} ->
		XForm = #xdata{type = form,
			       fields =
				   pubsub_get_pending:encode([{node, Nodes}],
							     Lang)},
		#adhoc_command{status = executing, action = execute,
			       xdata = XForm};
	    Err -> Err
	  end
    end.

- spec ( { { get_pending_nodes , 3 } , [ { type , 1295 , 'fun' , [ { type , 1295 , product , [ { type , 1295 , binary , [ ] } , { type , 1295 , jid , [ ] } , { type , 1295 , list , [ { type , 1295 , binary , [ ] } ] } ] } , { type , 1295 , union , [ { type , 1295 , tuple , [ { atom , 1295 , ok } , { type , 1295 , list , [ { type , 1295 , binary , [ ] } ] } ] } , { type , 1296 , tuple , [ { atom , 1296 , error } , { type , 1296 , stanza_error , [ ] } ] } ] } ] } ] } ) .


get_pending_nodes(Host, Owner, Plugins) ->
    Tr = fun (Type) ->
		 case node_call(Host, Type, get_pending_nodes,
				[Host, Owner])
		     of
		   {result, Nodes} -> Nodes;
		   _ -> []
		 end
	 end,
    Action = fun () -> {result, lists:flatmap(Tr, Plugins)}
	     end,
    case transaction(Host, Action, sync_dirty) of
      {result, Res} -> {ok, Res};
      Err -> Err
    end.

%% @doc <p>Send a subscription approval form to Owner for all pending
%% subscriptions on Host and Node.</p>
- spec ( { { send_pending_auth_events , 4 } , [ { type , 1312 , 'fun' , [ { type , 1312 , product , [ { type , 1312 , binary , [ ] } , { type , 1312 , binary , [ ] } , { type , 1312 , jid , [ ] } , { type , 1313 , binary , [ ] } ] } , { type , 1313 , union , [ { type , 1313 , adhoc_command , [ ] } , { type , 1313 , tuple , [ { atom , 1313 , error } , { type , 1313 , stanza_error , [ ] } ] } ] } ] } ] } ) .


send_pending_auth_events(Host, Node, Owner, Lang) ->
    ?DEBUG("Sending pending auth events for ~s on "
	   "~s:~s",
	   [jid:encode(Owner), Host, Node]),
    Action = fun (#pubsub_node{id = Nidx, type = Type}) ->
		     case lists:member(<<"get-pending">>,
				       plugin_features(Host, Type))
			 of
		       true ->
			   case node_call(Host, Type, get_affiliation,
					  [Nidx, Owner])
			       of
			     {result, owner} ->
				 node_call(Host, Type, get_node_subscriptions,
					   [Nidx]);
			     _ ->
				 {error,
				  xmpp:err_forbidden(<<"Owner privileges required">>,
						     Lang)}
			   end;
		       false ->
			   {error,
			    extended_error(xmpp:err_feature_not_implemented(),
					   err_unsupported('get-pending'))}
		     end
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {N, Subs}} ->
	  lists:foreach(fun ({J, pending, _SubId}) ->
				send_authorization_request(N, jid:make(J));
			    ({J, pending}) ->
				send_authorization_request(N, jid:make(J));
			    (_) -> ok
			end,
			Subs),
	  #adhoc_command{};
      Err -> Err
    end.

%%% authorization handling
- spec ( { { send_authorization_request , 2 } , [ { type , 1346 , 'fun' , [ { type , 1346 , product , [ { type , 1346 , record , [ { atom , 1346 , pubsub_node } ] } , { type , 1346 , jid , [ ] } ] } , { atom , 1346 , ok } ] } ] } ) .


send_authorization_request(#pubsub_node{nodeid =
					    {Host, Node},
					type = Type, id = Nidx, owners = O},
			   Subscriber) ->
    %% TODO: pass lang to this function
    Lang = <<"en">>,
    Fs = pubsub_subscribe_authorization:encode([{node,
						 Node},
						{subscriber_jid, Subscriber},
						{allow, false}],
					       Lang),
    X = #xdata{type = form,
	       title =
		   translate:translate(Lang,
				       <<"PubSub subscriber request">>),
	       instructions =
		   [translate:translate(Lang,
					<<"Choose whether to approve this entity's "
					  "subscription.">>)],
	       fields = Fs},
    Stanza = #message{from = service_jid(Host),
		      sub_els = [X]},
    lists:foreach(fun (Owner) ->
			  ejabberd_router:route(xmpp:set_to(Stanza,
							    jid:make(Owner)))
		  end,
		  node_owners_action(Host, Type, Nidx, O)).

- spec ( { { find_authorization_response , 1 } , [ { type , 1371 , 'fun' , [ { type , 1371 , product , [ { type , 1371 , message , [ ] } ] } , { type , 1371 , union , [ { atom , 1371 , undefined } , { remote_type , 1372 , [ { atom , 1372 , pubsub_subscribe_authorization } , { atom , 1372 , result } , [ ] ] } , { type , 1373 , tuple , [ { atom , 1373 , error } , { type , 1373 , stanza_error , [ ] } ] } ] } ] } ] } ) .


find_authorization_response(Packet) ->
    case xmpp:get_subtag(Packet, #xdata{type = form}) of
      #xdata{type = cancel} -> undefined;
      #xdata{type = submit, fields = Fs} ->
	  try pubsub_subscribe_authorization:decode(Fs) of
	    Result -> Result
	  catch
	    _:{pubsub_subscribe_authorization, Why} ->
		Lang = xmpp:get_lang(Packet),
		Txt = pubsub_subscribe_authorization:format_error(Why),
		{error, xmpp:err_bad_request(Txt, Lang)}
	  end;
      #xdata{} -> {error, xmpp:err_bad_request()};
      false -> undefined
    end.

%% @doc Send a message to JID with the supplied Subscription
- spec ( { { send_authorization_approval , 4 } , [ { type , 1393 , 'fun' , [ { type , 1393 , product , [ { type , 1393 , binary , [ ] } , { type , 1393 , jid , [ ] } , { type , 1393 , binary , [ ] } , { type , 1393 , union , [ { atom , 1393 , subscribed } , { atom , 1393 , none } ] } ] } , { atom , 1393 , ok } ] } ] } ) .


send_authorization_approval(Host, JID, SNode,
			    Subscription) ->
    Event = #ps_event{subscription =
			  #ps_subscription{jid = JID, node = SNode,
					   type = Subscription}},
    Stanza = #message{from = service_jid(Host), to = JID,
		      sub_els = [Event]},
    ejabberd_router:route(Stanza).

- spec ( { { handle_authorization_response , 3 } , [ { type , 1402 , 'fun' , [ { type , 1402 , product , [ { type , 1402 , binary , [ ] } , { type , 1402 , message , [ ] } , { remote_type , 1403 , [ { atom , 1403 , pubsub_subscribe_authorization } , { atom , 1403 , result } , [ ] ] } ] } , { atom , 1403 , ok } ] } ] } ) .


handle_authorization_response(Host,
			      #message{from = From} = Packet, Response) ->
    Node = proplists:get_value(node, Response),
    Subscriber = proplists:get_value(subscriber_jid,
				     Response),
    Allow = proplists:get_value(allow, Response),
    Lang = xmpp:get_lang(Packet),
    FromLJID = jid:tolower(jid:remove_resource(From)),
    Action = fun (#pubsub_node{type = Type, id = Nidx,
			       owners = O}) ->
		     Owners = node_owners_call(Host, Type, Nidx, O),
		     case lists:member(FromLJID, Owners) of
		       true ->
			   {result, Subs} = node_call(Host, Type,
						      get_subscriptions,
						      [Nidx, Subscriber]),
			   update_auth(Host, Node, Type, Nidx, Subscriber,
				       Allow, Subs);
		       false ->
			   {error,
			    xmpp:err_forbidden(<<"Owner privileges required">>,
					       Lang)}
		     end
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {error, Error} ->
	  ejabberd_router:route_error(Packet, Error);
      {result, {_, _NewSubscription}} ->
	  %% XXX: notify about subscription state change, section 12.11
	  ok;
      _ ->
	  Err = xmpp:err_internal_server_error(),
	  ejabberd_router:route_error(Packet, Err)
    end.

- spec ( { { update_auth , 7 } , [ { type , 1432 , 'fun' , [ { type , 1432 , product , [ { type , 1432 , binary , [ ] } , { type , 1432 , binary , [ ] } , { var , 1432 , '_' } , { var , 1432 , '_' } , { type , 1432 , union , [ { type , 1432 , jid , [ ] } , { atom , 1432 , error } ] } , { type , 1432 , boolean , [ ] } , { var , 1432 , '_' } ] } , { type , 1433 , union , [ { type , 1433 , tuple , [ { atom , 1433 , result } , { atom , 1433 , ok } ] } , { type , 1433 , tuple , [ { atom , 1433 , error } , { type , 1433 , stanza_error , [ ] } ] } ] } ] } ] } ) .


update_auth(Host, Node, Type, Nidx, Subscriber, Allow,
	    Subs) ->
    Sub = [V1 || V1 <- Subs, update_auth_1(V1)],
    case Sub of
      [{pending, SubId} | _] ->
	  NewSub = case Allow of
		     true -> subscribed;
		     false -> none
		   end,
	  node_call(Host, Type, set_subscriptions,
		    [Nidx, Subscriber, NewSub, SubId]),
	  send_authorization_approval(Host, Subscriber, Node,
				      NewSub),
	  {result, ok};
      _ ->
	  Txt = <<"No pending subscriptions found">>,
	  {error,
	   xmpp:err_unexpected_request(Txt,
				       ejabberd_config:get_mylang())}
    end.

update_auth_1({pending, _}) -> true;
update_auth_1(_) -> false.

%% @doc <p>Create new pubsub nodes</p>
%%<p>In addition to method-specific error conditions, there are several general reasons why the node creation request might fail:</p>
%%<ul>
%%<li>The service does not support node creation.</li>
%%<li>Only entities that are registered with the service are allowed to create nodes but the requesting entity is not registered.</li>
%%<li>The requesting entity does not have sufficient privileges to create nodes.</li>
%%<li>The requested Node already exists.</li>
%%<li>The request did not include a Node and "instant nodes" are not supported.</li>
%%</ul>
%%<p>ote: node creation is a particular case, error return code is evaluated at many places:</p>
%%<ul>
%%<li>iq_pubsub checks if service supports node creation (type exists)</li>
%%<li>create_node checks if instant nodes are supported</li>
%%<li>create_node asks node plugin if entity have sufficient privilege</li>
%%<li>nodetree create_node checks if nodeid already exists</li>
%%<li>node plugin create_node just sets default affiliation/subscription</li>
%%</ul>
- spec ( { { create_node , 5 } , [ { type , 1471 , 'fun' , [ { type , 1471 , product , [ { type , 1471 , host , [ ] } , { type , 1471 , binary , [ ] } , { type , 1471 , binary , [ ] } , { type , 1471 , jid , [ ] } , { type , 1472 , binary , [ ] } ] } , { type , 1472 , union , [ { type , 1472 , tuple , [ { atom , 1472 , result } , { type , 1472 , pubsub , [ ] } ] } , { type , 1472 , tuple , [ { atom , 1472 , error } , { type , 1472 , stanza_error , [ ] } ] } ] } ] } ] } ) .


create_node(Host, ServerHost, Node, Owner, Type) ->
    create_node(Host, ServerHost, Node, Owner, Type, all,
		[]).

- spec ( { { create_node , 7 } , [ { type , 1476 , 'fun' , [ { type , 1476 , product , [ { type , 1476 , host , [ ] } , { type , 1476 , binary , [ ] } , { type , 1476 , binary , [ ] } , { type , 1476 , jid , [ ] } , { type , 1476 , binary , [ ] } , { type , 1477 , atom , [ ] } , { type , 1477 , list , [ { type , 1477 , tuple , [ { type , 1477 , binary , [ ] } , { type , 1477 , list , [ { type , 1477 , binary , [ ] } ] } ] } ] } ] } , { type , 1477 , union , [ { type , 1477 , tuple , [ { atom , 1477 , result } , { type , 1477 , pubsub , [ ] } ] } , { type , 1477 , tuple , [ { atom , 1477 , error } , { type , 1477 , stanza_error , [ ] } ] } ] } ] } ] } ) .


create_node(Host, ServerHost, <<>>, Owner, Type, Access,
	    Configuration) ->
    case lists:member(<<"instant-nodes">>,
		      plugin_features(Host, Type))
	of
      true ->
	  Node = p1_rand:get_string(),
	  case create_node(Host, ServerHost, Node, Owner, Type,
			   Access, Configuration)
	      of
	    {result, _} -> {result, #pubsub{create = Node}};
	    Error -> Error
	  end;
      false ->
	  {error,
	   extended_error(xmpp:err_not_acceptable(),
			  err_nodeid_required())}
    end;
create_node(Host, ServerHost, Node, Owner, GivenType,
	    Access, Configuration) ->
    Type = select_type(ServerHost, Host, Node, GivenType),
    NodeOptions = merge_config([node_config(Node,
					    ServerHost),
				Configuration, node_options(Host, Type)]),
    CreateNode = fun () ->
			 Parent = case node_call(Host, Type, node_to_path,
						 [Node])
				      of
				    {result, [Node]} -> <<>>;
				    {result, Path} ->
					element(2,
						node_call(Host, Type,
							  path_to_node,
							  [lists:sublist(Path,
									 length(Path)
									   -
									   1)]))
				  end,
			 Parents = case Parent of
				     <<>> -> [];
				     _ -> [Parent]
				   end,
			 case node_call(Host, Type, create_node_permission,
					[Host, ServerHost, Node, Parent, Owner,
					 Access])
			     of
			   {result, true} ->
			       case tree_call(Host, create_node,
					      [Host, Node, Type, Owner,
					       NodeOptions, Parents])
				   of
				 {ok, Nidx} ->
				     SubsByDepth = get_node_subs_by_depth(Host,
									  Node,
									  Owner),
				     case node_call(Host, Type, create_node,
						    [Nidx, Owner])
					 of
				       {result, Result} ->
					   {result,
					    {Nidx, SubsByDepth, Result}};
				       Error -> Error
				     end;
				 {error, {virtual, Nidx}} ->
				     case node_call(Host, Type, create_node,
						    [Nidx, Owner])
					 of
				       {result, Result} ->
					   {result, {Nidx, [], Result}};
				       Error -> Error
				     end;
				 Error -> Error
			       end;
			   _ ->
			       Txt = <<"You're not allowed to create nodes">>,
			       {error,
				xmpp:err_forbidden(Txt,
						   ejabberd_config:get_mylang())}
			 end
		 end,
    Reply = #pubsub{create = Node},
    case transaction(Host, CreateNode, transaction) of
      {result, {Nidx, SubsByDepth, {Result, broadcast}}} ->
	  broadcast_created_node(Host, Node, Nidx, Type,
				 NodeOptions, SubsByDepth),
	  ejabberd_hooks:run(pubsub_create_node, ServerHost,
			     [ServerHost, Host, Node, Nidx, NodeOptions]),
	  case Result of
	    default -> {result, Reply};
	    _ -> {result, Result}
	  end;
      {result, {Nidx, _SubsByDepth, Result}} ->
	  ejabberd_hooks:run(pubsub_create_node, ServerHost,
			     [ServerHost, Host, Node, Nidx, NodeOptions]),
	  case Result of
	    default -> {result, Reply};
	    _ -> {result, Result}
	  end;
      Error ->
	  %% in case we change transaction to sync_dirty...
	  %%  node_call(Host, Type, delete_node, [Host, Node]),
	  %%  tree_call(Host, delete_node, [Host, Node]),
	  Error
    end.

%% @doc <p>Delete specified node and all childs.</p>
%%<p>There are several reasons why the node deletion request might fail:</p>
%%<ul>
%%<li>The requesting entity does not have sufficient privileges to delete the node.</li>
%%<li>The node is the root collection node, which cannot be deleted.</li>
%%<li>The specified node does not exist.</li>
%%</ul>
- spec ( { { delete_node , 3 } , [ { type , 1565 , 'fun' , [ { type , 1565 , product , [ { type , 1565 , host , [ ] } , { type , 1565 , binary , [ ] } , { type , 1565 , jid , [ ] } ] } , { type , 1565 , union , [ { type , 1565 , tuple , [ { atom , 1565 , result } , { type , 1565 , pubsub_owner , [ ] } ] } , { type , 1565 , tuple , [ { atom , 1565 , error } , { type , 1565 , stanza_error , [ ] } ] } ] } ] } ] } ) .


delete_node(_Host, <<>>, _Owner) ->
    {error,
     xmpp:err_not_allowed(<<"No node specified">>,
			  ejabberd_config:get_mylang())};
delete_node(Host, Node, Owner) ->
    Action = fun (#pubsub_node{type = Type, id = Nidx}) ->
		     case node_call(Host, Type, get_affiliation,
				    [Nidx, Owner])
			 of
		       {result, owner} ->
			   SubsByDepth = get_node_subs_by_depth(Host, Node,
								service_jid(Host)),
			   Removed = tree_call(Host, delete_node, [Host, Node]),
			   case node_call(Host, Type, delete_node, [Removed]) of
			     {result, Res} -> {result, {SubsByDepth, Res}};
			     Error -> Error
			   end;
		       _ ->
			   {error,
			    xmpp:err_forbidden(<<"Owner privileges required">>,
					       ejabberd_config:get_mylang())}
		     end
	     end,
    Reply = undefined,
    ServerHost = serverhost(Host),
    case transaction(Host, Node, Action, transaction) of
      {result,
       {_, {SubsByDepth, {Result, broadcast, Removed}}}} ->
	  lists:foreach(fun ({RNode, _RSubs}) ->
				{RH, RN} = RNode#pubsub_node.nodeid,
				RNidx = RNode#pubsub_node.id,
				RType = RNode#pubsub_node.type,
				ROptions = RNode#pubsub_node.options,
				unset_cached_item(RH, RNidx),
				broadcast_removed_node(RH, RN, RNidx, RType,
						       ROptions, SubsByDepth),
				ejabberd_hooks:run(pubsub_delete_node,
						   ServerHost,
						   [ServerHost, RH, RN, RNidx])
			end,
			Removed),
	  case Result of
	    default -> {result, Reply};
	    _ -> {result, Result}
	  end;
      {result, {_, {_, {Result, Removed}}}} ->
	  lists:foreach(fun ({RNode, _RSubs}) ->
				{RH, RN} = RNode#pubsub_node.nodeid,
				RNidx = RNode#pubsub_node.id,
				unset_cached_item(RH, RNidx),
				ejabberd_hooks:run(pubsub_delete_node,
						   ServerHost,
						   [ServerHost, RH, RN, RNidx])
			end,
			Removed),
	  case Result of
	    default -> {result, Reply};
	    _ -> {result, Result}
	  end;
      {result, {TNode, {_, Result}}} ->
	  Nidx = TNode#pubsub_node.id,
	  unset_cached_item(Host, Nidx),
	  ejabberd_hooks:run(pubsub_delete_node, ServerHost,
			     [ServerHost, Host, Node, Nidx]),
	  case Result of
	    default -> {result, Reply};
	    _ -> {result, Result}
	  end;
      Error -> Error
    end.

%% @see node_hometree:subscribe_node/5
%% @doc <p>Accepts or rejects subcription requests on a PubSub node.</p>
%%<p>There are several reasons why the subscription request might fail:</p>
%%<ul>
%%<li>The bare JID portions of the JIDs do not match.</li>
%%<li>The node has an access model of "presence" and the requesting entity is not subscribed to the owner's presence.</li>
%%<li>The node has an access model of "roster" and the requesting entity is not in one of the authorized roster groups.</li>
%%<li>The node has an access model of "whitelist" and the requesting entity is not on the whitelist.</li>
%%<li>The service requires payment for subscriptions to the node.</li>
%%<li>The requesting entity is anonymous and the service does not allow anonymous entities to subscribe.</li>
%%<li>The requesting entity has a pending subscription.</li>
%%<li>The requesting entity is blocked from subscribing (e.g., because having an affiliation of outcast).</li>
%%<li>The node does not support subscriptions.</li>
%%<li>The node does not exist.</li>
%%</ul>
- spec ( { { subscribe_node , 5 } , [ { type , 1644 , 'fun' , [ { type , 1644 , product , [ { type , 1644 , host , [ ] } , { type , 1644 , binary , [ ] } , { type , 1644 , jid , [ ] } , { type , 1644 , jid , [ ] } , { type , 1644 , list , [ { type , 1644 , tuple , [ { type , 1644 , binary , [ ] } , { type , 1644 , list , [ { type , 1644 , binary , [ ] } ] } ] } ] } ] } , { type , 1645 , union , [ { type , 1645 , tuple , [ { atom , 1645 , result } , { type , 1645 , pubsub , [ ] } ] } , { type , 1645 , tuple , [ { atom , 1645 , error } , { type , 1645 , stanza_error , [ ] } ] } ] } ] } ] } ) .


subscribe_node(Host, Node, From, JID, Configuration) ->
    SubModule = subscription_plugin(Host),
    SubOpts = case
		SubModule:parse_options_xform(Configuration)
		  of
		{result, GoodSubOpts} -> GoodSubOpts;
		_ -> invalid
	      end,
    Subscriber = jid:tolower(JID),
    Action = fun (#pubsub_node{options = Options,
			       type = Type, id = Nidx, owners = O}) ->
		     Features = plugin_features(Host, Type),
		     SubscribeFeature = lists:member(<<"subscribe">>,
						     Features),
		     OptionsFeature =
			 lists:member(<<"subscription-options">>, Features),
		     HasOptions = not (SubOpts == []),
		     SubscribeConfig = get_option(Options, subscribe),
		     AccessModel = get_option(Options, access_model),
		     SendLast = get_option(Options,
					   send_last_published_item),
		     AllowedGroups = get_option(Options,
						roster_groups_allowed, []),
		     CanSubscribe = case get_max_subscriptions_node(Host) of
				      Max when is_integer(Max) ->
					  case node_call(Host, Type,
							 get_node_subscriptions,
							 [Nidx])
					      of
					    {result, NodeSubs} ->
						SubsNum = lists:foldl(fun ({_,
									    subscribed,
									    _},
									   Acc) ->
									      Acc
										+
										1;
									  (_,
									   Acc) ->
									      Acc
								      end,
								      0,
								      NodeSubs),
						SubsNum < Max;
					    _ -> true
					  end;
				      _ -> true
				    end,
		     if not SubscribeFeature ->
			    {error,
			     extended_error(xmpp:err_feature_not_implemented(),
					    err_unsupported(subscribe))};
			not SubscribeConfig ->
			    {error,
			     extended_error(xmpp:err_feature_not_implemented(),
					    err_unsupported(subscribe))};
			HasOptions andalso not OptionsFeature ->
			    {error,
			     extended_error(xmpp:err_feature_not_implemented(),
					    err_unsupported('subscription-options'))};
			SubOpts == invalid ->
			    {error,
			     extended_error(xmpp:err_bad_request(),
					    err_invalid_options())};
			not CanSubscribe ->
			    %% fallback to closest XEP compatible result, assume we are not allowed to subscribe
			    {error,
			     extended_error(xmpp:err_not_allowed(),
					    err_closed_node())};
			true ->
			    Owners = node_owners_call(Host, Type, Nidx, O),
			    {PS, RG} = get_presence_and_roster_permissions(Host,
									   Subscriber,
									   Owners,
									   AccessModel,
									   AllowedGroups),
			    node_call(Host, Type, subscribe_node,
				      [Nidx, From, Subscriber, AccessModel,
				       SendLast, PS, RG, SubOpts])
		     end
	     end,
    Reply = fun (Subscription) ->
		    Sub = case Subscription of
			    {subscribed, SubId} ->
				#ps_subscription{jid = JID, type = subscribed,
						 subid = SubId};
			    Other -> #ps_subscription{jid = JID, type = Other}
			  end,
		    #pubsub{subscription = Sub#ps_subscription{node = Node}}
	    end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result,
       {TNode, {Result, subscribed, SubId, send_last}}} ->
	  Nidx = TNode#pubsub_node.id,
	  Type = TNode#pubsub_node.type,
	  Options = TNode#pubsub_node.options,
	  send_items(Host, Node, Nidx, Type, Options, Subscriber,
		     last),
	  ServerHost = serverhost(Host),
	  ejabberd_hooks:run(pubsub_subscribe_node, ServerHost,
			     [ServerHost, Host, Node, Subscriber, SubId]),
	  case Result of
	    default -> {result, Reply({subscribed, SubId})};
	    _ -> {result, Result}
	  end;
      {result, {_TNode, {default, subscribed, SubId}}} ->
	  {result, Reply({subscribed, SubId})};
      {result, {_TNode, {Result, subscribed, _SubId}}} ->
	  {result, Result};
      {result, {TNode, {default, pending, _SubId}}} ->
	  send_authorization_request(TNode, Subscriber),
	  {result, Reply(pending)};
      {result, {TNode, {Result, pending}}} ->
	  send_authorization_request(TNode, Subscriber),
	  {result, Result};
      {result, {_, Result}} -> {result, Result};
      Error -> Error
    end.

%% @doc <p>Unsubscribe <tt>JID</tt> from the <tt>Node</tt>.</p>
%%<p>There are several reasons why the unsubscribe request might fail:</p>
%%<ul>
%%<li>The requesting entity has multiple subscriptions to the node but does not specify a subscription ID.</li>
%%<li>The request does not specify an existing subscriber.</li>
%%<li>The requesting entity does not have sufficient privileges to unsubscribe the specified JID.</li>
%%<li>The node does not exist.</li>
%%<li>The request specifies a subscription ID that is not valid or current.</li>
%%</ul>
- spec ( { { unsubscribe_node , 5 } , [ { type , 1748 , 'fun' , [ { type , 1748 , product , [ { type , 1748 , host , [ ] } , { type , 1748 , binary , [ ] } , { type , 1748 , jid , [ ] } , { type , 1748 , jid , [ ] } , { type , 1748 , binary , [ ] } ] } , { type , 1749 , union , [ { type , 1749 , tuple , [ { atom , 1749 , result } , { atom , 1749 , undefined } ] } , { type , 1749 , tuple , [ { atom , 1749 , error } , { type , 1749 , stanza_error , [ ] } ] } ] } ] } ] } ) .


unsubscribe_node(Host, Node, From, JID, SubId) ->
    Subscriber = jid:tolower(JID),
    Action = fun (#pubsub_node{type = Type, id = Nidx}) ->
		     node_call(Host, Type, unsubscribe_node,
			       [Nidx, From, Subscriber, SubId])
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_, default}} ->
	  ServerHost = serverhost(Host),
	  ejabberd_hooks:run(pubsub_unsubscribe_node, ServerHost,
			     [ServerHost, Host, Node, Subscriber, SubId]),
	  {result, undefined};
      Error -> Error
    end.

%% @doc <p>Publish item to a PubSub node.</p>
%% <p>The permission to publish an item must be verified by the plugin implementation.</p>
%%<p>There are several reasons why the publish request might fail:</p>
%%<ul>
%%<li>The requesting entity does not have sufficient privileges to publish.</li>
%%<li>The node does not support item publication.</li>
%%<li>The node does not exist.</li>
%%<li>The payload size exceeds a service-defined limit.</li>
%%<li>The item contains more than one payload element or the namespace of the root payload element does not match the configured namespace for the node.</li>
%%<li>The request does not match the node configuration.</li>
%%</ul>
- spec ( { { publish_item , 6 } , [ { type , 1775 , 'fun' , [ { type , 1775 , product , [ { type , 1775 , host , [ ] } , { type , 1775 , binary , [ ] } , { type , 1775 , binary , [ ] } , { type , 1775 , jid , [ ] } , { type , 1775 , binary , [ ] } , { type , 1776 , list , [ { type , 1776 , xmlel , [ ] } ] } ] } , { type , 1776 , union , [ { type , 1776 , tuple , [ { atom , 1776 , result } , { type , 1776 , pubsub , [ ] } ] } , { type , 1776 , tuple , [ { atom , 1776 , error } , { type , 1776 , stanza_error , [ ] } ] } ] } ] } ] } ) .


publish_item(Host, ServerHost, Node, Publisher, ItemId,
	     Payload) ->
    publish_item(Host, ServerHost, Node, Publisher, ItemId,
		 Payload, [], all).

publish_item(Host, ServerHost, Node, Publisher, <<>>,
	     Payload, PubOpts, Access) ->
    publish_item(Host, ServerHost, Node, Publisher,
		 uniqid(), Payload, PubOpts, Access);
publish_item(Host, ServerHost, Node, Publisher, ItemId,
	     Payload, PubOpts, Access) ->
    Action = fun (#pubsub_node{options = Options,
			       type = Type, id = Nidx}) ->
		     Features = plugin_features(Host, Type),
		     PublishFeature = lists:member(<<"publish">>, Features),
		     PublishModel = get_option(Options, publish_model),
		     DeliverPayloads = get_option(Options, deliver_payloads),
		     PersistItems = get_option(Options, persist_items),
		     MaxItems = max_items(Host, Options),
		     PayloadCount = payload_xmlelements(Payload),
		     PayloadSize = byte_size(term_to_binary(Payload)) - 2,
		     PayloadMaxSize = get_option(Options, max_payload_size),
		     PreconditionsMet = preconditions_met(PubOpts, Options),
		     if not PublishFeature ->
			    {error,
			     extended_error(xmpp:err_feature_not_implemented(),
					    err_unsupported(publish))};
			not PreconditionsMet ->
			    {error,
			     extended_error(xmpp:err_conflict(),
					    err_precondition_not_met())};
			PayloadSize > PayloadMaxSize ->
			    {error,
			     extended_error(xmpp:err_not_acceptable(),
					    err_payload_too_big())};
			(DeliverPayloads or PersistItems) and
			  (PayloadCount == 0) ->
			    {error,
			     extended_error(xmpp:err_bad_request(),
					    err_item_required())};
			(DeliverPayloads or PersistItems) and
			  (PayloadCount > 1) ->
			    {error,
			     extended_error(xmpp:err_bad_request(),
					    err_invalid_payload())};
			not (DeliverPayloads or PersistItems) and
			  (PayloadCount > 0) ->
			    {error,
			     extended_error(xmpp:err_bad_request(),
					    err_item_forbidden())};
			true ->
			    node_call(Host, Type, publish_item,
				      [Nidx, Publisher, PublishModel, MaxItems,
				       ItemId, Payload, PubOpts])
		     end
	     end,
    Reply = #pubsub{publish =
			#ps_publish{node = Node,
				    items = [#ps_item{id = ItemId}]}},
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {TNode, {Result, Broadcast, Removed}}} ->
	  Nidx = TNode#pubsub_node.id,
	  Type = TNode#pubsub_node.type,
	  Options = TNode#pubsub_node.options,
	  BrPayload = case Broadcast of
			broadcast -> Payload;
			PluginPayload -> PluginPayload
		      end,
	  set_cached_item(Host, Nidx, ItemId, Publisher,
			  BrPayload),
	  case get_option(Options, deliver_notifications) of
	    true ->
		broadcast_publish_item(Host, Node, Nidx, Type, Options,
				       ItemId, Publisher, BrPayload, Removed);
	    false -> ok
	  end,
	  ejabberd_hooks:run(pubsub_publish_item, ServerHost,
			     [ServerHost, Node, Publisher, service_jid(Host),
			      ItemId, BrPayload]),
	  case Result of
	    default -> {result, Reply};
	    _ -> {result, Result}
	  end;
      {result, {TNode, {default, Removed}}} ->
	  Nidx = TNode#pubsub_node.id,
	  Type = TNode#pubsub_node.type,
	  Options = TNode#pubsub_node.options,
	  broadcast_retract_items(Host, Node, Nidx, Type, Options,
				  Removed),
	  set_cached_item(Host, Nidx, ItemId, Publisher, Payload),
	  {result, Reply};
      {result, {TNode, {Result, Removed}}} ->
	  Nidx = TNode#pubsub_node.id,
	  Type = TNode#pubsub_node.type,
	  Options = TNode#pubsub_node.options,
	  broadcast_retract_items(Host, Node, Nidx, Type, Options,
				  Removed),
	  set_cached_item(Host, Nidx, ItemId, Publisher, Payload),
	  {result, Result};
      {result, {_, default}} -> {result, Reply};
      {result, {_, Result}} -> {result, Result};
      {error, #stanza_error{reason = 'item-not-found'}} ->
	  Type = select_type(ServerHost, Host, Node),
	  case lists:member(<<"auto-create">>,
			    plugin_features(Host, Type))
	      of
	    true ->
		case create_node(Host, ServerHost, Node, Publisher,
				 Type, Access, PubOpts)
		    of
		  {result, #pubsub{create = NewNode}} ->
		      publish_item(Host, ServerHost, NewNode, Publisher,
				   ItemId, Payload, PubOpts, Access);
		  _ -> {error, xmpp:err_item_not_found()}
		end;
	    false ->
		Txt = <<"Automatic node creation is not enabled">>,
		{error,
		 xmpp:err_item_not_found(Txt,
					 ejabberd_config:get_mylang())}
	  end;
      Error -> Error
    end.

%% @doc <p>Delete item from a PubSub node.</p>
%% <p>The permission to delete an item must be verified by the plugin implementation.</p>
%%<p>There are several reasons why the item retraction request might fail:</p>
%%<ul>
%%<li>The publisher does not have sufficient privileges to delete the requested item.</li>
%%<li>The node or item does not exist.</li>
%%<li>The request does not specify a node.</li>
%%<li>The request does not include an <item/> element or the <item/> element does not specify an ItemId.</li>
%%<li>The node does not support persistent items.</li>
%%<li>The service does not support the deletion of items.</li>
%%</ul>
- spec ( { { delete_item , 4 } , [ { type , 1889 , 'fun' , [ { type , 1889 , product , [ { type , 1889 , host , [ ] } , { type , 1889 , binary , [ ] } , { type , 1889 , jid , [ ] } , { type , 1889 , binary , [ ] } ] } , { type , 1889 , union , [ { type , 1889 , tuple , [ { atom , 1889 , result } , { atom , 1889 , undefined } ] } , { type , 1890 , tuple , [ { atom , 1890 , error } , { type , 1890 , stanza_error , [ ] } ] } ] } ] } ] } ) .


delete_item(Host, Node, Publisher, ItemId) ->
    delete_item(Host, Node, Publisher, ItemId, false).

delete_item(_, <<>>, _, _, _) ->
    {error,
     extended_error(xmpp:err_bad_request(),
		    err_nodeid_required())};
delete_item(Host, Node, Publisher, ItemId,
	    ForceNotify) ->
    Action = fun (#pubsub_node{options = Options,
			       type = Type, id = Nidx}) ->
		     Features = plugin_features(Host, Type),
		     PersistentFeature = lists:member(<<"persistent-items">>,
						      Features),
		     DeleteFeature = lists:member(<<"delete-items">>,
						  Features),
		     PublishModel = get_option(Options, publish_model),
		     if %%->   iq_pubsub just does that matchs
			%%        %% Request does not specify an item
			%%        {error, extended_error(?ERR_BAD_REQUEST, "item-required")};
			not PersistentFeature ->
			    {error,
			     extended_error(xmpp:err_feature_not_implemented(),
					    err_unsupported('persistent-items'))};
			not DeleteFeature ->
			    {error,
			     extended_error(xmpp:err_feature_not_implemented(),
					    err_unsupported('delete-items'))};
			true ->
			    node_call(Host, Type, delete_item,
				      [Nidx, Publisher, PublishModel, ItemId])
		     end
	     end,
    Reply = undefined,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {TNode, {Result, broadcast}}} ->
	  Nidx = TNode#pubsub_node.id,
	  Type = TNode#pubsub_node.type,
	  Options = TNode#pubsub_node.options,
	  broadcast_retract_items(Host, Node, Nidx, Type, Options,
				  [ItemId], ForceNotify),
	  case get_cached_item(Host, Nidx) of
	    #pubsub_item{itemid = {ItemId, Nidx}} ->
		unset_cached_item(Host, Nidx);
	    _ -> ok
	  end,
	  case Result of
	    default -> {result, Reply};
	    _ -> {result, Result}
	  end;
      {result, {_, default}} -> {result, Reply};
      {result, {_, Result}} -> {result, Result};
      Error -> Error
    end.

%% @doc <p>Delete all items of specified node owned by JID.</p>
%%<p>There are several reasons why the node purge request might fail:</p>
%%<ul>
%%<li>The node or service does not support node purging.</li>
%%<li>The requesting entity does not have sufficient privileges to purge the node.</li>
%%<li>The node is not configured to persist items.</li>
%%<li>The specified node does not exist.</li>
%%</ul>
- spec ( { { purge_node , 3 } , [ { type , 1945 , 'fun' , [ { type , 1945 , product , [ { remote_type , 1945 , [ { atom , 1945 , mod_pubsub } , { atom , 1945 , host } , [ ] ] } , { type , 1945 , binary , [ ] } , { type , 1945 , jid , [ ] } ] } , { type , 1945 , union , [ { type , 1945 , tuple , [ { atom , 1945 , result } , { atom , 1945 , undefined } ] } , { type , 1946 , tuple , [ { atom , 1946 , error } , { type , 1946 , stanza_error , [ ] } ] } ] } ] } ] } ) .


purge_node(Host, Node, Owner) ->
    Action = fun (#pubsub_node{options = Options,
			       type = Type, id = Nidx}) ->
		     Features = plugin_features(Host, Type),
		     PurgeFeature = lists:member(<<"purge-nodes">>,
						 Features),
		     PersistentFeature = lists:member(<<"persistent-items">>,
						      Features),
		     PersistentConfig = get_option(Options, persist_items),
		     if not PurgeFeature ->
			    {error,
			     extended_error(xmpp:err_feature_not_implemented(),
					    err_unsupported('purge-nodes'))};
			not PersistentFeature ->
			    {error,
			     extended_error(xmpp:err_feature_not_implemented(),
					    err_unsupported('persistent-items'))};
			not PersistentConfig ->
			    {error,
			     extended_error(xmpp:err_feature_not_implemented(),
					    err_unsupported('persistent-items'))};
			true -> node_call(Host, Type, purge_node, [Nidx, Owner])
		     end
	     end,
    Reply = undefined,
    case transaction(Host, Node, Action, transaction) of
      {result, {TNode, {Result, broadcast}}} ->
	  Nidx = TNode#pubsub_node.id,
	  Type = TNode#pubsub_node.type,
	  Options = TNode#pubsub_node.options,
	  broadcast_purge_node(Host, Node, Nidx, Type, Options),
	  unset_cached_item(Host, Nidx),
	  case Result of
	    default -> {result, Reply};
	    _ -> {result, Result}
	  end;
      {result, {_, default}} -> {result, Reply};
      {result, {_, Result}} -> {result, Result};
      Error -> Error
    end.

%% @doc <p>Return the items of a given node.</p>
%% <p>The number of items to return is limited by MaxItems.</p>
%% <p>The permission are not checked in this function.</p>
- spec ( { { get_items , 7 } , [ { type , 1988 , 'fun' , [ { type , 1988 , product , [ { type , 1988 , host , [ ] } , { type , 1988 , binary , [ ] } , { type , 1988 , jid , [ ] } , { type , 1988 , binary , [ ] } , { type , 1989 , binary , [ ] } , { type , 1989 , list , [ { type , 1989 , binary , [ ] } ] } , { type , 1989 , union , [ { atom , 1989 , undefined } , { type , 1989 , rsm_set , [ ] } ] } ] } , { type , 1990 , union , [ { type , 1990 , tuple , [ { atom , 1990 , result } , { type , 1990 , pubsub , [ ] } ] } , { type , 1990 , tuple , [ { atom , 1990 , error } , { type , 1990 , stanza_error , [ ] } ] } ] } ] } ] } ) .


get_items(Host, Node, From, SubId, MaxItems, ItemIds,
	  undefined)
    when MaxItems =/= undefined ->
    get_items(Host, Node, From, SubId, MaxItems, ItemIds,
	      #rsm_set{max = MaxItems, before = <<>>});
get_items(Host, Node, From, SubId, _MaxItems, ItemIds,
	  RSM) ->
    Action = fun (#pubsub_node{options = Options,
			       type = Type, id = Nidx, owners = O}) ->
		     Features = plugin_features(Host, Type),
		     RetreiveFeature = lists:member(<<"retrieve-items">>,
						    Features),
		     PersistentFeature = lists:member(<<"persistent-items">>,
						      Features),
		     AccessModel = get_option(Options, access_model),
		     AllowedGroups = get_option(Options,
						roster_groups_allowed, []),
		     if not RetreiveFeature ->
			    {error,
			     extended_error(xmpp:err_feature_not_implemented(),
					    err_unsupported('retrieve-items'))};
			not PersistentFeature ->
			    {error,
			     extended_error(xmpp:err_feature_not_implemented(),
					    err_unsupported('persistent-items'))};
			true ->
			    Owners = node_owners_call(Host, Type, Nidx, O),
			    {PS, RG} = get_presence_and_roster_permissions(Host,
									   From,
									   Owners,
									   AccessModel,
									   AllowedGroups),
			    case ItemIds of
			      [ItemId] ->
				  NotFound = xmpp:err_item_not_found(),
				  case node_call(Host, Type, get_item,
						 [Nidx, ItemId, From,
						  AccessModel, PS, RG,
						  undefined])
				      of
				    {error, NotFound} ->
					{result, {[], undefined}};
				    Result -> Result
				  end;
			      _ ->
				  node_call(Host, Type, get_items,
					    [Nidx, From, AccessModel, PS, RG,
					     SubId, RSM])
			    end
		     end
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {TNode, {Items, RsmOut}}} ->
	  SendItems = case ItemIds of
			[] -> Items;
			_ -> [V1 || V1 <- Items, get_items_1(V1, ItemIds)]
		      end,
	  Options = TNode#pubsub_node.options,
	  {result,
	   #pubsub{items = items_els(Node, Options, SendItems),
		   rsm = RsmOut}};
      {result, {TNode, Item}} ->
	  Options = TNode#pubsub_node.options,
	  {result,
	   #pubsub{items = items_els(Node, Options, [Item])}};
      Error -> Error
    end.

get_items_1(#pubsub_item{itemid = {ItemId, _}},
	    ItemIds) ->
    lists:member(ItemId, ItemIds).

get_items(Host, Node) ->
    Action = fun (#pubsub_node{type = Type, id = Nidx}) ->
		     node_call(Host, Type, get_items,
			       [Nidx, service_jid(Host), undefined])
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_, {Items, _}}} -> Items;
      Error -> Error
    end.

get_item(Host, Node, ItemId) ->
    Action = fun (#pubsub_node{type = Type, id = Nidx}) ->
		     node_call(Host, Type, get_item, [Nidx, ItemId])
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_, Items}} -> Items;
      Error -> Error
    end.

get_allowed_items_call(Host, Nidx, From, Type, Options,
		       Owners) ->
    case get_allowed_items_call(Host, Nidx, From, Type,
				Options, Owners, undefined)
	of
      {result, {Items, _RSM}} -> {result, Items};
      Error -> Error
    end.

get_allowed_items_call(Host, Nidx, From, Type, Options,
		       Owners, RSM) ->
    AccessModel = get_option(Options, access_model),
    AllowedGroups = get_option(Options,
			       roster_groups_allowed, []),
    {PS, RG} = get_presence_and_roster_permissions(Host,
						   From, Owners, AccessModel,
						   AllowedGroups),
    node_call(Host, Type, get_items,
	      [Nidx, From, AccessModel, PS, RG, undefined, RSM]).

get_last_items(Host, Type, Nidx, LJID, last) ->
    % hack to handle section 6.1.7 of XEP-0060
    get_last_items(Host, Type, Nidx, LJID, 1);
get_last_items(Host, Type, Nidx, LJID, 1) ->
    case get_cached_item(Host, Nidx) of
      undefined ->
	  case node_action(Host, Type, get_last_items,
			   [Nidx, LJID, 1])
	      of
	    {result, Items} -> Items;
	    _ -> []
	  end;
      LastItem -> [LastItem]
    end;
get_last_items(Host, Type, Nidx, LJID, Count)
    when Count > 1 ->
    case node_action(Host, Type, get_last_items,
		     [Nidx, LJID, Count])
	of
      {result, Items} -> Items;
      _ -> []
    end;
get_last_items(_Host, _Type, _Nidx, _LJID, _Count) ->
    [].

%% @doc <p>Return the list of affiliations as an XMPP response.</p>
- spec ( { { get_affiliations , 4 } , [ { type , 2101 , 'fun' , [ { type , 2101 , product , [ { type , 2101 , host , [ ] } , { type , 2101 , binary , [ ] } , { type , 2101 , jid , [ ] } , { type , 2101 , list , [ { type , 2101 , binary , [ ] } ] } ] } , { type , 2102 , union , [ { type , 2102 , tuple , [ { atom , 2102 , result } , { type , 2102 , pubsub , [ ] } ] } , { type , 2102 , tuple , [ { atom , 2102 , error } , { type , 2102 , stanza_error , [ ] } ] } ] } ] } ] } ) .


get_affiliations(Host, Node, JID, Plugins)
    when is_list(Plugins) ->
    Result = lists:foldl(fun (Type, {Status, Acc}) ->
				 Features = plugin_features(Host, Type),
				 RetrieveFeature =
				     lists:member(<<"retrieve-affiliations">>,
						  Features),
				 if not RetrieveFeature ->
					{{error,
					  extended_error(xmpp:err_feature_not_implemented(),
							 err_unsupported('retrieve-affiliations'))},
					 Acc};
				    true ->
					{result, Affs} = node_action(Host, Type,
								     get_entity_affiliations,
								     [Host,
								      JID]),
					{Status, [Affs | Acc]}
				 end
			 end,
			 {ok, []}, Plugins),
    case Result of
      {ok, Affs} ->
	  Entities = lists:flatmap(fun ({_, none}) -> [];
				       ({#pubsub_node{nodeid = {_, NodeId}},
					 Aff}) ->
					   if (Node == <<>>) or
						(Node == NodeId) ->
						  [#ps_affiliation{node =
								       NodeId,
								   type = Aff}];
					      true -> []
					   end;
				       (_) -> []
				   end,
				   lists:usort(lists:flatten(Affs))),
	  {result, #pubsub{affiliations = {<<>>, Entities}}};
      {Error, _} -> Error
    end.

- spec ( { { get_affiliations , 3 } , [ { type , 2141 , 'fun' , [ { type , 2141 , product , [ { type , 2141 , host , [ ] } , { type , 2141 , binary , [ ] } , { type , 2141 , jid , [ ] } ] } , { type , 2142 , union , [ { type , 2142 , tuple , [ { atom , 2142 , result } , { type , 2142 , pubsub_owner , [ ] } ] } , { type , 2142 , tuple , [ { atom , 2142 , error } , { type , 2142 , stanza_error , [ ] } ] } ] } ] } ] } ) .


get_affiliations(Host, Node, JID) ->
    Action = fun (#pubsub_node{type = Type, id = Nidx}) ->
		     Features = plugin_features(Host, Type),
		     RetrieveFeature =
			 lists:member(<<"modify-affiliations">>, Features),
		     {result, Affiliation} = node_call(Host, Type,
						       get_affiliation,
						       [Nidx, JID]),
		     if not RetrieveFeature ->
			    {error,
			     extended_error(xmpp:err_feature_not_implemented(),
					    err_unsupported('modify-affiliations'))};
			Affiliation /= owner ->
			    {error,
			     xmpp:err_forbidden(<<"Owner privileges required">>,
						ejabberd_config:get_mylang())};
			true ->
			    node_call(Host, Type, get_node_affiliations, [Nidx])
		     end
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_, []}} -> {error, xmpp:err_item_not_found()};
      {result, {_, Affs}} ->
	  Entities = lists:flatmap(fun ({_, none}) -> [];
				       ({AJID, Aff}) ->
					   [#ps_affiliation{jid = AJID,
							    type = Aff}]
				   end,
				   Affs),
	  {result,
	   #pubsub_owner{affiliations = {Node, Entities}}};
      Error -> Error
    end.

- spec ( { { set_affiliations , 4 } , [ { type , 2173 , 'fun' , [ { type , 2173 , product , [ { type , 2173 , host , [ ] } , { type , 2173 , binary , [ ] } , { type , 2173 , jid , [ ] } , { type , 2173 , list , [ { type , 2173 , ps_affiliation , [ ] } ] } ] } , { type , 2174 , union , [ { type , 2174 , tuple , [ { atom , 2174 , result } , { atom , 2174 , undefined } ] } , { type , 2174 , tuple , [ { atom , 2174 , error } , { type , 2174 , stanza_error , [ ] } ] } ] } ] } ] } ) .


set_affiliations(Host, Node, From, Affs) ->
    Owner = jid:tolower(jid:remove_resource(From)),
    Action = fun (#pubsub_node{type = Type, id = Nidx,
			       owners = O} =
		      N) ->
		     Owners = node_owners_call(Host, Type, Nidx, O),
		     case lists:member(Owner, Owners) of
		       true ->
			   OwnerJID = jid:make(Owner),
			   FilteredAffs = case Owners of
					    [Owner] ->
						[Aff
						 || Aff <- Affs,
						    Aff#ps_affiliation.jid /=
						      OwnerJID];
					    _ -> Affs
					  end,
			   lists:foreach(fun (#ps_affiliation{jid = JID,
							      type =
								  Affiliation}) ->
						 node_call(Host, Type,
							   set_affiliation,
							   [Nidx, JID,
							    Affiliation]),
						 case Affiliation of
						   owner ->
						       NewOwner =
							   jid:tolower(jid:remove_resource(JID)),
						       NewOwners = [NewOwner
								    | Owners],
						       tree_call(Host, set_node,
								 [N#pubsub_node{owners
										    =
										    NewOwners}]);
						   none ->
						       OldOwner =
							   jid:tolower(jid:remove_resource(JID)),
						       case
							 lists:member(OldOwner,
								      Owners)
							   of
							 true ->
							     NewOwners = Owners
									   --
									   [OldOwner],
							     tree_call(Host,
								       set_node,
								       [N#pubsub_node{owners
											  =
											  NewOwners}]);
							 _ -> ok
						       end;
						   _ -> ok
						 end
					 end,
					 FilteredAffs),
			   {result, undefined};
		       _ ->
			   {error,
			    xmpp:err_forbidden(<<"Owner privileges required">>,
					       ejabberd_config:get_mylang())}
		     end
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_, Result}} -> {result, Result};
      Other -> Other
    end.

- spec ( { { get_options , 5 } , [ { type , 2227 , 'fun' , [ { type , 2227 , product , [ { type , 2227 , binary , [ ] } , { type , 2227 , binary , [ ] } , { type , 2227 , jid , [ ] } , { type , 2227 , binary , [ ] } , { type , 2227 , binary , [ ] } ] } , { type , 2228 , union , [ { type , 2228 , tuple , [ { atom , 2228 , result } , { type , 2228 , xdata , [ ] } ] } , { type , 2228 , tuple , [ { atom , 2228 , error } , { type , 2228 , stanza_error , [ ] } ] } ] } ] } ] } ) .


get_options(Host, Node, JID, SubId, Lang) ->
    Action = fun (#pubsub_node{type = Type, id = Nidx}) ->
		     case lists:member(<<"subscription-options">>,
				       plugin_features(Host, Type))
			 of
		       true ->
			   get_options_helper(Host, JID, Lang, Node, Nidx,
					      SubId, Type);
		       false ->
			   {error,
			    extended_error(xmpp:err_feature_not_implemented(),
					   err_unsupported('subscription-options'))}
		     end
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_Node, XForm}} -> {result, XForm};
      Error -> Error
    end.

- spec ( { { get_options_helper , 7 } , [ { type , 2244 , 'fun' , [ { type , 2244 , product , [ { type , 2244 , binary , [ ] } , { type , 2244 , jid , [ ] } , { type , 2244 , binary , [ ] } , { type , 2244 , binary , [ ] } , { var , 2244 , '_' } , { type , 2244 , binary , [ ] } , { type , 2245 , binary , [ ] } ] } , { type , 2245 , union , [ { type , 2245 , tuple , [ { atom , 2245 , result } , { type , 2245 , pubsub , [ ] } ] } , { type , 2245 , tuple , [ { atom , 2245 , error } , { type , 2245 , stanza_error , [ ] } ] } ] } ] } ] } ) .


get_options_helper(Host, JID, Lang, Node, Nidx, SubId,
		   Type) ->
    Subscriber = jid:tolower(JID),
    {result, Subs} = node_call(Host, Type,
			       get_subscriptions, [Nidx, Subscriber]),
    SubIds = [Id || {Sub, Id} <- Subs, Sub == subscribed],
    case {SubId, SubIds} of
      {_, []} ->
	  {error,
	   extended_error(xmpp:err_not_acceptable(),
			  err_not_subscribed())};
      {<<>>, [SID]} ->
	  read_sub(Host, Node, Nidx, Subscriber, SID, Lang);
      {<<>>, _} ->
	  {error,
	   extended_error(xmpp:err_not_acceptable(),
			  err_subid_required())};
      {_, _} ->
	  ValidSubId = lists:member(SubId, SubIds),
	  if ValidSubId ->
		 read_sub(Host, Node, Nidx, Subscriber, SubId, Lang);
	     true ->
		 {error,
		  extended_error(xmpp:err_not_acceptable(),
				 err_invalid_subid())}
	  end
    end.

- spec ( { { read_sub , 6 } , [ { type , 2269 , 'fun' , [ { type , 2269 , product , [ { type , 2269 , binary , [ ] } , { type , 2269 , binary , [ ] } , { type , 2269 , nodeIdx , [ ] } , { type , 2269 , ljid , [ ] } , { type , 2269 , binary , [ ] } , { type , 2269 , binary , [ ] } ] } , { type , 2269 , tuple , [ { atom , 2269 , result } , { type , 2269 , pubsub , [ ] } ] } ] } ] } ) .


read_sub(Host, Node, Nidx, Subscriber, SubId, Lang) ->
    SubModule = subscription_plugin(Host),
    XData = case SubModule:get_subscription(Subscriber,
					    Nidx, SubId)
		of
	      {error, notfound} -> undefined;
	      {result, #pubsub_subscription{options = Options}} ->
		  {result, X} = SubModule:get_options_xform(Lang,
							    Options),
		  X
	    end,
    {result,
     #pubsub{options =
		 #ps_options{jid = jid:make(Subscriber), subid = SubId,
			     node = Node, xdata = XData}}}.

- spec ( { { set_options , 5 } , [ { type , 2284 , 'fun' , [ { type , 2284 , product , [ { type , 2284 , binary , [ ] } , { type , 2284 , binary , [ ] } , { type , 2284 , jid , [ ] } , { type , 2284 , binary , [ ] } , { type , 2285 , list , [ { type , 2285 , tuple , [ { type , 2285 , binary , [ ] } , { type , 2285 , list , [ { type , 2285 , binary , [ ] } ] } ] } ] } ] } , { type , 2286 , union , [ { type , 2286 , tuple , [ { atom , 2286 , result } , { atom , 2286 , undefined } ] } , { type , 2286 , tuple , [ { atom , 2286 , error } , { type , 2286 , stanza_error , [ ] } ] } ] } ] } ] } ) .


set_options(Host, Node, JID, SubId, Configuration) ->
    Action = fun (#pubsub_node{type = Type, id = Nidx}) ->
		     case lists:member(<<"subscription-options">>,
				       plugin_features(Host, Type))
			 of
		       true ->
			   set_options_helper(Host, Configuration, JID, Nidx,
					      SubId, Type);
		       false ->
			   {error,
			    extended_error(xmpp:err_feature_not_implemented(),
					   err_unsupported('subscription-options'))}
		     end
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_Node, Result}} -> {result, Result};
      Error -> Error
    end.

- spec ( { { set_options_helper , 6 } , [ { type , 2302 , 'fun' , [ { type , 2302 , product , [ { type , 2302 , binary , [ ] } , { type , 2302 , list , [ { type , 2302 , tuple , [ { type , 2302 , binary , [ ] } , { type , 2302 , list , [ { type , 2302 , binary , [ ] } ] } ] } ] } , { type , 2302 , jid , [ ] } , { type , 2303 , nodeIdx , [ ] } , { type , 2303 , binary , [ ] } , { type , 2303 , binary , [ ] } ] } , { type , 2304 , union , [ { type , 2304 , tuple , [ { atom , 2304 , result } , { atom , 2304 , undefined } ] } , { type , 2304 , tuple , [ { atom , 2304 , error } , { type , 2304 , stanza_error , [ ] } ] } ] } ] } ] } ) .


set_options_helper(Host, Configuration, JID, Nidx,
		   SubId, Type) ->
    SubModule = subscription_plugin(Host),
    SubOpts = case
		SubModule:parse_options_xform(Configuration)
		  of
		{result, GoodSubOpts} -> GoodSubOpts;
		_ -> invalid
	      end,
    Subscriber = jid:tolower(JID),
    {result, Subs} = node_call(Host, Type,
			       get_subscriptions, [Nidx, Subscriber]),
    SubIds = [Id || {Sub, Id} <- Subs, Sub == subscribed],
    case {SubId, SubIds} of
      {_, []} ->
	  {error,
	   extended_error(xmpp:err_not_acceptable(),
			  err_not_subscribed())};
      {<<>>, [SID]} ->
	  write_sub(Host, Nidx, Subscriber, SID, SubOpts);
      {<<>>, _} ->
	  {error,
	   extended_error(xmpp:err_not_acceptable(),
			  err_subid_required())};
      {_, _} ->
	  write_sub(Host, Nidx, Subscriber, SubId, SubOpts)
    end.

- spec ( { { write_sub , 5 } , [ { type , 2325 , 'fun' , [ { type , 2325 , product , [ { type , 2325 , binary , [ ] } , { type , 2325 , nodeIdx , [ ] } , { type , 2325 , ljid , [ ] } , { type , 2325 , binary , [ ] } , { var , 2325 , '_' } ] } , { type , 2325 , union , [ { type , 2325 , tuple , [ { atom , 2325 , result } , { atom , 2325 , undefined } ] } , { type , 2326 , tuple , [ { atom , 2326 , error } , { type , 2326 , stanza_error , [ ] } ] } ] } ] } ] } ) .


write_sub(_Host, _Nidx, _Subscriber, _SubId, invalid) ->
    {error,
     extended_error(xmpp:err_bad_request(),
		    err_invalid_options())};
write_sub(_Host, _Nidx, _Subscriber, _SubId, []) ->
    {result, undefined};
write_sub(Host, Nidx, Subscriber, SubId, Options) ->
    SubModule = subscription_plugin(Host),
    case SubModule:set_subscription(Subscriber, Nidx, SubId,
				    Options)
	of
      {result, _} -> {result, undefined};
      {error, _} ->
	  {error,
	   extended_error(xmpp:err_not_acceptable(),
			  err_invalid_subid())}
    end.

%% @doc <p>Return the list of subscriptions as an XMPP response.</p>
- spec ( { { get_subscriptions , 4 } , [ { type , 2340 , 'fun' , [ { type , 2340 , product , [ { type , 2340 , host , [ ] } , { type , 2340 , binary , [ ] } , { type , 2340 , jid , [ ] } , { type , 2340 , list , [ { type , 2340 , binary , [ ] } ] } ] } , { type , 2341 , union , [ { type , 2341 , tuple , [ { atom , 2341 , result } , { type , 2341 , pubsub , [ ] } ] } , { type , 2341 , tuple , [ { atom , 2341 , error } , { type , 2341 , stanza_error , [ ] } ] } ] } ] } ] } ) .


get_subscriptions(Host, Node, JID, Plugins)
    when is_list(Plugins) ->
    Result = lists:foldl(fun (Type, {Status, Acc}) ->
				 Features = plugin_features(Host, Type),
				 RetrieveFeature =
				     lists:member(<<"retrieve-subscriptions">>,
						  Features),
				 if not RetrieveFeature ->
					{{error,
					  extended_error(xmpp:err_feature_not_implemented(),
							 err_unsupported('retrieve-subscriptions'))},
					 Acc};
				    true ->
					Subscriber = jid:remove_resource(JID),
					{result, Subs} = node_action(Host, Type,
								     get_entity_subscriptions,
								     [Host,
								      Subscriber]),
					{Status, [Subs | Acc]}
				 end
			 end,
			 {ok, []}, Plugins),
    case Result of
      {ok, Subs} ->
	  Entities = lists:flatmap(fun ({#pubsub_node{nodeid =
							  {_, SubsNode}},
					 Sub}) ->
					   case Node of
					     <<>> ->
						 [#ps_subscription{node =
								       SubsNode,
								   type = Sub}];
					     SubsNode ->
						 [#ps_subscription{type = Sub}];
					     _ -> []
					   end;
				       ({#pubsub_node{nodeid = {_, SubsNode}},
					 Sub, SubId, SubJID}) ->
					   case Node of
					     <<>> ->
						 [#ps_subscription{jid = SubJID,
								   subid =
								       SubId,
								   type = Sub,
								   node =
								       SubsNode}];
					     SubsNode ->
						 [#ps_subscription{jid = SubJID,
								   subid =
								       SubId,
								   type = Sub}];
					     _ -> []
					   end;
				       ({#pubsub_node{nodeid = {_, SubsNode}},
					 Sub, SubJID}) ->
					   case Node of
					     <<>> ->
						 [#ps_subscription{jid = SubJID,
								   type = Sub,
								   node =
								       SubsNode}];
					     SubsNode ->
						 [#ps_subscription{jid = SubJID,
								   type = Sub}];
					     _ -> []
					   end
				   end,
				   lists:usort(lists:flatten(Subs))),
	  {result, #pubsub{subscriptions = {<<>>, Entities}}};
      {Error, _} -> Error
    end.

- spec ( { { get_subscriptions , 3 } , [ { type , 2403 , 'fun' , [ { type , 2403 , product , [ { type , 2403 , host , [ ] } , { type , 2403 , binary , [ ] } , { type , 2403 , jid , [ ] } ] } , { type , 2403 , union , [ { type , 2403 , tuple , [ { atom , 2403 , result } , { type , 2403 , pubsub_owner , [ ] } ] } , { type , 2404 , tuple , [ { atom , 2404 , error } , { type , 2404 , stanza_error , [ ] } ] } ] } ] } ] } ) .


get_subscriptions(Host, Node, JID) ->
    Action = fun (#pubsub_node{type = Type, id = Nidx}) ->
		     Features = plugin_features(Host, Type),
		     RetrieveFeature =
			 lists:member(<<"manage-subscriptions">>, Features),
		     {result, Affiliation} = node_call(Host, Type,
						       get_affiliation,
						       [Nidx, JID]),
		     if not RetrieveFeature ->
			    {error,
			     extended_error(xmpp:err_feature_not_implemented(),
					    err_unsupported('manage-subscriptions'))};
			Affiliation /= owner ->
			    {error,
			     xmpp:err_forbidden(<<"Owner privileges required">>,
						ejabberd_config:get_mylang())};
			true ->
			    node_call(Host, Type, get_node_subscriptions,
				      [Nidx])
		     end
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_, Subs}} ->
	  Entities = lists:flatmap(fun ({_, none}) -> [];
				       ({_, pending, _}) -> [];
				       ({AJID, Sub}) ->
					   [#ps_subscription{jid = AJID,
							     type = Sub}];
				       ({AJID, Sub, SubId}) ->
					   [#ps_subscription{jid = AJID,
							     type = Sub,
							     subid = SubId}]
				   end,
				   Subs),
	  {result,
	   #pubsub_owner{subscriptions = {Node, Entities}}};
      Error -> Error
    end.

get_subscriptions_for_send_last(Host, PType, sql, JID,
				LJID, BJID) ->
    {result, Subs} = node_action(Host, PType,
				 get_entity_subscriptions_for_send_last,
				 [Host, JID]),
    [{Node, SubId, SubJID}
     || {Node, Sub, SubId, SubJID} <- Subs,
	Sub =:= subscribed,
	(SubJID == LJID) or (SubJID == BJID)];
% sql version already filter result by on_sub_and_presence
get_subscriptions_for_send_last(Host, PType, _, JID,
				LJID, BJID) ->
    {result, Subs} = node_action(Host, PType,
				 get_entity_subscriptions, [Host, JID]),
    [{Node, SubId, SubJID}
     || {Node, Sub, SubId, SubJID} <- Subs,
	Sub =:= subscribed,
	(SubJID == LJID) or (SubJID == BJID),
	match_option(Node, send_last_published_item,
		     on_sub_and_presence)].

- spec ( { { set_subscriptions , 4 } , [ { type , 2454 , 'fun' , [ { type , 2454 , product , [ { type , 2454 , host , [ ] } , { type , 2454 , binary , [ ] } , { type , 2454 , jid , [ ] } , { type , 2454 , list , [ { type , 2454 , ps_subscription , [ ] } ] } ] } , { type , 2455 , union , [ { type , 2455 , tuple , [ { atom , 2455 , result } , { atom , 2455 , undefined } ] } , { type , 2455 , tuple , [ { atom , 2455 , error } , { type , 2455 , stanza_error , [ ] } ] } ] } ] } ] } ) .


set_subscriptions(Host, Node, From, Entities) ->
    Owner = jid:tolower(jid:remove_resource(From)),
    Notify = fun (#ps_subscription{jid = JID,
				   type = Sub}) ->
		     Stanza = #message{from = service_jid(Host), to = JID,
				       sub_els =
					   [#ps_event{subscription =
							  #ps_subscription{jid =
									       JID,
									   type
									       =
									       Sub,
									   node
									       =
									       Node}}]},
		     ejabberd_router:route(Stanza)
	     end,
    Action = fun (#pubsub_node{type = Type, id = Nidx,
			       owners = O}) ->
		     Owners = node_owners_call(Host, Type, Nidx, O),
		     case lists:member(Owner, Owners) of
		       true ->
			   Result = lists:foldl(fun (_, {error, _} = Err) ->
							Err;
						    (#ps_subscription{jid = JID,
								      type =
									  Sub,
								      subid =
									  SubId} =
							 Entity,
						     _) ->
							case node_call(Host,
								       Type,
								       set_subscriptions,
								       [Nidx,
									JID,
									Sub,
									SubId])
							    of
							  {error, _} = Err ->
							      Err;
							  _ -> Notify(Entity)
							end
						end,
						ok, Entities),
			   case Result of
			     ok -> {result, undefined};
			     {error, _} = Err -> Err
			   end;
		       _ ->
			   {error,
			    xmpp:err_forbidden(<<"Owner privileges required">>,
					       ejabberd_config:get_mylang())}
		     end
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_, Result}} -> {result, Result};
      Other -> Other
    end.

- spec ( { { get_presence_and_roster_permissions , 5 } , [ { type , 2504 , 'fun' , [ { type , 2504 , product , [ { type , 2505 , host , [ ] } , { type , 2505 , ljid , [ ] } , { type , 2505 , list , [ { type , 2505 , ljid , [ ] } ] } , { type , 2505 , accessModel , [ ] } , { type , 2506 , list , [ { type , 2506 , binary , [ ] } ] } ] } , { type , 2506 , tuple , [ { type , 2506 , boolean , [ ] } , { type , 2506 , boolean , [ ] } ] } ] } ] } ) .


get_presence_and_roster_permissions(Host, From, Owners,
				    AccessModel, AllowedGroups) ->
    if (AccessModel == presence) or
	 (AccessModel == roster) ->
	   case Host of
	     {User, Server, _} ->
		 get_roster_info(User, Server, From, AllowedGroups);
	     _ ->
		 [{OUser, OServer, _} | _] = Owners,
		 get_roster_info(OUser, OServer, From, AllowedGroups)
	   end;
       true -> {true, true}
    end.

get_roster_info(_, _, {<<>>, <<>>, _}, _) ->
    {false, false};
get_roster_info(OwnerUser, OwnerServer,
		{SubscriberUser, SubscriberServer, _}, AllowedGroups) ->
    LJID = {SubscriberUser, SubscriberServer, <<>>},
    {Subscription, _Ask, Groups} =
	ejabberd_hooks:run_fold(roster_get_jid_info,
				OwnerServer, {none, none, []},
				[OwnerUser, OwnerServer, LJID]),
    PresenceSubscription = Subscription == both orelse
			     Subscription == from orelse
			       {OwnerUser, OwnerServer} ==
				 {SubscriberUser, SubscriberServer},
    RosterGroup = lists:any(fun (Group) ->
				    lists:member(Group, AllowedGroups)
			    end,
			    Groups),
    {PresenceSubscription, RosterGroup};
get_roster_info(OwnerUser, OwnerServer, JID,
		AllowedGroups) ->
    get_roster_info(OwnerUser, OwnerServer,
		    jid:tolower(JID), AllowedGroups).

- spec ( { { preconditions_met , 2 } , [ { type , 2538 , 'fun' , [ { type , 2538 , product , [ { remote_type , 2538 , [ { atom , 2538 , pubsub_publish_options } , { atom , 2538 , result } , [ ] ] } , { remote_type , 2539 , [ { atom , 2539 , pubsub_node_config } , { atom , 2539 , result } , [ ] ] } ] } , { type , 2539 , boolean , [ ] } ] } ] } ) .


preconditions_met(PubOpts, NodeOpts) ->
    lists:all(fun (Opt) -> lists:member(Opt, NodeOpts) end,
	      PubOpts).

- spec ( { { service_jid , 1 } , [ { type , 2543 , 'fun' , [ { type , 2543 , product , [ { type , 2543 , union , [ { type , 2543 , jid , [ ] } , { type , 2543 , ljid , [ ] } , { type , 2543 , binary , [ ] } ] } ] } , { type , 2543 , jid , [ ] } ] } ] } ) .


service_jid(#jid{} = Jid) -> Jid;
service_jid({U, S, R}) -> jid:make(U, S, R);
service_jid(Host) -> jid:make(Host).

%% @spec (LJID, NotifyType, Depth, NodeOptions, SubOptions) -> boolean()
%%        LJID = jid()
%%        NotifyType = items | nodes
%%        Depth = integer()
%%        NodeOptions = [{atom(), term()}]
%%        SubOptions = [{atom(), term()}]
%% @doc <p>Check if a notification must be delivered or not based on
%% node and subscription options.</p>
is_to_deliver(LJID, NotifyType, Depth, NodeOptions,
	      SubOptions) ->
    sub_to_deliver(LJID, NotifyType, Depth, SubOptions)
      andalso node_to_deliver(LJID, NodeOptions).

sub_to_deliver(_LJID, NotifyType, Depth, SubOptions) ->
    lists:all(fun (Option) ->
		      sub_option_can_deliver(NotifyType, Depth, Option)
	      end,
	      SubOptions).

node_to_deliver(LJID, NodeOptions) ->
    presence_can_deliver(LJID,
			 get_option(NodeOptions, presence_based_delivery)).

sub_option_can_deliver(items, _,
		       {subscription_type, nodes}) ->
    false;
sub_option_can_deliver(nodes, _,
		       {subscription_type, items}) ->
    false;
sub_option_can_deliver(_, _,
		       {subscription_depth, all}) ->
    true;
sub_option_can_deliver(_, Depth,
		       {subscription_depth, D}) ->
    Depth =< D;
sub_option_can_deliver(_, _, {deliver, false}) -> false;
sub_option_can_deliver(_, _, {expire, When}) ->
    p1_time_compat:timestamp() < When;
sub_option_can_deliver(_, _, _) -> true.

- spec ( { { presence_can_deliver , 2 } , [ { type , 2577 , 'fun' , [ { type , 2577 , product , [ { type , 2577 , ljid , [ ] } , { type , 2577 , boolean , [ ] } ] } , { type , 2577 , boolean , [ ] } ] } ] } ) .


presence_can_deliver(_, false) -> true;
presence_can_deliver({User, Server, Resource}, true) ->
    case ejabberd_sm:get_user_present_resources(User,
						Server)
	of
      [] -> false;
      Ss ->
	  lists:foldl(fun (_, true) -> true;
			  ({_, R}, _Acc) ->
			      case Resource of
				<<>> -> true;
				R -> true;
				_ -> false
			      end
		      end,
		      false, Ss)
    end.

- spec ( { { state_can_deliver , 2 } , [ { type , 2598 , 'fun' , [ { type , 2598 , product , [ { type , 2598 , ljid , [ ] } , { type , 2598 , union , [ { type , 2598 , subOptions , [ ] } , { type , 2598 , nil , [ ] } ] } ] } , { type , 2598 , list , [ { type , 2598 , ljid , [ ] } ] } ] } ] } ) .


state_can_deliver({U, S, R}, []) -> [{U, S, R}];
state_can_deliver({U, S, R}, SubOptions) ->
    case lists:keysearch(show_values, 1, SubOptions) of
      %% If not in suboptions, item can be delivered, case doesn't apply
      false -> [{U, S, R}];
      %% If in a suboptions ...
      {_, {_, ShowValues}} ->
	  Resources = case R of
			%% If the subscriber JID is a bare one, get all its resources
			<<>> -> user_resources(U, S);
			%% If the subscriber JID is a full one, use its resource
			R -> [R]
		      end,
	  lists:foldl(fun (Resource, Acc) ->
			      get_resource_state({U, S, Resource}, ShowValues,
						 Acc)
		      end,
		      [], Resources)
    end.

- spec ( { { get_resource_state , 3 } , [ { type , 2618 , 'fun' , [ { type , 2618 , product , [ { type , 2618 , ljid , [ ] } , { type , 2618 , list , [ { type , 2618 , binary , [ ] } ] } , { type , 2618 , list , [ { type , 2618 , ljid , [ ] } ] } ] } , { type , 2618 , list , [ { type , 2618 , ljid , [ ] } ] } ] } ] } ) .


get_resource_state({U, S, R}, ShowValues, JIDs) ->
    case ejabberd_sm:get_session_pid(U, S, R) of
      none ->
	  %% If no PID, item can be delivered
	  lists:append([{U, S, R}], JIDs);
      Pid ->
	  Show = case ejabberd_c2s:get_presence(Pid) of
		   #presence{type = unavailable} -> <<"unavailable">>;
		   #presence{show = undefined} -> <<"online">>;
		   #presence{show = S} -> atom_to_binary(S, latin1)
		 end,
	  case lists:member(Show, ShowValues) of
	    %% If yes, item can be delivered
	    true -> lists:append([{U, S, R}], JIDs);
	    %% If no, item can't be delivered
	    false -> JIDs
	  end
    end.

- spec ( { { payload_xmlelements , 1 } , [ { type , 2638 , 'fun' , [ { type , 2638 , product , [ { type , 2638 , list , [ { type , 2638 , xmlel , [ ] } ] } ] } , { type , 2638 , non_neg_integer , [ ] } ] } ] } ) .


payload_xmlelements(Payload) ->
    payload_xmlelements(Payload, 0).

payload_xmlelements([], Count) -> Count;
payload_xmlelements([#xmlel{} | Tail], Count) ->
    payload_xmlelements(Tail, Count + 1);
payload_xmlelements([_ | Tail], Count) ->
    payload_xmlelements(Tail, Count).

items_els(Node, Options, Items) ->
    Els = case get_option(Options, itemreply) of
	    publisher ->
		[#ps_item{id = ItemId, sub_els = Payload,
			  publisher = jid:encode(USR)}
		 || #pubsub_item{itemid = {ItemId, _}, payload = Payload,
				 modification = {_, USR}}
			<- Items];
	    _ ->
		[#ps_item{id = ItemId, sub_els = Payload}
		 || #pubsub_item{itemid = {ItemId, _}, payload = Payload}
			<- Items]
	  end,
    #ps_items{node = Node, items = Els}.

%%%%%% broadcast functions

broadcast_publish_item(Host, Node, Nidx, Type,
		       NodeOptions, ItemId, From, Payload, Removed) ->
    case get_collection_subscriptions(Host, Node) of
      SubsByDepth when is_list(SubsByDepth) ->
	  ItemPublisher = case get_option(NodeOptions, itemreply)
			      of
			    publisher -> jid:encode(From);
			    _ -> <<>>
			  end,
	  ItemPayload = case get_option(NodeOptions,
					deliver_payloads)
			    of
			  true -> Payload;
			  false -> []
			end,
	  ItemsEls = #ps_items{node = Node,
			       items =
				   [#ps_item{id = ItemId,
					     publisher = ItemPublisher,
					     sub_els = ItemPayload}]},
	  Stanza = #message{sub_els =
				[#ps_event{items = ItemsEls}]},
	  broadcast_stanza(Host, From, Node, Nidx, Type,
			   NodeOptions, SubsByDepth, items, Stanza, true),
	  case Removed of
	    [] -> ok;
	    _ ->
		case get_option(NodeOptions, notify_retract) of
		  true ->
		      RetractStanza = #message{sub_els =
						   [#ps_event{items =
								  #ps_items{node
										=
										Node,
									    retract
										=
										Removed}}]},
		      broadcast_stanza(Host, Node, Nidx, Type, NodeOptions,
				       SubsByDepth, items, RetractStanza, true);
		  _ -> ok
		end
	  end,
	  {result, true};
      _ -> {result, false}
    end.

broadcast_retract_items(Host, Node, Nidx, Type,
			NodeOptions, ItemIds) ->
    broadcast_retract_items(Host, Node, Nidx, Type,
			    NodeOptions, ItemIds, false).

broadcast_retract_items(_Host, _Node, _Nidx, _Type,
			_NodeOptions, [], _ForceNotify) ->
    {result, false};
broadcast_retract_items(Host, Node, Nidx, Type,
			NodeOptions, ItemIds, ForceNotify) ->
    case get_option(NodeOptions, notify_retract) or
	   ForceNotify
	of
      true ->
	  case get_collection_subscriptions(Host, Node) of
	    SubsByDepth when is_list(SubsByDepth) ->
		Stanza = #message{sub_els =
				      [#ps_event{items =
						     #ps_items{node = Node,
							       retract =
								   ItemIds}}]},
		broadcast_stanza(Host, Node, Nidx, Type, NodeOptions,
				 SubsByDepth, items, Stanza, true),
		{result, true};
	    _ -> {result, false}
	  end;
      _ -> {result, false}
    end.

broadcast_purge_node(Host, Node, Nidx, Type,
		     NodeOptions) ->
    case get_option(NodeOptions, notify_retract) of
      true ->
	  case get_collection_subscriptions(Host, Node) of
	    SubsByDepth when is_list(SubsByDepth) ->
		Stanza = #message{sub_els = [#ps_event{purge = Node}]},
		broadcast_stanza(Host, Node, Nidx, Type, NodeOptions,
				 SubsByDepth, nodes, Stanza, false),
		{result, true};
	    _ -> {result, false}
	  end;
      _ -> {result, false}
    end.

broadcast_removed_node(Host, Node, Nidx, Type,
		       NodeOptions, SubsByDepth) ->
    case get_option(NodeOptions, notify_delete) of
      true ->
	  case SubsByDepth of
	    [] -> {result, false};
	    _ ->
		Stanza = #message{sub_els =
				      [#ps_event{delete = {Node, <<>>}}]},
		broadcast_stanza(Host, Node, Nidx, Type, NodeOptions,
				 SubsByDepth, nodes, Stanza, false),
		{result, true}
	  end;
      _ -> {result, false}
    end.

broadcast_created_node(_, _, _, _, _, []) ->
    {result, false};
broadcast_created_node(Host, Node, Nidx, Type,
		       NodeOptions, SubsByDepth) ->
    Stanza = #message{sub_els = [#ps_event{create = Node}]},
    broadcast_stanza(Host, Node, Nidx, Type, NodeOptions,
		     SubsByDepth, nodes, Stanza, true),
    {result, true}.

broadcast_config_notification(Host, Node, Nidx, Type,
			      NodeOptions, Lang) ->
    case get_option(NodeOptions, notify_config) of
      true ->
	  case get_collection_subscriptions(Host, Node) of
	    SubsByDepth when is_list(SubsByDepth) ->
		Content = case get_option(NodeOptions, deliver_payloads)
			      of
			    true ->
				#xdata{type = result,
				       fields =
					   get_configure_xfields(Type,
								 NodeOptions,
								 Lang, [])};
			    false -> undefined
			  end,
		Stanza = #message{sub_els =
				      [#ps_event{configuration =
						     {Node, Content}}]},
		broadcast_stanza(Host, Node, Nidx, Type, NodeOptions,
				 SubsByDepth, nodes, Stanza, false),
		{result, true};
	    _ -> {result, false}
	  end;
      _ -> {result, false}
    end.

get_collection_subscriptions(Host, Node) ->
    Action = fun () ->
		     {result,
		      get_node_subs_by_depth(Host, Node, service_jid(Host))}
	     end,
    case transaction(Host, Action, sync_dirty) of
      {result, CollSubs} -> CollSubs;
      _ -> []
    end.

get_node_subs_by_depth(Host, Node, From) ->
    ParentTree = tree_call(Host, get_parentnodes_tree,
			   [Host, Node, From]),
    [{Depth, [{N, get_node_subs(Host, N)} || N <- Nodes]}
     || {Depth, Nodes} <- ParentTree].

get_node_subs(Host,
	      #pubsub_node{type = Type, id = Nidx}) ->
    WithOptions = lists:member(<<"subscription-options">>,
			       plugin_features(Host, Type)),
    case node_call(Host, Type, get_node_subscriptions,
		   [Nidx])
	of
      {result, Subs} ->
	  get_options_for_subs(Host, Nidx, Subs, WithOptions);
      Other -> Other
    end.

get_options_for_subs(_Host, _Nidx, Subs, false) ->
    lists:foldl(fun ({JID, subscribed, SubID}, Acc) ->
			[{JID, SubID, []} | Acc];
		    (_, Acc) -> Acc
		end,
		[], Subs);
get_options_for_subs(Host, Nidx, Subs, true) ->
    SubModule = subscription_plugin(Host),
    lists:foldl(fun ({JID, subscribed, SubID}, Acc) ->
			case SubModule:get_subscription(JID, Nidx, SubID) of
			  #pubsub_subscription{options = Options} ->
			      [{JID, SubID, Options} | Acc];
			  {error, notfound} -> [{JID, SubID, []} | Acc]
			end;
		    (_, Acc) -> Acc
		end,
		[], Subs).

broadcast_stanza(Host, _Node, _Nidx, _Type, NodeOptions,
		 SubsByDepth, NotifyType, BaseStanza, SHIM) ->
    NotificationType = get_option(NodeOptions,
				  notification_type, headline),
    BroadcastAll = get_option(NodeOptions,
			      broadcast_all_resources), %% XXX this is not standard, but useful
    Stanza = add_message_type(xmpp:set_from(BaseStanza,
					    service_jid(Host)),
			      NotificationType),
    %% Handles explicit subscriptions
    SubIDsByJID = subscribed_nodes_by_jid(NotifyType,
					  SubsByDepth),
    lists:foreach(fun ({LJID, _NodeName, SubIDs}) ->
			  LJIDs = case BroadcastAll of
				    true ->
					{U, S, _} = LJID,
					[{U, S, R}
					 || R <- user_resources(U, S)];
				    false -> [LJID]
				  end,
			  %% Determine if the stanza should have SHIM ('SubID' and 'name') headers
			  StanzaToSend = case {SHIM, SubIDs} of
					   {false, _} -> Stanza;
					   %% If there's only one SubID, don't add it
					   {true, [_]} -> Stanza;
					   {true, SubIDs} ->
					       add_shim_headers(Stanza,
								subid_shim(SubIDs))
					 end,
			  lists:foreach(fun (To) ->
						ejabberd_router:route(xmpp:set_to(StanzaToSend,
										  jid:make(To)))
					end,
					LJIDs)
		  end,
		  SubIDsByJID).

broadcast_stanza({LUser, LServer, LResource}, Publisher,
		 Node, Nidx, Type, NodeOptions, SubsByDepth, NotifyType,
		 BaseStanza, SHIM) ->
    broadcast_stanza({LUser, LServer, <<>>}, Node, Nidx,
		     Type, NodeOptions, SubsByDepth, NotifyType, BaseStanza,
		     SHIM),
    %% Handles implicit presence subscriptions
    SenderResource = user_resource(LUser, LServer,
				   LResource),
    NotificationType = get_option(NodeOptions,
				  notification_type, headline),
    %% set the from address on the notification to the bare JID of the account owner
    %% Also, add "replyto" if entity has presence subscription to the account owner
    %% See XEP-0163 1.1 section 4.3.1
    FromBareJid = xmpp:set_from(BaseStanza,
				jid:make(LUser, LServer)),
    Stanza =
	add_extended_headers(add_message_type(FromBareJid,
					      NotificationType),
			     extended_headers([Publisher])),
    ejabberd_sm:route(jid:make(LUser, LServer,
			       SenderResource),
		      {pep_message, <<Node/binary, "+notify">>, Stanza}),
    ejabberd_router:route(xmpp:set_to(Stanza,
				      jid:make(LUser, LServer)));
broadcast_stanza(Host, _Publisher, Node, Nidx, Type,
		 NodeOptions, SubsByDepth, NotifyType, BaseStanza,
		 SHIM) ->
    broadcast_stanza(Host, Node, Nidx, Type, NodeOptions,
		     SubsByDepth, NotifyType, BaseStanza, SHIM).

- spec ( { { c2s_handle_info , 2 } , [ { type , 2882 , 'fun' , [ { type , 2882 , product , [ { remote_type , 2882 , [ { atom , 2882 , ejabberd_c2s } , { atom , 2882 , state } , [ ] ] } , { type , 2882 , term , [ ] } ] } , { remote_type , 2882 , [ { atom , 2882 , ejabberd_c2s } , { atom , 2882 , state } , [ ] ] } ] } ] } ) .


c2s_handle_info ( # { lserver : = LServer } = C2SState , { pep_message , Feature , Packet } ) -> [ maybe_send_pep_stanza ( LServer , USR , Caps , Feature , Packet ) || { USR , Caps } <- mod_caps : list_features ( C2SState ) ] , { stop , C2SState } ; c2s_handle_info ( # { lserver : = LServer } = C2SState , { pep_message , Feature , Packet , USR } ) -> case mod_caps : get_user_caps ( USR , C2SState ) of { ok , Caps } -> maybe_send_pep_stanza ( LServer , USR , Caps , Feature , Packet ) ; error -> ok end , { stop , C2SState } ; c2s_handle_info ( C2SState , _ ) -> C2SState .


send_items(Host, Node, Nidx, Type, Options, LJID,
	   Number) ->
    send_items(Host, Node, Nidx, Type, Options, Host, LJID,
	       LJID, Number).

send_items(Host, Node, Nidx, Type, Options, Publisher,
	   SubLJID, ToLJID, Number) ->
    case get_last_items(Host, Type, Nidx, SubLJID, Number)
	of
      [] -> ok;
      Items ->
	  Delay = case Number of
		    last -> % handle section 6.1.7 of XEP-0060
			[Last] = Items,
			{Stamp, _USR} = Last#pubsub_item.modification,
			[#delay{stamp = Stamp}];
		    _ -> []
		  end,
	  Stanza = #message{sub_els =
				[#ps_event{items =
					       items_els(Node, Options, Items)}
				 | Delay]},
	  NotificationType = get_option(Options,
					notification_type, headline),
	  send_stanza(Publisher, ToLJID, Node,
		      add_message_type(Stanza, NotificationType))
    end.

send_stanza({LUser, LServer, _} = Publisher, USR, Node,
	    BaseStanza) ->
    Stanza = xmpp:set_from(BaseStanza,
			   jid:make(LUser, LServer)),
    USRs = case USR of
	     {PUser, PServer, <<>>} ->
		 [{PUser, PServer, PRessource}
		  || PRessource <- user_resources(PUser, PServer)];
	     _ -> [USR]
	   end,
    [ejabberd_sm:route(jid:make(Publisher),
		       {pep_message, <<Node/binary, "+notify">>,
			add_extended_headers(Stanza,
					     extended_headers([Publisher])),
			To})
     || To <- USRs];
send_stanza(Host, USR, _Node, Stanza) ->
    ejabberd_router:route(xmpp:set_from_to(Stanza,
					   service_jid(Host), jid:make(USR))).

maybe_send_pep_stanza(LServer, USR, Caps, Feature,
		      Packet) ->
    Features = mod_caps:get_features(LServer, Caps),
    case lists:member(Feature, Features) of
      true ->
	  ejabberd_router:route(xmpp:set_to(Packet,
					    jid:make(USR)));
      false -> ok
    end.

send_last_items(JID) ->
    ServerHost = JID#jid.lserver,
    Host = host(ServerHost),
    DBType = config(ServerHost, db_type),
    LJID = jid:tolower(JID),
    BJID = jid:remove_resource(LJID),
    lists:foreach(fun (PType) ->
			  Subs = get_subscriptions_for_send_last(Host, PType,
								 DBType, JID,
								 LJID, BJID),
			  lists:foreach(fun ({#pubsub_node{nodeid = {_, Node},
							   type = Type,
							   id = Nidx,
							   options = Options},
					      _, SubJID})
						when Type == PType ->
						send_items(Host, Node, Nidx,
							   PType, Options, Host,
							   SubJID, LJID, 1);
					    (_) -> ok
					end,
					lists:usort(Subs))
		  end,
		  config(ServerHost, plugins)).

% pep_from_offline hack can not work anymore, as sender c2s does not
% exists when sender is offline, so we can't get match receiver caps
% does it make sens to send PEP from an offline contact anyway ?
%    case config(ServerHost, ignore_pep_from_offline) of
%	false ->
%	    Roster = ejabberd_hooks:run_fold(roster_get, ServerHost, [],
%					     [{JID#jid.luser, ServerHost}]),
%	    lists:foreach(
%	      fun(#roster{jid = {U, S, R}, subscription = Sub})
%		    when Sub == both orelse Sub == from,
%			 S == ServerHost ->
%		      case user_resources(U, S) of
%			  [] -> send_last_pep(jid:make(U, S, R), JID);
%			  _ -> ok %% this is already handled by presence probe
%		      end;
%		 (_) ->
%		      ok %% we can not do anything in any cases
%	      end, Roster);
%	true ->
%	    ok
%    end.
send_last_pep(From, To) ->
    ServerHost = From#jid.lserver,
    Host = host(ServerHost),
    Publisher = jid:tolower(From),
    Owner = jid:remove_resource(Publisher),
    lists:foreach(fun (#pubsub_node{nodeid = {_, Node},
				    type = Type, id = Nidx,
				    options = Options}) ->
			  case match_option(Options, send_last_published_item,
					    on_sub_and_presence)
			      of
			    true ->
				LJID = jid:tolower(To),
				Subscribed = case get_option(Options,
							     access_model)
						 of
					       open -> true;
					       presence -> true;
					       whitelist ->
						   false; % subscribers are added manually
					       authorize -> false; % likewise
					       roster ->
						   Grps = get_option(Options,
								     roster_groups_allowed,
								     []),
						   {OU, OS, _} = Owner,
						   element(2,
							   get_roster_info(OU,
									   OS,
									   LJID,
									   Grps))
					     end,
				if Subscribed ->
				       send_items(Owner, Node, Nidx, Type,
						  Options, Publisher, LJID,
						  LJID, 1);
				   true -> ok
				end;
			    _ -> ok
			  end
		  end,
		  tree_action(Host, get_nodes, [Owner, From])).

subscribed_nodes_by_jid(NotifyType, SubsByDepth) ->
    NodesToDeliver = fun (Depth, Node, Subs, Acc) ->
			     NodeName = case Node#pubsub_node.nodeid of
					  {_, N} -> N;
					  Other -> Other
					end,
			     NodeOptions = Node#pubsub_node.options,
			     lists:foldl(fun ({LJID, SubID, SubOptions},
					      {JIDs, Recipients}) ->
						 case is_to_deliver(LJID,
								    NotifyType,
								    Depth,
								    NodeOptions,
								    SubOptions)
						     of
						   true ->
						       case
							 state_can_deliver(LJID,
									   SubOptions)
							   of
							 [] ->
							     {JIDs, Recipients};
							 [LJID] ->
							     {JIDs,
							      [{LJID, NodeName,
								[SubID]}
							       | Recipients]};
							 JIDsToDeliver ->
							     lists:foldl(fun
									   (JIDToDeliver,
									    {JIDsAcc,
									     RecipientsAcc}) ->
									       case
										 lists:member(JIDToDeliver,
											      JIDs)
										   of
										 %% check if the JIDs co-accumulator contains the Subscription Jid,
										 false ->
										     %%  - if not,
										     %%  - add the Jid to JIDs list co-accumulator ;
										     %%  - create a tuple of the Jid, Nidx, and SubID (as list),
										     %%    and add the tuple to the Recipients list co-accumulator
										     {[JIDToDeliver
										       | JIDsAcc],
										      [{JIDToDeliver,
											NodeName,
											[SubID]}
										       | RecipientsAcc]};
										 true ->
										     %% - if the JIDs co-accumulator contains the Jid
										     %%   get the tuple containing the Jid from the Recipient list co-accumulator
										     {_,
										      {JIDToDeliver,
										       NodeName1,
										       SubIDs}} =
											 lists:keysearch(JIDToDeliver,
													 1,
													 RecipientsAcc),
										     %%   delete the tuple from the Recipients list
										     % v1 : Recipients1 = lists:keydelete(LJID, 1, Recipients),
										     % v2 : Recipients1 = lists:keyreplace(LJID, 1, Recipients, {LJID, Nidx1, [SubID | SubIDs]}),
										     %%   add the SubID to the SubIDs list in the tuple,
										     %%   and add the tuple back to the Recipients list co-accumulator
										     % v1.1 : {JIDs, lists:append(Recipients1, [{LJID, Nidx1, lists:append(SubIDs, [SubID])}])}
										     % v1.2 : {JIDs, [{LJID, Nidx1, [SubID | SubIDs]} | Recipients1]}
										     % v2: {JIDs, Recipients1}
										     {JIDsAcc,
										      lists:keyreplace(JIDToDeliver,
												       1,
												       RecipientsAcc,
												       {JIDToDeliver,
													NodeName1,
													[SubID
													 | SubIDs]})}
									       end
									 end,
									 {JIDs,
									  Recipients},
									 JIDsToDeliver)
						       end;
						   false -> {JIDs, Recipients}
						 end
					 end,
					 Acc, Subs)
		     end,
    DepthsToDeliver = fun ({Depth, SubsByNode}, Acc1) ->
			      lists:foldl(fun ({Node, Subs}, Acc2) ->
						  NodesToDeliver(Depth, Node,
								 Subs, Acc2)
					  end,
					  Acc1, SubsByNode)
		      end,
    {_, JIDSubs} = lists:foldl(DepthsToDeliver, {[], []},
			       SubsByDepth),
    JIDSubs.

- spec ( { { user_resources , 2 } , [ { type , 3077 , 'fun' , [ { type , 3077 , product , [ { type , 3077 , binary , [ ] } , { type , 3077 , binary , [ ] } ] } , { type , 3077 , list , [ { type , 3077 , binary , [ ] } ] } ] } ] } ) .


user_resources(User, Server) ->
    ejabberd_sm:get_user_resources(User, Server).

- spec ( { { user_resource , 3 } , [ { type , 3081 , 'fun' , [ { type , 3081 , product , [ { type , 3081 , binary , [ ] } , { type , 3081 , binary , [ ] } , { type , 3081 , binary , [ ] } ] } , { type , 3081 , binary , [ ] } ] } ] } ) .


user_resource(User, Server, <<>>) ->
    case user_resources(User, Server) of
      [R | _] -> R;
      _ -> <<>>
    end;
user_resource(_, _, Resource) -> Resource.

%%%%%%% Configuration handling
- spec ( { { get_configure , 5 } , [ { type , 3091 , 'fun' , [ { type , 3091 , product , [ { type , 3091 , host , [ ] } , { type , 3091 , binary , [ ] } , { type , 3091 , binary , [ ] } , { type , 3091 , jid , [ ] } , { type , 3092 , binary , [ ] } ] } , { type , 3092 , union , [ { type , 3092 , tuple , [ { atom , 3092 , error } , { type , 3092 , stanza_error , [ ] } ] } , { type , 3092 , tuple , [ { atom , 3092 , result } , { type , 3092 , pubsub_owner , [ ] } ] } ] } ] } ] } ) .


get_configure(Host, ServerHost, Node, From, Lang) ->
    Action = fun (#pubsub_node{options = Options,
			       type = Type, id = Nidx}) ->
		     case node_call(Host, Type, get_affiliation,
				    [Nidx, From])
			 of
		       {result, owner} ->
			   Groups = ejabberd_hooks:run_fold(roster_groups,
							    ServerHost, [],
							    [ServerHost]),
			   Fs = get_configure_xfields(Type, Options, Lang,
						      Groups),
			   {result,
			    #pubsub_owner{configure =
					      {Node,
					       #xdata{type = form,
						      fields = Fs}}}};
		       _ ->
			   {error,
			    xmpp:err_forbidden(<<"Owner privileges required">>,
					       Lang)}
		     end
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, {_, Result}} -> {result, Result};
      Other -> Other
    end.

- spec ( { { get_default , 4 } , [ { type , 3111 , 'fun' , [ { type , 3111 , product , [ { type , 3111 , host , [ ] } , { type , 3111 , binary , [ ] } , { type , 3111 , jid , [ ] } , { type , 3111 , binary , [ ] } ] } , { type , 3111 , tuple , [ { atom , 3111 , result } , { type , 3111 , pubsub_owner , [ ] } ] } ] } ] } ) .


get_default(Host, Node, _From, Lang) ->
    Type = select_type(serverhost(Host), Host, Node),
    Options = node_options(Host, Type),
    Fs = get_configure_xfields(Type, Options, Lang, []),
    {result,
     #pubsub_owner{default =
		       {<<>>, #xdata{type = form, fields = Fs}}}}.

- spec ( { { match_option , 3 } , [ { type , 3118 , 'fun' , [ { type , 3118 , product , [ { type , 3118 , union , [ { type , 3118 , record , [ { atom , 3118 , pubsub_node } ] } , { type , 3118 , list , [ { type , 3118 , tuple , [ { type , 3118 , atom , [ ] } , { type , 3118 , any , [ ] } ] } ] } ] } , { type , 3118 , atom , [ ] } , { type , 3118 , any , [ ] } ] } , { type , 3118 , boolean , [ ] } ] } ] } ) .


match_option(Node, Var, Val)
    when is_record(Node, pubsub_node) ->
    match_option(Node#pubsub_node.options, Var, Val);
match_option(Options, Var, Val) when is_list(Options) ->
    get_option(Options, Var) == Val;
match_option(_, _, _) -> false.

- spec ( { { get_option , 2 } , [ { type , 3126 , 'fun' , [ { type , 3126 , product , [ { type , 3126 , list , [ { type , 3126 , tuple , [ { type , 3126 , atom , [ ] } , { type , 3126 , any , [ ] } ] } ] } , { type , 3126 , atom , [ ] } ] } , { type , 3126 , any , [ ] } ] } ] } ) .


get_option([], _) -> false;
get_option(Options, Var) ->
    get_option(Options, Var, false).

- spec ( { { get_option , 3 } , [ { type , 3130 , 'fun' , [ { type , 3130 , product , [ { type , 3130 , list , [ { type , 3130 , tuple , [ { type , 3130 , atom , [ ] } , { type , 3130 , any , [ ] } ] } ] } , { type , 3130 , atom , [ ] } , { type , 3130 , any , [ ] } ] } , { type , 3130 , any , [ ] } ] } ] } ) .


get_option(Options, Var, Def) ->
    case lists:keysearch(Var, 1, Options) of
      {value, {_Val, Ret}} -> Ret;
      _ -> Def
    end.

- spec ( { { node_options , 2 } , [ { type , 3137 , 'fun' , [ { type , 3137 , product , [ { type , 3137 , host , [ ] } , { type , 3137 , binary , [ ] } ] } , { type , 3137 , list , [ { type , 3137 , tuple , [ { type , 3137 , atom , [ ] } , { type , 3137 , any , [ ] } ] } ] } ] } ] } ) .


node_options(Host, Type) ->
    DefaultOpts = node_plugin_options(Host, Type),
    case config(Host, plugins) of
      [Type | _] ->
	  config(Host, default_node_config, DefaultOpts);
      _ -> DefaultOpts
    end.

- spec ( { { node_plugin_options , 2 } , [ { type , 3145 , 'fun' , [ { type , 3145 , product , [ { type , 3145 , host , [ ] } , { type , 3145 , binary , [ ] } ] } , { type , 3145 , list , [ { type , 3145 , tuple , [ { type , 3145 , atom , [ ] } , { type , 3145 , any , [ ] } ] } ] } ] } ] } ) .


node_plugin_options(Host, Type) ->
    Module = plugin(Host, Type),
    case catch Module:options() of
      {'EXIT', {undef, _}} ->
	  DefaultModule = plugin(Host, ?STDNODE),
	  DefaultModule:options();
      Result -> Result
    end.

- spec ( { { node_owners_action , 4 } , [ { type , 3156 , 'fun' , [ { type , 3156 , product , [ { type , 3156 , host , [ ] } , { type , 3156 , binary , [ ] } , { type , 3156 , nodeIdx , [ ] } , { type , 3156 , list , [ { type , 3156 , ljid , [ ] } ] } ] } , { type , 3156 , list , [ { type , 3156 , ljid , [ ] } ] } ] } ] } ) .


node_owners_action(Host, Type, Nidx, []) ->
    case node_action(Host, Type, get_node_affiliations,
		     [Nidx])
	of
      {result, Affs} ->
	  [LJID || {LJID, Aff} <- Affs, Aff =:= owner];
      _ -> []
    end;
node_owners_action(_Host, _Type, _Nidx, Owners) ->
    Owners.

- spec ( { { node_owners_call , 4 } , [ { type , 3165 , 'fun' , [ { type , 3165 , product , [ { type , 3165 , host , [ ] } , { type , 3165 , binary , [ ] } , { type , 3165 , nodeIdx , [ ] } , { type , 3165 , list , [ { type , 3165 , ljid , [ ] } ] } ] } , { type , 3165 , list , [ { type , 3165 , ljid , [ ] } ] } ] } ] } ) .


node_owners_call(Host, Type, Nidx, []) ->
    case node_call(Host, Type, get_node_affiliations,
		   [Nidx])
	of
      {result, Affs} ->
	  [LJID || {LJID, Aff} <- Affs, Aff =:= owner];
      _ -> []
    end;
node_owners_call(_Host, _Type, _Nidx, Owners) -> Owners.

node_config(Node, ServerHost) ->
    Opts = gen_mod:get_module_opt(ServerHost, ?MODULE,
				  force_node_config),
    node_config(Node, ServerHost, Opts).

node_config(Node, ServerHost,
	    [{RE, Opts} | NodeOpts]) ->
    case re:run(Node, RE) of
      {match, _} -> Opts;
      nomatch -> node_config(Node, ServerHost, NodeOpts)
    end;
node_config(_, _, []) -> [].

%% @spec (Host, Options) -> MaxItems
%%         Host = host()
%%         Options = [Option]
%%         Option = {Key::atom(), Value::term()}
%%         MaxItems = integer() | unlimited
%% @doc <p>Return the maximum number of items for a given node.</p>
%% <p>Unlimited means that there is no limit in the number of items that can
%% be stored.</p>
- spec ( { { max_items , 2 } , [ { type , 3196 , 'fun' , [ { type , 3196 , product , [ { type , 3196 , host , [ ] } , { type , 3196 , list , [ { type , 3196 , tuple , [ { type , 3196 , atom , [ ] } , { type , 3196 , any , [ ] } ] } ] } ] } , { type , 3196 , non_neg_integer , [ ] } ] } ] } ) .


max_items(Host, Options) ->
    case get_option(Options, persist_items) of
      true ->
	  case get_option(Options, max_items) of
	    I when is_integer(I), I < 0 -> 0;
	    I when is_integer(I) -> I;
	    _ -> ?MAXITEMS
	  end;
      false ->
	  case get_option(Options, send_last_published_item) of
	    never -> 0;
	    _ ->
		case is_last_item_cache_enabled(Host) of
		  true -> 0;
		  false -> 1
		end
	  end
    end.

- spec ( { { get_configure_xfields , 4 } , [ { type , 3217 , 'fun' , [ { type , 3217 , product , [ { var , 3217 , '_' } , { remote_type , 3217 , [ { atom , 3217 , pubsub_node_config } , { atom , 3217 , result } , [ ] ] } , { type , 3218 , binary , [ ] } , { type , 3218 , list , [ { type , 3218 , binary , [ ] } ] } ] } , { type , 3218 , list , [ { type , 3218 , xdata_field , [ ] } ] } ] } ] } ) .


get_configure_xfields(_Type, Options, Lang, Groups) ->
    pubsub_node_config:encode([get_configure_xfields_1(V1,
						       Groups)
			       || V1 <- Options],
			      Lang).

get_configure_xfields_1({roster_groups_allowed, Value},
			Groups) ->
    {roster_groups_allowed, Value, Groups};
get_configure_xfields_1(Opt, Groups) -> Opt.

%%<p>There are several reasons why the node configuration request might fail:</p>
%%<ul>
%%<li>The service does not support node configuration.</li>
%%<li>The requesting entity does not have sufficient privileges to configure the node.</li>
%%<li>The request did not specify a node.</li>
%%<li>The node has no configuration options.</li>
%%<li>The specified node does not exist.</li>
%%</ul>
- spec ( { { set_configure , 5 } , [ { type , 3237 , 'fun' , [ { type , 3237 , product , [ { type , 3237 , host , [ ] } , { type , 3237 , binary , [ ] } , { type , 3237 , jid , [ ] } , { type , 3237 , list , [ { type , 3237 , tuple , [ { type , 3237 , binary , [ ] } , { type , 3237 , list , [ { type , 3237 , binary , [ ] } ] } ] } ] } , { type , 3238 , binary , [ ] } ] } , { type , 3238 , union , [ { type , 3238 , tuple , [ { atom , 3238 , result } , { atom , 3238 , undefined } ] } , { type , 3238 , tuple , [ { atom , 3238 , error } , { type , 3238 , stanza_error , [ ] } ] } ] } ] } ] } ) .


set_configure(_Host, <<>>, _From, _Config, _Lang) ->
    {error,
     extended_error(xmpp:err_bad_request(),
		    err_nodeid_required())};
set_configure(Host, Node, From, Config, Lang) ->
    Action = fun (#pubsub_node{options = Options,
			       type = Type, id = Nidx} =
		      N) ->
		     case node_call(Host, Type, get_affiliation,
				    [Nidx, From])
			 of
		       {result, owner} ->
			   OldOpts = case Options of
				       [] -> node_options(Host, Type);
				       _ -> Options
				     end,
			   NewOpts = merge_config([node_config(Node,
							       serverhost(Host)),
						   Config, OldOpts]),
			   case tree_call(Host, set_node,
					  [N#pubsub_node{options = NewOpts}])
			       of
			     {result, Nidx} -> {result, NewOpts};
			     ok -> {result, NewOpts};
			     Err -> Err
			   end;
		       _ ->
			   {error,
			    xmpp:err_forbidden(<<"Owner privileges required">>,
					       Lang)}
		     end
	     end,
    case transaction(Host, Node, Action, transaction) of
      {result, {TNode, Options}} ->
	  Nidx = TNode#pubsub_node.id,
	  Type = TNode#pubsub_node.type,
	  broadcast_config_notification(Host, Node, Nidx, Type,
					Options, Lang),
	  {result, undefined};
      Other -> Other
    end.

- spec ( { { merge_config , 1 } , [ { type , 3275 , 'fun' , [ { type , 3275 , product , [ { type , 3275 , list , [ { type , 3275 , list , [ { remote_type , 3275 , [ { atom , 3275 , proplists } , { atom , 3275 , property } , [ ] ] } ] } ] } ] } , { type , 3275 , list , [ { remote_type , 3275 , [ { atom , 3275 , proplists } , { atom , 3275 , property } , [ ] ] } ] } ] } ] } ) .


merge_config(ListOfConfigs) ->
    lists:ukeysort(1, lists:flatten(ListOfConfigs)).

- spec ( { { decode_node_config , 3 } , [ { type , 3279 , 'fun' , [ { type , 3279 , product , [ { type , 3279 , union , [ { atom , 3279 , undefined } , { type , 3279 , xdata , [ ] } ] } , { type , 3279 , binary , [ ] } , { type , 3279 , binary , [ ] } ] } , { type , 3280 , union , [ { remote_type , 3280 , [ { atom , 3280 , pubsub_node_config } , { atom , 3280 , result } , [ ] ] } , { type , 3281 , tuple , [ { atom , 3281 , error } , { type , 3281 , stanza_error , [ ] } ] } ] } ] } ] } ) .


decode_node_config(undefined, _, _) -> [];
decode_node_config(#xdata{fields = Fs}, Host, Lang) ->
    try Config = pubsub_node_config:decode(Fs),
	Max = get_max_items_node(Host),
	case {check_opt_range(max_items, Config, Max),
	      check_opt_range(max_payload_size, Config,
			      ?MAX_PAYLOAD_SIZE)}
	    of
	  {true, true} -> Config;
	  {true, false} ->
	      erlang:error({pubsub_node_config,
			    {bad_var_value, <<"pubsub#max_payload_size">>,
			     ?NS_PUBSUB_NODE_CONFIG}});
	  {false, _} ->
	      erlang:error({pubsub_node_config,
			    {bad_var_value, <<"pubsub#max_items">>,
			     ?NS_PUBSUB_NODE_CONFIG}})
	end
    catch
      _:{pubsub_node_config, Why} ->
	  Txt = pubsub_node_config:format_error(Why),
	  {error, xmpp:err_resource_constraint(Txt, Lang)}
    end.

- spec ( { { decode_subscribe_options , 2 } , [ { type , 3308 , 'fun' , [ { type , 3308 , product , [ { type , 3308 , union , [ { atom , 3308 , undefined } , { type , 3308 , xdata , [ ] } ] } , { type , 3308 , binary , [ ] } ] } , { type , 3309 , union , [ { remote_type , 3309 , [ { atom , 3309 , pubsub_subscribe_options } , { atom , 3309 , result } , [ ] ] } , { type , 3310 , tuple , [ { atom , 3310 , error } , { type , 3310 , stanza_error , [ ] } ] } ] } ] } ] } ) .


decode_subscribe_options(undefined, _) -> [];
decode_subscribe_options(#xdata{fields = Fs}, Lang) ->
    try pubsub_subscribe_options:decode(Fs) catch
      _:{pubsub_subscribe_options, Why} ->
	  Txt = pubsub_subscribe_options:format_error(Why),
	  {error, xmpp:err_resource_constraint(Txt, Lang)}
    end.

- spec ( { { decode_publish_options , 2 } , [ { type , 3320 , 'fun' , [ { type , 3320 , product , [ { type , 3320 , union , [ { atom , 3320 , undefined } , { type , 3320 , xdata , [ ] } ] } , { type , 3320 , binary , [ ] } ] } , { type , 3321 , union , [ { remote_type , 3321 , [ { atom , 3321 , pubsub_publish_options } , { atom , 3321 , result } , [ ] ] } , { type , 3322 , tuple , [ { atom , 3322 , error } , { type , 3322 , stanza_error , [ ] } ] } ] } ] } ] } ) .


decode_publish_options(undefined, _) -> [];
decode_publish_options(#xdata{fields = Fs}, Lang) ->
    try pubsub_publish_options:decode(Fs) catch
      _:{pubsub_publish_options, Why} ->
	  Txt = pubsub_publish_options:format_error(Why),
	  {error, xmpp:err_resource_constraint(Txt, Lang)}
    end.

- spec ( { { decode_get_pending , 2 } , [ { type , 3332 , 'fun' , [ { type , 3332 , product , [ { type , 3332 , xdata , [ ] } , { type , 3332 , binary , [ ] } ] } , { type , 3333 , union , [ { remote_type , 3333 , [ { atom , 3333 , pubsub_get_pending } , { atom , 3333 , result } , [ ] ] } , { type , 3334 , tuple , [ { atom , 3334 , error } , { type , 3334 , stanza_error , [ ] } ] } ] } ] } ] } ) .


decode_get_pending(#xdata{fields = Fs}, Lang) ->
    try pubsub_get_pending:decode(Fs) catch
      _:{pubsub_get_pending, Why} ->
	  Txt = pubsub_get_pending:format_error(Why),
	  {error, xmpp:err_resource_constraint(Txt, Lang)}
    end;
decode_get_pending(undefined, Lang) ->
    {error,
     xmpp:err_bad_request(<<"No data form found">>, Lang)}.

- spec ( { { check_opt_range , 3 } , [ { type , 3344 , 'fun' , [ { type , 3344 , product , [ { type , 3344 , atom , [ ] } , { type , 3344 , list , [ { remote_type , 3344 , [ { atom , 3344 , proplists } , { atom , 3344 , property } , [ ] ] } ] } , { type , 3344 , non_neg_integer , [ ] } ] } , { type , 3344 , boolean , [ ] } ] } ] } ) .


check_opt_range(_Opt, _Opts, undefined) -> true;
check_opt_range(Opt, Opts, Max) ->
    Val = proplists:get_value(Opt, Opts, Max), Val =< Max.

- spec ( { { get_max_items_node , 1 } , [ { type , 3351 , 'fun' , [ { type , 3351 , product , [ { type , 3351 , host , [ ] } ] } , { type , 3351 , union , [ { atom , 3351 , undefined } , { type , 3351 , non_neg_integer , [ ] } ] } ] } ] } ) .


get_max_items_node(Host) ->
    config(Host, max_items_node, undefined).

- spec ( { { get_max_subscriptions_node , 1 } , [ { type , 3355 , 'fun' , [ { type , 3355 , product , [ { type , 3355 , host , [ ] } ] } , { type , 3355 , union , [ { atom , 3355 , undefined } , { type , 3355 , non_neg_integer , [ ] } ] } ] } ] } ) .


get_max_subscriptions_node(Host) ->
    config(Host, max_subscriptions_node, undefined).

%%%% last item cache handling
- spec ( { { is_last_item_cache_enabled , 1 } , [ { type , 3360 , 'fun' , [ { type , 3360 , product , [ { type , 3360 , host , [ ] } ] } , { type , 3360 , boolean , [ ] } ] } ] } ) .


is_last_item_cache_enabled(Host) ->
    config(Host, last_item_cache, false).

- spec ( { { set_cached_item , 5 } , [ { type , 3364 , 'fun' , [ { type , 3364 , product , [ { type , 3364 , host , [ ] } , { type , 3364 , nodeIdx , [ ] } , { type , 3364 , binary , [ ] } , { type , 3364 , binary , [ ] } , { type , 3364 , list , [ { type , 3364 , xmlel , [ ] } ] } ] } , { atom , 3364 , ok } ] } ] } ) .


set_cached_item({_, ServerHost, _}, Nidx, ItemId,
		Publisher, Payload) ->
    set_cached_item(ServerHost, Nidx, ItemId, Publisher,
		    Payload);
set_cached_item(Host, Nidx, ItemId, Publisher,
		Payload) ->
    case is_last_item_cache_enabled(Host) of
      true ->
	  Stamp = {p1_time_compat:timestamp(),
		   jid:tolower(jid:remove_resource(Publisher))},
	  Item = #pubsub_last_item{nodeid = {Host, Nidx},
				   itemid = ItemId, creation = Stamp,
				   payload = Payload},
	  mnesia:dirty_write(Item);
      _ -> ok
    end.

- spec ( { { unset_cached_item , 2 } , [ { type , 3380 , 'fun' , [ { type , 3380 , product , [ { type , 3380 , host , [ ] } , { type , 3380 , nodeIdx , [ ] } ] } , { atom , 3380 , ok } ] } ] } ) .


unset_cached_item({_, ServerHost, _}, Nidx) ->
    unset_cached_item(ServerHost, Nidx);
unset_cached_item(Host, Nidx) ->
    case is_last_item_cache_enabled(Host) of
      true ->
	  mnesia:dirty_delete({pubsub_last_item, {Host, Nidx}});
      _ -> ok
    end.

- spec ( { { get_cached_item , 2 } , [ { type , 3389 , 'fun' , [ { type , 3389 , product , [ { type , 3389 , host , [ ] } , { type , 3389 , nodeIdx , [ ] } ] } , { type , 3389 , union , [ { atom , 3389 , undefined } , { type , 3389 , pubsubItem , [ ] } ] } ] } ] } ) .


get_cached_item({_, ServerHost, _}, Nidx) ->
    get_cached_item(ServerHost, Nidx);
get_cached_item(Host, Nidx) ->
    case is_last_item_cache_enabled(Host) of
      true ->
	  case mnesia:dirty_read({pubsub_last_item, {Host, Nidx}})
	      of
	    [#pubsub_last_item{itemid = ItemId, creation = Creation,
			       payload = Payload}] ->
		#pubsub_item{itemid = {ItemId, Nidx}, payload = Payload,
			     creation = Creation, modification = Creation};
	    _ -> undefined
	  end;
      _ -> undefined
    end.

%%%% plugin handling
- spec ( { { host , 1 } , [ { type , 3408 , 'fun' , [ { type , 3408 , product , [ { type , 3408 , binary , [ ] } ] } , { type , 3408 , binary , [ ] } ] } ] } ) .


host(ServerHost) ->
    config(ServerHost, host,
	   <<"pubsub.", ServerHost/binary>>).

- spec ( { { serverhost , 1 } , [ { type , 3412 , 'fun' , [ { type , 3412 , product , [ { type , 3412 , host , [ ] } ] } , { type , 3412 , binary , [ ] } ] } ] } ) .


serverhost({_U, ServerHost, _R}) ->
    serverhost(ServerHost);
serverhost(Host) -> ejabberd_router:host_of_route(Host).

- spec ( { { tree , 1 } , [ { type , 3418 , 'fun' , [ { type , 3418 , product , [ { type , 3418 , host , [ ] } ] } , { type , 3418 , atom , [ ] } ] } ] } ) .


tree(Host) ->
    case config(Host, nodetree) of
      undefined -> tree(Host, ?STDTREE);
      Tree -> Tree
    end.

- spec ( { { tree , 2 } , [ { type , 3425 , 'fun' , [ { type , 3425 , product , [ { type , 3425 , host , [ ] } , { type , 3425 , binary , [ ] } ] } , { type , 3425 , atom , [ ] } ] } ] } ) .


tree(_Host, <<"virtual">>) ->
    nodetree_virtual;   % special case, virtual does not use any backend
tree(Host, Name) ->
    submodule(Host, <<"nodetree">>, Name).

- spec ( { { plugin , 2 } , [ { type , 3431 , 'fun' , [ { type , 3431 , product , [ { type , 3431 , host , [ ] } , { type , 3431 , binary , [ ] } ] } , { type , 3431 , atom , [ ] } ] } ] } ) .


plugin(Host, Name) -> submodule(Host, <<"node">>, Name).

- spec ( { { plugins , 1 } , [ { type , 3435 , 'fun' , [ { type , 3435 , product , [ { type , 3435 , host , [ ] } ] } , { type , 3435 , list , [ { type , 3435 , binary , [ ] } ] } ] } ] } ) .


plugins(Host) ->
    case config(Host, plugins) of
      undefined -> [?STDNODE];
      [] -> [?STDNODE];
      Plugins -> Plugins
    end.

- spec ( { { subscription_plugin , 1 } , [ { type , 3443 , 'fun' , [ { type , 3443 , product , [ { type , 3443 , host , [ ] } ] } , { type , 3443 , atom , [ ] } ] } ] } ) .


subscription_plugin(Host) ->
    submodule(Host, <<"pubsub">>, <<"subscription">>).

- spec ( { { submodule , 3 } , [ { type , 3447 , 'fun' , [ { type , 3447 , product , [ { type , 3447 , host , [ ] } , { type , 3447 , binary , [ ] } , { type , 3447 , binary , [ ] } ] } , { type , 3447 , atom , [ ] } ] } ] } ) .


submodule(Host, Type, Name) ->
    case gen_mod:get_module_opt(serverhost(Host), ?MODULE,
				db_type)
	of
      mnesia ->
	  ejabberd:module_name([<<"pubsub">>, Type, Name]);
      Db ->
	  ejabberd:module_name([<<"pubsub">>, Type, Name,
				misc:atom_to_binary(Db)])
    end.

- spec ( { { config , 2 } , [ { type , 3454 , 'fun' , [ { type , 3454 , product , [ { type , 3454 , binary , [ ] } , { type , 3454 , any , [ ] } ] } , { type , 3454 , any , [ ] } ] } ] } ) .


config(ServerHost, Key) ->
    config(ServerHost, Key, undefined).

- spec ( { { config , 3 } , [ { type , 3458 , 'fun' , [ { type , 3458 , product , [ { type , 3458 , host , [ ] } , { type , 3458 , any , [ ] } , { type , 3458 , any , [ ] } ] } , { type , 3458 , any , [ ] } ] } ] } ) .


config({_User, Host, _Resource}, Key, Default) ->
    config(Host, Key, Default);
config(ServerHost, Key, Default) ->
    case catch
	   ets:lookup(gen_mod:get_module_proc(ServerHost, config),
		      Key)
	of
      [{Key, Value}] -> Value;
      _ -> Default
    end.

- spec ( { { select_type , 4 } , [ { type , 3467 , 'fun' , [ { type , 3467 , product , [ { type , 3467 , binary , [ ] } , { type , 3467 , host , [ ] } , { type , 3467 , binary , [ ] } , { type , 3467 , binary , [ ] } ] } , { type , 3467 , binary , [ ] } ] } ] } ) .


select_type(ServerHost, {_User, _Server, _Resource},
	    Node, _Type) ->
    case config(ServerHost, pep_mapping) of
      undefined -> ?PEPNODE;
      Mapping -> proplists:get_value(Node, Mapping, ?PEPNODE)
    end;
select_type(ServerHost, _Host, _Node, Type) ->
    case config(ServerHost, plugins) of
      undefined -> Type;
      Plugins ->
	  case lists:member(Type, Plugins) of
	    true -> Type;
	    false -> hd(Plugins)
	  end
    end.

- spec ( { { select_type , 3 } , [ { type , 3484 , 'fun' , [ { type , 3484 , product , [ { type , 3484 , binary , [ ] } , { type , 3484 , host , [ ] } , { type , 3484 , binary , [ ] } ] } , { type , 3484 , binary , [ ] } ] } ] } ) .


select_type(ServerHost, Host, Node) ->
    select_type(ServerHost, Host, Node, hd(plugins(Host))).

- spec ( { { feature , 1 } , [ { type , 3488 , 'fun' , [ { type , 3488 , product , [ { type , 3488 , binary , [ ] } ] } , { type , 3488 , binary , [ ] } ] } ] } ) .


feature(<<"rsm">>) -> ?NS_RSM;
feature(Feature) ->
    <<(?NS_PUBSUB)/binary, "#", Feature/binary>>.

- spec ( { { features , 0 } , [ { type , 3492 , 'fun' , [ { type , 3492 , product , [ ] } , { type , 3492 , list , [ { type , 3492 , binary , [ ] } ] } ] } ] } ) .


features() ->
    [% see plugin "access-authorize",   % OPTIONAL
     <<"access-open">>,   % OPTIONAL this relates to access_model option in node_hometree
     <<"access-presence">>,   % OPTIONAL this relates to access_model option in node_pep
     <<"access-whitelist">>,   % OPTIONAL
     <<"collections">>,   % RECOMMENDED
     <<"config-node">>,   % RECOMMENDED
     <<"create-and-configure">>,   % RECOMMENDED
     <<"item-ids">>,   % RECOMMENDED
     <<"last-published">>,   % RECOMMENDED
     <<"member-affiliation">>,   % RECOMMENDED
     <<"presence-notifications">>,   % OPTIONAL
     <<"presence-subscribe">>,   % RECOMMENDED
     <<"publisher-affiliation">>,   % RECOMMENDED
     <<"publish-only-affiliation">>,   % OPTIONAL
     <<"publish-options">>,   % OPTIONAL
     <<"retrieve-default">>,
     <<"shim">>].   % RECOMMENDED

% see plugin "retrieve-items",   % RECOMMENDED
% see plugin "retrieve-subscriptions",   % RECOMMENDED
% see plugin "subscribe",   % REQUIRED
% see plugin "subscription-options",   % OPTIONAL
% see plugin "subscription-notifications"   % OPTIONAL
- spec ( { { plugin_features , 2 } , [ { type , 3517 , 'fun' , [ { type , 3517 , product , [ { type , 3517 , binary , [ ] } , { type , 3517 , binary , [ ] } ] } , { type , 3517 , list , [ { type , 3517 , binary , [ ] } ] } ] } ] } ) .


plugin_features(Host, Type) ->
    Module = plugin(Host, Type),
    case catch Module:features() of
      {'EXIT', {undef, _}} -> [];
      Result -> Result
    end.

- spec ( { { features , 2 } , [ { type , 3525 , 'fun' , [ { type , 3525 , product , [ { type , 3525 , binary , [ ] } , { type , 3525 , binary , [ ] } ] } , { type , 3525 , list , [ { type , 3525 , binary , [ ] } ] } ] } ] } ) .


features(Host, <<>>) ->
    lists:usort(lists:foldl(fun (Plugin, Acc) ->
				    Acc ++ plugin_features(Host, Plugin)
			    end,
			    features(), plugins(Host)));
features(Host, Node) when is_binary(Node) ->
    Action = fun (#pubsub_node{type = Type}) ->
		     {result, plugin_features(Host, Type)}
	     end,
    case transaction(Host, Node, Action, sync_dirty) of
      {result, Features} ->
	  lists:usort(features() ++ Features);
      _ -> features()
    end.

%% @doc <p>node tree plugin call.</p>
tree_call({_User, Server, _Resource}, Function, Args) ->
    tree_call(Server, Function, Args);
tree_call(Host, Function, Args) ->
    Tree = tree(Host),
    ?DEBUG("tree_call apply(~s, ~s, ~p) @ ~s",
	   [Tree, Function, Args, Host]),
    apply(Tree, Function, Args).

tree_action(Host, Function, Args) ->
    ?DEBUG("tree_action ~p ~p ~p", [Host, Function, Args]),
    ServerHost = serverhost(Host),
    Fun = fun () -> tree_call(Host, Function, Args) end,
    case gen_mod:get_module_opt(ServerHost, ?MODULE,
				db_type)
	of
      mnesia -> mnesia:sync_dirty(Fun);
      sql ->
	  case ejabberd_sql:sql_bloc(ServerHost, Fun) of
	    {atomic, Result} -> Result;
	    {aborted, Reason} ->
		?ERROR_MSG("transaction return internal error: ~p~n",
			   [{aborted, Reason}]),
		ErrTxt = <<"Database failure">>,
		{error,
		 xmpp:err_internal_server_error(ErrTxt,
						ejabberd_config:get_mylang())}
	  end;
      _ -> Fun()
    end.

%% @doc <p>node plugin call.</p>
node_call(Host, Type, Function, Args) ->
    ?DEBUG("node_call ~p ~p ~p", [Type, Function, Args]),
    Module = plugin(Host, Type),
    case apply(Module, Function, Args) of
      {result, Result} -> {result, Result};
      {error, Error} -> {error, Error};
      {'EXIT', {undef, Undefined}} ->
	  case Type of
	    ?STDNODE -> {error, {undef, Undefined}};
	    _ -> node_call(Host, ?STDNODE, Function, Args)
	  end;
      {'EXIT', Reason} -> {error, Reason};
      Result ->
	  {result,
	   Result} %% any other return value is forced as result
    end.

node_action(Host, Type, Function, Args) ->
    ?DEBUG("node_action ~p ~p ~p ~p",
	   [Host, Type, Function, Args]),
    transaction(Host,
		fun () -> node_call(Host, Type, Function, Args) end,
		sync_dirty).

%% @doc <p>plugin transaction handling.</p>
transaction(Host, Node, Action, Trans) ->
    transaction(Host,
		fun () ->
			case tree_call(Host, get_node, [Host, Node]) of
			  N when is_record(N, pubsub_node) ->
			      case Action(N) of
				{result, Result} -> {result, {N, Result}};
				{atomic, {result, Result}} ->
				    {result, {N, Result}};
				Other -> Other
			      end;
			  Error -> Error
			end
		end,
		Trans).

transaction(Host, Fun, Trans) ->
    ServerHost = serverhost(Host),
    DBType = gen_mod:get_module_opt(ServerHost, ?MODULE,
				    db_type),
    do_transaction(ServerHost, Fun, Trans, DBType).

do_transaction(ServerHost, Fun, Trans, DBType) ->
    Res = case DBType of
	    mnesia -> mnesia:Trans(Fun);
	    sql ->
		SqlFun = case Trans of
			   transaction -> sql_transaction;
			   _ -> sql_bloc
			 end,
		ejabberd_sql:SqlFun(ServerHost, Fun);
	    _ -> Fun()
	  end,
    case Res of
      {result, Result} -> {result, Result};
      {error, Error} -> {error, Error};
      {atomic, {result, Result}} -> {result, Result};
      {atomic, {error, Error}} -> {error, Error};
      {aborted, Reason} ->
	  ?ERROR_MSG("transaction return internal error: ~p~n",
		     [{aborted, Reason}]),
	  {error,
	   xmpp:err_internal_server_error(<<"Database failure">>,
					  ejabberd_config:get_mylang())};
      Other ->
	  ?ERROR_MSG("transaction return internal error: ~p~n",
		     [Other]),
	  {error,
	   xmpp:err_internal_server_error(<<"Database failure">>,
					  ejabberd_config:get_mylang())}
    end.

%%%% helpers

%% Add pubsub-specific error element
- spec ( { { extended_error , 2 } , [ { type , 3649 , 'fun' , [ { type , 3649 , product , [ { type , 3649 , stanza_error , [ ] } , { type , 3649 , ps_error , [ ] } ] } , { type , 3649 , stanza_error , [ ] } ] } ] } ) .


extended_error(StanzaErr, PubSubErr) ->
    StanzaErr#stanza_error{sub_els = [PubSubErr]}.

- spec ( { { err_closed_node , 0 } , [ { type , 3653 , 'fun' , [ { type , 3653 , product , [ ] } , { type , 3653 , ps_error , [ ] } ] } ] } ) .


err_closed_node() -> #ps_error{type = 'closed-node'}.

- spec ( { { err_configuration_required , 0 } , [ { type , 3657 , 'fun' , [ { type , 3657 , product , [ ] } , { type , 3657 , ps_error , [ ] } ] } ] } ) .


err_configuration_required() ->
    #ps_error{type = 'configuration-required'}.

- spec ( { { err_invalid_jid , 0 } , [ { type , 3661 , 'fun' , [ { type , 3661 , product , [ ] } , { type , 3661 , ps_error , [ ] } ] } ] } ) .


err_invalid_jid() -> #ps_error{type = 'invalid-jid'}.

- spec ( { { err_invalid_options , 0 } , [ { type , 3665 , 'fun' , [ { type , 3665 , product , [ ] } , { type , 3665 , ps_error , [ ] } ] } ] } ) .


err_invalid_options() ->
    #ps_error{type = 'invalid-options'}.

- spec ( { { err_invalid_payload , 0 } , [ { type , 3669 , 'fun' , [ { type , 3669 , product , [ ] } , { type , 3669 , ps_error , [ ] } ] } ] } ) .


err_invalid_payload() ->
    #ps_error{type = 'invalid-payload'}.

- spec ( { { err_invalid_subid , 0 } , [ { type , 3673 , 'fun' , [ { type , 3673 , product , [ ] } , { type , 3673 , ps_error , [ ] } ] } ] } ) .


err_invalid_subid() ->
    #ps_error{type = 'invalid-subid'}.

- spec ( { { err_item_forbidden , 0 } , [ { type , 3677 , 'fun' , [ { type , 3677 , product , [ ] } , { type , 3677 , ps_error , [ ] } ] } ] } ) .


err_item_forbidden() ->
    #ps_error{type = 'item-forbidden'}.

- spec ( { { err_item_required , 0 } , [ { type , 3681 , 'fun' , [ { type , 3681 , product , [ ] } , { type , 3681 , ps_error , [ ] } ] } ] } ) .


err_item_required() ->
    #ps_error{type = 'item-required'}.

- spec ( { { err_jid_required , 0 } , [ { type , 3685 , 'fun' , [ { type , 3685 , product , [ ] } , { type , 3685 , ps_error , [ ] } ] } ] } ) .


err_jid_required() -> #ps_error{type = 'jid-required'}.

- spec ( { { err_max_items_exceeded , 0 } , [ { type , 3689 , 'fun' , [ { type , 3689 , product , [ ] } , { type , 3689 , ps_error , [ ] } ] } ] } ) .


err_max_items_exceeded() ->
    #ps_error{type = 'max-items-exceeded'}.

- spec ( { { err_max_nodes_exceeded , 0 } , [ { type , 3693 , 'fun' , [ { type , 3693 , product , [ ] } , { type , 3693 , ps_error , [ ] } ] } ] } ) .


err_max_nodes_exceeded() ->
    #ps_error{type = 'max-nodes-exceeded'}.

- spec ( { { err_nodeid_required , 0 } , [ { type , 3697 , 'fun' , [ { type , 3697 , product , [ ] } , { type , 3697 , ps_error , [ ] } ] } ] } ) .


err_nodeid_required() ->
    #ps_error{type = 'nodeid-required'}.

- spec ( { { err_not_in_roster_group , 0 } , [ { type , 3701 , 'fun' , [ { type , 3701 , product , [ ] } , { type , 3701 , ps_error , [ ] } ] } ] } ) .


err_not_in_roster_group() ->
    #ps_error{type = 'not-in-roster-group'}.

- spec ( { { err_not_subscribed , 0 } , [ { type , 3705 , 'fun' , [ { type , 3705 , product , [ ] } , { type , 3705 , ps_error , [ ] } ] } ] } ) .


err_not_subscribed() ->
    #ps_error{type = 'not-subscribed'}.

- spec ( { { err_payload_too_big , 0 } , [ { type , 3709 , 'fun' , [ { type , 3709 , product , [ ] } , { type , 3709 , ps_error , [ ] } ] } ] } ) .


err_payload_too_big() ->
    #ps_error{type = 'payload-too-big'}.

- spec ( { { err_payload_required , 0 } , [ { type , 3713 , 'fun' , [ { type , 3713 , product , [ ] } , { type , 3713 , ps_error , [ ] } ] } ] } ) .


err_payload_required() ->
    #ps_error{type = 'payload-required'}.

- spec ( { { err_pending_subscription , 0 } , [ { type , 3717 , 'fun' , [ { type , 3717 , product , [ ] } , { type , 3717 , ps_error , [ ] } ] } ] } ) .


err_pending_subscription() ->
    #ps_error{type = 'pending-subscription'}.

- spec ( { { err_precondition_not_met , 0 } , [ { type , 3721 , 'fun' , [ { type , 3721 , product , [ ] } , { type , 3721 , ps_error , [ ] } ] } ] } ) .


err_precondition_not_met() ->
    #ps_error{type = 'precondition-not-met'}.

- spec ( { { err_presence_subscription_required , 0 } , [ { type , 3725 , 'fun' , [ { type , 3725 , product , [ ] } , { type , 3725 , ps_error , [ ] } ] } ] } ) .


err_presence_subscription_required() ->
    #ps_error{type = 'presence-subscription-required'}.

- spec ( { { err_subid_required , 0 } , [ { type , 3729 , 'fun' , [ { type , 3729 , product , [ ] } , { type , 3729 , ps_error , [ ] } ] } ] } ) .


err_subid_required() ->
    #ps_error{type = 'subid-required'}.

- spec ( { { err_too_many_subscriptions , 0 } , [ { type , 3733 , 'fun' , [ { type , 3733 , product , [ ] } , { type , 3733 , ps_error , [ ] } ] } ] } ) .


err_too_many_subscriptions() ->
    #ps_error{type = 'too-many-subscriptions'}.

- spec ( { { err_unsupported , 1 } , [ { type , 3737 , 'fun' , [ { type , 3737 , product , [ { type , 3737 , ps_feature , [ ] } ] } , { type , 3737 , ps_error , [ ] } ] } ] } ) .


err_unsupported(Feature) ->
    #ps_error{type = unsupported, feature = Feature}.

- spec ( { { err_unsupported_access_model , 0 } , [ { type , 3741 , 'fun' , [ { type , 3741 , product , [ ] } , { type , 3741 , ps_error , [ ] } ] } ] } ) .


err_unsupported_access_model() ->
    #ps_error{type = 'unsupported-access-model'}.

- spec ( { { uniqid , 0 } , [ { type , 3745 , 'fun' , [ { type , 3745 , product , [ ] } , { remote_type , 3745 , [ { atom , 3745 , mod_pubsub } , { atom , 3745 , itemId } , [ ] ] } ] } ] } ) .


uniqid() ->
    {T1, T2, T3} = p1_time_compat:timestamp(),
    str:format("~.16B~.16B~.16B", [T1, T2, T3]).

- spec ( { { add_message_type , 2 } , [ { type , 3750 , 'fun' , [ { type , 3750 , product , [ { type , 3750 , message , [ ] } , { type , 3750 , message_type , [ ] } ] } , { type , 3750 , message , [ ] } ] } ] } ) .


add_message_type(#message{} = Message, Type) ->
    Message#message{type = Type}.

%% Place of <headers/> changed at the bottom of the stanza
%% cf. http://xmpp.org/extensions/xep-0060.html#publisher-publish-success-subid
%%
%% "[SHIM Headers] SHOULD be included after the event notification information
%% (i.e., as the last child of the <message/> stanza)".

- spec ( { { add_shim_headers , 2 } , [ { type , 3760 , 'fun' , [ { type , 3760 , product , [ { type , 3760 , stanza , [ ] } , { type , 3760 , list , [ { type , 3760 , tuple , [ { type , 3760 , binary , [ ] } , { type , 3760 , binary , [ ] } ] } ] } ] } , { type , 3760 , stanza , [ ] } ] } ] } ) .


add_shim_headers(Stanza, Headers) ->
    xmpp:set_subtag(Stanza, #shim{headers = Headers}).

- spec ( { { add_extended_headers , 2 } , [ { type , 3764 , 'fun' , [ { type , 3764 , product , [ { type , 3764 , stanza , [ ] } , { type , 3764 , list , [ { type , 3764 , address , [ ] } ] } ] } , { type , 3764 , stanza , [ ] } ] } ] } ) .


add_extended_headers(Stanza, Addrs) ->
    xmpp:set_subtag(Stanza, #addresses{list = Addrs}).

- spec ( { { subid_shim , 1 } , [ { type , 3768 , 'fun' , [ { type , 3768 , product , [ { type , 3768 , list , [ { type , 3768 , binary , [ ] } ] } ] } , { type , 3768 , list , [ { type , 3768 , tuple , [ { type , 3768 , binary , [ ] } , { type , 3768 , binary , [ ] } ] } ] } ] } ] } ) .


subid_shim(SubIds) ->
    [{<<"SubId">>, SubId} || SubId <- SubIds].

%% The argument is a list of Jids because this function could be used
%% with the 'pubsub#replyto' (type=jid-multi) node configuration.

- spec ( { { extended_headers , 1 } , [ { type , 3775 , 'fun' , [ { type , 3775 , product , [ { type , 3775 , list , [ { type , 3775 , jid , [ ] } ] } ] } , { type , 3775 , list , [ { type , 3775 , address , [ ] } ] } ] } ] } ) .


extended_headers(Jids) ->
    [#address{type = replyto, jid = Jid} || Jid <- Jids].

- spec ( { { purge_offline , 1 } , [ { type , 3779 , 'fun' , [ { type , 3779 , product , [ { type , 3779 , ljid , [ ] } ] } , { atom , 3779 , ok } ] } ] } ) .


purge_offline(LJID) ->
    Host = host(element(2, LJID)),
    Plugins = plugins(Host),
    Result = lists:foldl(fun (Type, {Status, Acc}) ->
				 Features = plugin_features(Host, Type),
				 case lists:member(<<"retrieve-affiliations">>,
						   plugin_features(Host, Type))
				     of
				   false ->
				       {{error,
					 extended_error(xmpp:err_feature_not_implemented(),
							err_unsupported('retrieve-affiliations'))},
					Acc};
				   true ->
				       Items = lists:member(<<"retract-items">>,
							    Features)
						 andalso
						 lists:member(<<"persistent-items">>,
							      Features),
				       if Items ->
					      {result, Affs} = node_action(Host,
									   Type,
									   get_entity_affiliations,
									   [Host,
									    LJID]),
					      {Status, [Affs | Acc]};
					  true -> {Status, Acc}
				       end
				 end
			 end,
			 {ok, []}, Plugins),
    case Result of
      {ok, Affs} ->
	  lists:foreach(fun ({Node, Affiliation}) ->
				Options = Node#pubsub_node.options,
				Publisher = lists:member(Affiliation,
							 [owner, publisher,
							  publish_only]),
				Open = get_option(Options, publish_model) ==
					 open,
				Purge = get_option(Options, purge_offline)
					  andalso
					  get_option(Options, persist_items),
				if (Publisher or Open) and Purge ->
				       purge_offline(Host, LJID, Node);
				   true -> ok
				end
			end,
			lists:usort(lists:flatten(Affs)));
      {Error, _} ->
	  ?ERROR_MSG("can not purge offline: ~p", [Error])
    end.

- spec ( { { purge_offline , 3 } , [ { type , 3822 , 'fun' , [ { type , 3822 , product , [ { type , 3822 , host , [ ] } , { type , 3822 , ljid , [ ] } , { type , 3822 , binary , [ ] } ] } , { type , 3822 , union , [ { atom , 3822 , ok } , { type , 3822 , tuple , [ { atom , 3822 , error } , { type , 3822 , stanza_error , [ ] } ] } ] } ] } ] } ) .


purge_offline(Host, LJID, Node) ->
    Nidx = Node#pubsub_node.id,
    Type = Node#pubsub_node.type,
    Options = Node#pubsub_node.options,
    case node_action(Host, Type, get_items,
		     [Nidx, service_jid(Host), undefined])
	of
      {result, {[], _}} -> ok;
      {result, {Items, _}} ->
	  {User, Server, Resource} = LJID,
	  PublishModel = get_option(Options, publish_model),
	  ForceNotify = get_option(Options, notify_retract),
	  {_, NodeId} = Node#pubsub_node.nodeid,
	  lists:foreach(fun (#pubsub_item{itemid = {ItemId, _},
					  modification = {_, {U, S, R}}})
				when (U == User) and (S == Server) and
				       (R == Resource) ->
				case node_action(Host, Type, delete_item,
						 [Nidx, {U, S, <<>>},
						  PublishModel, ItemId])
				    of
				  {result, {_, broadcast}} ->
				      broadcast_retract_items(Host, NodeId,
							      Nidx, Type,
							      Options, [ItemId],
							      ForceNotify),
				      case get_cached_item(Host, Nidx) of
					#pubsub_item{itemid = {ItemId, Nidx}} ->
					    unset_cached_item(Host, Nidx);
					_ -> ok
				      end;
				  {result, _} -> ok;
				  Error -> Error
				end;
			    (_) -> true
			end,
			Items);
      Error -> Error
    end.

mod_opt_type(access_createnode) ->
    fun acl:access_rules_validator/1;
mod_opt_type(db_type) ->
    fun (T) -> ejabberd_config:v_db(?MODULE, T) end;
mod_opt_type(name) -> fun iolist_to_binary/1;
mod_opt_type(host) -> fun ejabberd_config:v_host/1;
mod_opt_type(hosts) -> fun ejabberd_config:v_hosts/1;
mod_opt_type(ignore_pep_from_offline) ->
    fun (A) when is_boolean(A) -> A end;
mod_opt_type(last_item_cache) ->
    fun (A) when is_boolean(A) -> A end;
mod_opt_type(max_items_node) ->
    fun (A) when is_integer(A) andalso A >= 0 -> A end;
mod_opt_type(max_subscriptions_node) ->
    fun (A) when is_integer(A) andalso A >= 0 -> A;
	(undefined) -> undefined
    end;
mod_opt_type(force_node_config) ->
    fun (NodeOpts) -> [mod_opt_type_1(V1) || V1 <- NodeOpts]
    end;
mod_opt_type(default_node_config) ->
    fun (A) when is_list(A) -> A end;
mod_opt_type(nodetree) ->
    fun (A) when is_binary(A) -> A end;
mod_opt_type(pep_mapping) ->
    fun (A) when is_list(A) -> A end;
mod_opt_type(plugins) ->
    fun (A) when is_list(A) -> A end.

mod_opt_type_1({Node, Opts}) ->
    {ok, RE} = re:compile(ejabberd_regexp:sh_to_awk(Node)),
    {RE, lists:keysort(1, Opts)}.

mod_options(Host) ->
    [{access_createnode, all},
     {db_type, ejabberd_config:default_db(Host, ?MODULE)},
     {host, <<"pubsub.@HOST@">>}, {hosts, []},
     {name, ?T("Publish-Subscribe")},
     {ignore_pep_from_offline, true},
     {last_item_cache, false}, {max_items_node, ?MAXITEMS},
     {nodetree, ?STDTREE}, {pep_mapping, []},
     {plugins, [?STDNODE]},
     {max_subscriptions_node, undefined},
     {default_node_config, []}, {force_node_config, []}].

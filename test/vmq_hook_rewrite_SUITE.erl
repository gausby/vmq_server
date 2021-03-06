-module(vmq_hook_rewrite_SUITE).
-export([
         %% suite/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2,
         all/0
        ]).

-export([auth_on_publish_rewrite_payload_test/1
         , auth_on_publish_rewrite_packet_test/1
         , auth_on_subscribe_rewrite_test/1
         , on_deliver_rewrite_payload_test/1
         , on_deliver_rewrite_packet_test/1
        ]).


-export([hook_auth_on_subscribe/3,
         hook_auth_on_publish/6,
         hook_on_deliver/4]).

%% ===================================================================
%% common_test callbacks
%% ===================================================================
init_per_suite(_Config) ->
    cover:start(),
    _Config.

end_per_suite(_Config) ->
    _Config.

init_per_testcase(_Case, Config) ->
    vmq_test_utils:setup(),
    vmq_server_cmd:set_config(allow_anonymous, true),
    vmq_server_cmd:set_config(retry_interval, 10),
    vmq_server_cmd:listener_start(1888, []),
    Config.

end_per_testcase(_, Config) ->
    vmq_test_utils:teardown(),
    Config.

all() ->
    [auth_on_publish_rewrite_payload_test
     , auth_on_publish_rewrite_packet_test
     , auth_on_subscribe_rewrite_test
     , on_deliver_rewrite_payload_test
     , on_deliver_rewrite_packet_test
     ].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Actual Tests
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
auth_on_publish_rewrite_payload_test(_) ->
    Connect = packet:gen_connect("pub-rewrite-test", [{keepalive, 60}]),
    Connack = packet:gen_connack(0),
    Publish = packet:gen_publish("pub/rewrite/payload", 1, <<"message">>,
                                 [{mid, 19}]),
    Puback = packet:gen_puback(19),
    Subscribe = packet:gen_subscribe(3265, "pub/rewrite/payload", 0),
    Suback = packet:gen_suback(3265, 0),

    enable_on_subscribe(),
    enable_on_publish(),

    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = gen_tcp:send(Socket, Subscribe),
    ok = packet:expect_packet(Socket, "suback", Suback),
    %% publish
    ok = gen_tcp:send(Socket, Publish),
    ok = packet:expect_packet(Socket, "puback", Puback),

    %% receive publish with rewritten payload
    PublishRewritten = packet:gen_publish("pub/rewrite/payload", 0, <<"hello world">>, [{mid, 1}]),
    ok = packet:expect_packet(Socket, "publish", PublishRewritten),


    disable_on_publish(),
    disable_on_subscribe(),
    ok = gen_tcp:close(Socket).

auth_on_publish_rewrite_packet_test(_) ->
    Connect = packet:gen_connect("pub-rewrite-test", [{keepalive, 60}]),
    Connack = packet:gen_connack(0),
    Publish = packet:gen_publish("pub/rewrite/packet", 1, <<"message">>,
                                 [{mid, 19}]),
    Puback = packet:gen_puback(19),
    Subscribe = packet:gen_subscribe(3265, "pub/rewrite/topic", 0),
    Suback = packet:gen_suback(3265, 0),

    enable_on_subscribe(),
    enable_on_publish(),

    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = gen_tcp:send(Socket, Subscribe),
    ok = packet:expect_packet(Socket, "suback", Suback),
    %% publish
    ok = gen_tcp:send(Socket, Publish),
    ok = packet:expect_packet(Socket, "puback", Puback),

    %% receive publish with rewritten payload and rewritten topic
    PublishRewritten = packet:gen_publish("pub/rewrite/topic", 0, <<"hello world">>, [{mid, 1}]),
    ok = packet:expect_packet(Socket, "publish", PublishRewritten),

    disable_on_publish(),
    disable_on_subscribe(),
    ok = gen_tcp:close(Socket).

auth_on_subscribe_rewrite_test(_) ->
    Connect = packet:gen_connect("sub-rewrite-test", [{keepalive, 60}]),
    Connack = packet:gen_connack(0),
    Publish = packet:gen_publish("sub/rewrite/topic", 1, <<"message">>, [{mid, 123}]),
    Puback = packet:gen_puback(123),
    % subscribes for sub/rewrite/me with QoS 1
    % but we'll deliver sub/rewrite/topic with QoS 0
    Subscribe = packet:gen_subscribe(3265, "sub/rewrite/me", 1),
    Suback = packet:gen_suback(3265, [0]),

    enable_on_subscribe(),
    enable_on_publish(),

    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = gen_tcp:send(Socket, Subscribe),
    ok = packet:expect_packet(Socket, "suback", Suback),
    %% publish
    timer:sleep(100),
    ok = gen_tcp:send(Socket, Publish),
    ok = packet:expect_packet(Socket, "puback", Puback),

    %% receive publish
    Publish1 = packet:gen_publish("sub/rewrite/topic", 0, <<"message">>, []),
    ok = packet:expect_packet(Socket, "publish", Publish1),

    disable_on_publish(),
    disable_on_subscribe(),
    ok = gen_tcp:close(Socket).


on_deliver_rewrite_payload_test(_) ->
    Connect = packet:gen_connect("dlvr-rewrite-test", [{keepalive, 60}]),
    Connack = packet:gen_connack(0),
    Publish = packet:gen_publish("dlvr/rewrite/payload", 1, <<"message">>, [{mid, 123}]),
    Puback = packet:gen_puback(123),
    Subscribe = packet:gen_subscribe(3265, "dlvr/rewrite/payload", 0),
    Suback = packet:gen_suback(3265, 0),

    enable_on_subscribe(),
    enable_on_deliver(),
    enable_on_publish(),

    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = gen_tcp:send(Socket, Subscribe),
    ok = packet:expect_packet(Socket, "suback", Suback),
    %% publish
    timer:sleep(100),
    ok = gen_tcp:send(Socket, Publish),
    ok = packet:expect_packet(Socket, "puback", Puback),

    %% receive publish
    Publish1 = packet:gen_publish("dlvr/rewrite/payload", 0, <<"hello world">>, []),
    ok = packet:expect_packet(Socket, "publish", Publish1),

    disable_on_publish(),
    disable_on_deliver(),
    disable_on_subscribe(),
    ok = gen_tcp:close(Socket).

on_deliver_rewrite_packet_test(_) ->
    Connect = packet:gen_connect("dlvr-rewrite-test", [{keepalive, 60}]),
    Connack = packet:gen_connack(0),
    Publish = packet:gen_publish("dlvr/rewrite/me", 1, <<"message">>, [{mid, 123}]),
    Puback = packet:gen_puback(123),
    Subscribe = packet:gen_subscribe(3265, "dlvr/rewrite/me", 0),
    Suback = packet:gen_suback(3265, 0),

    enable_on_subscribe(),
    enable_on_deliver(),
    enable_on_publish(),

    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = gen_tcp:send(Socket, Subscribe),
    ok = packet:expect_packet(Socket, "suback", Suback),
    %% publish
    timer:sleep(100),
    ok = gen_tcp:send(Socket, Publish),
    ok = packet:expect_packet(Socket, "puback", Puback),

    %% receive publish
    Publish1 = packet:gen_publish("dlvr/rewrite/payload", 0, <<"hello world">>, []),
    ok = packet:expect_packet(Socket, "publish", Publish1),

    disable_on_publish(),
    disable_on_deliver(),
    disable_on_subscribe(),
    ok = gen_tcp:close(Socket).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Hooks (as explicit as possible)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
hook_auth_on_subscribe(_, {"", <<"sub-rewrite-test">>}, [{[<<"sub">>, <<"rewrite">>, <<"me">>], 1}]) ->
    %% REWRITE SUBSCRIPTION .. different topic, different qos
    {ok, [{[<<"sub">>, <<"rewrite">>, <<"topic">>], 0}]};
hook_auth_on_subscribe(_, _, _) -> ok.

hook_auth_on_publish(_, {"", <<"pub-rewrite-test">>}, _MsgId, [<<"pub">>, <<"rewrite">>, <<"payload">>],
                     <<"message">>, false) ->
    %% REWRITE PAYLOAD
    {ok, <<"hello world">>};

hook_auth_on_publish(_, {"", <<"pub-rewrite-test">>}, _MsgId, [<<"pub">>, <<"rewrite">>, <<"packet">>],
                     <<"message">>, false) ->
    %% REWRITE PAYLOAD
    {ok, [{payload, <<"hello world">>}, {topic, [<<"pub">>, <<"rewrite">>, <<"topic">>]}]};

hook_auth_on_publish(_, _, _MsgId, _, _, _) ->
    ok.

hook_on_deliver(_User, {"", <<"dlvr-rewrite-test">>}, [<<"dlvr">>, <<"rewrite">>, <<"payload">>],
                <<"message">>) ->
    {ok, <<"hello world">>};
hook_on_deliver(_User, {"", <<"dlvr-rewrite-test">>}, [<<"dlvr">>, <<"rewrite">>, <<"me">>],
                <<"message">>) ->
    {ok, [{topic, [<<"dlvr">>, <<"rewrite">>, <<"payload">>]},
          {payload, <<"hello world">>}]};
hook_on_deliver(_, _, _, _) -> ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Helper
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
enable_on_subscribe() ->
    vmq_plugin_mgr:enable_module_plugin(
      auth_on_subscribe, ?MODULE, hook_auth_on_subscribe, 3).
enable_on_publish() ->
    vmq_plugin_mgr:enable_module_plugin(
      auth_on_publish, ?MODULE, hook_auth_on_publish, 6).
enable_on_deliver() ->
    vmq_plugin_mgr:enable_module_plugin(
      on_deliver, ?MODULE, hook_on_deliver, 4).
disable_on_subscribe() ->
    vmq_plugin_mgr:disable_module_plugin(
      auth_on_subscribe, ?MODULE, hook_auth_on_subscribe, 3).
disable_on_publish() ->
    vmq_plugin_mgr:disable_module_plugin(
      auth_on_publish, ?MODULE, hook_auth_on_publish, 6).
disable_on_deliver() ->
    vmq_plugin_mgr:disable_module_plugin(
      on_deliver, ?MODULE, hook_on_deliver, 4).



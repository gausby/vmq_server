%% Copyright 2014 Erlio GmbH Basel Switzerland (http://erl.io)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(vmq_writer).
-export([start_link/2,
         send/2,
         main_loop/2,
         recv_loop/2]).

-define(HIBERNATE_AFTER, 5000).

start_link(Transport, Socket) ->
    MaybeMaskedSocket =
    case Transport of
        ranch_ssl -> {ssl, Socket};
        _ -> Socket
    end,
    {ok, proc_lib:spawn_link(?MODULE, main_loop, [MaybeMaskedSocket, []])}.

send(WriterPid, Bin) when is_binary(Bin) ->
    WriterPid ! {send, Bin};
send(WriterPid, Frame) when is_tuple(Frame) ->
    WriterPid ! {send_frame, Frame}.

main_loop(Socket, Pending) ->
    process_flag(trap_exit, true),
    try
        recv_loop(Socket, Pending)
    catch
        exit:_Reason ->
            internal_flush(Socket, Pending),
            exit(normal)
    end.

recv_loop(Socket, []) ->
    receive
        Message ->
            ?MODULE:recv_loop(Socket, handle_message(Message, Socket, []))
    after
        ?HIBERNATE_AFTER ->
            erlang:hibernate(?MODULE, main_loop, [Socket, []])
    end;
recv_loop(Socket, Pending) ->
    receive
        Message ->
            ?MODULE:recv_loop(Socket, handle_message(Message, Socket, Pending))
    after
        0 ->
            ?MODULE:recv_loop(Socket, internal_flush(Socket, Pending))
    end.

handle_message({send, Bin}, Socket, Pending) ->
    maybe_flush(Socket, [Bin|Pending]);
handle_message({send_frame, Frame}, Socket, Pending) ->
    Bin = emqtt_frame:serialise(Frame),
    maybe_flush(Socket, [Bin|Pending]);
handle_message({inet_reply, _, ok}, _Socket, Pending) ->
    Pending;
handle_message({inet_reply, _, Status}, _, _) ->
    exit({writer, send_failed, Status});
handle_message({'EXIT', _Parent, Reason}, _, _) ->
    exit({writer, reader_exit, Reason});
handle_message(Msg, _, _) ->
    exit({writer, unknown_message_type, Msg}).



%% This magic number is the tcp-over-ethernet MSS (1460) minus the
%% minimum size of a AMQP basic.deliver method frame (24) plus basic
%% content header (22). The idea is that we want to flush just before
%% exceeding the MSS.
-define(FLUSH_THRESHOLD, 1414).
maybe_flush(Socket, Pending) ->
    case iolist_size(Pending) >= ?FLUSH_THRESHOLD of
        true ->
            internal_flush(Socket, Pending);
        false ->
            Pending
    end.

internal_flush(_Socket, Pending = []) -> Pending;
internal_flush(Socket, Pending) ->
    ok = port_cmd(Socket, lists:reverse(Pending)),
    [].

%% gen_tcp:send/2 does a selective receive of {inet_reply, Sock,
%% Status} to obtain the result. That is bad when it is called from
%% the writer since it requires scanning of the writers possibly quite
%% large message queue.
%%
%% So instead we lift the code from prim_inet:send/2, which is what
%% gen_tcp:send/2 calls, do the first half here and then just process
%% the result code in handle_message/3 as and when it arrives.
%%
%% This means we may end up happily sending data down a closed/broken
%% socket, but that's ok since a) data in the buffers will be lost in
%% any case (so qualitatively we are no worse off than if we used
%% gen_tcp:send/2), and b) we do detect the changed socket status
%% eventually, i.e. when we get round to handling the result code.
%%
%% Also note that the port has bounded buffers and port_command blocks
%% when these are full. So the fact that we process the result
%% asynchronously does not impact flow control.
port_cmd(Socket, Data) ->
    true =
    try port_cmd_(Socket, Data)
    catch error:Error ->
              exit({writer, send_failed, Error})
    end,
    vmq_systree:incr_bytes_sent(iolist_size(Data)),
    ok.

port_cmd_({ssl, Socket}, Data) ->
    case ssl:send(Socket, Data) of
        ok ->
            self() ! {inet_reply, Socket, ok},
            true;
        {error, Reason} ->
            erlang:error(Reason)
    end;
port_cmd_(Socket, Data) ->
    erlang:port_command(Socket, Data).

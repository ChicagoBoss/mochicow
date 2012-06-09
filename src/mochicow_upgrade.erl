-module(mochicow_upgrade).

-export([upgrade/4]).

-include_lib("cowboy/include/http.hrl").
-include("mochicow.hrl"upgrade(_ListenerPid, _Handler, Opts, Req) ->
    {loop, HttpLoop} = proplists:lookup(loop, Opts),
    #http_req{socket=Socket,
              transport=Transport,
              method=Method,
              version=Version,
              raw_path=Path,
              raw_qs=QS,
              headers=Headers,
              raw_host=Host,
              port=Port,
              buffer=Buffer} = Req,

    MochiSocket = mochiweb_socket(Transport, Socket),
    MochiHeaders = mochiweb_headers:make(Headers),
    DefaultPort = default_port(Transport:name()),
    MochiHost = case Port of
        DefaultPort ->
            Port;
        _ ->
            %% fix raw host
            binary_to_list(Host) ++ ":" ++ integer_to_list(Port)
    end,
    MochiHeaders1 = mochiweb_headers:enter('Host', MochiHost,
                MochiHeaders),

    %% fix raw path
    Path1 = case Path of
        <<>> ->
            <<"/">>;
        _ ->
            Path
    end,
    RawPath = case QS of
        <<>> ->
            Path1;
        _ ->
            << Path1/binary, "?", QS/binary >>
    end,
    MochiReq = mochiweb_request:new(MochiSocket,
                                    Method,
                                    binary_to_list(RawPath),
                                    Version,
                                    MochiHeaders1),
    case Buffer of
        <<>> -> ok;
        _ ->
            %%gen_tcp:unrecv(Socket, Buffer)
            erlang:put(mochiweb_request_body, Buffer)
    end,
    call_body(HttpLoop, MochiReq),
    after_response(Req, MochiReq).

mochiweb_socket(cowboy_transport_ssl, Socket) ->
    {ssl, Socket};
mochiweb_socket(_Transport, Socket) ->
    Socket.

call_body({M, F, A}, Req) ->
    erlang:apply(M, F, [Req | A]);
call_body({M, F}, Req) ->
    M:F(Req);
call_body(Body, Req) ->
    Body(Req).

after_response(Req, MochiReq) ->
    Connection =MochiReq:get_header_value("connection"),
    Req2 = Req#http_req{connection = list_to_connection(Connection),
                        resp_state = done,
                        body_state = done,
                        buffer = <<>> },

    MochiReq:cleanup(),
    erlang:garbage_collect(),
    {ok, Req2}.

list_to_connection(Connection) when is_binary(Connection) ->
    list_to_connection(binary_to_list(Connection));
list_to_connection(Connection) when is_atom(Connection) ->
    Connection;
list_to_connection("keep-alive") ->
    keepalive;
list_to_connection(_) ->
    close.

-spec default_port(atom()) -> 80 | 443.
default_port(ssl) -> 443;
default_port(_) -> 80.

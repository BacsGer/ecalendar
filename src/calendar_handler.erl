%%%-------------------------------------------------------------------
%%% @doc Handles the requests to "/" on the server.
%%%-------------------------------------------------------------------

-module(calendar_handler).

%%====================================================================
%% Exports
%%====================================================================

%% API
-export([init/2,
        known_methods/2,
        allowed_methods/2,
        is_authorized/2,
        content_types_accepted/2,
        content_types_provided/2,
        propfind_calendar/2]).

%%====================================================================
%% API
%%====================================================================

%% @doc Handle a PROPFIND Request.
-spec init(Req :: cowboy_req:req(), State :: any()) -> {atom(), Req :: cowboy_req:req(), any()}.
init(Req0=#{method := <<"PROPFIND">>}, State) ->
    Username = cowboy_req:binding(username, Req0),
    IsUser = filelib:is_dir(<<"data/", Username/binary>>),
    case IsUser of
        true ->
            Ctag = create_ctag(Username),
            Uri = iolist_to_binary(cowboy_req:uri(Req0)),
            {ok, IoBody, _} = read_body(Req0, <<"">>),
            ReqBody = binary:split(IoBody, <<"getetag">>),
            Body = case length(ReqBody) of
                   1 -> ecalendar_xmlparse:create_response(Username, IoBody, Uri);
                        %propfind_xml(Ctag, (Username));
                        %{ok, F}=file:read_file("works.xml"),
                        %F;
                   _ -> ecalendar_xmlparse:create_response(Username, IoBody, Uri)
               end,
        Req = cowboy_req:reply(207, #{<<"DAV">> => <<"1, 2, 3 calendar-access, calendar-schedule, calendar-query">>}, Body, Req0);
    false = IsUser ->
        Body = <<"NOT REGISTERED USER">>,
        Req = cowboy_req:reply(412, #{<<"DAV">> => <<"1, 2, 3 calendar-access, calendar-schedule, calendar-query">>}, Body, Req0)
        end,
    {ok, Req, State};

%% @doc Handle a REPORT Request.
init(Req0=#{method := <<"REPORT">>}, State) ->
    {ok, IoBody, _} = read_body(Req0, <<"">>),
    Uri = iolist_to_binary(cowboy_req:uri(Req0)),
    Body = ecalendar_xmlparse:create_response(cowboy_req:binding(username, Req0), IoBody, Uri),
    Req = cowboy_req:reply(207, #{}, Body, Req0),
    {ok, Req, State};

%% @doc Switch to REST handler behavior.
init(Req,Opts)->
    {cowboy_rest,Req,Opts}.

%% NOTE: These callbacks seems useless so far, because PROPFIND requests are
%% handled at init/2, and no other request should be handled by this handler

%% @doc Set the allowed http methods for this handler.
-spec allowed_methods(Req :: cowboy_req:req(), State :: any()) -> {[binary()], Req :: cowboy_req:req(), State :: any()}.
allowed_methods(Req, State) ->
    {[<<"OPTIONS">>, <<"GET">>, <<"PROPFIND">>, <<"REPORT">>], Req, State}.

%% @doc Set the known http methods for this handler.
-spec known_methods(Req :: cowboy_req:req(), State :: any()) -> {[binary()], Req :: cowboy_req:req(), State :: any()}.
known_methods(Req, State) ->
    {[<<"OPTIONS">>, <<"DELETE">>, <<"GET">>, <<"PUT">>, <<"PROPFIND">>, <<"REPORT">>], Req, State}.

%% @doc Media types accepted by the server.
-spec content_types_accepted(Req :: cowboy_req:req(), State :: any()) -> {[{{binary()}, atom()}], Req :: cowboy_req:req(), State :: any()}.
content_types_accepted(Req,State)->
    {[
        {{<<"text">>, <<"xml">>, '*'}, propfind_calendar}
    ],Req,State}.

%% @doc Media types provided by the server.
-spec content_types_provided(Req :: cowboy_req:req(), State :: any()) -> {[{{binary()}, atom()}], Req :: cowboy_req:req(), State :: any()}.
content_types_provided(Req,State)->
    {[
        {{<<"text">>, <<"xml">>, []}, propfind_calendar}
    ],Req,State}.

%% @doc Check the authorization of the request.
is_authorized(Req, State) ->
    Username = cowboy_req:binding(username, Req),
    [{Username, StoredPasswordHash}]= ets:lookup(authorization, Username),
    case cowboy_req:parse_header(<<"authorization">>, Req) of
        {basic, Username, <<"password">>} ->
            {true, Req, State};
        _ ->
            {{false, <<"Basic realm=\"Access to the staging site\"">>}, Req, State}
    end.

%% @doc Send back a simple response based on the method of the request.
-spec propfind_calendar(Req :: cowboy_req:req(), State :: any()) -> {atom(), Req :: cowboy_req:req(), State :: any()}.
propfind_calendar(Req, State) ->
    {ok, Req, State}.

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Concatenate all of the etags from the ets and then creates the Ctag for the calendar
-spec create_ctag(Username :: binary()) -> binary().
create_ctag(Username) ->
    UserList = ets:match_object(calendar, {'_', ['_', '_', '_', Username]}),
    create_ctag(UserList, <<"">>).

-spec create_ctag([], Username :: binary()) -> binary().
create_ctag([UserListHead | UserListTail], Acc) ->
    {Filename, [Body, Etag, Uri, Username]} = UserListHead,
    create_ctag(UserListTail, <<Acc/binary, Etag/binary>>);

create_ctag([], Acc) ->
    base64:encode(Acc).

%create_ctag(_, '$end_of_table', Acc) ->
    %base64:encode(Acc);

%create_ctag(Cal, Key, Acc) ->
    %[{Key, CalendarList} | _] = ets:lookup(Cal, Key),
    %CurrentEtag = lists:nth(2, CalendarList),
    %create_ctag(Cal, ets:next(Cal, Key), <<Acc/binary, CurrentEtag/binary>>).

%% @doc The Response body for a PROPFIND Request in xml form.
-spec propfind_xml(Ctag :: binary(), Username :: binary()) -> binary().
propfind_xml(Ctag,Username) ->
<<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<D:multistatus xmlns:D=\"DAV:\" xmlns:CS=\"http://calendarserver.org/ns/\" xmlns:C=\"urn:ietf:params:xml:ns:caldav\">
<D:response>
<D:href>", Username/binary, "/calendar/</D:href>
<D:propstat>\r\n<D:prop>\r\n<D:resourcetype>\r\n<D:collection />\r\n<C:calendar />
</D:resourcetype>
<D:owner>
<D:href>http://localhost:8080/", Username/binary, "/calendar/
</D:href>
</D:owner>
<D:current-user-principal>
<D:href>http://localhost:8080/", Username/binary, "/calendar/
</D:href>
</D:current-user-principal>
<D:supported-report-set>
<D:supported-report>
<D:report>
<C:calendar-multiget />
</D:report>
</D:supported-report>
<D:supported-report>
<D:report>
<C:calendar-query />
</D:report>
</D:supported-report>
<D:supported-report>
<D:report>
<C:free-busy-query />
</D:report>
</D:supported-report>
</D:supported-report-set>
<C:supported-calendar-component-set>
<C:comp name=\"VEVENT\" />
</C:supported-calendar-component-set>
<CS:getctag>", Ctag/binary, "</CS:getctag>\r\n</D:prop>
<D:status>HTTP/1.1 200 OK</D:status>\r\n</D:propstat>\r\n</D:response>\r\n</D:multistatus>">>.

%% @doc Read the request body.
-spec read_body(Req0 :: cowboy_req:req(), Acc :: binary()) -> {atom(), binary(), Req :: cowboy_req:req()}.
read_body(Req0, Acc) ->
    case cowboy_req:read_body(Req0) of
        {ok, Data, Req} -> {ok, << Acc/binary, Data/binary >>, Req};
        {more, Data, Req} -> read_body(Req, << Acc/binary, Data/binary >>)
    end.

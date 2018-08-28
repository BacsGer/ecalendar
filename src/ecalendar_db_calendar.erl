%%%-------------------------------------------------------------------
%%% @doc ecalendar_db_calendar public API
%%%-------------------------------------------------------------------

-module(ecalendar_db_calendar).
-include("ecalendar.hrl").

%%====================================================================
%% Exports
%%====================================================================

%% API
-export([start/0,
         is_exists/1,
         add_new_user_calendar/2,
         add_component/2,
         get_component/1,
         get_user_components/1,
         delete_data/1,
         delete_user_calendar/1,
         delete_all/0,
         ics_time_to_utc/1]).

%%====================================================================
%% API
%%====================================================================

start() ->
    ets:new(calendar, [set, named_table, public]),
    ok = load(),

    ok.

%%====================================================================
%% Exported functions
%%====================================================================

%% @doc Check for a component in the ets.
-spec is_exists(Key :: binary()) -> true | false.
is_exists(Key) ->
    ets:member(calendar, Key).

%% @doc Return the component from the ets.
-spec get_component(Key :: binary()) -> CalendarList :: {Data :: binary(), Etag :: binary(), URI :: binary(), User :: binary()}.
get_component(Key) ->
    [{Key, CalendarList} | _] = ets:lookup(calendar, Key),
    CalendarList.

%% @doc Return all components of a user.
-spec get_user_components(User :: binary()) -> [{Filename :: binary(), [binary()]}].
get_user_components(User) ->
    ets:match_object(calendar, {'_', ['_', '_', User, '_']}).

%% @doc Add a new component to the database.
-spec add_component(Filename :: binary(), Value :: [binary()]) -> ok.
add_component(URI, Value) ->
    ets:insert(calendar,{URI, Value}),
    Username = lists:nth(3, Value),
    write_to_file(Username, URI).

%% @doc Create an empty calendar directory and an empty calendar for the new user.
-spec add_new_user_calendar(Username :: binary(), Email :: binary()) -> ok.
add_new_user_calendar(Username, Email) ->
    BaseDir = code:priv_dir(?APPLICATION),
    filelib:ensure_dir(filename:join([BaseDir, <<"data/">>, Username, <<"calendar/">>, <<"valami">>])),
    {ok, OpenedFile} = file:open(filename:join([BaseDir, <<"data/">>, Username, <<"event_calendar.ics">>]), [write, read, binary]),
    EmptyCal = eics:encode(#{events => [], 
                                    prodid => ["PRODID", 58, "Ecalendar 0.0.1", "\r\n"], 
                                    version => ["VERSION", 58, "2.0", "\r\n"], 
                                    todos => [], 
                                    type => calendar, 
                                    'x-valami' => ["X-VALAMI", 59, "CN", 61, Username, 58, "mailto", 58, Email, "\r\n"], 
                                    'x-cal-address' => ["X-CAL-ADDRESS", 58, Email, "\r\n"], 
                                    'x-owner' => ["X-OWNER", 58, Username, "\r\n"], 
                                    timezones => [#{standard => 
                                                             #{dtstart => ["DTSTART", 58, [["1970","10","25"], 84, ["03","00","00"]], "\r\n"], 
                                                             type => standard, 
                                                             tzname => ["TZNAME", 58, "UTC", "\r\n"], 
                                                             tzoffsetto => ["TZOFFSETTO", 58, [43,"00","00"], "\r\n"], 
                                                             tzoffsetfrom => ["TZOFFSETFROM", 58, [43,"00","00"], "\r\n"]}, 
                                                             type => timezone, 
                                                             tzid => ["TZID", 58, "UTC", "\r\n"]
                                                   }]
                            }),
    file:write(OpenedFile, EmptyCal),
    file:close(OpenedFile).

%% @doc Delete the specified calendar component file.
-spec delete_data(Filename :: binary()) -> ok.
delete_data(URI) ->
    BaseDir = code:priv_dir(?APPLICATION),
    FullURI = filename:join([BaseDir, <<"data", URI/binary>>]),
    io:format("DELETING EVENT FILE~n"),
    io:format(FullURI),
    io:format("~n"),
    file:delete(FullURI),
    ets:delete(calendar, URI),
    io:format("EVENT DELETED~n").

%% @doc Delete the whole calendar of the specified user.
-spec delete_user_calendar(Username :: binary()) -> {ok | error, binary()}.
delete_user_calendar(Username) ->
    io:format("Deleting user~n"),
    BaseDir = code:priv_dir(?APPLICATION),
    file:delete(filename:join([BaseDir, <<"data">>, Username, <<"event_calendar.ics">>])),
    case file:list_dir(filename:join([BaseDir, <<"data">>, Username, <<"calendar">>])) of
        {ok, Filenames} ->
            lists:foreach(fun(Filename1) ->
                                  Filename2 = binary:list_to_bin(Filename1),
                                  delete_data(filename:join([Username, <<"calendar">>, Filename2]))
                          end, Filenames),
            file:del_dir(filename:join([BaseDir, <<"data">>, Username, <<"calendar">>])),
            file:del_dir(filename:join([BaseDir, <<"data">>, Username])),
            io:format(<<Username/binary, " user deleted~n">>),
            {ok, 'deleted'};
        {error, _} ->
            {error, 'missing_calendar'}
    end.

%% @doc Delete all user's calendar.
-spec delete_all() -> {atom, binary()}.
delete_all() ->
    BaseDir = code:priv_dir(?APPLICATION),
    case file:list_dir(filename:join([BaseDir, <<"data">>])) of
        {ok, UsersDirs} ->
            lists:foreach(fun(UserDir) ->
                                  file:delete(filename:join([BaseDir, <<"data">>, UserDir, <<"event_calendar.ics">>])),
                                  case file:list_dir(filename:join([BaseDir, <<"data">>, UserDir, <<"calendar">>])) of
                                      {ok, UserEvents} ->
                                          lists:foreach(fun(UserEvent) ->
                                                                io:format(UserEvent),
                                                                delete_data(filename:join([<<"/">>, UserDir, <<"calendar">>, UserEvent]))
                                                        end, UserEvents),
                                          file:del_dir(filename:join([BaseDir, <<"data">>, UserDir, <<"calendar">>])),
                                          file:del_dir(filename:join([BaseDir, <<"data">>, UserDir]));
                                      {error, _} ->
                                          {error, <<"Calendar does not exist">>}
                                  end
                          end, UsersDirs),
            {ok, <<"SERVER HAS BEEN WIPED">>};
        {error, _} ->
            {error, <<"THERE IS NO SERVER DATA">>}
    end.

%% @doc Convert the time from a parsed ics body to utc.
-spec ics_time_to_utc(ParsedBody :: binary()) -> {DtStart :: calendar:datetime(), DtEnd :: calendar:datetime()}.
ics_time_to_utc(ParsedBody) ->
    #{events := Eventlist} = ParsedBody,
    Event = lists:nth(1, Eventlist),
    #{dtstart := Start, dtend := End} = Event,
    TempDtStart = iso8601:parse(list_to_binary(lists:nth(4, Start))),
    TempDtEnd = iso8601:parse(list_to_binary(lists:nth(4, End))),
    TimeZoneStart = binary_to_list(lists:nth(2, binary:split(list_to_binary(lists:nth(2, Start)), <<"=">>))),
    TimeZoneEnd = binary_to_list(lists:nth(2, binary:split(list_to_binary(lists:nth(2, End)), <<"=">>))),
    DtStart = localtime:local_to_utc(TempDtStart, TimeZoneStart),
    DtEnd = localtime:local_to_utc(TempDtEnd, TimeZoneEnd),
    {DtStart, DtEnd}.

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Load the saved ecalendar data into the calendar ets.
load() ->
    BaseDir = code:priv_dir(?APPLICATION),
    filelib:ensure_dir(filename:join([BaseDir, <<"data/valami">>])),
    Path = filename:join([BaseDir, <<"data/">>]),
    filelib:ensure_dir(Path),
    io:format("~nLOADING SAVED DATA~n"),
    {ok, UsersDirs} = file:list_dir(Path),
    io:format("All users: "),
    io:format(UsersDirs),
    io:format("~n"),

    ok = load_calendars([filename:join([Path, D, <<"calendar/">>]) || D <- UsersDirs]),

    io:format("LOADING FINISHED~n").

%% @doc Recursive function that loads the calendars of the users into the calendar ets.
load_calendars([]) ->
    ok;

load_calendars([Directory | Directories]) ->
    ok = load_calendar(Directory),
    load_calendars(Directories).

load_calendar(Directory) ->
    {ok, Filenames} = file:list_dir(Directory),

    Username = filename:basename(filename:dirname(Directory)),

    io:format(<<Username/binary, "'s calendar is loading...">>),
    ok = load_files(Username, [filename:join([Directory, Fn]) || Fn <- Filenames]),
    io:format("Calendar loading finished~n~n"),
    ok.

%% @doc Recursive function that loads the events of a user into the calendar ets.
-spec load_files(binary(), [string() | binary()]) -> ok.
load_files(_, []) ->
    ok;

load_files(Username, [Path | Paths]) ->
    ok = load_file(Username, Path),
    load_files(Username, Paths).

%% @doc Load the event of a user into the calendar ets.
-spec load_file(Username :: binary(), string() | binary()) -> ok.
load_file(Username, Path) ->
    Filename = filename:basename(Path),

    {ok, RawFile} = file:read_file(Path),
    SplitRawFile = binary:split(RawFile, <<"\r\n">>),
    Etag = lists:nth(1, SplitRawFile),
    Data = lists:nth(2, SplitRawFile),
    Uri = <<"/", Username/binary, "/calendar/", Filename/binary>>,
    ParsedBody = eics:decode(Data),
    ets:insert(calendar, {Uri, [Data, Etag, Username, ParsedBody]}),
    ok.

%% @doc Write the calendar component into an ics file.
-spec write_to_file(User :: binary(), Key :: binary()) -> ok.
write_to_file(User, URI) ->
    io:format("SAVING EVENT TO FILE~n"),
    io:format(User),
    io:format("-----"),
    io:format(URI),
    io:format("~n"),
    BaseDir = code:priv_dir(?APPLICATION),
    {ok, OpenedFile} = file:open(filename:join([BaseDir, <<"data", URI/binary>>]), [write, read, binary]),
    [{URI, CalendarList} | _] = ets:lookup(calendar, URI),
    ComponentData = lists:nth(1, CalendarList),
    ComponentEtag = lists:nth(2, CalendarList),
    file:write(OpenedFile, <<ComponentEtag/binary, "\r\n", ComponentData/binary>>),
    file:close(OpenedFile),
    io:format("EVENT SAVED~n").

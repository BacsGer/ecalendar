-module(ecalendar_test).

-export([setup_http_connection/1,
         teardown_http_connection/1,
         is_xml_response/1,
         get_test_putbody/0,
         content_type_headers/3,
         get_report_request/1,
         get_http_connection/1]).

-export([authorization_headers/2]).

setup_http_connection(Config) ->
    {ok, ConnPid} = http_client:connect("localhost", 8080),

    [{http_conn, ConnPid} | Config].

teardown_http_connection(Config) ->
    ConnPid = proplists:get_value(http_conn, Config),
    ok = http_client:disconnect(ConnPid),

    Config.

get_http_connection(Config) ->
    proplists:get_value(http_conn, Config).

content_type_headers(Username, Password, ContentTypes) ->
    AuthHeader = authorization_headers(Username, Password),
    lists:merge(ContentTypes, AuthHeader).

authorization_headers(Username, Password) ->
    EncodedCredentials = base64:encode(<<Username/binary, ":", Password/binary>>),
    [{<<"Authorization">>, <<"Basic ", EncodedCredentials/binary>>}].

is_xml_response(Input) ->
    [FirstLine | _] = binary:split(Input, <<"\n">>),
    FirstLine =:= <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>">>.

get_test_putbody() ->
    <<"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:TESTICSBODY\r\nEND:VCALENDAR">>.

get_report_request(Filename) ->
    <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
    <C:calendar-multiget xmlns:D=\"DAV:\" xmlns:C=\"urn:ietf:params:xml:ns:caldav\"><D:prop><D:getetag/><C:calendar-data/>
    </D:prop><D:href>/jozsi/calendar/", Filename/binary, "</D:href></C:calendar-multiget>">>.

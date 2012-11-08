-module(udp_packetizer_tests).
-compile(export_all).
-include_lib("erlmedia/include/video_frame.hrl").
-include_lib("erlmedia/include/media_info.hrl").
-include_lib("eunit/include/eunit.hrl").



udp_packetizet_test_() ->
  {foreach,
  fun() ->
    error_logger:delete_report_handler(error_logger_tty_h),
    application:stop(ranch),
    application:stop(gen_tracker),
    application:stop(flussonic),
    ok = application:start(ranch),
    ok = application:start(gen_tracker),
    ok = application:start(flussonic),
    gen_tracker_sup:start_tracker(flu_streams)
  end,
  fun(_) ->
    application:stop(ranch),
    application:stop(gen_tracker),
    application:stop(flussonic)
  end, [
    fun test_packetizer/0
  ]}.


frames() ->
  {ok, File} = file:open("../../../priv/bunny.mp4", [binary,read,raw]),
  {ok, R} = mp4_reader:init({file,File},[]),
  MI = mp4_reader:media_info(R),
  Frames1 = read_frames(R, undefined),
  Frames2 = lists:flatmap(fun
    (#video_frame{flavor = keyframe} = F) -> [MI,F];
    (#video_frame{} = F) -> [F]
  end, Frames1),
  file:close(File),
  {ok, MI, Frames2}.

read_frames(R, Key) ->
  case mp4_reader:read_frame(R, Key) of
    #video_frame{next_id = Next} = F ->
      [F|read_frames(R, Next)];
    eof ->
      []
  end.

listen_multicast(Port) ->
  {ok,Addr} = inet_parse:address("239.0.0.1"),
  {ok,Sock} = gen_udp:open(Port, [binary,{add_membership,{Addr,{0,0,0,0}}},
    {reuseaddr,true},{multicast_ttl,4},{multicast_loop,true},{active,true}]),
  {ok, Sock}.  

test_packetizer() ->
  {ok, _MI, Frames} = frames(),
  Port = crypto:rand_uniform(5000, 10000),
  {ok, Sock} = listen_multicast(Port),
  {ok, S} = flu_stream:autostart(<<"livestream">>, [{udp, "udp://239.0.0.1:"++integer_to_list(Port) }]),
  link(S),
  [S ! F || F <- Frames],

  Frames1 = read_from_udp(Sock),
  Length = length(Frames1),
  ?assertMatch(_ when Length > 500, Length),

  ok.

read_from_udp(Sock) ->
  Data = iolist_to_binary(fetch_udp(Sock)),
  {ok, Frames1} = mpegts_decoder:decode_file(Data),
  gen_udp:close(Sock),
  Frames1.

fetch_udp(Sock) ->
  receive
    {udp, Sock, _, _, Bin} -> [Bin|fetch_udp(Sock)]
  after
    100 -> []
  end.


udp_raw_packetizer_test() ->
  {ok, _MI, Frames} = frames(),
  Port = crypto:rand_uniform(5000, 10000),
  {ok, Sock} = listen_multicast(Port),
  {ok, UDP1} = udp_packetizer:init([{name,<<"livestream">>},{udp, "udp://239.0.0.1:"++integer_to_list(Port) }]),
  UDP2 = lists:foldl(fun(F, UDP1_) ->
    {noreply, UDP2_} = udp_packetizer:handle_info(F, UDP1_),
    UDP2_
  end, UDP1, Frames),
  udp_packetizer:terminate(normal, UDP2),
  Frames1 = read_from_udp(Sock),
  Length = length(Frames1),
  ?assertMatch(_ when Length > 200, Length),
  ok.


udp_raw_packetizer_from_middle_of_stream_test() ->
  {ok, _MI, Frames1} = frames(),
  Frames = lists:nthtail(20,Frames1),
  Port = crypto:rand_uniform(5000, 10000),
  {ok, UDP1} = udp_packetizer:init([{name,<<"livestream">>},{udp, "udp://239.0.0.1:"++integer_to_list(Port) }]),
  UDP2 = lists:foldl(fun(F, UDP1_) ->
    {noreply, UDP2_} = udp_packetizer:handle_info(F, UDP1_),
    UDP2_
  end, UDP1, Frames),
  udp_packetizer:terminate(normal, UDP2),
  ok.










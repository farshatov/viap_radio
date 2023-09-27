import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viap_radio/utils/assets.dart';
import 'package:viap_radio/utils/audio_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:http/http.dart' as http;

Future<Playlist> fetchAlbum() async {
  final response = await http.get(Uri.https('kipr4you.org', 'playlist.json'));

  if (response.statusCode == 200) {
    // If the server did return a 200 OK response,
    // then parse the JSON.
    return Playlist.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  } else {
    // If the server did not return a 200 OK response,
    // then throw an exception.
    throw Exception('Failed to load album');
  }
}

class Playlist {
  final List<AudioSource> tracks;

  const Playlist({
    required this.tracks,
  });

  factory Playlist.fromJson(List<dynamic> json) {
    List<AudioSource> tracks = <AudioSource>[];

    json.asMap().forEach((index, track) {
      tracks.add(AudioSource.uri(
        Uri.parse(track['mp3']),
        tag: AudioMetadata(
          album: "VIAP",
          title: track['title'],
          artwork: "https://kipr4you.org/images/logo.png",
        ),
      ));
    });

    return Playlist(tracks: tracks);
  }
}

Duration parseTime(String input) {
  final parts = input.split(':');

  if (parts.length != 3) throw const FormatException('Invalid time format');

  int days;
  int hours;
  int minutes;
  int seconds;
  int milliseconds;
  int microseconds;

  {
    final p = parts[2].split('.');

    if (p.length != 2) throw const FormatException('Invalid time format');

    // If fractional seconds is passed, but less than 6 digits
    // Pad out to the right so we can calculate the ms/us correctly
    final p2 = int.parse(p[1].padRight(6, '0'));
    microseconds = p2 % 1000;
    milliseconds = p2 ~/ 1000;

    seconds = int.parse(p[0]);
  }

  minutes = int.parse(parts[1]);

  {
    int p = int.parse(parts[0]);
    hours = p % 24;
    days = p ~/ 24;
  }

  // TODO verify that there are no negative parts

  return Duration(
      days: days,
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
      microseconds: microseconds);
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  late Future<int> _index;
  late Future<String> _position;

  Future<void> _saveIndex(int index) async {
    final SharedPreferences prefs = await _prefs;

    setState(() {
      _index = prefs.setInt('index', index).then((bool success) => index);
      print(_index);
    });
  }

  Future<void> _savePosition(String position) async {
    final SharedPreferences prefs = await _prefs;

    setState(() {
      _position = prefs
          .setString('position', position)
          .then((bool success) => position);

    });

    final _p = prefs.getString('position');
    print(_p);
  }

  late AudioPlayer _player;
  late ConcatenatingAudioSource _playlist;

  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();

    _index = _prefs.then((SharedPreferences prefs) {
      return prefs.getInt('index') ?? 0;
    });
    _position = _prefs.then((SharedPreferences prefs) {
      return prefs.getString('position').toString();
    });

    ambiguate(WidgetsBinding.instance)!.addObserver(this);
    _player = AudioPlayer();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
    ));
    _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    final tracks = (await fetchAlbum()).tracks;
    _playlist = ConcatenatingAudioSource(children: tracks);

    // Сохраняем текущую позицию трека
    _player.positionStream.listen((event) {
      _savePosition(event.toString());
    });

    // Сохраняем текущий номер трека
    _player.currentIndexStream.listen((event) {
      _saveIndex(event ?? 0);
    });

    _player.playbackEventStream.listen((event) {},
        onError: (Object e, StackTrace stackTrace) {
      print('A stream error occurred: $e');
      // TODO: выводить инфу об ошибке пользователю
    });

    try {
      // Preloading audio is not currently supported on Linux.
      await _player.setAudioSource(_playlist,
          preload: kIsWeb || defaultTargetPlatform != TargetPlatform.linux);
    } catch (e) {
      // Catch load errors: 404, invalid url...
      print("Error loading audio source: $e");
    }

    // Пробуем выставить позицию и номер трека
    final initPosition = parseTime(await _position);
    final initIndex = await _index;
    print("init position");
    print(initPosition);
    print("init index");
    print(initIndex);
    _player.seek(initPosition, index: initIndex);

    // Show a snackbar whenever reaching the end of an item in the playlist.
    _player.positionDiscontinuityStream.listen((discontinuity) {
      if (discontinuity.reason == PositionDiscontinuityReason.autoAdvance) {
        _showItemFinished(discontinuity.previousEvent.currentIndex);
      }
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _showItemFinished(_player.currentIndex);
      }
    });
  }

  void _showItemFinished(int? index) {
    if (index == null) return;
    final sequence = _player.sequence;
    if (sequence == null) return;
    final source = sequence[index];
    final metadata = source.tag as AudioMetadata;
    _scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
      content: Text('Finished playing ${metadata.title}'),
      duration: const Duration(seconds: 1),
    ));
  }

  @override
  void dispose() {
    ambiguate(WidgetsBinding.instance)!.removeObserver(this);
    _player.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Release the player's resources when not in use. We use "stop" so that
      // if the app resumes later, it will still remember what position to
      // resume from.
      _player.stop();
    }
  }

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          _player.positionStream,
          _player.bufferedPositionStream,
          _player.durationStream,
          (position, bufferedPosition, duration) => PositionData(
              position, bufferedPosition, duration ?? Duration.zero));

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      home: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: StreamBuilder<SequenceState?>(
                  stream: _player.sequenceStateStream,
                  builder: (context, snapshot) {
                    final state = snapshot.data;
                    if (state?.sequence.isEmpty ?? true) {
                      return const SizedBox();
                    }
                    final metadata = state!.currentSource!.tag as AudioMetadata;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Center(
                              child: Image.asset(
                                Assets.logo,
                                width: 200,
                                height: 200,
                              ),
                            ),
                          ),
                        ),
                        Text(metadata.album,
                            style: Theme.of(context).textTheme.titleLarge),
                        Text(metadata.title),
                      ],
                    );
                  },
                ),
              ),
              ControlButtons(_player),
              StreamBuilder<PositionData>(
                stream: _positionDataStream,
                builder: (context, snapshot) {
                  final positionData = snapshot.data;
                  return SeekBar(
                    duration: positionData?.duration ?? Duration.zero,
                    position: positionData?.position ?? Duration.zero,
                    bufferedPosition:
                        positionData?.bufferedPosition ?? Duration.zero,
                    onChangeEnd: (newPosition) {
                      // _player.seek(newPosition);
                    },
                  );
                },
              ),
              const SizedBox(height: 8.0),
            ],
          ),
        ),
      ),
    );
  }
}

class ControlButtons extends StatelessWidget {
  final AudioPlayer player;

  const ControlButtons(this.player, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.volume_up),
          onPressed: () {
            showSliderDialog(
              context: context,
              title: "Adjust volume",
              divisions: 10,
              min: 0.0,
              max: 1.0,
              value: player.volume,
              stream: player.volumeStream,
              onChanged: player.setVolume,
            );
          },
        ),
        // StreamBuilder<SequenceState?>(
        //   stream: player.sequenceStateStream,
        //   builder: (context, snapshot) => IconButton(
        //     icon: const Icon(Icons.skip_previous),
        //     onPressed: player.hasPrevious ? player.seekToPrevious : null,
        //   ),
        // ),
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final processingState = playerState?.processingState;
            final playing = playerState?.playing;
            if (processingState == ProcessingState.loading ||
                processingState == ProcessingState.buffering) {
              return Container(
                margin: const EdgeInsets.all(8.0),
                width: 64.0,
                height: 64.0,
                child: const CircularProgressIndicator(),
              );
            } else if (playing != true) {
              return IconButton(
                icon: const Icon(Icons.play_arrow),
                iconSize: 64.0,
                onPressed: player.play,
              );
            } else if (processingState != ProcessingState.completed) {
              return IconButton(
                icon: const Icon(Icons.pause),
                iconSize: 64.0,
                onPressed: player.pause,
              );
            } else {
              return IconButton(
                icon: const Icon(Icons.replay),
                iconSize: 64.0,
                onPressed: () => player.seek(Duration.zero,
                    index: player.effectiveIndices!.first),
              );
            }
          },
        ),
        // StreamBuilder<SequenceState?>(
        //   stream: player.sequenceStateStream,
        //   builder: (context, snapshot) => IconButton(
        //     icon: const Icon(Icons.skip_next),
        //     onPressed: player.hasNext ? player.seekToNext : null,
        //   ),
        // ),
        StreamBuilder<double>(
          stream: player.speedStream,
          builder: (context, snapshot) => IconButton(
            icon: Text("${snapshot.data?.toStringAsFixed(1)}x",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: () {
              showSliderDialog(
                context: context,
                title: "Adjust speed",
                divisions: 10,
                min: 0.5,
                max: 1.5,
                value: player.speed,
                stream: player.speedStream,
                onChanged: player.setSpeed,
              );
            },
          ),
        ),
      ],
    );
  }
}

class AudioMetadata {
  final String album;
  final String title;
  final String artwork;

  AudioMetadata({
    required this.album,
    required this.title,
    required this.artwork,
  });
}

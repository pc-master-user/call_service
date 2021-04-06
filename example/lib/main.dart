import 'dart:async';
//import 'dart:io';
import 'dart:math';
// @dart=2.9
// ignore: import_of_legacy_library_into_null_safe
import 'package:agora_rtc_engine/rtc_engine.dart';
import 'package:agora_rtc_engine/rtc_local_view.dart' as RtcLocalView;
import 'package:agora_rtc_engine/rtc_remote_view.dart' as RtcRemoteView;
import 'package:call_service/call_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
//import 'package:flutter_tts/flutter_tts.dart';
import 'package:rxdart/rxdart.dart';

import 'PermissionHelper.dart';

//final _isTtsSupported = kIsWeb || !Platform.isMacOS;

// You might want to provide this using dependency injection rather than a
// global variable.
AudioHandler _audioHandler;

/// Extension methods for our custom actions.
extension DemoAudioHandler on AudioHandler {
  Future<void> switchToHandler(int index) async {
    if (index == null) return;
    await _audioHandler.customAction('switchToHandler', {'index': index});
  }
}

Future<void> main() async {
  _audioHandler = await AudioService.init(
    builder: () =>  AudioPlayerHandler(),
    config: CallServiceConfig(
      androidNotificationChannelName: 'Audio Service Demo',
      androidNotificationOngoing: true,
      androidEnableQueue: true,
    ),
  );
  runApp(new MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Service Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatelessWidget {
  static final handlerNames = [
    'Audio Player',
    //if (_isTtsSupported) 'Text-To-Speech',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Service Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Play/pause/stop buttons.
            StreamBuilder<bool>(
              stream: _audioHandler.playbackState
                  .map((state) => state.playing)
                  .distinct(),
              builder: (context, snapshot) {
                final playing = snapshot.data ?? false;
                return Column(
                  children: [
                    if(playing)
                      Container(
                        child: RtcLocalView.SurfaceView(
                          channelId: '58438b40-ccdb-4121-b805-b774527185c0',
                          //uid: AudioPlayerHandler.userId,
                          onPlatformViewCreated: (int) {
                            //notifyListeners();
                          },
                        ),
                        height: 200,),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (playing) pauseButton() else playButton(),
                        stopButton(),
                      ],

                    ),
                  ],
                );
              },
            ),
            // Display the processing state.
            StreamBuilder<AudioProcessingState>(
              stream: _audioHandler.playbackState
                  .map((state) => state.processingState)
                  .distinct(),
              builder: (context, snapshot) {
                final processingState =
                    snapshot.data ?? AudioProcessingState.idle;
                return Text(
                    "Processing state: ${describeEnum(processingState)}");
              },
            ),
            // Display the latest custom event.
            StreamBuilder(
              stream: _audioHandler.customEvent,
              builder: (context, snapshot) {
                return Text("custom event: ${snapshot.data}");
              },
            ),
            // Display the notification click status.
            StreamBuilder<bool>(
              stream: AudioService.notificationClickEvent,
              builder: (context, snapshot) {
                return Text(
                  'Notification Click Status: ${snapshot.data}',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  ElevatedButton startButton(String label, VoidCallback onPressed) =>
      ElevatedButton(
        child: Text(label),
        onPressed: onPressed,
      );

  IconButton playButton() => IconButton(
    icon: Icon(Icons.play_arrow),
    iconSize: 64.0,
    onPressed: _audioHandler.play,
  );

  IconButton pauseButton() => IconButton(
    icon: Icon(Icons.pause),
    iconSize: 64.0,
    onPressed: _audioHandler.play,
  );

  IconButton stopButton() => IconButton(
      icon: Icon(Icons.stop),
      iconSize: 64.0,
      onPressed: _audioHandler.onNotificationDeleted
  );
}

class QueueState {
  final List<MediaItem> queue;
  final MediaItem mediaItem;

  QueueState(this.queue, this.mediaItem);
}

class MediaState {
  final MediaItem mediaItem;
  final Duration position;

  MediaState(this.mediaItem, this.position);
}

/// An [AudioHandler] for playing a list of podcast episodes.
class AudioPlayerHandler extends BaseAudioHandler
   {
  MediaItem itm= MediaItem(
    title: "",
    album: "",
    id: "",
  );
  // ignore: close_sinks
  final BehaviorSubject<MediaItem> _recentSubject =
  BehaviorSubject<MediaItem>();

  static const appId = 'c67b893eb46f4e1380d5ae46e48dc0f5';
  RtcEngine _engine;
  String channelId= 'c6c2096f-21aa-40de-ab63-5654053d2f0b';
  String uid = 'SlYEuxcJ8ndu0tFI3LhpqMuyEjx1';

  /*AudioPlayerHandler() {
    initRtcEngine();
  }*/

  initRtcEngine() async {
    bool isPermissionsGranted = await checkPermissions();
    if (isPermissionsGranted) {
      _engine = await RtcEngine.createWithConfig(RtcEngineConfig(
        appId,
        areaCode: AreaCode.IN,
      ));
      await _engine.setChannelProfile(ChannelProfile.Communication);
      await _engine.setClientRole(ClientRole.Broadcaster);
      await _engine.setParameters('{"che.audio.opensl":true}');
      //callState = AgoraCallState(channelId, uid);
      /*mediaItem
          .whereType<MediaItem>()
          .listen((item) => _recentSubject.add(item));*/
      addAgoraEventHandlers();
    }
  }

  Future<bool> checkPermissions() async {
    bool camAccess = await PermissionHelper.requestCameraPermission();
    bool micAccess = await PermissionHelper.requestMicroPhonePermission();
    bool phoneAccess = await PermissionHelper.requestPhonePermission();
    return camAccess && micAccess && phoneAccess;
  }

  String token = '006c67b893eb46f4e1380d5ae46e48dc0f5IAA/KCAWg0pFbO36wGn/ZyU0xkbr89VjE2FhlkFXnYk5WmbxuZPYfoVVIgAX/mvNTq5tYAQAAQBOrm1gAgBOrm1gAwBOrm1gBABOrm1g';
  @override
  Future<void> play() async {
    if(_engine==null){
      await initRtcEngine();
    }

    ChannelMediaOptions options = ChannelMediaOptions(true, true);
    mediaItem.add(MediaItem(
        id: 'c6c2096f-21aa-40de-ab63-5654053d2f0b',
        album: "Psychiatry Consult",
        title: 'Prabhakar'
    ));
    try {
      await _engine.enableVideo();
      await _engine.enableAudio();
      await _engine.joinChannelWithUserAccount(
          token,channelId, uid, options);
    } catch (e) {
      print(e);
    }
  }
  static int userId=0;
  static getLocalView() {
    return RtcRemoteView.SurfaceView(
      channelId: '58438b40-ccdb-4121-b805-b774527185c0',
      onPlatformViewCreated: (int) {
        //notifyListeners();
      },
    );
    //return RtcLocalView.SurfaceView();
  }

  @override
  Future<void> stop() async {
    await _engine.leaveChannel();
    await _engine.disableVideo();
    await _engine.destroy();
    _engine=null;
    trigger(false,AudioProcessingState.completed);
    await super.stop();
  }

  void addAgoraEventHandlers() {
    trigger(false,AudioProcessingState.idle);
    _engine.setEventHandler(RtcEngineEventHandler(
        error: (code) {
          final info = 'onError: $code';
          print(info);
        },
        joinChannelSuccess: (channel, uid, elapsed) {
          final info = 'onJoinChannel: $channel, uid: $uid';
          print(info);
          trigger(true, AudioProcessingState.ready);
        },
        leaveChannel: (stats) {
          print('onLeaveChannel');
          trigger(false,AudioProcessingState.completed);
        },
        userJoined: (int uid, int elapsed){
          userId=uid;
          //trigger(true, AudioProcessingState.ready);
        }
    ));
  }
  trigger(bool isJoined, AudioProcessingState state){
    playbackState.add(playbackState.value.copyWith(

      controls: [ MediaControl.stop,],
      playing: isJoined,
      processingState: state,
    ));
  }
}

/// Provides access to a library of media items. In your app, this could come
/// from a database or web service.
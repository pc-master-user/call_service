import 'package:flutter/services.dart';

import 'Platform_Channel_Call_Service.dart';



class MethodChannelCallService extends CallServicePlatform {
  final MethodChannel _clientChannel =
  MethodChannel('com.clinix.call_service.client.methods');
  final MethodChannel _handlerChannel =
  MethodChannel('com.clinix.call_service.handler.methods');

  @override
  Future<ConfigureResponse> configure(ConfigureRequest request) async {
    return ConfigureResponse.fromMap((await _clientChannel
        .invokeMethod<Map<dynamic, dynamic>>('configure', request.toMap())));
  }

  @override
  Future<void> setState(SetStateRequest request) async {
    await _handlerChannel.invokeMethod('setState', request.toMap());
  }

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async {
    await _handlerChannel.invokeMethod('setMediaItem', request.toMap());
  }

  @override
  Future<void> stopService(StopServiceRequest request) async {
    await _handlerChannel.invokeMethod('stopService', request.toMap());
  }

  @override
  Future<void> setAndroidPlaybackInfo(
      SetAndroidPlaybackInfoRequest request) async {
    await _handlerChannel.invokeMethod(
        'setAndroidPlaybackInfo', request.toMap());
  }

  void setClientCallbacks(CallClientCallbacks callbacks) {
    _clientChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPlaybackStateChanged':
          callbacks.onPlaybackStateChanged(
              OnPlaybackStateChangedRequest.fromMap(call.arguments));
          break;
        case 'onMediaItemChanged':
          callbacks.onMediaItemChanged(
              OnMediaItemChangedRequest.fromMap(call.arguments));
          break;
      }
    });
  }

  void setHandlerCallbacks(CallHandlerCallbacks callbacks) {
    _handlerChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'getMediaItem':
          return (await callbacks.getMediaItem(
              GetMediaItemRequest(mediaId: call.arguments['mediaId'])));
        case 'click':
          print('### received click: ${call.arguments}');
          try {
            print('button value is "${call.arguments['button']}"');
            print('type: ${call.arguments['button'].runtimeType}');
            await callbacks.click(ClickRequest(
                button: MediaButtonMessage.values[call.arguments['button']]));
          } catch (e, stackTrace) {
            print(e);
            print(stackTrace);
          }
          print('### called callbacks.click');
          return null;
        case 'stop':
          await callbacks.stop(StopRequest());
          return null;
        case 'prepare':
          await callbacks.prepare(PrepareRequest());
          return null;
        case 'prepareFromMediaId':
          await callbacks.prepareFromMediaId(PrepareFromMediaIdRequest(
              mediaId: call.arguments['mediaId'],
              extras: _castMap(call.arguments['extras'])));
          return null;
        case 'play':
          await callbacks.play(PlayRequest());
          return null;
        case 'playFromMediaId':
          await callbacks.playFromMediaId(PlayFromMediaIdRequest(
              mediaId: call.arguments['mediaId'],
              extras: _castMap(call.arguments['extras'])));
          return null;
        case 'playMediaItem':
          await callbacks.playMediaItem(PlayMediaItemRequest(
              mediaItem:
              MediaItemMessage.fromMap(call.arguments['mediaItem'])));
          return null;
        case 'updateMediaItem':
          await callbacks.updateMediaItem(UpdateMediaItemRequest(
              mediaItem:
              MediaItemMessage.fromMap(call.arguments['mediaItem'])));
          return null;
        case 'onTaskRemoved':
          await callbacks.onTaskRemoved(OnTaskRemovedRequest());
          return null;
        case 'onNotificationDeleted':
          await callbacks.onNotificationDeleted(OnNotificationDeletedRequest());
          return null;
        case 'customAction':
          await callbacks.customAction(CustomActionRequest(
              name: call.arguments['name'],
              extras: _castMap(call.arguments['extras'])));
          return null;
        default:
          throw PlatformException(code: 'Unimplemented');
      }
    });
  }
}

_castMap(Map map) => map?.cast<String, dynamic>();
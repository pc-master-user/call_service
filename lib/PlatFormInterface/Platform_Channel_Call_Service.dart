import 'package:flutter/material.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'MethodChannel_Call_Service.dart';

abstract class CallServicePlatform extends PlatformInterface {
  /// Constructs an CallServicePlatform.
  CallServicePlatform() : super(token: _token);

  static final Object _token = Object();

  static CallServicePlatform _instance = MethodChannelCallService();

  /// The default instance of [CallServicePlatform] to use.
  ///
  /// Defaults to [MethodChannelCallService].
  static CallServicePlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [CallServicePlatform] when they register themselves.
  // TODO(amirh): Extract common platform interface logic.
  // https://github.com/flutter/flutter/issues/43368
  static set instance(CallServicePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<ConfigureResponse> configure(ConfigureRequest request) {
    throw UnimplementedError('configure() has not been implemented.');
  }

  Future<void> setState(SetStateRequest request) {
    throw UnimplementedError('setState() has not been implemented.');
  }

  Future<void> setMediaItem(SetMediaItemRequest request) {
    throw UnimplementedError('setMediaItem() has not been implemented.');
  }

  Future<void> stopService(StopServiceRequest request) {
    throw UnimplementedError('stopService() has not been implemented.');
  }

  Future<void> setAndroidPlaybackInfo(
      SetAndroidPlaybackInfoRequest request) async {}

  void setClientCallbacks(CallClientCallbacks callbacks);

  void setHandlerCallbacks(CallHandlerCallbacks callbacks);
}

/// Callbacks from the platform to a client running in another isolate.
abstract class CallClientCallbacks {
  Future<void> onPlaybackStateChanged(OnPlaybackStateChangedRequest request);

  Future<void> onMediaItemChanged(OnMediaItemChangedRequest request);

// We currently implement children notification in Dart through inter-isolate
// send/receive ports.
// XXX: Could we actually implement the above 3 callbacks in the same way?
// If so, then platform->client communication should be reserved for a future
// feature where an app can observe another process's media session.
//Future<void> onChildrenLoaded(OnChildrenLoadedRequest request);

// TODO: Add more callbacks
}

/// Callbacks from the platform to the handler.
abstract class CallHandlerCallbacks {
  /// Prepare media items for playback.
  Future<void> prepare(PrepareRequest request);

  /// Prepare a specific media item for playback.
  Future<void> prepareFromMediaId(PrepareFromMediaIdRequest request);

  /// Start or resume playback.
  Future<void> play(PlayRequest request);

  /// Play a specific media item.
  Future<void> playFromMediaId(PlayFromMediaIdRequest request);

  /// Play a specific media item.
  Future<void> playMediaItem(PlayMediaItemRequest request);

  /// Pause playback.
  Future<void> pause(PauseRequest request);

  /// Process a headset button click, where [button] defaults to
  /// [MediaButton.media].
  Future<void> click(ClickRequest request);

  /// Stop playback and release resources.
  Future<void> stop(StopRequest request);

  /// Update the properties of [mediaItem].
  Future<void> updateMediaItem(UpdateMediaItemRequest request);

  /// Set the rating.
  Future<void> setRating(SetRatingRequest request);

  /// A mechanism to support app-specific actions.
  Future<dynamic> customAction(CustomActionRequest request);

  /// Handle the task being swiped away in the task manager (Android).
  Future<void> onTaskRemoved(OnTaskRemovedRequest request);

  /// Handle the notification being swiped away (Android).
  Future<void> onNotificationDeleted(OnNotificationDeletedRequest request);

  Future<void> onNotificationClicked(OnNotificationClickedRequest request);

  /// Get a particular media item.
  Future<GetMediaItemResponse> getMediaItem(GetMediaItemRequest request);

}

/// The different states during Call processing.
enum CallProcessingStateMessage {
  idle,
  loading,
  buffering,
  ready,
  completed,
  error,
}

/// The actons associated with playing Call.
enum MediaActionMessage {
  stop,
  pause,
  play,
  rewind,
  skipToPrevious,
  skipToNext,
  fastForward,
  setRating,
  seek,
  playPause,
  playFromMediaId,
  playFromSearch,
  skipToQueueItem,
  playFromUri,
  prepare,
  prepareFromMediaId,
  prepareFromSearch,
  prepareFromUri,
  setRepeatMode,
  unused_1,
  unused_2,
  setShuffleMode,
  seekBackward,
  seekForward,
}

class MediaControlMessage {
  /// A reference to an Android icon resource for the control (e.g.
  /// `"drawable/ic_action_pause"`)
  final String androidIcon;

  /// A label for the control
  final String label;

  /// The action to be executed by this control
  final MediaActionMessage action;

  const MediaControlMessage({
    required this.androidIcon,
    required this.label,
    required this.action,
  });

  Map<String, dynamic> toMap() => {
    'androidIcon': androidIcon,
    'label': label,
    'action': action.index,
  };
}

/// The playback state which includes a [playing] boolean state, a processing
/// state such as [CallProcessingState.buffering], the playback position and
/// the currently enabled actions to be shown in the Android notification or the
/// iOS control center.
class PlaybackStateMessage {
  /// The Call processing state e.g. [BasicPlaybackState.buffering].
  final CallProcessingStateMessage processingState;

  /// Whether Call is either playing, or will play as soon as [processingState]
  /// is [CallProcessingState.ready]. A true value should be broadcast whenever
  /// it would be appropriate for UIs to display a pause or stop button.
  ///
  /// Since [playing] and [processingState] can vary independently, it is
  /// possible distinguish a particular Call processing state while Call is
  /// playing vs paused. For example, when buffering occurs during a seek, the
  /// [processingState] can be [CallProcessingState.buffering], but alongside
  /// that [playing] can be true to indicate that the seek was performed while
  /// playing, or false to indicate that the seek was performed while paused.
  final bool? playing;

  /// The list of currently enabled controls which should be shown in the media
  /// notification. Each control represents a clickable button with a
  /// [MediaAction] that must be one of:
  ///
  /// * [MediaAction.stop]
  /// * [MediaAction.pause]
  /// * [MediaAction.play]
  /// * [MediaAction.rewind]
  /// * [MediaAction.skipToPrevious]
  /// * [MediaAction.skipToNext]
  /// * [MediaAction.fastForward]
  /// * [MediaAction.playPause]
  final List<MediaControlMessage> controls;

  /// Up to 3 indices of the [controls] that should appear in Android's compact
  /// media notification view. When the notification is expanded, all [controls]
  /// will be shown.
  final List<int>? androidCompactActionIndices;

  /// The set of system actions currently enabled. This is for specifying any
  /// other [MediaAction]s that are not supported by [controls], because they do
  /// not represent clickable buttons. For example:
  ///
  /// * [MediaAction.seek] (enable a seek bar)
  /// * [MediaAction.seekForward] (enable press-and-hold fast-forward control)
  /// * [MediaAction.seekBackward] (enable press-and-hold rewind control)
  ///
  /// Note that specifying [MediaAction.seek] in [systemActions] will enable
  /// a seek bar in both the Android notification and the iOS control center.
  /// [MediaAction.seekForward] and [MediaAction.seekBackward] have a special
  /// behaviour on iOS in which if you have already enabled the
  /// [MediaAction.skipToNext] and [MediaAction.skipToPrevious] buttons, these
  /// additional actions will allow the user to press and hold the buttons to
  /// activate the continuous seeking behaviour.
  ///
  /// When enabling the seek bar, also note that some Android devices will not
  /// render the seek bar correctly unless your
  /// [CallServiceConfig.androidNotificationIcon] is a monochrome white icon on
  /// a transparent background, and your [CallServiceConfig.notificationColor]
  /// is a non-transparent color.
  final Set<MediaActionMessage> systemActions;

  /// The time at which the playback position was last updated.
  final DateTime updateTime;

  /// The error code when [processingState] is [CallProcessingState.error].
  final int? errorCode;

  /// The error message when [processingState] is [CallProcessingState.error].
  final String? errorMessage;


  /// Creates a [PlaybackState] with given field values, and with [updateTime]
  /// defaulting to [DateTime.now()].
  PlaybackStateMessage({
    this.processingState = CallProcessingStateMessage.idle,
    this.playing = false,
    this.controls = const [],
    this.androidCompactActionIndices,
    this.systemActions = const {},
    DateTime? updateTime,
    this.errorCode,
    this.errorMessage,
  })  : assert(androidCompactActionIndices == null ||
      androidCompactActionIndices.length <= 3),
        this.updateTime = updateTime ?? DateTime.now();

  factory PlaybackStateMessage.fromMap(Map map) => PlaybackStateMessage(
    processingState:
    CallProcessingStateMessage.values[map['processingState']],
    playing: map['playing'],
    controls: [],
    androidCompactActionIndices: null,
    systemActions: (map['systemActions'] as List)
        .map((dynamic action) => MediaActionMessage.values[action as int])
        .toSet(),
    updateTime: DateTime.fromMillisecondsSinceEpoch(map['updateTime']),
    errorCode: map['errorCode'],
    errorMessage: map['errorMessage'],
  );
  Map<String, dynamic> toMap() => {
    'processingState': processingState.index,
    'playing': playing,
    'controls': controls.map((control) => control.toMap()).toList(),
    'androidCompactActionIndices': androidCompactActionIndices,
    'systemActions': systemActions.map((action) => action.index).toList(),
    'updateTime': updateTime.millisecondsSinceEpoch,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
  };
}

class AndroidPlaybackTypeMessage {
  static final local = AndroidPlaybackTypeMessage(1);
  static final remote = AndroidPlaybackTypeMessage(2);
  final int index;

  AndroidPlaybackTypeMessage(this.index);

  @override
  String toString() => '$index';
}

enum AndroidVolumeControlTypeMessage { fixed, relative, absolute }

abstract class AndroidPlaybackInfoMessage {
  Map<String, dynamic> toMap();
}

class RemoteAndroidPlaybackInfoMessage extends AndroidPlaybackInfoMessage {
  //final AndroidCallAttributes CallAttributes;
  final AndroidVolumeControlTypeMessage volumeControlType;
  final int maxVolume;
  final int volume;

  RemoteAndroidPlaybackInfoMessage({
    required this.volumeControlType,
    required this.maxVolume,
    required this.volume,
  });

  Map<String, dynamic> toMap() => {
    'playbackType': AndroidPlaybackTypeMessage.remote.index,
    'volumeControlType': volumeControlType.index,
    'maxVolume': maxVolume,
    'volume': volume,
  };

  @override
  String toString() => '${toMap()}';
}

class LocalAndroidPlaybackInfoMessage extends AndroidPlaybackInfoMessage {
  Map<String, dynamic> toMap() => {
    'playbackType': AndroidPlaybackTypeMessage.local.index,
  };

  @override
  String toString() => '${toMap()}';
}

/// The different buttons on a headset.
enum MediaButtonMessage {
  media,
  next,
  previous,
}

class MediaItemMessage {
  /// A unique id.
  final String? id;

  /// The album this media item belongs to.
  final String? album;

  /// The title of this media item.
  final String? title;

  /// The artwork for this media item as a uri.
  final Uri? artUri;

  /// Whether this is playable (i.e. not a folder).
  final bool? playable;

  /// Override the default title for display purposes.
  final String? displayTitle;

  /// Override the default subtitle for display purposes.
  final String? displaySubtitle;

  /// Override the default description for display purposes.
  final String? displayDescription;

  /// The rating of the MediaItemMessage.
  final RatingMessage? rating;

  /// A map of additional metadata for the media item.
  ///
  /// The values must be integers or strings.
  final Map<String, dynamic>? extras;

  /// Creates a [MediaItemMessage].
  ///
  /// [id], [album] and [title] must not be null, and [id] must be unique for
  /// each instance.
  const MediaItemMessage({
    required this.id,
    required this.album,
    required this.title,
    this.artUri,
    this.playable = true,
    this.displayTitle,
    this.displaySubtitle,
    this.displayDescription,
    this.rating,
    this.extras,
  });

  /// Creates a [MediaItemMessage] from a map of key/value pairs corresponding to
  /// fields of this class.
  factory MediaItemMessage.fromMap(Map raw) => MediaItemMessage(
    id: raw['id'],
    album: raw['album'],
    title: raw['title'],
    artUri: raw['artUri'] != null ? Uri.parse(raw['artUri']) : null,
    playable: raw['playable'],
    displayTitle: raw['displayTitle'],
    displaySubtitle: raw['displaySubtitle'],
    displayDescription: raw['displayDescription'],
    rating:
    raw['rating'] != null ? RatingMessage.fromMap(raw['rating']) : null,
    extras: (raw['extras'] as Map?)?.cast<String, dynamic>(),
  );

  /// Converts this [MediaItemMessage] to a map of key/value pairs corresponding to
  /// the fields of this class.
  Map<String, dynamic> toMap() => {
    'id': id,
    'album': album,
    'title': title,
    'artUri': artUri?.toString(),
    'playable': playable,
    'displayTitle': displayTitle,
    'displaySubtitle': displaySubtitle,
    'displayDescription': displayDescription,
    'rating': rating?.toMap(),
    'extras': extras,
  };
}

/// A rating to attach to a MediaItemMessage.
class RatingMessage {
  final RatingStyleMessage type;
  final dynamic value;

  const RatingMessage({required this.type, required this.value});

  /// Returns a percentage rating value greater or equal to 0.0f, or a
  /// negative value if the rating style is not percentage-based, or
  /// if it is unrated.
  double get percentRating {
    if (type != RatingStyleMessage.percentage) return -1;
    if (value < 0 || value > 100) return -1;
    return value ?? -1;
  }

  /// Returns a rating value greater or equal to 0.0f, or a negative
  /// value if the rating style is not star-based, or if it is
  /// unrated.
  int get starRating {
    if (type != RatingStyleMessage.range3stars &&
        type != RatingStyleMessage.range4stars &&
        type != RatingStyleMessage.range5stars) return -1;
    return value ?? -1;
  }

  /// Returns true if the rating is "heart selected" or false if the
  /// rating is "heart unselected", if the rating style is not [heart]
  /// or if it is unrated.
  bool get hasHeart {
    if (type != RatingStyleMessage.heart) return false;
    return value ?? false;
  }

  /// Returns true if the rating is "thumb up" or false if the rating
  /// is "thumb down", if the rating style is not [thumbUpDown] or if
  /// it is unrated.
  bool get isThumbUp {
    if (type != RatingStyleMessage.thumbUpDown) return false;
    return value ?? false;
  }

  /// Return whether there is a rating value available.
  bool get isRated => value != null;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.index,
      'value': value,
    };
  }

  // Even though this should take a Map<String, dynamic>, that makes an error.
  RatingMessage.fromMap(Map<dynamic, dynamic> raw)
      : this(type: RatingStyleMessage.values[raw['type']], value: raw['value']);

  @override
  String toString() => '${toMap()}';
}

enum RatingStyleMessage {
  /// Indicates a rating style is not supported.
  ///
  /// A Rating will never have this type, but can be used by other classes
  /// to indicate they do not support Rating.
  none,

  /// A rating style with a single degree of rating, "heart" vs "no heart".
  ///
  /// Can be used to indicate the content referred to is a favorite (or not).
  heart,

  /// A rating style for "thumb up" vs "thumb down".
  thumbUpDown,

  /// A rating style with 0 to 3 stars.
  range3stars,

  /// A rating style with 0 to 4 stars.
  range4stars,

  /// A rating style with 0 to 5 stars.
  range5stars,

  /// A rating style expressed as a percentage.
  percentage,
}

class OnPlaybackStateChangedRequest {
  final PlaybackStateMessage state;

  OnPlaybackStateChangedRequest({
    required this.state,
  });

  factory OnPlaybackStateChangedRequest.fromMap(Map map) =>
      OnPlaybackStateChangedRequest(
          state: PlaybackStateMessage.fromMap(map['state']));

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'state': state.toMap(),
  };
}


class OnMediaItemChangedRequest {
  final MediaItemMessage? mediaItem;

  OnMediaItemChangedRequest({
    required this.mediaItem,
  });

  factory OnMediaItemChangedRequest.fromMap(Map map) =>
      OnMediaItemChangedRequest(
        mediaItem: map['mediaItem'] == null
            ? null
            : MediaItemMessage.fromMap(map['mediaItem']),
      );

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'mediaItem': mediaItem?.toMap(),
  };
}

class OnNotificationClickedRequest {
  final bool clicked;

  OnNotificationClickedRequest({
    required this.clicked,
  });

  factory OnNotificationClickedRequest.fromMap(Map map) =>
      OnNotificationClickedRequest(
        clicked: map['clicked'] == null,
      );

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'clicked': clicked,
  };
}

class SetStateRequest {
  final PlaybackStateMessage state;

  SetStateRequest({
    required this.state,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'state': state.toMap(),
  };
}

class SetMediaItemRequest {
  final MediaItemMessage mediaItem;

  SetMediaItemRequest({required this.mediaItem});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'mediaItem': mediaItem.toMap(),
  };
}

class StopServiceRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class SetAndroidPlaybackInfoRequest {
  final AndroidPlaybackInfoMessage playbackInfo;

  SetAndroidPlaybackInfoRequest({required this.playbackInfo});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'playbackInfo': playbackInfo.toMap(),
  };
}

class PrepareRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class PrepareFromMediaIdRequest {
  final String? mediaId;
  final Map<String, dynamic>? extras;

  PrepareFromMediaIdRequest({required this.mediaId, this.extras});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'mediaId': mediaId,
  };
}

class PlayRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class PlayFromMediaIdRequest {
  final String? mediaId;
  final Map<String, dynamic>? extras;

  PlayFromMediaIdRequest({required this.mediaId, this.extras});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'mediaId': mediaId,
  };
}

class PlayMediaItemRequest {
  final MediaItemMessage mediaItem;

  PlayMediaItemRequest({required this.mediaItem});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'mediaItem': mediaItem.toString(),
  };
}

class PauseRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class ClickRequest {
  final MediaButtonMessage button;

  ClickRequest({required this.button});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'button': button.index,
  };
}

class StopRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class UpdateMediaItemRequest {
  final MediaItemMessage mediaItem;

  UpdateMediaItemRequest({required this.mediaItem});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'mediaItem': mediaItem.toMap(),
  };
}

class SetRatingRequest {
  final RatingMessage rating;
  final Map<String, dynamic>? extras;

  SetRatingRequest({required this.rating, this.extras});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'rating': rating.toMap(),
    'extras': extras,
  };
}

class CustomActionRequest {
  final String? name;
  final Map<String, dynamic>? extras;

  CustomActionRequest({required this.name, this.extras});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'name': name,
    'extras': extras,
  };
}

class OnTaskRemovedRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class OnNotificationDeletedRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class GetMediaItemRequest {
  final String? mediaId;

  GetMediaItemRequest({required this.mediaId});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'mediaId': mediaId,
  };
}

class GetMediaItemResponse {
  final MediaItemMessage? mediaItem;

  GetMediaItemResponse({required this.mediaItem});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'mediaItem': mediaItem?.toMap(),
  };
}

class ConfigureRequest {
  final CallServiceConfigMessage config;

  ConfigureRequest({
    required this.config,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'config': config.toMap(),
  };
}


class ConfigureResponse {
  static ConfigureResponse fromMap(Map<dynamic, dynamic>? map) =>
      ConfigureResponse();
}

class CallServiceConfigMessage {
  final bool androidResumeOnClick;
  final String androidNotificationChannelName;
  final String? androidNotificationChannelDescription;

  /// The color to use on the background of the notification on Android. This
  /// should be a non-transparent color.
  final Color? notificationColor;

  /// The icon resource to be used in the Android media notification, specified
  /// like an XML resource reference. This should be a monochrome white icon on
  /// a transparent background. The default value is `"mipmap/ic_launcher"`.
  final String androidNotificationIcon;

  /// Whether notification badges (also known as notification dots) should
  /// appear on a launcher icon when the app has an active notification.
  final bool androidShowNotificationBadge;
  final bool androidNotificationClickStartsActivity;
  final bool androidNotificationOngoing;

  /// Whether the Android service should switch to a lower priority state when
  /// playback is paused allowing the user to swipe away the notification. Note
  /// that while in this lower priority state, the operating system will also be
  /// able to kill your service at any time to reclaim resources.
  final bool androidStopForegroundOnPause;

  /// If not null, causes the artwork specified by [MediaItemMessage.artUri] to be
  /// downscaled to this maximum pixel width. If the resolution of your artwork
  /// is particularly high, this can help to conserve memory. If specified,
  /// [artDownscaleHeight] must also be specified.
  final int? artDownscaleWidth;

  /// If not null, causes the artwork specified by [MediaItemMessage.artUri] to be
  /// downscaled to this maximum pixel height. If the resolution of your artwork
  /// is particularly high, this can help to conserve memory. If specified,
  /// [artDownscaleWidth] must also be specified.
  final int? artDownscaleHeight;

  final bool preloadArtwork;

  /// Extras to report on Android in response to an `onGetRoot` request.
  final Map<String, dynamic>? androidBrowsableRootExtras;

  CallServiceConfigMessage({
    this.androidResumeOnClick = true,
    this.androidNotificationChannelName = "Notifications",
    this.androidNotificationChannelDescription,
    this.notificationColor,
    this.androidNotificationIcon = 'mipmap/ic_launcher',
    this.androidShowNotificationBadge = false,
    this.androidNotificationClickStartsActivity = true,
    this.androidNotificationOngoing = false,
    this.androidStopForegroundOnPause = true,
    this.artDownscaleWidth,
    this.artDownscaleHeight,
    this.preloadArtwork = false,
    this.androidBrowsableRootExtras,
  })  : assert((artDownscaleWidth != null) == (artDownscaleHeight != null));

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'androidResumeOnClick': androidResumeOnClick,
    'androidNotificationChannelName': androidNotificationChannelName,
    'androidNotificationChannelDescription':
    androidNotificationChannelDescription,
    'notificationColor': notificationColor?.value,
    'androidNotificationIcon': androidNotificationIcon,
    'androidShowNotificationBadge': androidShowNotificationBadge,
    'androidNotificationClickStartsActivity':
    androidNotificationClickStartsActivity,
    'androidNotificationOngoing': androidNotificationOngoing,
    'androidStopForegroundOnPause': androidStopForegroundOnPause,
    'artDownscaleWidth': artDownscaleWidth,
    'artDownscaleHeight': artDownscaleHeight,
    'preloadArtwork': preloadArtwork,
    'androidBrowsableRootExtras': androidBrowsableRootExtras,
  };
}
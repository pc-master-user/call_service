import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:rxdart/rxdart.dart';
import 'package:call_service/PlatFormInterface/MethodChannel_Call_Service.dart';
import 'package:call_service/PlatFormInterface/Platform_Channel_Call_Service.dart';

CallServicePlatform _platform = CallServicePlatform.instance;

/// The different buttons on a headset.
enum MediaButton {
  media,
  next,
  previous,
}

/// The actons associated with playing audio.
enum MediaAction {
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

/// The different states during audio processing.
enum AudioProcessingState {
  idle,
  loading,
  buffering,
  ready,
  completed,
  error,
}

/// The playback state which includes a [playing] boolean state, a processing
/// state such as [AudioProcessingState.buffering], the playback position and
/// the currently enabled actions to be shown in the Android notification or the
/// iOS control center.
class PlaybackState {
  /// The audio processing state e.g. [BasicPlaybackState.buffering].
  final AudioProcessingState processingState;

  /// Whether audio is either playing, or will play as soon as [processingState]
  /// is [AudioProcessingState.ready]. A true value should be broadcast whenever
  /// it would be appropriate for UIs to display a pause or stop button.
  ///
  /// Since [playing] and [processingState] can vary independently, it is
  /// possible distinguish a particular audio processing state while audio is
  /// playing vs paused. For example, when buffering occurs during a seek, the
  /// [processingState] can be [AudioProcessingState.buffering], but alongside
  /// that [playing] can be true to indicate that the seek was performed while
  /// playing, or false to indicate that the seek was performed while paused.
  final bool playing;

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
  final List<MediaControl> controls;

  /// Up to 3 indices of the [controls] that should appear in Android's compact
  /// media notification view. When the notification is expanded, all [controls]
  /// will be shown.
  final List<int> androidCompactActionIndices;

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
  /// [AudioServiceConfig.androidNotificationIcon] is a monochrome white icon on
  /// a transparent background, and your [AudioServiceConfig.notificationColor]
  /// is a non-transparent color.
  final Set<MediaAction> systemActions;

  /// The error code when [processingState] is [AudioProcessingState.error].
  final int errorCode;

  /// The error message when [processingState] is [AudioProcessingState.error].
  final String errorMessage;

  /// Creates a [PlaybackState] with given field values, and with [updateTime]
  /// defaulting to [DateTime.now()].
  PlaybackState({
    this.processingState = AudioProcessingState.idle,
    this.playing = false,
    this.controls = const [],
    this.androidCompactActionIndices,
    this.systemActions = const {},
    DateTime updateTime,
    this.errorCode,
    this.errorMessage,
  })  : assert(androidCompactActionIndices == null ||
      androidCompactActionIndices.length <= 3);

  /// Creates a copy of this state with given fields replaced by new values,
  /// with [updateTime] set to [DateTime.now()], and unless otherwise replaced,
  /// with [updatePosition] set to [this.position]. [errorCode] and
  /// [errorMessage] will be set to null unless [processingState] is
  /// [AudioProcessingState.error].
  PlaybackState copyWith({
    AudioProcessingState processingState,
    bool playing,
    List<MediaControl> controls,
    List<int> androidCompactActionIndices,
    Set<MediaAction> systemActions,
    int errorCode,
    String errorMessage,
  }) {
    processingState ??= this.processingState;
    return PlaybackState(
      processingState: processingState,
      playing: playing ?? this.playing,
      controls: controls ?? this.controls,
      androidCompactActionIndices:
      androidCompactActionIndices ?? this.androidCompactActionIndices,
      systemActions: systemActions ?? this.systemActions,
      errorCode: processingState != AudioProcessingState.error
          ? null
          : (errorCode ?? this.errorCode),
      errorMessage: processingState != AudioProcessingState.error
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }

  PlaybackStateMessage _toMessage() => PlaybackStateMessage(
    processingState:
    AudioProcessingStateMessage.values[processingState.index],
    playing: playing,
    controls: controls.map((control) => control._toMessage()).toList(),
    androidCompactActionIndices: androidCompactActionIndices,
    systemActions: systemActions
        .map((action) => MediaActionMessage.values[action.index])
        .toSet(),
    errorCode: errorCode,
    errorMessage: errorMessage,
  );
}

enum RatingStyle {
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

/// A rating to attach to a MediaItem.
class Rating {
  final RatingStyle _type;
  final dynamic _value;

  const Rating._internal(this._type, this._value);

  /// Creates a new heart rating.
  const Rating.newHeartRating(bool hasHeart)
      : this._internal(RatingStyle.heart, hasHeart);

  /// Creates a new percentage rating.
  factory Rating.newPercentageRating(double percent) {
    if (percent < 0 || percent > 100) throw ArgumentError();
    return Rating._internal(RatingStyle.percentage, percent);
  }

  /// Creates a new star rating.
  factory Rating.newStarRating(RatingStyle starRatingStyle, int starRating) {
    if (starRatingStyle != RatingStyle.range3stars &&
        starRatingStyle != RatingStyle.range4stars &&
        starRatingStyle != RatingStyle.range5stars) {
      throw ArgumentError();
    }
    if (starRating > starRatingStyle.index || starRating < 0)
      throw ArgumentError();
    return Rating._internal(starRatingStyle, starRating);
  }

  /// Creates a new thumb rating.
  const Rating.newThumbRating(bool isThumbsUp)
      : this._internal(RatingStyle.thumbUpDown, isThumbsUp);

  /// Creates a new unrated rating.
  const Rating.newUnratedRating(RatingStyle ratingStyle)
      : this._internal(ratingStyle, null);

  /// Return the rating style.
  RatingStyle getRatingStyle() => _type;

  /// Returns a percentage rating value greater or equal to 0.0f, or a
  /// negative value if the rating style is not percentage-based, or
  /// if it is unrated.
  double getPercentRating() {
    if (_type != RatingStyle.percentage) return -1;
    if (_value < 0 || _value > 100) return -1;
    return _value ?? -1;
  }

  /// Returns a rating value greater or equal to 0.0f, or a negative
  /// value if the rating style is not star-based, or if it is
  /// unrated.
  int getStarRating() {
    if (_type != RatingStyle.range3stars &&
        _type != RatingStyle.range4stars &&
        _type != RatingStyle.range5stars) return -1;
    return _value ?? -1;
  }

  /// Returns true if the rating is "heart selected" or false if the
  /// rating is "heart unselected", if the rating style is not [heart]
  /// or if it is unrated.
  bool hasHeart() {
    if (_type != RatingStyle.heart) return false;
    return _value ?? false;
  }

  /// Returns true if the rating is "thumb up" or false if the rating
  /// is "thumb down", if the rating style is not [thumbUpDown] or if
  /// it is unrated.
  bool isThumbUp() {
    if (_type != RatingStyle.thumbUpDown) return false;
    return _value ?? false;
  }

  /// Return whether there is a rating value available.
  bool isRated() => _value != null;

  RatingMessage _toMessage() => RatingMessage(
      type: RatingStyleMessage.values[_type.index], value: _value);
}

/// Metadata about an audio item that can be played, or a folder containing
/// audio items.
class MediaItem {
  /// A unique id.
  final String id;

  /// The album this media item belongs to.
  final String album;

  /// The title of this media item.
  final String title;

  /// The artwork for this media item as a uri.
  final Uri artUri;

  /// Whether this is playable (i.e. not a folder).
  final bool playable;

  /// Override the default title for display purposes.
  final String displayTitle;

  /// Override the default subtitle for display purposes.
  final String displaySubtitle;

  /// Override the default description for display purposes.
  final String displayDescription;

  /// The rating of the MediaItem.
  final Rating rating;

  /// A map of additional metadata for the media item.
  ///
  /// The values must be integers or strings.
  final Map<String, dynamic> extras;

  /// Creates a [MediaItem].
  ///
  /// [id], [album] and [title] must not be null, and [id] must be unique for
  /// each instance.
  const MediaItem({
    @required this.id,
    @required this.album,
    @required this.title,
    this.artUri,
    this.playable = true,
    this.displayTitle,
    this.displaySubtitle,
    this.displayDescription,
    this.rating,
    this.extras,
  });

  /// Creates a copy of this [MediaItem] with with the given fields replaced by
  /// new values.
  MediaItem copyWith({
    String id,
    String album,
    String title,
    Uri artUri,
    bool playable,
    String displayTitle,
    String displaySubtitle,
    String displayDescription,
    Rating rating,
    Map<String, dynamic> extras,
  }) =>
      MediaItem(
        id: id ?? this.id,
        album: album ?? this.album,
        title: title ?? this.title,
        artUri: artUri ?? this.artUri,
        playable: playable ?? this.playable,
        displayTitle: displayTitle ?? this.displayTitle,
        displaySubtitle: displaySubtitle ?? this.displaySubtitle,
        displayDescription: displayDescription ?? this.displayDescription,
        rating: rating ?? this.rating,
        extras: extras ?? this.extras,
      );

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(dynamic other) => other is MediaItem && other.id == id;

  MediaItemMessage _toMessage() => MediaItemMessage(
    id: id,
    album: album,
    title: title,
    artUri: artUri,
    playable: playable,
    displayTitle: displayTitle,
    displaySubtitle: displaySubtitle,
    displayDescription: displayDescription,
    rating: rating?._toMessage(),
    extras: extras,
  );
}

/// A button to appear in the Android notification, lock screen, Android smart
/// watch, or Android Auto device. The set of buttons you would like to display
/// at any given moment should be streamed via [AudioHandler.playbackState].
///
/// Each [MediaControl] button controls a specified [MediaAction]. Only the
/// following actions can be represented as buttons:
///
/// * [MediaAction.stop]
/// * [MediaAction.pause]
/// * [MediaAction.play]
/// * [MediaAction.rewind]
/// * [MediaAction.skipToPrevious]
/// * [MediaAction.skipToNext]
/// * [MediaAction.fastForward]
/// * [MediaAction.playPause]
///
/// Predefined controls with default Android icons and labels are defined as
/// static fields of this class. If you wish to define your own custom Android
/// controls with your own icon resources, you will need to place the Android
/// resources in `android/app/src/main/res`. Here, you will find a subdirectory
/// for each different resolution:
///
/// ```
/// drawable-hdpi
/// drawable-mdpi
/// drawable-xhdpi
/// drawable-xxhdpi
/// drawable-xxxhdpi
/// ```
///
/// You can use [Android Asset
/// Studio](https://romannurik.github.io/AndroidAssetStudio/) to generate these
/// different subdirectories for any standard material design icon.
class MediaControl {
  /// A default control for [MediaAction.stop].
  static final stop = MediaControl(
    androidIcon: 'drawable/audio_service_stop',
    label: 'stop',
    action: MediaAction.stop,
  );

  /// A default control for [MediaAction.pause].
  static final pause = MediaControl(
    androidIcon: 'drawable/audio_service_pause',
    label: 'Pause',
    action: MediaAction.pause,
  );

  /// A default control for [MediaAction.play].
  static final play = MediaControl(
    androidIcon: 'drawable/audio_service_play_arrow',
    label: 'Play',
    action: MediaAction.play,
  );

  /// A reference to an Android icon resource for the control (e.g.
  /// `"drawable/ic_action_pause"`)
  final String androidIcon;

  /// A label for the control
  final String label;

  /// The action to be executed by this control
  final MediaAction action;

  const MediaControl({
    @required this.androidIcon,
    @required this.label,
    @required this.action,
  });

  MediaControlMessage _toMessage() => MediaControlMessage(
    androidIcon: androidIcon,
    label: label,
    action: MediaActionMessage.values[action.index],
  );
}

/// Provides an API to manage the app's [AudioHandler]. An app must call [init]
/// during initialisation to register the [AudioHandler] that will service all
/// requests to play audio.
class AudioService {
  /// The cache to use when loading artwork. Defaults to [DefaultCacheManager].
  static BaseCacheManager get cacheManager => _cacheManager;
  static BaseCacheManager _cacheManager;

  static  CallServiceConfig _config;
  static  AudioHandler _handler;

  /// The current configuration.
  static CallServiceConfig get config => _config;

  /// The root media ID for browsing media provided by the background
  /// task.
  static const String browsableRootId = 'root';

  /// The root media ID for browsing the most recently played item(s).
  static const String recentRootId = 'recent';

  // ignore: close_sinks
  static final BehaviorSubject<bool> _notificationClickEvent =
  BehaviorSubject.seeded(false);

  /// A stream that broadcasts the status of the notificationClick event.
  static ValueStream<bool> get notificationClickEvent =>
      _notificationClickEvent;

  static ReceivePort _customActionReceivePort;

  /// Connect to the [AudioHandler] from another isolate. The [AudioHandler]
  /// must have been initialised via [init] prior to connecting.
  static Future<AudioHandler> connectFromIsolate() async {
    WidgetsFlutterBinding.ensureInitialized();
    return _IsolateAudioHandler();
  }

  /// Register the app's [AudioHandler] with configuration options. This must be
  /// called during the app's initialisation so that it is prepared to handle
  /// audio requests immediately after a cold restart (e.g. if the user clicks
  /// on the play button in the media notification while your app is not running
  /// and your app needs to be woken up).
  ///
  /// You may optionally specify a [cacheManager] to use when loading artwork to
  /// display in the media notification and lock screen. This defaults to
  /// [DefaultCacheManager].
  static Future<T> init<T extends AudioHandler>({
    @required T builder(),
    CallServiceConfig config,
    BaseCacheManager cacheManager,
  }) async {
    assert(_cacheManager == null);
    config ??= CallServiceConfig();
    print("### AudioService.init");
    WidgetsFlutterBinding.ensureInitialized();
    _cacheManager = (cacheManager ??= DefaultCacheManager());
    await _platform.configure(ConfigureRequest(config: config._toMessage()));
    _config = config;
    final handler = builder();
    _handler = handler;

    _platform.setHandlerCallbacks(_HandlerCallbacks(handler));
    // This port listens to connections from other isolates.
    _customActionReceivePort = ReceivePort();
    _customActionReceivePort.listen((dynamic event) async {
      final request = event as _IsolateRequest;
      switch (request.method) {
        case 'prepare':
          await _handler.prepare();
          request.sendPort.send(null);
          break;
        case 'prepareFromMediaId':
          await _handler.prepareFromMediaId(
              request.arguments[0], request.arguments[1]);
          request.sendPort.send(null);
          break;
        case 'play':
          await _handler.play();
          request.sendPort.send(null);
          break;
        case 'playFromMediaId':
          await _handler.playFromMediaId(
              request.arguments[0], request.arguments[1]);
          request.sendPort.send(null);
          break;
        case 'playMediaItem':
          await _handler.playMediaItem(request.arguments[0]);
          request.sendPort.send(null);
          break;
        case 'pause':
          await _handler.pause();
          request.sendPort.send(null);
          break;
        case 'click':
          await _handler.click(request.arguments[0]);
          request.sendPort.send(null);
          break;
        case 'stop':
          await _handler.stop();
          request.sendPort.send(null);
          break;
        case 'updateMediaItem':
          await _handler.updateMediaItem(request.arguments[0]);
          request.sendPort.send(null);
          break;
        case 'setRating':
          await _handler.setRating(
              request.arguments[0], request.arguments[1]);
          request.sendPort.send(null);
          break;
        case 'customAction':
          await _handler.customAction(
              request.arguments[0], request.arguments[1]);
          request.sendPort.send(null);
          break;
        case 'onTaskRemoved':
          await _handler.onTaskRemoved();
          request.sendPort.send(null);
          break;
        case 'onNotificationDeleted':
          await _handler.onNotificationDeleted();
          request.sendPort.send(null);
          break;
        case 'getMediaItem':
          request.sendPort
              .send(await _handler.getMediaItem(request.arguments[0]));
          break;
      }
    });
    //IsolateNameServer.removePortNameMapping(_isolatePortName);
    IsolateNameServer.registerPortWithName(
        _customActionReceivePort.sendPort, _isolatePortName);
    _handler.mediaItem.listen((MediaItem mediaItem) async {
      if (mediaItem == null) return;
      final artUri = mediaItem.artUri;
      if (artUri != null) {
        // We potentially need to fetch the art.
        String filePath;
        if (artUri.scheme == 'file') {
          filePath = artUri.toFilePath();
        } else {
          final FileInfo fileInfo =
          await cacheManager.getFileFromMemory(artUri.toString());
          filePath = fileInfo.file.path;
          if (filePath == null) {
            // We haven't fetched the art yet, so show the metadata now, and again
            // after we load the art.
            await _platform.setMediaItem(
                SetMediaItemRequest(mediaItem: mediaItem._toMessage()));
            // Load the art
            filePath = await _loadArtwork(mediaItem);
            // If we failed to download the art, abort.
            if (filePath == null) return;
            // If we've already set a new media item, cancel this request.
            // XXX: Test this
            //if (mediaItem != _handler.mediaItem.value) return;
          }
        }
        final extras = Map.of(mediaItem.extras ?? <String, dynamic>{});
        extras['artCacheFile'] = filePath;
        final platformMediaItem = mediaItem.copyWith(extras: extras);
        // Show the media item after the art is loaded.
        await _platform.setMediaItem(
            SetMediaItemRequest(mediaItem: platformMediaItem._toMessage()));
      } else {
        await _platform.setMediaItem(
            SetMediaItemRequest(mediaItem: mediaItem._toMessage()));
      }
    });
    _handler.androidPlaybackInfo
        .listen((AndroidPlaybackInfo playbackInfo) async {
      await _platform.setAndroidPlaybackInfo(SetAndroidPlaybackInfoRequest(
          playbackInfo: playbackInfo._toMessage()));
    });
    _handler.playbackState.listen((PlaybackState playbackState) async {
      await _platform
          .setState(SetStateRequest(state: playbackState._toMessage()));
    });

    return handler;
  }

  /// Stops the service.
  static Future<void> _stop() async {
    final audioSession = await AudioSession.instance;
    try {
      await audioSession.setActive(false);
    } catch (e) {
      print("While deactivating audio session: $e");
    }
    await _platform.stopService(StopServiceRequest());
  }

  static Future<void> _loadAllArtwork(List<MediaItem> queue) async {
    for (var mediaItem in queue) {
      await _loadArtwork(mediaItem);
    }
  }

  static Future<String> _loadArtwork(MediaItem mediaItem) async {
    try {
      final artUri = mediaItem.artUri;
      if (artUri != null) {
        if (artUri.scheme == 'file') {
          return artUri.toFilePath();
        } else {
          final file =
          await cacheManager.getSingleFile(mediaItem.artUri.toString());
          return file.path;
        }
      }
    } catch (e) {}
    return null;
  }

  // DEPRECATED members

  /// Deprecated. Use [AudioHandler.playbackState] instead.
  @deprecated
  static ValueStream<PlaybackState> get playbackStateStream =>
      _handler.playbackState;

  /// Deprecated. Use [AudioHandler.playbackState.value] instead.
  @deprecated
  static PlaybackState get playbackState =>
      _handler.playbackState.value ?? PlaybackState();

  /// Deprecated. Use [AudioHandler.mediaItem] instead.
  @deprecated
  static ValueStream<MediaItem> get currentMediaItemStream =>
      _handler.mediaItem;

  /// Deprecated. Use [AudioHandler.mediaItem.value] instead.
  @deprecated
  static MediaItem get currentMediaItem => _handler.mediaItem.value;

  /// Deprecated. Use [AudioHandler.customEvent] instead.
  @deprecated
  static Stream<dynamic> get customEventStream => _handler.customEvent;

  /// Deprecated. Use [AudioHandler.playbackState] instead.
  @deprecated
  static ValueStream<bool> get runningStream => playbackStateStream
      .map((state) => state.processingState != AudioProcessingState.idle)
  as ValueStream<bool>;

  /// Deprecated. Use [AudioHandler.playbackState.value.processingState] instead.
  @deprecated
  static bool get running => runningStream.value ?? false;

  /// Deprecated. Use [AudioHandler.updateMediaItem] instead.
  @deprecated
  static final updateMediaItem = _handler.updateMediaItem;

  /// Deprecated. Use [AudioHandler.click] instead.
  @deprecated
  static final Future<void> Function([MediaButton]) click = _handler.click;

  /// Deprecated. Use [AudioHandler.prepare] instead.
  @deprecated
  static final prepare = _handler.prepare;

  /// Deprecated. Use [AudioHandler.prepareFromMediaId] instead.
  @deprecated
  static final Future<void> Function(String, [Map<String, dynamic>])
  prepareFromMediaId = _handler.prepareFromMediaId;

  /// Deprecated. Use [AudioHandler.play] instead.
  @deprecated
  static final play = _handler.play;

  /// Deprecated. Use [AudioHandler.playFromMediaId] instead.
  @deprecated
  static final Future<void> Function(String, [Map<String, dynamic>])
  playFromMediaId = _handler.playFromMediaId;

  /// Deprecated. Use [AudioHandler.playMediaItem] instead.
  @deprecated
  static final playMediaItem = _handler.playMediaItem;

  /// Deprecated. Use [AudioHandler.pause] instead.
  @deprecated
  static final pause = _handler.pause;

  /// Deprecated. Use [AudioHandler.stop] instead.
  @deprecated
  static final stop = _handler.stop;

  /// Deprecated. Use [AudioHandler.setRating] instead.
  @deprecated
  static final Future<void> Function(Rating, Map<dynamic, dynamic>) setRating =
      _handler.setRating;

  /// Deprecated. Use [AudioHandler.customAction] instead.
  @deprecated
  static final Future<dynamic> Function(String, Map<String, dynamic>)
  customAction = _handler.customAction;
}

/// An [AudioHandler] plays audio, provides state updates and query results to
/// clients. It implements standard protocols that allow it to be remotely
/// controlled by the lock screen, media notifications, the iOS control center,
/// headsets, smart watches, car audio systems, and other compatible agents.
///
/// This class cannot be subclassed directly. Implementations should subclass
/// [BaseAudioHandler], and composite behaviours should be defined as subclasses
/// of [CompositeAudioHandler].
abstract class AudioHandler {
  AudioHandler._();

  /// Prepare media items for playback.
  Future<void> prepare();

  /// Prepare a specific media item for playback.
  Future<void> prepareFromMediaId(String mediaId,
      [Map<String, dynamic> extras]);

  /// Start or resume playback.
  Future<void> play();

  /// Play a specific media item.
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic> extras]);

  /// Play a specific media item.
  Future<void> playMediaItem(MediaItem mediaItem);

  /// Pause playback.
  Future<void> pause();

  /// Process a headset button click, where [button] defaults to
  /// [MediaButton.media].
  Future<void> click([MediaButton button = MediaButton.media]);

  /// Stop playback and release resources.
  Future<void> stop();

  /// Update the properties of [mediaItem].
  Future<void> updateMediaItem(MediaItem mediaItem);

  /// Set the rating.
  Future<void> setRating(Rating rating, Map<dynamic, dynamic> extras);

  /// A mechanism to support app-specific actions.
  Future<dynamic> customAction(String name, Map<String, dynamic> extras);

  /// Handle the task being swiped away in the task manager (Android).
  Future<void> onTaskRemoved();

  /// Handle the notification being swiped away (Android).
  Future<void> onNotificationDeleted();

  /// Get a particular media item.
  Future<MediaItem> getMediaItem(String mediaId);

  /// A value stream of playback states.
  ValueStream<PlaybackState> get playbackState;
  
  /// A value stream of the current queueTitle.
  ValueStream<String> get queueTitle;

  /// A value stream of the current media item.
  ValueStream<MediaItem> get mediaItem;

  /// A value stream of the current rating style.
  ValueStream<RatingStyle> get ratingStyle;

  /// A value stream of the current [AndroidPlaybackInfo].
  ValueStream<AndroidPlaybackInfo> get androidPlaybackInfo;

  /// A stream of custom events.
  Stream<dynamic> get customEvent;

  /// A stream of custom states.
  ValueStream<dynamic> get customState;
}

/// A [SwitchAudioHandler] wraps another [AudioHandler] that may be switched for
/// another at any time by setting [inner].
class SwitchAudioHandler extends CompositeAudioHandler {
  @override
  // ignore: close_sinks
  final BehaviorSubject<PlaybackState> playbackState = BehaviorSubject();
  @override
  // ignore: close_sinks
  final BehaviorSubject<String> queueTitle = BehaviorSubject();
  @override
  // ignore: close_sinks
  final BehaviorSubject<MediaItem> mediaItem = BehaviorSubject();
  @override
  // ignore: close_sinks
  final BehaviorSubject<AndroidPlaybackInfo> androidPlaybackInfo =
  BehaviorSubject();
  @override
  // ignore: close_sinks
  final BehaviorSubject<RatingStyle> ratingStyle = BehaviorSubject();
  @override
  // ignore: close_sinks
  final PublishSubject<dynamic> customEvent = PublishSubject<dynamic>();
  @override
  // ignore: close_sinks
  final BehaviorSubject<dynamic> customState = BehaviorSubject();

  StreamSubscription<PlaybackState> playbackStateSubscription;
  StreamSubscription<String> queueTitleSubscription;
  StreamSubscription<MediaItem> mediaItemSubscription;
  StreamSubscription<AndroidPlaybackInfo> androidPlaybackInfoSubscription;
  StreamSubscription<RatingStyle> ratingStyleSubscription;
  StreamSubscription<dynamic> customEventSubscription;
  StreamSubscription<dynamic> customStateSubscription;

  SwitchAudioHandler(AudioHandler inner) : super(inner) {
    this.inner = inner;
  }

  /// The current inner [AudioHandler] that this [SwitchAudioHandler] will
  /// delegate to.
  AudioHandler get inner => _inner;

  set inner(AudioHandler newInner) {
    // Should disallow all ancestors...
    assert(newInner != this);
    playbackStateSubscription?.cancel();
    queueTitleSubscription?.cancel();
    mediaItemSubscription?.cancel();
    androidPlaybackInfoSubscription?.cancel();
    ratingStyleSubscription?.cancel();
    customEventSubscription?.cancel();
    customStateSubscription?.cancel();
    _inner = newInner;
    playbackStateSubscription = inner.playbackState.listen(playbackState.add);
    queueTitleSubscription = inner.queueTitle.listen(queueTitle.add);
    mediaItemSubscription = inner.mediaItem.listen(mediaItem.add);
    androidPlaybackInfoSubscription =
        inner.androidPlaybackInfo.listen(androidPlaybackInfo.add);
    ratingStyleSubscription = inner.ratingStyle.listen(ratingStyle.add);
    customEventSubscription = inner.customEvent.listen(customEvent.add);
    customStateSubscription = inner.customState.listen(customState.add);
  }
}

/// A [CompositeAudioHandler] wraps another [AudioHandler] and adds additional
/// behaviour to it. Each method will by default pass through to the
/// corresponding method of the wrapped handler. If you override a method, it
/// must call super in addition to any "additional" functionality you add.
class CompositeAudioHandler extends AudioHandler {
  AudioHandler _inner;

  /// Create the [CompositeAudioHandler] with the given wrapped handler.
  CompositeAudioHandler(AudioHandler inner)
      : _inner = inner,
        super._();

  @override
  @mustCallSuper
  Future<void> prepare() => _inner.prepare();

  @override
  @mustCallSuper
  Future<void> prepareFromMediaId(String mediaId,
      [Map<String, dynamic> extras]) =>
      _inner.prepareFromMediaId(mediaId, extras);
  
  @override
  @mustCallSuper
  Future<void> play() => _inner.play();

  @override
  @mustCallSuper
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic> extras]) =>
      _inner.playFromMediaId(mediaId, extras);

  @override
  @mustCallSuper
  Future<void> playMediaItem(MediaItem mediaItem) =>
      _inner.playMediaItem(mediaItem);

  @override
  @mustCallSuper
  Future<void> pause() => _inner.pause();

  @override
  @mustCallSuper
  Future<void> click([MediaButton button = MediaButton.media]) =>
      _inner.click(button);

  @override
  @mustCallSuper
  Future<void> stop() => _inner.stop();

  @override
  @mustCallSuper
  Future<void> updateMediaItem(MediaItem mediaItem) =>
      _inner.updateMediaItem(mediaItem);

  @override
  @mustCallSuper
  Future<void> setRating(Rating rating, Map<dynamic, dynamic> extras) =>
      _inner.setRating(rating, extras);

  @override
  @mustCallSuper
  Future<dynamic> customAction(String name, Map<String, dynamic> extras) =>
      _inner.customAction(name, extras);

  @override
  @mustCallSuper
  Future<void> onTaskRemoved() => _inner.onTaskRemoved();

  @override
  @mustCallSuper
  Future<void> onNotificationDeleted() => _inner.onNotificationDeleted();

  @override
  @mustCallSuper
  Future<MediaItem> getMediaItem(String mediaId) =>
      _inner.getMediaItem(mediaId);

  @override
  ValueStream<PlaybackState> get playbackState => _inner.playbackState;

  @override
  ValueStream<String> get queueTitle => _inner.queueTitle;

  @override
  ValueStream<MediaItem> get mediaItem => _inner.mediaItem;

  @override
  ValueStream<RatingStyle> get ratingStyle => _inner.ratingStyle;

  @override
  ValueStream<AndroidPlaybackInfo> get androidPlaybackInfo =>
      _inner.androidPlaybackInfo;

  @override
  Stream<dynamic> get customEvent => _inner.customEvent;

  @override
  ValueStream<dynamic> get customState => _inner.customState;
}

class _IsolateRequest {
  /// The send port for sending the response of this request.
  final SendPort sendPort;
  final String method;
  final List<dynamic> arguments;

  _IsolateRequest(this.sendPort, this.method, [this.arguments]);
}

const _isolatePortName = 'com.ryanheise.audioservice.port';

class _IsolateAudioHandler extends AudioHandler {

  @override
  // ignore: close_sinks
  final BehaviorSubject<PlaybackState> playbackState =
  BehaviorSubject.seeded(PlaybackState());

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) =>
      _send('updateMediaItem', [mediaItem]);

  @override
  // TODO
  // ignore: close_sinks
  final BehaviorSubject<String> queueTitle = BehaviorSubject.seeded('');
  @override
  // ignore: close_sinks
  final BehaviorSubject<MediaItem> mediaItem = BehaviorSubject.seeded(null);
  @override
  // TODO
  // ignore: close_sinks
  final BehaviorSubject<AndroidPlaybackInfo> androidPlaybackInfo =
  BehaviorSubject();
  @override
  // TODO
  // ignore: close_sinks
  final BehaviorSubject<RatingStyle> ratingStyle = BehaviorSubject();
  @override
  // TODO
  // ignore: close_sinks
  final PublishSubject<dynamic> customEvent = PublishSubject<dynamic>();

  @override
  // TODO
  // ignore: close_sinks
  final BehaviorSubject<dynamic> customState = BehaviorSubject();

  _IsolateAudioHandler() : super._() {
    _platform.setClientCallbacks(_ClientCallbacks(this));
  }

  @override
  Future<void> prepare() => _send('prepare');

  @override
  Future<void> prepareFromMediaId(String mediaId,
      [Map<String, dynamic> extras]) =>
      _send('prepareFromMediaId', [mediaId, extras]);

  @override
  Future<void> play() => _send('play');

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic> extras]) =>
      _send('playFromMediaId', [mediaId, extras]);

  @override
  Future<void> playMediaItem(MediaItem mediaItem) =>
      _send('playMediaItem', [mediaItem]);

  @override
  Future<void> pause() => _send('pause');

  @override
  Future<void> click([MediaButton button = MediaButton.media]) =>
      _send('click', [button]);

  @override
  @mustCallSuper
  Future<void> stop() => _send('stop');

  @override
  Future<void> setRating(Rating rating, Map<dynamic, dynamic> extras) =>
      _send('setRating', [rating, extras]);
  

  @override
  Future<dynamic> customAction(String name, Map<String, dynamic> arguments) =>
      _send('customAction', [name, arguments]);

  @override
  Future<void> onTaskRemoved() => _send('onTaskRemoved');

  @override
  Future<void> onNotificationDeleted() => _send('onNotificationDeleted');

  @override
  Future<MediaItem> getMediaItem(String mediaId) async =>
      (await _send('getMediaItem', [mediaId])) as MediaItem;
  

  Future<dynamic> _send(String method, [List<dynamic> arguments]) async {
    final sendPort = IsolateNameServer.lookupPortByName(_isolatePortName);
    if (sendPort == null) return null;
    final receivePort = ReceivePort();
    sendPort.send(_IsolateRequest(receivePort.sendPort, method, arguments));
    final result = await receivePort.first;
    print("isolate result received: $result");
    receivePort.close();
    return result;
  }
}

/// Base class for implementations of [AudioHandler]. It provides default
/// implementations of all methods and provides controllers for emitting stream
/// events:
///
/// * [playbackStateSubject] is a [BehaviorSubject] that emits events to
/// [playbackStateStream].
/// * [queueSubject] is a [BehaviorSubject] that emits events to [queueStream].
/// * [mediaItemSubject] is a [BehaviorSubject] that emits events to
/// [mediaItemStream].
/// * [customEventSubject] is a [PublishSubject] that emits events to
/// [customEvent].
///
/// You can choose to implement all methods yourself, or you may leverage some
/// mixins to provide default implementations of certain behaviours:
///
/// * [QueueHandler] provides default implementations of methods for updating
/// and navigating the queue.
/// * [SeekHandler] provides default implementations of methods for seeking
/// forwards and backwards.
///
/// ## Android service lifecycle and state transitions
///
/// On Android, the [AudioHandler] runs inside an Android service. This allows
/// the audio logic to continue running in the background, and also an app that
/// had previously been terminated to wake up and resume playing audio when the
/// user click on the play button in a media notification or headset.
///
/// ### Foreground/background transitions
///
/// The underlying Android service enters the `foreground` state whenever
/// [PlaybackState.playing] becomes `true`, and enters the `background` state
/// whenever [PlaybackState.playing] becomes `false`.
///
/// ### Start/stop transitions
///
/// The underlying Android service enters the `started` state whenever
/// [PlaybackState.playing] becomes `true`, and enters the `stopped` state
/// whenever [stop] is called. If you override [stop], you must call `super` to
/// ensure that the service is stopped.
///
/// ### Create/destroy lifecycle
///
/// The underlying service is created either when a client binds to it, or when
/// it is started, and it is destroyed when no clients are bound to it AND it is
/// stopped. When the Flutter UI is attached to an Android Activity, this will
/// also bind to the service, and it will unbind from the service when the
/// Activity is destroyed. A media notification will also bind to the service.
///
/// If the service needs to be created when the app is not already running, your
/// app's `main` entrypoint will be called in the background which should
/// initialise your [AudioHandler].
class BaseAudioHandler extends AudioHandler {
  /// A controller for broadcasting the current [PlaybackState] to the app's UI,
  /// media notification and other clients. Example usage:
  ///
  /// ```dart
  /// playbackState.add(playbackState.copyWith(playing: true));
  /// ```
  @override
  // ignore: close_sinks
  final BehaviorSubject<PlaybackState> playbackState =
  BehaviorSubject.seeded(PlaybackState());

  /// A controller for broadcasting the current queue title to the app's UI, media
  /// notification and other clients. Example usage:
  ///
  /// ```dart
  /// queueTitle.add(newTitle);
  /// ```
  @override
  // ignore: close_sinks
  final BehaviorSubject<String> queueTitle = BehaviorSubject.seeded('');

  /// A controller for broadcasting the current media item to the app's UI,
  /// media notification and other clients. Example usage:
  ///
  /// ```dart
  /// mediaItem.add(item);
  /// ```
  @override
  // ignore: close_sinks
  final BehaviorSubject<MediaItem> mediaItem = BehaviorSubject.seeded(null);

  /// A controller for broadcasting the current [AndroidPlaybackInfo] to the app's UI,
  /// media notification and other clients. Example usage:
  ///
  /// ```dart
  /// androidPlaybackInfo.add(newPlaybackInfo);
  /// ```
  @override
  // ignore: close_sinks
  final BehaviorSubject<AndroidPlaybackInfo> androidPlaybackInfo =
  BehaviorSubject();

  /// A controller for broadcasting the current rating style to the app's UI,
  /// media notification and other clients. Example usage:
  ///
  /// ```dart
  /// ratingStyle.add(item);
  /// ```
  @override
  // ignore: close_sinks
  final BehaviorSubject<RatingStyle> ratingStyle = BehaviorSubject();

  /// A controller for broadcasting a custom event to the app's UI. Example
  /// usage:
  ///
  /// ```dart
  /// customEventSubject.add(MyCustomEvent(arg: 3));
  /// ```
  @protected
  // ignore: close_sinks
  final customEventSubject = PublishSubject<dynamic>();

  /// A controller for broadcasting the current custom state to the app's UI.
  /// Example usage:
  ///
  /// ```dart
  /// customState.add(MyCustomState(...));
  /// ```
  @override
  // ignore: close_sinks
  final BehaviorSubject<dynamic> customState = BehaviorSubject();

  BaseAudioHandler() : super._();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> prepareFromMediaId(String mediaId,
      [Map<String, dynamic> extras]) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic> extras]) async {}

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        if (playbackState.value?.playing == true) {
          await pause();
        } else {
          await play();
        }
        break;
      case MediaButton.next:
        //await skipToNext();
        break;
      case MediaButton.previous:
        //await skipToPrevious();
        break;
    }
  }

  @override
  @mustCallSuper
  Future<void> stop() async {
    await AudioService._stop();
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {}

  @override
  Future<void> setRating(Rating rating, Map<dynamic, dynamic> extras) async {}

  @override
  Future<dynamic> customAction(
      String name, Map<String, dynamic> arguments) async {}

  @override
  Future<void> onTaskRemoved() async {}

  @override
  Future<void> onNotificationDeleted() async {
    await stop();
  }

  @override
  Future<MediaItem> getMediaItem(String mediaId) async => null;

  @override
  Stream<dynamic> get customEvent => customEventSubject.stream;
}

/// The configuration options to use when registering an [AudioHandler].
class CallServiceConfig {
  final bool androidResumeOnClick;
  final String androidNotificationChannelName;
  final String androidNotificationChannelDescription;

  /// The color to use on the background of the notification on Android. This
  /// should be a non-transparent color.
  final Color notificationColor;

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

  /// If not null, causes the artwork specified by [MediaItem.artUri] to be
  /// downscaled to this maximum pixel width. If the resolution of your artwork
  /// is particularly high, this can help to conserve memory. If specified,
  /// [artDownscaleHeight] must also be specified.
  final int artDownscaleWidth;

  /// If not null, causes the artwork specified by [MediaItem.artUri] to be
  /// downscaled to this maximum pixel height. If the resolution of your artwork
  /// is particularly high, this can help to conserve memory. If specified,
  /// [artDownscaleWidth] must also be specified.
  final int artDownscaleHeight;

  /// The interval to be used in [AudioHandler.fastForward]. This value will
  /// also be used on iOS to render the skip-forward button. This value must be
  /// positive.
  final Duration fastForwardInterval;

  /// The interval to be used in [AudioHandler.rewind]. This value will also be
  /// used on iOS to render the skip-backward button. This value must be
  /// positive.
  final Duration rewindInterval;

  /// Whether queue support should be enabled on the media session on Android.
  /// If your app will run on Android and has a queue, you should set this to
  /// true.
  final bool androidEnableQueue;
  final bool preloadArtwork;

  /// Extras to report on Android in response to an `onGetRoot` request.
  final Map<String, dynamic> androidBrowsableRootExtras;

  CallServiceConfig({
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
    this.fastForwardInterval = const Duration(seconds: 10),
    this.rewindInterval = const Duration(seconds: 10),
    this.androidEnableQueue = false,
    this.preloadArtwork = false,
    this.androidBrowsableRootExtras,
  })  : assert((artDownscaleWidth != null) == (artDownscaleHeight != null)),
        assert(fastForwardInterval > Duration.zero),
        assert(rewindInterval > Duration.zero);

  CallServiceConfigMessage _toMessage() => CallServiceConfigMessage(
    androidResumeOnClick: androidResumeOnClick,
    androidNotificationChannelName: androidNotificationChannelName,
    androidNotificationChannelDescription:
    androidNotificationChannelDescription,
    notificationColor: notificationColor,
    androidNotificationIcon: androidNotificationIcon,
    androidShowNotificationBadge: androidShowNotificationBadge,
    androidNotificationClickStartsActivity:
    androidNotificationClickStartsActivity,
    androidNotificationOngoing: androidNotificationOngoing,
    androidStopForegroundOnPause: androidStopForegroundOnPause,
    artDownscaleWidth: artDownscaleWidth,
    artDownscaleHeight: artDownscaleHeight,
    preloadArtwork: preloadArtwork,
    androidBrowsableRootExtras: androidBrowsableRootExtras,
  );
}

/// Key/value codes for use in [MediaItem.extras] and
/// [AudioServiceConfig.androidBrowsableRootExtras] to influence how Android
/// Auto will style browsable and playable media items.
class AndroidContentStyle {
  /// Set this key to `true` in [AudioServiceConfig.androidBrowsableRootExtras]
  /// to declare that content style is supported.
  static final supportedKey = 'android.media.browse.CONTENT_STYLE_SUPPORTED';

  /// The key in [MediaItem.extras] and
  /// [AudioServiceConfig.androidBrowsableRootExtras] to configure the content
  /// style for playable items. The value can be any of the `*ItemHintValue`
  /// constants defined in this class.
  static final playableHintKey =
      'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';

  /// The key in [MediaItem.extras] and
  /// [AudioServiceConfig.androidBrowsableRootExtras] to configure the content
  /// style for browsable items. The value can be any of the `*ItemHintValue`
  /// constants defined in this class.
  static final browsableHintKey =
      'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';

  /// Specifies that items should be presented as lists.
  static final listItemHintValue = 1;

  /// Specifies that items should be presented as grids.
  static final gridItemHintValue = 2;

  /// Specifies that items should be presented as lists with vector icons.
  static final categoryListItemHintValue = 3;

  /// Specifies that items should be presented as grids with vector icons.
  static final categoryGridItemHintValue = 4;
}

/// (Maybe) temporary.
extension AudioServiceValueStream<T> on ValueStream<T> {
  @Deprecated('Use "this" instead. Will be removed before the release')
  ValueStream<T> get stream => this;
}

extension MediaItemMessageExtension on MediaItemMessage {
  MediaItem toPlugin() => MediaItem(
    id: id,
    album: album,
    title: title,
    artUri: artUri,
    playable: playable,
    displayTitle: displayTitle,
    displaySubtitle: displaySubtitle,
    displayDescription: displayDescription,
    rating: rating?.toPlugin(),
    extras: extras,
  );
}

extension RatingMessageExtension on RatingMessage {
  Rating toPlugin() => Rating._internal(RatingStyle.values[type.index], value);
}

extension MediaButtonMessageExtension on MediaButtonMessage {
  MediaButton toPlugin() => MediaButton.values[index];
}

enum AndroidVolumeControlType { fixed, relative, absolute }

abstract class AndroidPlaybackInfo {
  AndroidPlaybackInfoMessage _toMessage();
}

class RemoteAndroidPlaybackInfo extends AndroidPlaybackInfo {
  //final AndroidAudioAttributes audioAttributes;
  final AndroidVolumeControlType volumeControlType;
  final int maxVolume;
  final int volume;

  RemoteAndroidPlaybackInfo({
    @required this.volumeControlType,
    @required this.maxVolume,
    @required this.volume,
  });

  AndroidPlaybackInfo copyWith({
    AndroidVolumeControlType volumeControlType,
    int maxVolume,
    int volume,
  }) =>
      RemoteAndroidPlaybackInfo(
        volumeControlType: volumeControlType ?? this.volumeControlType,
        maxVolume: maxVolume ?? this.maxVolume,
        volume: volume ?? this.volume,
      );

  @override
  RemoteAndroidPlaybackInfoMessage _toMessage() =>
      RemoteAndroidPlaybackInfoMessage(
        volumeControlType:
        AndroidVolumeControlTypeMessage.values[volumeControlType.index],
        maxVolume: maxVolume,
        volume: volume,
      );
}

class LocalAndroidPlaybackInfo extends AndroidPlaybackInfo {
  LocalAndroidPlaybackInfoMessage _toMessage() =>
      LocalAndroidPlaybackInfoMessage();
}

@deprecated
class AudioServiceBackground {
  static BaseAudioHandler get _handler =>
      AudioService._handler as BaseAudioHandler;

  /// The current media item.
  ///
  /// This is the value most recently set via [setMediaItem].
  static PlaybackState get state =>
      _handler.playbackState.value ?? PlaybackState();

  /// Broadcasts to all clients the current state, including:
  ///
  /// * Whether media is playing or paused
  /// * Whether media is buffering or skipping
  /// * The current position, buffered position and speed
  /// * The current set of media actions that should be enabled
  ///
  /// Connected clients will use this information to update their UI.
  ///
  /// You should use [controls] to specify the set of clickable buttons that
  /// should currently be visible in the notification in the current state,
  /// where each button is a [MediaControl] that triggers a different
  /// [MediaAction]. Only the following actions can be enabled as
  /// [MediaControl]s:
  ///
  /// * [MediaAction.stop]
  /// * [MediaAction.pause]
  /// * [MediaAction.play]
  /// * [MediaAction.rewind]
  /// * [MediaAction.skipToPrevious]
  /// * [MediaAction.skipToNext]
  /// * [MediaAction.fastForward]
  /// * [MediaAction.playPause]
  ///
  /// Any other action you would like to enable for clients that is not a clickable
  /// notification button should be specified in the [systemActions] parameter. For
  /// example:
  ///
  /// * [MediaAction.seekTo] (enable a seek bar)
  /// * [MediaAction.seekForward] (enable press-and-hold fast-forward control)
  /// * [MediaAction.seekBackward] (enable press-and-hold rewind control)
  ///
  /// In practice, iOS will treat all entries in [controls] and [systemActions]
  /// in the same way since you cannot customise the icons of controls in the
  /// Control Center. However, on Android, the distinction is important as clickable
  /// buttons in the notification require you to specify your own icon.
  ///
  /// Note that specifying [MediaAction.seekTo] in [systemActions] will enable
  /// a seek bar in both the Android notification and the iOS control center.
  /// [MediaAction.seekForward] and [MediaAction.seekBackward] have a special
  /// behaviour on iOS in which if you have already enabled the
  /// [MediaAction.skipToNext] and [MediaAction.skipToPrevious] buttons, these
  /// additional actions will allow the user to press and hold the buttons to
  /// activate the continuous seeking behaviour.
  ///
  /// On Android, a media notification has a compact and expanded form. In the
  /// compact view, you can optionally specify the indices of up to 3 of your
  /// [controls] that you would like to be shown via [androidCompactActions].
  ///
  /// The playback [position] should NOT be updated continuously in real time.
  /// Instead, it should be updated only when the normal continuity of time is
  /// disrupted, such as during a seek, buffering and seeking. When
  /// broadcasting such a position change, the [updateTime] specifies the time
  /// of that change, allowing clients to project the realtime value of the
  /// position as `position + (DateTime.now() - updateTime)`. As a convenience,
  /// this calculation is provided by [PlaybackState.currentPosition].
  ///
  /// The playback [speed] is given as a double where 1.0 means normal speed.
  static Future<void> setState({
    List<MediaControl> controls,
    List<MediaAction> systemActions,
    AudioProcessingState processingState,
    bool playing,
    Duration position,
    Duration bufferedPosition,
    double speed,
    DateTime updateTime,
    List<int> androidCompactActions,
  }) async {
    _handler.playbackState.add(_handler.playbackState.value.copyWith(
      controls: controls,
      systemActions: systemActions?.toSet(),
      processingState: processingState,
      playing: playing,
      androidCompactActionIndices: androidCompactActions,
    ));
  }

  /// Sets the currently playing media item and notifies all clients.
  static Future<void> setMediaItem(MediaItem mediaItem) async {
    _handler.mediaItem.add(mediaItem);
  }

  /// Sends a custom event to the Flutter UI.
  ///
  /// The event parameter can contain any data permitted by Dart's
  /// SendPort/ReceivePort API. Please consult the relevant documentation for
  /// further information.
  static void sendCustomEvent(dynamic event) {
    _handler.customEventSubject.add(event);
  }
}

class _HandlerCallbacks extends CallHandlerCallbacks {
  final AudioHandler handler;

  _HandlerCallbacks(this.handler);

  @override
  Future<void> click(ClickRequest request) {
    print('### calling handler.click(${request.button.toPlugin()})');
    return handler.click(request.button.toPlugin());
  }

  @override
  Future customAction(CustomActionRequest request) =>
      handler.customAction(request.name, request.extras);

  @override
  Future<GetMediaItemResponse> getMediaItem(GetMediaItemRequest request) async {
    return GetMediaItemResponse(
        mediaItem: (await handler.getMediaItem(request.mediaId))?._toMessage());
  }

  @override
  Future<void> onNotificationClicked(
      OnNotificationClickedRequest request) async {
    AudioService._notificationClickEvent.add(request.clicked);
  }

  @override
  Future<void> onNotificationDeleted(OnNotificationDeletedRequest request) =>
      handler.onNotificationDeleted();

  @override
  Future<void> onTaskRemoved(OnTaskRemovedRequest request) =>
      handler.onTaskRemoved();

  @override
  Future<void> pause(PauseRequest request) => handler.pause();

  @override
  Future<void> play(PlayRequest request) => handler.play();

  @override
  Future<void> playFromMediaId(PlayFromMediaIdRequest request) =>
      handler.playFromMediaId(request.mediaId);

  @override
  Future<void> playMediaItem(PlayMediaItemRequest request) =>
      handler.playMediaItem(request.mediaItem.toPlugin());

  @override
  Future<void> prepare(PrepareRequest request) => handler.prepare();

  @override
  Future<void> prepareFromMediaId(PrepareFromMediaIdRequest request) =>
      handler.prepareFromMediaId(request.mediaId);

  @override
  Future<void> setRating(SetRatingRequest request) =>
      handler.setRating(request.rating.toPlugin(), request.extras);

  @override
  Future<void> stop(StopRequest request) => handler.stop();

  @override
  Future<void> updateMediaItem(UpdateMediaItemRequest request) =>
      handler.updateMediaItem(request.mediaItem.toPlugin());

  final Map<String, ValueStream<Map<String, dynamic>>> _childrenSubscriptions =
  <String, ValueStream<Map<String, dynamic>>>{};
}

class _ClientCallbacks extends CallClientCallbacks {
  final _IsolateAudioHandler handler;

  _ClientCallbacks(this.handler);

  @override
  Future<void> onMediaItemChanged(OnMediaItemChangedRequest request) async {
    handler.mediaItem.add(request.mediaItem?.toPlugin());
  }

  @override
  Future<void> onPlaybackStateChanged(
      OnPlaybackStateChangedRequest request) async {
    final state = request.state;
    handler.playbackState.add(PlaybackState(
      processingState: AudioProcessingState.values[state.processingState.index],
      playing: state.playing,
      // We can't determine whether they are controls.
      systemActions: state.systemActions
          .map((action) => MediaAction.values[action.index])
          .toSet(),
      updateTime: state.updateTime,
    ));
  }

//@override
//Future<void> onChildrenLoaded(OnChildrenLoadedRequest request) {
//  // TODO: implement onChildrenLoaded
//  throw UnimplementedError();
//}
}

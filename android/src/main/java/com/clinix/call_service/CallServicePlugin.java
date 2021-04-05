package com.clinix.call_service;

import android.Manifest;
import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.media.AudioTrack;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.telecom.Connection;
import android.telecom.PhoneAccount;
import android.telecom.PhoneAccountHandle;
import android.telecom.TelecomManager;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;
import android.support.v4.media.MediaBrowserCompat;

import androidx.media.MediaBrowserServiceCompat;

import android.support.v4.media.MediaDescriptionCompat;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.RatingCompat;
import android.support.v4.media.session.MediaControllerCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.session.PlaybackStateCompat;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;

import static com.clinix.call_service.Constants.EXTRA_CALLER_NAME;
import static com.clinix.call_service.Constants.EXTRA_CALL_NUMBER;
import static com.clinix.call_service.Constants.EXTRA_CALL_UUID;
/** CallServicePlugin */
public class CallServicePlugin implements FlutterPlugin, ActivityAware {
  private static String flutterEngineId = "audio_service_engine";
  /** Must be called BEFORE any FlutterEngine is created. e.g. in Application class. */
  public static void setFlutterEngineId(String id) {
    flutterEngineId = id;
  }
  public static String getFlutterEngineId() {
    return flutterEngineId;
  }
  public static synchronized FlutterEngine getFlutterEngine(Context context) {
    FlutterEngine flutterEngine = FlutterEngineCache.getInstance().get(flutterEngineId);
    if (flutterEngine == null) {
      System.out.println("### Creating new FlutterEngine");
      // XXX: The constructor triggers onAttachedToEngine so this variable doesn't help us.
      // Maybe need a boolean flag to tell us we're currently loading the main flutter engine.
      flutterEngine = new FlutterEngine(context.getApplicationContext());
      flutterEngine.getDartExecutor().executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault());
      FlutterEngineCache.getInstance().put(flutterEngineId, flutterEngine);
    } else {
      System.out.println("### Reusing existing FlutterEngine");
    }
    return flutterEngine;
  }

  public static void disposeFlutterEngine() {
    FlutterEngine flutterEngine = FlutterEngineCache.getInstance().get(flutterEngineId);
    if (flutterEngine != null) {
      System.out.println("### FlutterEngine.destroy()");
      flutterEngine.destroy();
      FlutterEngineCache.getInstance().remove(flutterEngineId);
    }
  }

  private static final String CHANNEL_CLIENT = "com.clinix.call_service.client.methods";
  private static final String CHANNEL_HANDLER = "com.clinix.call_service.handler.methods";

  private static Context applicationContext;
  private static Set<ClientInterface> clientInterfaces = new HashSet<ClientInterface>();
  private static ClientInterface mainClientInterface;
  private static AudioHandlerInterface audioHandlerInterface;
  private static volatile Result startResult;
  private static volatile Result stopResult;
  private static long bootTime;
  private static Result configureResult;

  static {
    bootTime = System.currentTimeMillis() - SystemClock.elapsedRealtime();
  }
/*
  static AudioHandlerInterface audioHandlerInterface() throws Exception {
    if (audioHandlerInterface == null) throw new Exception("Background audio task not running");
    return audioHandlerInterface;
  }*/

  private static MediaBrowserCompat mediaBrowser;
  private static MediaControllerCompat mediaController;

  private static MediaControllerCompat.Callback controllerCallback = new MediaControllerCompat.Callback() {
    @Override
    public void onMetadataChanged(MediaMetadataCompat metadata) {
      Map<String, Object> map = new HashMap<String, Object>();
      map.put("mediaItem", mediaMetadata2raw(metadata));
      invokeClientMethod("onMediaItemChanged", map);
    }

    @Override
    public void onPlaybackStateChanged(PlaybackStateCompat state) {
      // On the native side, we represent the update time relative to the boot time.
      // On the flutter side, we represent the update time relative to the epoch.
      long updateTimeSinceBoot = state.getLastPositionUpdateTime();
      long updateTimeSinceEpoch = bootTime + updateTimeSinceBoot;
      Map<String, Object> stateMap = new HashMap<String, Object>();
      /*stateMap.put("processingState", CallService.instance.getProcessingState().ordinal());
      stateMap.put("playing", CallService.instance.isPlaying());*/
      stateMap.put("controls", new ArrayList<Object>());
      long actionBits = state.getActions();
      List<Object> systemActions = new ArrayList<Object>();
      for (int actionIndex = 0; actionIndex < 64; actionIndex++) {
        if ((actionBits & (1 << actionIndex)) != 0) {
          systemActions.add(actionIndex);
        }
      }
      stateMap.put("systemActions", systemActions);
      stateMap.put("updatePosition", state.getPosition());
      stateMap.put("bufferedPosition", state.getBufferedPosition());
      stateMap.put("speed", state.getPlaybackSpeed());
      stateMap.put("updateTime", updateTimeSinceEpoch);
      Map<String, Object> map = new HashMap<String, Object>();
      map.put("state", stateMap);
      invokeClientMethod("onPlaybackStateChanged", map);
    }

    @Override
    public void onQueueChanged(List<MediaSessionCompat.QueueItem> queue) {
      Map<String, Object> map = new HashMap<String, Object>();
      map.put("queue", queue2raw(queue));
      invokeClientMethod("onQueueChanged", map);
    }

  };
  private static final MediaBrowserCompat.ConnectionCallback connectionCallback = new MediaBrowserCompat.ConnectionCallback() {
    @Override
    public void onConnected() {
      System.out.println("### onConnected");
      try {
        MediaSessionCompat.Token token = mediaBrowser.getSessionToken();
        mediaController = new MediaControllerCompat(applicationContext, token);
        Activity activity = mainClientInterface != null ? mainClientInterface.activity : null;
        if (activity != null) {
          MediaControllerCompat.setMediaController(activity, mediaController);
        }
        mediaController.registerCallback(controllerCallback);
        System.out.println("### registered mediaController callback");
        PlaybackStateCompat state = mediaController.getPlaybackState();
        controllerCallback.onPlaybackStateChanged(state);
        MediaMetadataCompat metadata = mediaController.getMetadata();
        controllerCallback.onQueueChanged(mediaController.getQueue());
        controllerCallback.onMetadataChanged(metadata);
        if (configureResult != null) {
          configureResult.success(mapOf());
          configureResult = null;
        }
      } catch (Exception e) {
        e.printStackTrace();
        throw new RuntimeException(e);
      }
      System.out.println("### onConnected returned");
    }

    @Override
    public void onConnectionSuspended() {
      // TODO: Handle this
      System.out.println("### UNHANDLED: onConnectionSuspended");
    }

    @Override
    public void onConnectionFailed() {
      // TODO: Handle this
      System.out.println("### UNHANDLED: onConnectionFailed");
    }
  };
  private static void invokeClientMethod(String method, Object arg) {
    for (ClientInterface clientInterface : clientInterfaces) {
      clientInterface.channel.invokeMethod(method, arg);
    }
  }

  //
  // INSTANCE FIELDS AND METHODS
  //

  private FlutterPluginBinding flutterPluginBinding;
  private ActivityPluginBinding activityPluginBinding;
  private PluginRegistry.NewIntentListener newIntentListener;
  private ClientInterface clientInterface;

  //
  // FlutterPlugin callbacks
  //

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    System.out.println("### onAttachedToEngine");
    flutterPluginBinding = binding;
    clientInterface = new ClientInterface(flutterPluginBinding.getBinaryMessenger());
    clientInterface.setContext(flutterPluginBinding.getApplicationContext());
    clientInterfaces.add(clientInterface);
    System.out.println("### " + clientInterfaces.size() + " client handlers");
    if (applicationContext == null) {
      applicationContext = flutterPluginBinding.getApplicationContext();
    }
    if (audioHandlerInterface == null) {
      // We don't know yet whether this is the right engine that hosts the BackgroundAudioTask,
      // but we need to register a MethodCallHandler now just in case. If we're wrong, we
      // detect and correct this when receiving the "configure" message.
      audioHandlerInterface = new AudioHandlerInterface(flutterPluginBinding.getBinaryMessenger(), true /*androidEnableQueue*/);
      CallService.init(audioHandlerInterface);
    }
    if (mediaBrowser == null) {
      connect();
    }
    System.out.println("### onAttachedToEngine completed");
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    System.out.println("### onDetachedFromEngine");
    System.out.println("### " + clientInterfaces.size() + " client handlers");
    if (clientInterfaces.size() == 1) {
      disconnect();
    }
    clientInterfaces.remove(clientInterface);
    clientInterface.setContext(null);
    flutterPluginBinding = null;
    clientInterface = null;
    applicationContext = null;
    if (audioHandlerInterface != null) {
      audioHandlerInterface.destroy();
      audioHandlerInterface = null;
    }
    System.out.println("### onDetachedFromEngine completed");
  }

  //
  // ActivityAware callbacks
  //

  @Override
  public void onAttachedToActivity(ActivityPluginBinding binding) {
    System.out.println("### mainClientInterface set");
    activityPluginBinding = binding;
    clientInterface.setActivity(binding.getActivity());
    clientInterface.setContext(binding.getActivity());
    mainClientInterface = clientInterface;
    registerOnNewIntentListener();
    if (mediaController != null) {
      MediaControllerCompat.setMediaController(mainClientInterface.activity, mediaController);
    }
    if (mediaBrowser == null) {
      connect();
    }
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    System.out.println("### onDetachedFromActivityForConfigChanges");
    activityPluginBinding.removeOnNewIntentListener(newIntentListener);
    activityPluginBinding = null;
    clientInterface.setActivity(null);
    clientInterface.setContext(flutterPluginBinding.getApplicationContext());
  }

  @Override
  public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
    System.out.println("### onReattachedToActivityForConfigChanges");
    activityPluginBinding = binding;
    clientInterface.setActivity(binding.getActivity());
    clientInterface.setContext(binding.getActivity());
    registerOnNewIntentListener();
  }

  @Override
  public void onDetachedFromActivity() {
    System.out.println("### onDetachedFromActivity");
    activityPluginBinding.removeOnNewIntentListener(newIntentListener);
    activityPluginBinding = null;
    newIntentListener = null;
    clientInterface.setActivity(null);
    clientInterface.setContext(flutterPluginBinding.getApplicationContext());
    if (clientInterfaces.size() == 1) {
      // This unbinds from the service allowing CallService.onDestroy to
      // happen which in turn allows the FlutterEngine to be destroyed.
      disconnect();
    }
    if (clientInterface == mainClientInterface) {
      mainClientInterface = null;
    }
  }

  private void connect() {
    System.out.println("### connect");
    /* Activity activity = mainClientInterface.activity; */
    /* if (activity != null) { */
    /*     if (clientInterface.wasLaunchedFromRecents()) { */
    /*         // We do this to avoid using the old intent. */
    /*         activity.setIntent(new Intent(Intent.ACTION_MAIN)); */
    /*     } */
    /*     if (activity.getIntent().getAction() != null) */
    /*         invokeClientMethod("notificationClicked", activity.getIntent().getAction().equals(CallService.NOTIFICATION_CLICK_ACTION)); */
    /* } */
    if (mediaBrowser == null) {
      mediaBrowser = new MediaBrowserCompat(applicationContext,
              new ComponentName(applicationContext, CallService.class),
              connectionCallback,
              null);
      mediaBrowser.connect();
    }
    System.out.println("### connect returned");
  }

  private void disconnect() {
    System.out.println("### disconnect");
    Activity activity = mainClientInterface != null ? mainClientInterface.activity : null;
    /*if (activity != null) {
      // Since the activity enters paused state, we set the intent with ACTION_MAIN.
      activity.setIntent(new Intent(Intent.ACTION_MAIN));
    }*/
    //TODO deregister  Connection method callbacks

    if (mediaController != null) {
      mediaController.unregisterCallback(controllerCallback);
      mediaController = null;
    }
    if (mediaBrowser != null) {
      mediaBrowser.disconnect();
      mediaBrowser = null;
    }
    System.out.println("### disconnect returned");
  }

  private void registerOnNewIntentListener() {
    activityPluginBinding.addOnNewIntentListener(newIntentListener = new PluginRegistry.NewIntentListener() {
      @Override
      public boolean onNewIntent(Intent intent) {
        clientInterface.activity.setIntent(intent);
        return true;
      }
    });
  }

  private static class  ClientInterface implements MethodCallHandler {
    private Context context;
    private Activity activity;
    public final BinaryMessenger messenger;
    private MethodChannel channel;

    public ClientInterface(BinaryMessenger messenger) {
      this.messenger = messenger;
      channel = new MethodChannel(messenger, CHANNEL_CLIENT);
      channel.setMethodCallHandler(this);
    }

    private void setContext(Context context) {
      this.context = context;
    }

    private void setActivity(Activity activity) {
      this.activity = activity;
    }

    // See: https://stackoverflow.com/questions/13135545/android-activity-is-using-old-intent-if-launching-app-from-recent-task
    protected boolean wasLaunchedFromRecents() {
      return (activity.getIntent().getFlags() & Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY;
    }

    @Override
    public void onMethodCall(MethodCall call, final Result result) {
      try {
        System.out.println("### ClientInterface message: " + call.method);
        switch (call.method) {
          case "configure":
            Map<?, ?> args = (Map<?, ?>)call.arguments;
            Map<?, ?> configMap = (Map<?, ?>)args.get("config");
            CallServiceConfig config = new CallServiceConfig(context.getApplicationContext());
            config.androidNotificationClickStartsActivity = (Boolean)configMap.get("androidNotificationClickStartsActivity");
            config.androidNotificationOngoing = (Boolean)configMap.get("androidNotificationOngoing");
            config.androidResumeOnClick = (Boolean)configMap.get("androidResumeOnClick");
            config.androidNotificationChannelName = (String)configMap.get("androidNotificationChannelName");
            config.androidNotificationChannelDescription = (String)configMap.get("androidNotificationChannelDescription");
            config.notificationColor = configMap.get("notificationColor") == null ? -1 : getInt(configMap.get("notificationColor"));
            config.androidNotificationIcon = (String)configMap.get("androidNotificationIcon");
            config.androidShowNotificationBadge = (Boolean)configMap.get("androidShowNotificationBadge");
            config.androidStopForegroundOnPause = (Boolean)configMap.get("androidStopForegroundOnPause");
            config.artDownscaleWidth = configMap.get("artDownscaleWidth") != null ? (Integer)configMap.get("artDownscaleWidth") : -1;
            config.artDownscaleHeight = configMap.get("artDownscaleHeight") != null ? (Integer)configMap.get("artDownscaleHeight") : -1;
            config.setBrowsableRootExtras((Map<?,?>)configMap.get("androidBrowsableRootExtras"));
            if (activity != null) {
              config.activityClassName = activity.getClass().getName();
            }
            config.save();
            if (CallService.instance != null) {
              CallService.instance.configure(config);
            }
            mainClientInterface = ClientInterface.this;
            if (audioHandlerInterface == null) {
              audioHandlerInterface = new AudioHandlerInterface(messenger, true /*androidEnableQueue*/);
              CallService.init(audioHandlerInterface);
            } else if (audioHandlerInterface.messenger != messenger) {
              // We've detected this is the real engine hosting the AudioHandler,
              // so update AudioHandlerInterface to connect to it.
              audioHandlerInterface.switchToMessenger(messenger);
            }
            if (mediaController != null) {
              result.success(mapOf());
            } else {
              configureResult = result;
            }
            break;
        }
      } catch (Exception e) {
        e.printStackTrace();
        result.error(e.getMessage(), null, null);
      }
    }
  }

  private static class AudioHandlerInterface implements MethodCallHandler, CallService.ServiceListener {
    private boolean enableQueue;
    public BinaryMessenger messenger;
    public MethodChannel channel;
    private AudioTrack silenceAudioTrack;
    private static final int SILENCE_SAMPLE_RATE = 44100;
    private byte[] silence;

    public AudioHandlerInterface(BinaryMessenger messenger, boolean enableQueue) {
      System.out.println("### new AudioHandlerInterface");
      this.enableQueue = enableQueue;
      this.messenger = messenger;
      channel = new MethodChannel(messenger, CHANNEL_HANDLER);
      channel.setMethodCallHandler(this);
    }

    public void switchToMessenger(BinaryMessenger messenger) {
      channel.setMethodCallHandler(null);
      this.messenger = messenger;
      channel = new MethodChannel(messenger, CHANNEL_HANDLER);
      channel.setMethodCallHandler(this);
    }

    @Override
    public void onClick(MediaControl mediaControl) {
      System.out.println("### sending click map: " + mapOf("button", mediaControl.ordinal()));
      invokeMethod("click", mapOf("button", mediaControl.ordinal()));
    }

    @Override
    public void onPause() {
      invokeMethod("pause", mapOf());
    }

    @Override
    public void onPrepare() {
      invokeMethod("prepare", mapOf());
    }

    @Override
    public void onPrepareFromMediaId(String mediaId, Bundle extras) {
      invokeMethod("prepareFromMediaId", mapOf(
              "mediaId", mediaId,
              "extras", bundleToMap(extras)));
    }


    @Override
    public void onPlay() {
      invokeMethod("play", mapOf());
    }

    @Override
    public void onPlayFromMediaId(String mediaId, Bundle extras) {
      invokeMethod("playFromMediaId", mapOf(
              "mediaId", mediaId,
              "extras", bundleToMap(extras)));
    }


    @Override
    public void onPlayMediaItem(MediaMetadataCompat metadata) {
      invokeMethod("playMediaItem", mapOf("mediaItem", mediaMetadata2raw(metadata)));
    }

    @Override
    public void onStop() {
      invokeMethod("stop", mapOf());
    }

    @Override
    public void onTaskRemoved() {
      invokeMethod("onTaskRemoved", mapOf());
    }

    @Override
    public void onClose() {
      invokeMethod("onNotificationDeleted", mapOf());
    }

    @Override
    public void onDestroy() {
      disposeFlutterEngine();
    }

    @Override
    public void onMethodCall(MethodCall call, Result result) {
      System.out.println("### AudioHandlerInterface message: " + call.method);
      Context context = CallService.instance;
      Map<?, ?> args = (Map<?, ?>)call.arguments;
      switch (call.method) {
        case "setMediaItem": {
          Map<?, ?> rawMediaItem = (Map<?, ?>)args.get("mediaItem");
          MediaMetadataCompat mediaMetadata = createMediaMetadata(rawMediaItem);
          CallService.instance.setMetadata(mediaMetadata);
          result.success(null);
          break;
        }
        case "setState": {
          Map<?, ?> stateMap = (Map<?, ?>)args.get("state");
          AudioProcessingState processingState = AudioProcessingState.values()[(Integer)stateMap.get("processingState")];
          boolean playing = (Boolean)stateMap.get("playing");
          List<Map<?, ?>> rawControls = (List<Map<?, ?>>)stateMap.get("controls");
          List<Object> compactActionIndexList = (List<Object>)stateMap.get("androidCompactActionIndices");
          List<Integer> rawSystemActions = (List<Integer>)stateMap.get("systemActions");
          //long bufferedPosition = getLong(stateMap.get("bufferedPosition"));
          //float speed = (float)((double)((Double)stateMap.get("speed")));
          long updateTimeSinceEpoch = stateMap.get("updateTime") == null ? System.currentTimeMillis() : getLong(stateMap.get("updateTime"));
          Integer errorCode = (Integer)stateMap.get("errorCode");
          String errorMessage = (String)stateMap.get("errorMessage");

          // On the flutter side, we represent the update time relative to the epoch.
          // On the native side, we must represent the update time relative to the boot time.
          long updateTimeSinceBoot = updateTimeSinceEpoch - bootTime;

          List<NotificationCompat.Action> actions = new ArrayList<NotificationCompat.Action>();
          int actionBits = 0;
          for (Map<?, ?> rawControl : rawControls) {
            String resource = (String)rawControl.get("androidIcon");
            int actionCode = 1 << ((Integer)rawControl.get("action"));
            actionBits |= actionCode;
            actions.add(CallService.instance.action(resource, (String)rawControl.get("label"), actionCode));
          }
          for (Integer rawSystemAction : rawSystemActions) {
            int actionCode = 1 << rawSystemAction;
            actionBits |= actionCode;
          }
          int[] compactActionIndices = null;
          if (compactActionIndexList != null) {
            compactActionIndices = new int[Math.min(CallService.MAX_COMPACT_ACTIONS, compactActionIndexList.size())];
            for (int i = 0; i < compactActionIndices.length; i++)
              compactActionIndices[i] = (Integer)compactActionIndexList.get(i);
          }
          CallService.instance.setState(
                  actions,
                  actionBits,
                  compactActionIndices,
                  processingState,
                  playing,
                  updateTimeSinceBoot,
                  errorCode,
                  errorMessage);
          result.success(null);
          break;
        }
        case "stopService": {
          if (CallService.instance != null) {
            CallService.instance.stop();
          }
          result.success(null);
          break;
        }
      }
    }

    public void invokeMethod(String method, Object arg) {
      channel.invokeMethod(method, arg);
    }

    public void invokeMethod(final Result result, String method, Object arg) {
      channel.invokeMethod(method, arg, result);
    }

    private void destroy() {
      if (silenceAudioTrack != null)
        silenceAudioTrack.release();
    }
  }


  private static List<Map<?, ?>> queue2raw(List<MediaSessionCompat.QueueItem> queue) {
    if (queue == null) return null;
    List<Map<?, ?>> rawQueue = new ArrayList<Map<?, ?>>();
    for (MediaSessionCompat.QueueItem queueItem : queue) {
      MediaDescriptionCompat description = queueItem.getDescription();
      MediaMetadataCompat mediaMetadata = CallService.getMediaMetadata(description.getMediaId());
      rawQueue.add(mediaMetadata2raw(mediaMetadata));
    }
    return rawQueue;
  }

  private static RatingCompat raw2rating(Map<String, Object> raw) {
    if (raw == null) return null;
    Integer type = (Integer)raw.get("type");
    Object value = raw.get("value");
    if (value != null) {
      switch (type) {
        case RatingCompat.RATING_3_STARS:
        case RatingCompat.RATING_4_STARS:
        case RatingCompat.RATING_5_STARS:
          return RatingCompat.newStarRating(type, (int)value);
        case RatingCompat.RATING_HEART:
          return RatingCompat.newHeartRating((boolean)value);
        case RatingCompat.RATING_PERCENTAGE:
          return RatingCompat.newPercentageRating((float)value);
        case RatingCompat.RATING_THUMB_UP_DOWN:
          return RatingCompat.newThumbRating((boolean)value);
        default:
          return RatingCompat.newUnratedRating(type);
      }
    } else {
      return RatingCompat.newUnratedRating(type);
    }
  }

  private static HashMap<String, Object> rating2raw(RatingCompat rating) {
    HashMap<String, Object> raw = new HashMap<String, Object>();
    raw.put("type", rating.getRatingStyle());
    if (rating.isRated()) {
      switch (rating.getRatingStyle()) {
        case RatingCompat.RATING_3_STARS:
        case RatingCompat.RATING_4_STARS:
        case RatingCompat.RATING_5_STARS:
          raw.put("value", rating.getStarRating());
          break;
        case RatingCompat.RATING_HEART:
          raw.put("value", rating.hasHeart());
          break;
        case RatingCompat.RATING_PERCENTAGE:
          raw.put("value", rating.getPercentRating());
          break;
        case RatingCompat.RATING_THUMB_UP_DOWN:
          raw.put("value", rating.isThumbUp());
          break;
        case RatingCompat.RATING_NONE:
          raw.put("value", null);
      }
    } else {
      raw.put("value", null);
    }
    return raw;
  }

  private static String metadataToString(MediaMetadataCompat mediaMetadata, String key) {
    CharSequence value = mediaMetadata.getText(key);
    if (value != null && value.length() > 0)
      return value.toString();
    return null;
  }

  private static Map<?, ?> mediaMetadata2raw(MediaMetadataCompat mediaMetadata) {
    if (mediaMetadata == null) return null;
    MediaDescriptionCompat description = mediaMetadata.getDescription();
    Map<String, Object> raw = new HashMap<String, Object>();
    raw.put("id", description.getMediaId());
    raw.put("album", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_ALBUM));
    raw.put("title", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_TITLE));
    if (description.getIconUri() != null)
      raw.put("artUri", description.getIconUri().toString());
    raw.put("artist", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_ARTIST));
    raw.put("genre", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_GENRE));
    if (mediaMetadata.containsKey(MediaMetadataCompat.METADATA_KEY_DURATION))
      raw.put("duration", mediaMetadata.getLong(MediaMetadataCompat.METADATA_KEY_DURATION));
    raw.put("playable", mediaMetadata.getLong("playable_long") != 0);
    raw.put("displayTitle", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE));
    raw.put("displaySubtitle", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE));
    raw.put("displayDescription", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION));
    if (mediaMetadata.containsKey(MediaMetadataCompat.METADATA_KEY_RATING)) {
      raw.put("rating", rating2raw(mediaMetadata.getRating(MediaMetadataCompat.METADATA_KEY_RATING)));
    }
    Map<String, Object> extras = bundleToMap(mediaMetadata.getBundle());
    if (extras.size() > 0) {
      raw.put("extras", extras);
    }
    return raw;
  }

  private static MediaMetadataCompat createMediaMetadata(Map<?, ?> rawMediaItem) {
    return CallService.instance.createMediaMetadata(
            (String)rawMediaItem.get("id"),
            (String)rawMediaItem.get("album"),
            (String)rawMediaItem.get("title"),
            (String)rawMediaItem.get("artist"),
            (String)rawMediaItem.get("genre"),
            getLong(rawMediaItem.get("duration")),
            (String)rawMediaItem.get("artUri"),
            (Boolean)rawMediaItem.get("playable"),
            (String)rawMediaItem.get("displayTitle"),
            (String)rawMediaItem.get("displaySubtitle"),
            (String)rawMediaItem.get("displayDescription"),
            raw2rating((Map<String, Object>)rawMediaItem.get("rating")),
            (Map<?, ?>)rawMediaItem.get("extras")
    );
  }

  private static List<MediaSessionCompat.QueueItem> raw2queue(List<Map<?, ?>> rawQueue) {
    List<MediaSessionCompat.QueueItem> queue = new ArrayList<MediaSessionCompat.QueueItem>();
    int i = 0;
    for (Map<?, ?> rawMediaItem : rawQueue) {
      MediaMetadataCompat mediaMetadata = createMediaMetadata(rawMediaItem);
      MediaDescriptionCompat description = mediaMetadata.getDescription();
      queue.add(new MediaSessionCompat.QueueItem(description, i));
      i++;
    }
    return queue;
  }

  public static Long getLong(Object o) {
    return (o == null || o instanceof Long) ? (Long)o : new Long(((Integer)o).intValue());
  }

  public static Integer getInt(Object o) {
    return (o == null || o instanceof Integer) ? (Integer)o : new Integer((int)((Long)o).longValue());
  }

  static Map<String, Object> bundleToMap(Bundle bundle) {
    if (bundle == null) return null;
    Map<String, Object> map = new HashMap<String, Object>();
    for (String key : bundle.keySet()) {
      Object value = bundle.get(key);
      if (value instanceof Integer
              || value instanceof Long
              || value instanceof Double
              || value instanceof Float
              || value instanceof Boolean
              || value instanceof String) {
        map.put(key, value);
      }
    }
    return map;
  }

  static Bundle mapToBundle(Map<?, ?> map) {
    if (map == null) return null;
    final Bundle bundle = new Bundle();
    for (Object key : map.keySet()) {
      String skey = (String)key;
      Object value = map.get(skey);
      if (value instanceof Integer) bundle.putInt(skey, (Integer)value);
      else if (value instanceof Long) bundle.putLong(skey, (Long)value);
      else if (value instanceof Double) bundle.putDouble(skey, (Double)value);
      else if (value instanceof Boolean) bundle.putBoolean(skey, (Boolean)value);
      else if (value instanceof String) bundle.putString(skey, (String)value);
    }
    return bundle;
  }

  static Map<String, Object> mapOf(Object... args) {
    Map<String, Object> map = new HashMap<String, Object>();
    for (int i = 0; i < args.length; i += 2) {
      map.put((String)args[i], args[i + 1]);
    }
    return map;
  }

}

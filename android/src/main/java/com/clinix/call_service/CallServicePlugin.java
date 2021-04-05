package com.clinix.call_service;

import android.Manifest;
import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
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

import java.util.HashMap;
import java.util.HashSet;
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
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private MethodChannel channel;
  private static long bootTime;
  private boolean isReceiverRegistered = false;
  private static String flutterEngineId = "call_service_engine";
  private static final String[] permissions = {
          Manifest.permission.CALL_PHONE};
  static {
    bootTime = System.currentTimeMillis() - SystemClock.elapsedRealtime();
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
  private static CallHandlerInterface callHandlerInterface;


  //
  // INSTANCE FIELDS AND METHODS
  //

  private FlutterPluginBinding flutterPluginBinding;
  private ActivityPluginBinding activityPluginBinding;
  private PluginRegistry.NewIntentListener newIntentListener;
  private ClientInterface clientInterface;
  private static TelecomManager telecomManager;
  public static PhoneAccountHandle handle;

  //
  // FlutterPlugin callbacks
  //

  @RequiresApi(api = Build.VERSION_CODES.M)
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    System.out.println("### onAttachedToEngine");
    flutterPluginBinding = binding;
    clientInterface = new ClientInterface(flutterPluginBinding.getBinaryMessenger());
    clientInterface.setContext(flutterPluginBinding.getApplicationContext());
    clientInterfaces.add(clientInterface);
    System.out.println("### " + clientInterfaces.size() + " client handlers");
    if (applicationContext == null) {
      applicationContext = flutterPluginBinding.getApplicationContext();
    }
    if (callHandlerInterface == null) {
      // We don't know yet whether this is the right engine that hosts the BackgroundAudioTask,
      // but we need to register a MethodCallHandler now just in case. If we're wrong, we
      // detect and correct this when receiving the "configure" message.
      callHandlerInterface = new CallHandlerInterface(flutterPluginBinding.getBinaryMessenger());
      CallService.init(callHandlerInterface);
    }
    if (telecomManager == null) {
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
    if (callHandlerInterface != null) {
      callHandlerInterface = null;
    }
    System.out.println("### onDetachedFromEngine completed");
  }

  private static void invokeClientMethod(String method, Object arg) {
    for (ClientInterface clientInterface : clientInterfaces) {
      clientInterface.channel.invokeMethod(method, arg);
    }
  }

  @RequiresApi(api = Build.VERSION_CODES.M)
  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    System.out.println("### mainClientInterface set");
    activityPluginBinding = binding;
    clientInterface.setActivity(binding.getActivity());
    clientInterface.setContext(binding.getActivity());
    mainClientInterface = clientInterface;
    registerOnNewIntentListener();
    if (telecomManager == null) {
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
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
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
      // This unbinds from the service allowing AudioService.onDestroy to
      // happen which in turn allows the FlutterEngine to be destroyed.
      disconnect();
    }
    if (clientInterface == mainClientInterface) {
      mainClientInterface = null;
    }
  }
  @RequiresApi(api = Build.VERSION_CODES.M)
  private void connect() {
    System.out.println("### connect");
    if (telecomManager == null) {
      ComponentName cName = new ComponentName(applicationContext, CallService.class);
      String appName = this.getApplicationName(applicationContext);

      handle = new PhoneAccountHandle(cName, appName);
      telecomManager = (TelecomManager) applicationContext.getSystemService(Context.TELECOM_SERVICE);
      //TODO register  Connection method callbacks
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

    telecomManager = null;
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


  private static class ClientInterface implements MethodCallHandler {
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
    @RequiresApi(api = Build.VERSION_CODES.M)
    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
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
            if (callHandlerInterface == null) {
              callHandlerInterface = new CallHandlerInterface(messenger);
              CallService.init(callHandlerInterface);
            } else if (callHandlerInterface.messenger != messenger) {
              // We've detected this is the real engine hosting the AudioHandler,
              // so update AudioHandlerInterface to connect to it.
              callHandlerInterface.switchToMessenger(messenger);
            }
            CallService.setAvailable(false);
            /*ComponentName cName = new ComponentName(applicationContext, CallService.class);
            Intent intent = new Intent();
            intent.setComponent(cName);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
              applicationContext.startService(intent);
              //applicationContext.startForegroundService(intent);
            } else {
              //applicationContext.startService(intent);
            }*/
            //this.registerPhoneAccount();
            CallService.setAvailable(true);
            //result.success(mapOf());
            result.success(mapOf());
            break;
        }
      } catch (Exception e) {
        e.printStackTrace();
        result.error(e.getMessage(), null, null);
      }
    }
  }

  private static class CallHandlerInterface implements MethodCallHandler, CallService.ServiceListener {
    public BinaryMessenger messenger;
    public MethodChannel channel;
    public CallHandlerInterface(BinaryMessenger messenger) {
      System.out.println("### new AudioHandlerInterface");
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

    public void invokeMethod(String method, Object arg) {
      channel.invokeMethod(method, arg);
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
    public void onStop() {
      invokeMethod("stop", mapOf());
    }

    @Override
    public void onPlayMediaItem(String metadata) {
      //invokeMethod("playMediaItem", mapOf("mediaItem", mediaMetadata2raw(metadata)));
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
    private String id;
    private String name;
    private String title;
    private boolean isPlaying = false;
    @RequiresApi(api = Build.VERSION_CODES.M)
    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
      System.out.println("### AudioHandlerInterface message: " + call.method);
      Map<?, ?> args = (Map<?, ?>)call.arguments;
      switch (call.method) {
        case "setMediaItem": {
          Map<?, ?> rawMediaItem = (Map<?, ?>)args.get("mediaItem");
          id= (String)rawMediaItem.get("id");
          name= (String)rawMediaItem.get("album");
          title=  (String)rawMediaItem.get("title");
          /*MediaMetadataCompat mediaMetadata = createMediaMetadata(rawMediaItem);
          AudioService.instance.setMetadata(mediaMetadata);*/
          result.success(null);
          break;
        }

        case "setState": {
          Map<?, ?> stateMap = (Map<?, ?>)args.get("state");
          AudioProcessingState processingState = AudioProcessingState.values()[(Integer)stateMap.get("processingState")];
          boolean playing = (Boolean)stateMap.get("playing");
          long updateTimeSinceEpoch = stateMap.get("updateTime") == null ? System.currentTimeMillis() : getLong(stateMap.get("updateTime"));
          Integer errorCode = (Integer)stateMap.get("errorCode");
          String errorMessage = (String)stateMap.get("errorMessage");
          result.success(null);
          if(playing==true && isPlaying!=true){
            launchForegroundService();
            isPlaying= true;
          }
          // On the flutter side, we represent the update time relative to the epoch.
          // On the native side, we must represent the update time relative to the boot time.
          long updateTimeSinceBoot = updateTimeSinceEpoch - bootTime;
          break;
        }
        case "stopService": {
          if (CallService.instance != null) {
            CallService.instance.stop();
          }
          isPlaying= false;
          result.success(null);
          break;
        }
      }
    }
    private void launchForegroundService() {
      try{
        Intent intent = new Intent(applicationContext, CallService.class);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          applicationContext.startForegroundService(intent);
        } else {
          applicationContext.startService(intent);
        }
      }catch (Exception e){
        System.out.println("Printed start "+e.toString());
      }
    }
  }

  static Map<String, Object> mapOf(Object... args) {
    Map<String, Object> map = new HashMap<String, Object>();
    for (int i = 0; i < args.length; i += 2) {
      map.put((String)args[i], args[i + 1]);
    }
    return map;
  }
  public static Long getLong(Object o) {
    return (o == null || o instanceof Long) ? (Long)o : new Long(((Integer)o).intValue());
  }

  public static Integer getInt(Object o) {
    return (o == null || o instanceof Integer) ? (Integer)o : new Integer((int)((Long)o).longValue());
  }
  private String getApplicationName(Context appContext) {
    ApplicationInfo applicationInfo = appContext.getApplicationInfo();
    int stringId = applicationInfo.labelRes;
    return stringId == 0 ? applicationInfo.nonLocalizedLabel.toString() : appContext.getString(stringId);
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
}

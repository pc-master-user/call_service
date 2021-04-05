package com.clinix.call_service;

import android.annotation.TargetApi;
import android.app.Activity;
import android.app.ActivityManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.os.PowerManager;
import android.telecom.CallAudioState;
import android.telecom.Connection;
import android.telecom.ConnectionRequest;
import android.telecom.ConnectionService;
import android.telecom.DisconnectCause;
import android.telecom.PhoneAccountHandle;
import android.telecom.TelecomManager;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;

import static com.clinix.call_service.Constants.*;

import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import io.flutter.embedding.engine.FlutterEngine;

import static com.clinix.call_service.Constants.EXTRA_CALLER_NAME;
import static com.clinix.call_service.Constants.EXTRA_CALL_NUMBER;

@RequiresApi(api = Build.VERSION_CODES.M)
public class CallService extends Service {
    private static final int NOTIFICATION_ID = 1124;
    private static final int REQUEST_CONTENT_INTENT = 1000;
    public static final String NOTIFICATION_CLICK_ACTION = "com.clinix.call_service.NOTIFICATION_CLICK";
    private static PendingIntent contentIntent;
    private static ServiceListener listener;
    static CallService instance;
    private PowerManager.WakeLock wakeLock;
    private CallServiceConfig config;
    private static Boolean isAvailable;
    private static Boolean isInitialized;
    private static Boolean isReachable;
    private static Boolean hasOutgoingCall;
    private static String notReachableCallUuid;
    private static ConnectionRequest currentConnectionRequest;
    private static PhoneAccountHandle phoneAccountHandle = null;
    private String notificationChannelId;
    private boolean notificationCreated;
    private AudioProcessingState processingState = AudioProcessingState.idle;
    private static boolean playing;
    private FlutterEngine flutterEngine;
    private static Activity currentActivity;
    public static void init(ServiceListener listener) {
        CallService.listener = listener;
    }
    private static String TAG = "CliniX:CallConnectionService";
    public static Map<String, VoiceConnection> currentConnections = new HashMap<>();
    public static Connection getConnection(String connectionId) {
        if (currentConnections.containsKey(connectionId)) {
            return currentConnections.get(connectionId);
        }
        return null;
    }

    public void configure(CallServiceConfig config) {
        this.config = config;
    }

    public void stop(){
        stopSelf();
    }
    @Override
    public void onDestroy() {
        System.out.println("### onDestroy");
        super.onDestroy();
        listener.onDestroy();
        listener = null;
        stopForeground(true);
        releaseWakeLock();
        instance = null;
        //currentActivity=null;
        notificationCreated = false;
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        notificationChannelId = getApplication().getPackageName() + ".channel";
        config = new CallServiceConfig(getApplicationContext());
        if (config.activityClassName != null) {
            Context context = getApplicationContext();
            Intent intent = new Intent((String)null);
            intent.setComponent(new ComponentName(context, config.activityClassName));
            //Intent intent = new Intent(context, config.activityClassName);
            intent.setAction(NOTIFICATION_CLICK_ACTION);
            contentIntent = PendingIntent.getActivity(context, REQUEST_CONTENT_INTENT, intent, PendingIntent.FLAG_UPDATE_CURRENT);
        } else {
            contentIntent = null;
        }
        notificationCreated = false;
        playing = false;
        processingState = AudioProcessingState.idle;
        PowerManager pm = (PowerManager)getSystemService(Context.POWER_SERVICE);
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, CallService.class.getName());
        flutterEngine = CallServicePlugin.getFlutterEngine(this);
        System.out.println("flutterEngine warmed up");
    }

    @Override
    public int onStartCommand(final Intent intent, int flags, int startId) {
        System.out.println("### onStartCommand");
        acquireWakeLock();
        //internalStartForeground();
        startForeground(NOTIFICATION_ID, buildNotification());
        notificationCreated = true;
        return START_NOT_STICKY;
    }

    private Connection createConnection(ConnectionRequest request) {
        Bundle extras = request.getExtras();
        HashMap<String, String> extrasMap = this.bundleToMap(extras);
        extrasMap.put(EXTRA_CALL_NUMBER, request.getAddress().toString());
        VoiceConnection connection = new VoiceConnection(this, extrasMap);
        connection.setConnectionCapabilities(Connection.CAPABILITY_MUTE | Connection.CAPABILITY_SUPPORT_HOLD);
        connection.setInitializing();
        connection.setExtras(extras);
        currentConnections.put(extras.getString(EXTRA_CALL_UUID), connection);
        return connection;
    }
    private Notification buildNotification() {
        NotificationCompat.Builder builder = getNotificationBuilder();
        if (config.notificationColor != -1)
            builder.setColor(config.notificationColor);
        builder.setUsesChronometer(true);
        builder.setCategory(Notification.CATEGORY_CALL);
        builder.addAction(getNotificationIcon("stop_icon"),
                "Hang UP",
                buildStopPendingIntent());
        builder.setOngoing(true);
        //builder.setStyle(style);
        Notification notification = builder.build();
        return notification;
    }
    private NotificationCompat.Builder getNotificationBuilder() {
        NotificationCompat.Builder notificationBuilder = null;
        if (notificationBuilder == null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                createChannel();
            int iconId = getResourceId(config.androidNotificationIcon);
            notificationBuilder = new NotificationCompat.Builder(this, notificationChannelId)
                    .setSmallIcon(iconId)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setShowWhen(false)
                    .setDeleteIntent(buildDeletePendingIntent())
            ;
        }
        return notificationBuilder;
    }
    @RequiresApi(Build.VERSION_CODES.O)
    private void createChannel() {
        NotificationManager notificationManager = (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
        NotificationChannel channel = notificationManager.getNotificationChannel(notificationChannelId);
        if (channel == null) {
            channel = new NotificationChannel(notificationChannelId, config.androidNotificationChannelName, NotificationManager.IMPORTANCE_LOW);
            channel.setShowBadge(config.androidShowNotificationBadge);
            if (config.androidNotificationChannelDescription != null)
                channel.setDescription(config.androidNotificationChannelDescription);
            notificationManager.createNotificationChannel(channel);
        }
    }

    PendingIntent buildStopPendingIntent() {
        Intent intent = new Intent(this, CallButtonReceiver.class);
        intent.setAction(CallButtonReceiver.ACTION_NOTIFICATION_DELETE);
        return PendingIntent.getBroadcast(this, 0, intent, 0);
    }

    PendingIntent buildDeletePendingIntent() {
        Intent intent = new Intent(this, CallButtonReceiver.class);
        intent.setAction(CallButtonReceiver.ACTION_NOTIFICATION_DELETE);
        return PendingIntent.getBroadcast(this, 0, intent, 0);
    }
    public void handleDeleteNotification() {
        if (listener == null) return;
        listener.onClose();
    }

    public void handleStop() {
        if (listener == null) return;
        listener.onStop();
    }

    public static void setAvailable(Boolean value) {
        Log.d(TAG, "setAvailable: " + (value ? "true" : "false"));
        if (value) {
            isInitialized = true;
        }

        isAvailable = value;
    }

    public static void setReachable() {
        Log.d(TAG, "setReachable");
        isReachable = true;
        instance.currentConnectionRequest = null;
    }

    int getResourceId(String resource) {
        String[] parts = resource.split("/");
        String resourceType = parts[0];
        String resourceName = parts[1];
        return getResources().getIdentifier(resourceName, resourceType, "audio_service");
    }

    public static void deinitConnection(String connectionId) {
        Log.d(TAG, "deinitConnection:" + connectionId);
        instance.hasOutgoingCall = false;

        if (currentConnections.containsKey(connectionId)) {
            currentConnections.remove(connectionId);
        }
    }

    @TargetApi(Build.VERSION_CODES.M)
    public class VoiceConnection extends Connection {
        private boolean isMuted = false;
        private HashMap<String, String> handle;
        private Context context;
        private static final String TAG = "RNCK:VoiceConnection";

        VoiceConnection(Context context, HashMap<String, String> handle) {
            super();
            this.handle = handle;
            this.context = context;

            String number = handle.get(EXTRA_CALL_NUMBER);
            String name = handle.get(EXTRA_CALLER_NAME);

            if (number != null) {
                setAddress(Uri.parse(number), TelecomManager.PRESENTATION_ALLOWED);
            }
            if (name != null && !name.equals("")) {
                setCallerDisplayName(name, TelecomManager.PRESENTATION_ALLOWED);
            }
        }

        @Override
        public void onExtrasChanged(Bundle extras) {
            super.onExtrasChanged(extras);
            HashMap attributeMap = (HashMap<String, String>)extras.getSerializable("attributeMap");
            if (attributeMap != null) {
                handle = attributeMap;
            }
        }

        @Override
        public void onCallAudioStateChanged(CallAudioState state) {
            if (state.isMuted() == this.isMuted) {
                return;
            }

            this.isMuted = state.isMuted();
            //sendCallRequestToActivity(isMuted ? ACTION_MUTE_CALL : ACTION_UNMUTE_CALL, handle);
        }

        @Override
        public void onAnswer() {
            super.onAnswer();
            Log.d(TAG, "onAnswer called");

            setConnectionCapabilities(getConnectionCapabilities() | Connection.CAPABILITY_HOLD);
            setAudioModeIsVoip(true);

            //sendCallRequestToActivity(ACTION_ANSWER_CALL, handle);
            //sendCallRequestToActivity(ACTION_AUDIO_SESSION, handle);
            Log.d(TAG, "onAnswer executed");
        }

        @Override
        public void onDisconnect() {
            super.onDisconnect();
            setDisconnected(new DisconnectCause(DisconnectCause.LOCAL));
            listener.onStop();
            //sendCallRequestToActivity(ACTION_END_CALL, handle);
            Log.d(TAG, "onDisconnect executed");
            try {
                ((CallService) context).deinitConnection(handle.get(EXTRA_CALL_UUID));
            } catch(Throwable exception) {
                Log.e(TAG, "Handle map error", exception);
            }
            destroy();
        }

        public void reportDisconnect(int reason) {
            super.onDisconnect();
            switch (reason) {
                case 1:
                    setDisconnected(new DisconnectCause(DisconnectCause.ERROR));
                    break;
                case 2:
                case 5:
                    setDisconnected(new DisconnectCause(DisconnectCause.REMOTE));
                    break;
                case 3:
                    setDisconnected(new DisconnectCause(DisconnectCause.BUSY));
                    break;
                case 4:
                    setDisconnected(new DisconnectCause(DisconnectCause.ANSWERED_ELSEWHERE));
                    break;
                case 6:
                    setDisconnected(new DisconnectCause(DisconnectCause.MISSED));
                    break;
                default:
                    break;
            }
            ((CallService)context).deinitConnection(handle.get(EXTRA_CALL_UUID));
            destroy();
        }

        @Override
        public void onAbort() {
            super.onAbort();
            setDisconnected(new DisconnectCause(DisconnectCause.REJECTED));
            //sendCallRequestToActivity(ACTION_END_CALL, handle);
            listener.onStop();
            Log.d(TAG, "onAbort executed");
            try {
                ((CallService) context).deinitConnection(handle.get(EXTRA_CALL_UUID));
            } catch(Throwable exception) {
                Log.e(TAG, "Handle map error", exception);
            }
            destroy();
        }

        @Override
        public void onReject() {
            super.onReject();
            setDisconnected(new DisconnectCause(DisconnectCause.REJECTED));
            //sendCallRequestToActivity(ACTION_END_CALL, handle);
            listener.onStop();
            Log.d(TAG, "onReject executed");
            try {
                ((CallService) context).deinitConnection(handle.get(EXTRA_CALL_UUID));
            } catch(Throwable exception) {
                Log.e(TAG, "Handle map error", exception);
            }
            destroy();
        }
    }

    public static interface ServiceListener {
        void onClick(MediaControl mediaControl);
        void onPrepare();
        void onPrepareFromMediaId(String mediaId, Bundle extras);
        void onPlay();
        void onPlayFromMediaId(String mediaId, Bundle extras);
        void onPause();
        void onStop();
        //
        // NON-STANDARD METHODS
        //
        void onPlayMediaItem(String metadata);

        void onTaskRemoved();

        void onClose();

        void onDestroy();
    }
    /**
     * https://stackoverflow.com/questions/5446565/android-how-do-i-check-if-activity-is-running
     *
     * @param context Context
     * @return boolean
     */
    public static boolean isRunning(Context context) {
        ActivityManager activityManager = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        List<ActivityManager.RunningTaskInfo> tasks = activityManager.getRunningTasks(Integer.MAX_VALUE);

        for (ActivityManager.RunningTaskInfo task : tasks) {
            if (context.getPackageName().equalsIgnoreCase(task.baseActivity.getPackageName()))
                return true;
        }
        return false;
    }
    private void acquireWakeLock() {
        if (!wakeLock.isHeld())
            wakeLock.acquire();
    }

    private void releaseWakeLock() {
        if (wakeLock.isHeld())
            wakeLock.release();
    }
    private int getNotificationIcon(String iconName) {
        int resourceId = getApplicationContext().getResources().getIdentifier(iconName, "drawable", getApplicationContext().getPackageName());
        return resourceId;
    }
    private HashMap<String, String> bundleToMap(Bundle extras) {
        HashMap<String, String> extrasMap = new HashMap<>();
        Set<String> keySet = extras.keySet();
        Iterator<String> iterator = keySet.iterator();

        while(iterator.hasNext()) {
            String key = iterator.next();
            if (extras.get(key) != null) {
                extrasMap.put(key, extras.get(key).toString());
            }
        }
        return extrasMap;
    }
}

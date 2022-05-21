package com.clinix.call_service;

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
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.PowerManager;

import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;

import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Set;

import io.flutter.embedding.engine.FlutterEngine;

@RequiresApi(api = Build.VERSION_CODES.M)
public class CallService extends Service {
    private static final int RING_NOTIFICATION_ID = 1068;
    private static final int NOTIFICATION_ID = 1069;
    private static final int REQUEST_CONTENT_INTENT = 1100;
    public static final String NOTIFICATION_CLICK_ACTION = "com.clinix.call_service.NOTIFICATION_CLICK";
    public static final String ANSWER_CLICK_ACTION = "com.clinix.call_service.ANSWER_CLICK";
    public static final String NOTIFICATION_CHANNEL_ID = "CallChannel";
    public static final String ACTION_STOP_SERVICE = "STOP";
    public static final String ACTION_DECLINE = "DECLINE";
    public static final String ACTION_ANSWER = "ANSWER";
    private static final int SENSOR_SENSITIVITY = 4;
    private static PendingIntent contentIntent;
    private static ServiceListener listener;
    static CallService instance;
    private CallData callData;
    private PowerManager.WakeLock wakeLock;
    private PowerManager.WakeLock pWakeLock;
    private CallServiceConfig config;
    private static Boolean isAvailable;
    private static Boolean isInitialized;
    private static Boolean isReachable;
    private static Boolean hasOutgoingCall;
    private static String notReachableCallUuid;
    final Handler handler = new Handler();
    private String ONGOING_CHANNEL= "ONGOING CHANNEL";
    private String RINGING_CHANNEL="RINGING CHANNEL";
    private boolean notificationCreated;
    private CallProcessingState processingState = CallProcessingState.idle;
    private static boolean playing;
    private FlutterEngine flutterEngine;
    private static Activity currentActivity;
    public static void init(ServiceListener listener) {
        CallService.listener = listener;
    }
    private static String TAG = "CliniX:CallConnectionService";
    /*private SensorManager sensorManager;
    private Sensor proximity;*/

    public void configure(CallServiceConfig config) {
        this.config = config;
    }

    public void stop(){
        //sensorManager.unregisterListener(this);
        stopForeground(true);
        releaseWakeLock();
        stopSelf();
    }
    @Override
    public void onDestroy() {
        System.out.println("### onDestroy");
        super.onDestroy();
        listener.onDestroy();
        listener = null;
        /*proximity= null;
        sensorManager=null;*/
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
        config = new CallServiceConfig(getApplicationContext());
        if (config.activityClassName != null) {
            Context context = getApplicationContext();
            Intent intent = new Intent((String)null);
            intent.setComponent(new ComponentName(context, config.activityClassName));
            //Intent intent = new Intent(context, config.activityClassName);
            intent.setAction(NOTIFICATION_CLICK_ACTION);
            contentIntent = PendingIntent.getActivity(context, REQUEST_CONTENT_INTENT, intent, PendingIntent.FLAG_MUTABLE);
        } else {
            contentIntent = null;
        }
        notificationCreated = false;
        playing = false;
        processingState = CallProcessingState.idle;
        PowerManager pm = (PowerManager)getSystemService(Context.POWER_SERVICE);
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK , CallService.class.getName());
        pWakeLock= pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, CallService.class.getName());
        flutterEngine = CallServicePlugin.getFlutterEngine(this);
        /*sensorManager = (SensorManager) getSystemService(Context.SENSOR_SERVICE);
        proximity = sensorManager.getDefaultSensor(Sensor.TYPE_PROXIMITY);*/
        System.out.println("flutterEngine warmed up");
    }

    @Override
    public int onStartCommand(final Intent intent, int flags, int startId) {
        if(intent.getAction()==null){
            System.out.println("### onStartCommand");
            acquireWakeLock();
            //sensorManager.registerListener(this, proximity,SensorManager.SENSOR_DELAY_NORMAL);
            return START_NOT_STICKY;
        }else if(intent.getAction() == ACTION_STOP_SERVICE){
            handleStop();
            //stopSelf();
        }else if(intent.getAction() == ACTION_DECLINE){
            stop();
            updateNotification();
            //stopSelf();
        }else if(intent.getAction() == ACTION_ANSWER){
            handlePlay();
            updateNotification();
            //stopSelf();
        }
        return START_NOT_STICKY;
    }

    private Notification buildNotification(boolean useChronometer) {
        NotificationCompat.Builder builder = getNotificationBuilder()
                .setSmallIcon(getNotificationIcon("app_icon"))
                .setColor(config.notificationColor)
                .setContentTitle(this.callData.description)
                .setContentText(this.callData.callerName)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setContentIntent(contentIntent)
                .setOngoing(true);
        if(useChronometer){
            builder.setUsesChronometer(true);
        }
        Intent stopSelf = new Intent(this, CallService.class);
        stopSelf.setAction(ACTION_STOP_SERVICE);
        PendingIntent pStopSelf = PendingIntent
                .getService(this, 0, stopSelf, PendingIntent.FLAG_CANCEL_CURRENT);
        builder.addAction(getNotificationIcon("stop_icon"),
                "HangUp",
                pStopSelf);
        builder.setSubText("consult");
        return  builder.build();
    }

    private NotificationCompat.Builder getNotificationBuilder() {
        NotificationCompat.Builder notificationBuilder = null;
        if (notificationBuilder == null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                createChannel();
            int iconId = getResourceId(config.androidNotificationIcon);
            notificationBuilder = new NotificationCompat.Builder(this, ONGOING_CHANNEL)
                    .setSmallIcon(iconId)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setShowWhen(false)
                    .setDeleteIntent(buildDeletePendingIntent());
        }
        return notificationBuilder;
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private void createChannel() {
        NotificationManager notificationManager = (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
        NotificationChannel channel = notificationManager.getNotificationChannel(ONGOING_CHANNEL);
        if (channel == null) {
            channel = new NotificationChannel(ONGOING_CHANNEL, config.androidNotificationChannelName, NotificationManager.IMPORTANCE_LOW);
            channel.setShowBadge(config.androidShowNotificationBadge);
            if (config.androidNotificationChannelDescription != null)
                channel.setDescription(config.androidNotificationChannelDescription);
            notificationManager.createNotificationChannel(channel);
        }
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
    public void handlePlay() {
        if (listener == null) return;
        listener.onPlay();
    }

    int getResourceId(String resource) {
        String[] parts = resource.split("/");
        String resourceType = parts[0];
        String resourceName = parts[1];
        return getResources().getIdentifier(resourceName, resourceType, "Call_service");
    }

    void setState(CallProcessingState processingState, boolean playing, Integer errorCode, String errorMessage) {
        boolean wasPlaying = this.playing;
        CallProcessingState oldProcessingState = this.processingState;
        this.processingState = processingState;
        this.playing = playing;
        if (!wasPlaying && playing) {
            enterPlayingState();
        } else if (wasPlaying && !playing) {
            exitPlayingState();
        }
        if (oldProcessingState != CallProcessingState.idle && processingState == CallProcessingState.idle) {
            // TODO: Handle completed state as well?
            stop();
        }
        if(oldProcessingState != CallProcessingState.ready && processingState == CallProcessingState.ready){
            updateNotification();
        }
        /*if(processingState == CallProcessingState.loading){
            enterRingingState();
        }*/
        //updateNotification();
    }
    private boolean enterPlayingState() {
        acquireWakeLock();
        startService(new Intent(CallService.this, CallService.class));
        startForeground(NOTIFICATION_ID, buildNotification(false));
        notificationCreated = true;
        return true;
    }

    private void exitPlayingState() {
        stopForeground(true);
        releaseWakeLock();
    }

    private void updateNotification() {
        if (!notificationCreated) return;
        NotificationManager notificationManager = (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
        notificationManager.notify(NOTIFICATION_ID, buildNotification(true));
    }

    /*@Override
    public void onSensorChanged(SensorEvent event) {
        if (event.values[0] >= -SENSOR_SENSITIVITY && event.values[0] <= SENSOR_SENSITIVITY) {
            //near
        } else {
            //far
        }
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {

    }*/

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

    private void acquireWakeLock() {
        if (!wakeLock.isHeld()){
            wakeLock.acquire();
        }
        if(!pWakeLock.isHeld()){
            pWakeLock.acquire();;
        }
    }

    private void releaseWakeLock() {
        if (wakeLock.isHeld()){
            wakeLock.release();
        }
        if(pWakeLock.isHeld()){
            pWakeLock.release(1);
        }
    }

    public void setCallData(CallData callData){
        this.callData= callData;
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
    public boolean isActivityRunning() {
        ActivityManager activityManager = (ActivityManager) getApplicationContext().getSystemService(Context.ACTIVITY_SERVICE);
        List<ActivityManager.RunningTaskInfo> tasks = activityManager.getRunningTasks(Integer.MAX_VALUE);
        for (ActivityManager.RunningTaskInfo task : tasks) {
            if (config.activityClassName.equalsIgnoreCase(task.baseActivity.getClassName()))
                return true;
        }
        return false;
    }
}

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
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;

import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;

import io.flutter.embedding.engine.FlutterEngine;

import static com.clinix.call_service.Constants.EXTRA_CALLER_NAME;
import static com.clinix.call_service.Constants.EXTRA_CALL_NUMBER;
import static com.clinix.call_service.Constants.EXTRA_CALL_UUID;

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
    private static PendingIntent contentIntent;
    private static ServiceListener listener;
    static CallService instance;
    private CallData callData;
    private PowerManager.WakeLock wakeLock;
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

    public void configure(CallServiceConfig config) {
        this.config = config;
    }

    public void stop(){
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
            contentIntent = PendingIntent.getActivity(context, REQUEST_CONTENT_INTENT, intent, PendingIntent.FLAG_UPDATE_CURRENT);
        } else {
            contentIntent = null;
        }
        notificationCreated = false;
        playing = false;
        processingState = CallProcessingState.idle;
        PowerManager pm = (PowerManager)getSystemService(Context.POWER_SERVICE);
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, CallService.class.getName());
        flutterEngine = CallServicePlugin.getFlutterEngine(this);
        System.out.println("flutterEngine warmed up");
    }

    @Override
    public int onStartCommand(final Intent intent, int flags, int startId) {
        if(intent.getAction()==null){
            System.out.println("### onStartCommand");
            acquireWakeLock();
            return START_NOT_STICKY;
        }else if(intent.getAction()== ACTION_STOP_SERVICE){
            handleStop();
            //stopSelf();
        }else if(intent.getAction()== ACTION_DECLINE){
            stop();
            updateNotification();
            //stopSelf();
        }else if(intent.getAction()== ACTION_ANSWER){
            //boolean isRunning= isActivityRunning();
            /*Intent focusIntent = new Intent((String)null);
            focusIntent.setComponent(new ComponentName(getApplicationContext(), config.activityClassName));
            //Intent intent = new Intent(context, config.activityClassName);
            focusIntent.setAction(ANSWER_CLICK_ACTION);
            focusIntent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
            getApplicationContext().startActivity(focusIntent);*/
            handlePlay();
            updateNotification();
            //stopSelf();
        }
        return START_NOT_STICKY;
    }

    private Notification buildNotification() {
        NotificationCompat.Builder builder = getNotificationBuilder()
                .setSmallIcon(getNotificationIcon("app_icon"))
                .setColor(config.notificationColor)
                .setContentTitle(this.callData.description)
                .setContentText(this.callData.callerName)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setContentIntent(contentIntent)
                .setUsesChronometer(true)
                .setOngoing(true);
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

    private void startRingNotification() {
        NotificationCompat.Builder builder = getHighNotificationBuilder()
                .setSmallIcon(getNotificationIcon("app_icon"))
                .setColor(config.notificationColor)
                .setContentTitle(this.callData.description)
                .setContentText(this.callData.callerName)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setContentIntent(contentIntent)
                .setUsesChronometer(true)
                .setOngoing(true)
                .setFullScreenIntent(contentIntent,true)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setTimeoutAfter(40000L).setAutoCancel(true);
        Intent stopSelf = new Intent(this, CallService.class);
        stopSelf.setAction(ACTION_DECLINE);
        PendingIntent pStopSelf = PendingIntent
                .getService(this, 0, stopSelf, PendingIntent.FLAG_CANCEL_CURRENT);
        builder.addAction(getNotificationIcon("stop_icon"),
                "Decline",
                pStopSelf);
        Intent answer = new Intent(this, CallService.class);
        answer.setAction(ACTION_ANSWER);
        PendingIntent pAnswer = PendingIntent
                .getService(this, 0, answer, PendingIntent.FLAG_CANCEL_CURRENT);
        builder.addAction(getNotificationIcon("stop_icon"),
                "Answer",
                pAnswer);
        builder.setSubText("consult");
        Notification notification= builder.build();
        NotificationManager notificationManager = (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
        notificationManager.notify(RING_NOTIFICATION_ID,notification);
        //notification.flags = notification.flags |= Notification.FLAG_INSISTENT;
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

    private NotificationCompat.Builder getHighNotificationBuilder() {
        NotificationCompat.Builder notificationBuilder = null;
        if (notificationBuilder == null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                createHighChannel();
            int iconId = getResourceId(config.androidNotificationIcon);
            notificationBuilder = new NotificationCompat.Builder(this, RINGING_CHANNEL)
                    .setSmallIcon(iconId)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setShowWhen(false)
                    .setDeleteIntent(buildDeletePendingIntent());
        }
        return notificationBuilder;
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private void createHighChannel() {
        Uri uri= RingtoneManager.getActualDefaultRingtoneUri(this.getApplicationContext(), RingtoneManager.TYPE_RINGTONE);
        NotificationManager notificationManager = (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
        NotificationChannel channel = notificationManager.getNotificationChannel(RINGING_CHANNEL);
        if (channel == null) {
            channel = new NotificationChannel(RINGING_CHANNEL, "Call Ringing", NotificationManager.IMPORTANCE_HIGH);
            channel.setShowBadge(config.androidShowNotificationBadge);
            if (config.androidNotificationChannelDescription != null)
                channel.setDescription(config.androidNotificationChannelDescription);
            notificationManager.createNotificationChannel(channel);
            AudioAttributes att = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build();
            channel.setSound(uri,att);
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
        /*if(processingState == CallProcessingState.loading){
            enterRingingState();
        }*/
        //updateNotification();
    }

    private boolean enterPlayingState() {
        acquireWakeLock();
        startService(new Intent(CallService.this, CallService.class));
        startForeground(NOTIFICATION_ID, buildNotification());
        notificationCreated = true;
        return true;
    }

    private boolean enterRingingState() {
        acquireWakeLock();
        startService(new Intent(CallService.this, CallService.class));
        startRingNotification();
        //startForeground(RING_NOTIFICATION_ID, buildRingNotification());
        notificationCreated = true;
        return true;
    }

    private void exitPlayingState() {
        stopForeground(false);
        releaseWakeLock();
    }

    private void updateNotification() {
        if (!notificationCreated) return;
        NotificationManager notificationManager = (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
        notificationManager.cancel(RING_NOTIFICATION_ID);
        //notificationManager.notify(NOTIFICATION_ID, buildNotification());
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

    private void acquireWakeLock() {
        if (!wakeLock.isHeld())
            wakeLock.acquire();
    }

    private void releaseWakeLock() {
        if (wakeLock.isHeld())
            wakeLock.release();
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

package com.clinix.call_service;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

import androidx.annotation.RequiresApi;

public class CallButtonReceiver extends BroadcastReceiver {
    public static final String ACTION_NOTIFICATION_DELETE = "com.clinix.CallService.intent.action.ACTION_NOTIFICATION_DELETE";
    public static final String ACTION_STOP = "com.clinix.CallService.intent.action.ACTION_STOP";
    @RequiresApi(api = Build.VERSION_CODES.M)
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent != null
                && ACTION_NOTIFICATION_DELETE.equals(intent.getAction())
                && CallService.instance != null) {
            CallService.instance.handleDeleteNotification();
            return;
        }
        if (intent != null
                && ACTION_STOP.equals(intent.getAction())
                && CallService.instance != null) {
            CallService.instance.handleStop();
            return;
        }
        //This is used to close the notification tray
        Intent it = new Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS);
        context.sendBroadcast(it);
    }
}

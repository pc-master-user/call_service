package com.clinix.call_service;

import android.content.Context;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

import androidx.annotation.RequiresApi;

public class MediaButtonReceiver extends androidx.media.session.MediaButtonReceiver {
    public static final String ACTION_NOTIFICATION_DELETE = "com.clinix.call_service.intent.action.ACTION_NOTIFICATION_DELETE";

    @RequiresApi(api = Build.VERSION_CODES.M)
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent != null
                && ACTION_NOTIFICATION_DELETE.equals(intent.getAction())
                && CallService.instance != null) {
            CallService.instance.handleDeleteNotification();
            return;
        }
        super.onReceive(context, intent);
    }
}

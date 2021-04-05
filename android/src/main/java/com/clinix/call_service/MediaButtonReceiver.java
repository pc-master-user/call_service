package com.clinix.call_service;

import android.content.Context;
import android.content.Context;
import android.content.Intent;

public class MediaButtonReceiver extends androidx.media.session.MediaButtonReceiver {
    public static final String ACTION_NOTIFICATION_DELETE = "com.clinix.call_service.intent.action.ACTION_NOTIFICATION_DELETE";

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

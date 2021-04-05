package com.clinix.call_service;

import android.content.Context;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;

public class CallServiceActivity extends FlutterActivity {
    @Override
    public FlutterEngine provideFlutterEngine(Context context) {
        return CallServicePlugin.getFlutterEngine(context);
    }
}

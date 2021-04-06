package com.clinix.call_service_example;

import android.content.Context;

import com.clinix.call_service.CallServicePlugin;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;

public class MainActivity extends FlutterActivity {
    @Override
    public FlutterEngine provideFlutterEngine(Context context) {
        return CallServicePlugin.getFlutterEngine(context);
    }
}

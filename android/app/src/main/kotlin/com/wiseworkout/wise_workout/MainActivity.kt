package com.wiseworkout.wise_workout

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) — required by package:health's
// Health Connect integration, which uses registerForActivityResult() to launch
// the permission grant flow. That API needs an Activity castable to
// ComponentActivity, which only FlutterFragmentActivity provides (health
// package README, "Android 14" setup section).
class MainActivity : FlutterFragmentActivity()

package com.example.coffee_person

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "coffee_person/widget",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "updateCoffeeWidget" -> {
          CoffeeStatsWidgetProvider.requestUpdate(applicationContext)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }
}

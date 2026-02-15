package dev.solsynth.community.coffee_person

import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

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

    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "coffee_person/share",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "shareImage" -> {
          val args = call.arguments as? Map<*, *>
          val bytes = args?.get("bytes") as? ByteArray
          val text = args?.get("text") as? String
          if (bytes == null || bytes.isEmpty()) {
            result.error("invalid_args", "bytes is required", null)
            return@setMethodCallHandler
          }
          try {
            sharePng(bytes, text)
            result.success(null)
          } catch (e: Exception) {
            result.error("share_failed", e.message, null)
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun sharePng(bytes: ByteArray, text: String?) {
    val cacheDir = File(applicationContext.cacheDir, "share")
    if (!cacheDir.exists()) cacheDir.mkdirs()
    val file = File(cacheDir, "coffee_checkin_${System.currentTimeMillis()}.png")
    FileOutputStream(file).use { it.write(bytes) }

    val uri = FileProvider.getUriForFile(
      applicationContext,
      applicationContext.packageName + ".fileprovider",
      file,
    )

    val intent = Intent(Intent.ACTION_SEND).apply {
      type = "image/png"
      putExtra(Intent.EXTRA_STREAM, uri)
      if (!text.isNullOrBlank()) putExtra(Intent.EXTRA_TEXT, text)
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      clipData = ClipData.newUri(contentResolver, "coffee_checkin", uri)
    }
    startActivity(Intent.createChooser(intent, "分享"))
  }
}

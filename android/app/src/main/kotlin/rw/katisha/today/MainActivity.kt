package rw.katisha.today

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "rw.katisha.today/screen_security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecureFlag" -> {
                    enableSecureFlag()
                    result.success(null)
                }
                "disableSecureFlag" -> {
                    disableSecureFlag()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun enableSecureFlag() {
        runOnUiThread {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private fun disableSecureFlag() {
        runOnUiThread {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}

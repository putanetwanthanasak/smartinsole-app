package th.ac.kmutt.smartinsole

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The camera plugin mirrors the front preview only when the engine's
        // surface producer does not handle crop and rotation itself; the
        // foot check asks the same question so the front preview is always
        // mirrored (lib/footcheck/plugin_foot_camera.dart, S8C).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartinsole/camera_preview")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "handlesCropAndRotation" -> {
                        val producer = flutterEngine.renderer.createSurfaceProducer()
                        try {
                            result.success(producer.handlesCropAndRotation())
                        } finally {
                            producer.release()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

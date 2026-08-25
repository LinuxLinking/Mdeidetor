package com.mdeditor.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * 接收外部 intent (`ACTION_VIEW`) 传入的 `.md` 文件 URI。
 *
 * 触发路径(对应 `AndroidManifest.xml` 中 `action.VIEW` 的 intent-filter):
 *   1. **冷启动**:外部文件管理器"打开方式"选 Mdeditor → onCreate 里 intent 已带 data,
 *      MainActivity 把 URI 暂存到本 channel 的 `pendingUri`,Dart 端在 `main()` 启动后
 *      调 `getInitialUri` 取走并路由到 EditorPage。
 *   2. **singleTop 热启动**:新 intent 走 `onNewIntent`,MainActivity 调
 *      [handleIntent] 暂存 URI，并通过 EventChannel 立即推送给 Dart。
 *
 * 权限:`ACTION_VIEW` 的 intent 通常已带 `FLAG_GRANT_READ_URI_PERMISSION`,
 *   需显式 `takePersistableUriPermission(read+write)` 才能在 app 重启后继续访问。
 *   若来源仅授予 read,会抛 `SecurityException`,本类 catch 后只本次会话可读。
 */
class IntentChannel(private val activity: Activity) {
    companion object {
        const val CHANNEL = "mdeditor/intent"
        const val EVENTS = "mdeditor/intent/events"
        private const val TAG = "IntentChannel"
    }

    @Volatile
    private var pendingUri: String? = null
    private var eventSink: EventChannel.EventSink? = null

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialUri" -> {
                        // 一次性取走:避免重启后仍路由到旧 URI
                        val uri = pendingUri
                        pendingUri = null
                        result.success(uri)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(engine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    /**
     * 在 `MainActivity.onCreate` / `onNewIntent` 中调用:
     * 如 `intent.action == ACTION_VIEW` 且带 data,则 takePersistableUriPermission
     * 并暂存到 [pendingUri]。
     */
    fun handleIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_VIEW) return
        val uri: Uri = intent.data ?: return
        val flags = (Intent.FLAG_GRANT_READ_URI_PERMISSION
                or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try {
            activity.contentResolver.takePersistableUriPermission(uri, flags)
        } catch (e: SecurityException) {
            // 某些来源只授予 read,不允许 take persistable → 仅本次会话可读
            Log.w(TAG, "takePersistableUriPermission failed: ${e.message}")
        }
        pendingUri = uri.toString()
        eventSink?.success(pendingUri)
    }
}

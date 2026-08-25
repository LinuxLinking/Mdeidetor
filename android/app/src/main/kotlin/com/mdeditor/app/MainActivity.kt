package com.mdeditor.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.content.Intent

class MainActivity : FlutterActivity() {
    private lateinit var safChannel: SafChannel
    private lateinit var printChannel: PrintChannel
    private lateinit var intentChannel: IntentChannel
    private lateinit var nativeRenderChannel: NativeRenderChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        safChannel = SafChannel(this)
        safChannel.register(flutterEngine)

        printChannel = PrintChannel(this)
        printChannel.register(flutterEngine)

        intentChannel = IntentChannel(this)
        intentChannel.register(flutterEngine)
        nativeRenderChannel = NativeRenderChannel(this)
        nativeRenderChannel.register(flutterEngine.dartExecutor.binaryMessenger)
        // 处理冷启动 intent(外部"打开方式"拉起本 app 时,intent 已在 onCreate 时带 data)
        intentChannel.handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) // 让后续 getIntent() 能拿到最新 intent
        // singleTop 热启动:新 intent 走这里,转给 IntentChannel 暂存
        intentChannel.handleIntent(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        safChannel.onActivityResult(requestCode, resultCode, data)
    }
}

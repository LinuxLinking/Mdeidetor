package com.mdeditor.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class SafChannel(private val activity: Activity) {
    companion object {
        const val CHANNEL = "mdeditor/saf"
        const val REQ_OPEN = 0xA001
        const val REQ_SAVE = 0xA002
    }

    private var pendingResult: MethodChannel.Result? = null

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openDocument" -> {
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            // Android 14+:单一 type 严格匹配会过滤掉许多 .md 文件
                            // (有些文件管理器把 .md 注册为 text/plain 或 application/octet-stream)
                            // 改用 */* + EXTRA_MIME_TYPES 数组放宽过滤
                            type = "*/*"
                            val mimes = arrayOf(
                                "text/markdown",
                                "text/x-markdown",
                                "text/plain",
                                "application/octet-stream"
                            )
                            putExtra(Intent.EXTRA_MIME_TYPES, mimes)
                        }
                        activity.startActivityForResult(intent, REQ_OPEN)
                    }
                    "createDocument" -> {
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = call.argument<String>("mime") ?: "*/*"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("suggestedName"))
                        }
                        activity.startActivityForResult(intent, REQ_SAVE)
                    }
                    "readUri" -> {
                        val uri = Uri.parse(call.argument<String>("uri"))
                        try {
                            // 显式 UTF-8 解码:默认 bufferedReader 用平台 charset,
                            // 在中文 Windows/旧 Android 上可能误判为 GBK 导致乱码
                            val text = activity.contentResolver.openInputStream(uri)?.use {
                                it.bufferedReader(Charsets.UTF_8).readText()
                            }
                            result.success(text)
                        } catch (e: Exception) {
                            result.error("READ_FAIL", e.message, null)
                        }
                    }
                    "writeUri" -> {
                        val uri = Uri.parse(call.argument<String>("uri"))
                        val bytes = call.argument<ByteArray>("bytes")!!
                        try {
                            activity.contentResolver.openOutputStream(uri, "wt")?.use {
                                it.write(bytes)
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("WRITE_FAIL", e.message, null)
                        }
                    }
                    "queryName" -> {
                        // Phase 6 修复:之前 Dart 端 [SafColumn.name] 调本方法但
                        // Kotlin 端未实现,导致 MissingPluginException 抛出,
                        // _loadInitial 走 catch 丢弃已读文本 → 编辑器空白。
                        val uri = Uri.parse(call.argument<String>("uri"))
                        try {
                            val name = activity.contentResolver.query(
                                uri,
                                arrayOf(OpenableColumns.DISPLAY_NAME),
                                null, null, null
                            )?.use { c ->
                                if (c.moveToFirst()) c.getString(0) else null
                            }
                            result.success(name)
                        } catch (e: Exception) {
                            result.error("QUERY_NAME_FAIL", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pendingResult?.success(null)
            pendingResult = null
            return
        }

        val uri = data.data!!
        when (requestCode) {
            REQ_OPEN -> {
                val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                try {
                    activity.contentResolver.takePersistableUriPermission(uri, flags)
                } catch (e: Exception) {
                }
                pendingResult?.success(uri.toString())
            }
            REQ_SAVE -> pendingResult?.success(uri.toString())
        }
        pendingResult = null
    }
}

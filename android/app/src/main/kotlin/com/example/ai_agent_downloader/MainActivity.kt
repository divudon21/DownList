package com.example.ai_agent_downloader

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_NAME = "com.example.ai_agent_downloader/native"
        private const val REQ_PICK_FILES = 9401
        private const val BUFFER_SIZE = 65536

        private val BROWSER_PACKAGES = setOf(
            "com.android.chrome",
            "com.chrome.beta",
            "com.chrome.dev",
            "com.chrome.canary",
            "org.mozilla.firefox",
            "org.mozilla.fenix",
            "com.brave.browser",
            "com.microsoft.emmx",
            "com.opera.browser",
            "com.opera.mini.native",
            "com.sec.android.app.sbrowser",
            "com.UCMobile.intl",
            "com.duckduckgo.mobile.android",
            "com.vivaldi.browser",
            "com.kiwibrowser.browser"
        )
    }

    private class ActiveUpload(
        val cancelled: AtomicBoolean = AtomicBoolean(false),
        @Volatile var connection: HttpURLConnection? = null,
        @Volatile var inputStream: InputStream? = null
    )

    private var methodChannel: MethodChannel? = null
    private var pendingPickResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val uploadExecutor = Executors.newCachedThreadPool()
    private val activeUploads = ConcurrentHashMap<String, ActiveUpload>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFiles" -> handlePickFiles(result)
                "startUpload" -> handleStartUpload(call, result)
                "cancelUpload" -> handleCancelUpload(call, result)
                "cancelAllUploads" -> handleCancelAllUploads(result)
                "openExternalPlayer" -> handleOpenExternalPlayer(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handlePickFiles(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("ALREADY_ACTIVE", "File picker is already open", null)
            return
        }
        pendingPickResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
            startActivityForResult(intent, REQ_PICK_FILES)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("PICKER_ERROR", e.message ?: "Could not open file picker", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK_FILES) return

        val callback = pendingPickResult
        pendingPickResult = null
        if (callback == null) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            callback.success(emptyList<Map<String, Any>>())
            return
        }

        val uris = mutableListOf<Uri>()
        val clipData = data.clipData
        if (clipData != null) {
            for (i in 0 until clipData.itemCount) {
                val u = clipData.getItemAt(i)?.uri
                if (u != null) uris.add(u)
            }
        } else {
            data.data?.let { uris.add(it) }
        }

        val pickedList = mutableListOf<Map<String, Any>>()
        for (uri in uris) {
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: Exception) {
                // Temporary read permission is already granted for this session.
            }

            var displayName = "file_${System.currentTimeMillis()}"
            var sizeBytes = 0L

            try {
                contentResolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                    null,
                    null,
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIdx >= 0 && !cursor.isNull(nameIdx)) {
                            val n = cursor.getString(nameIdx)
                            if (!n.isNullOrBlank()) displayName = n
                        }
                        val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) {
                            sizeBytes = cursor.getLong(sizeIdx)
                        }
                    }
                }
            } catch (_: Exception) {
            }

            if (sizeBytes <= 0L) {
                try {
                    contentResolver.openAssetFileDescriptor(uri, "r")?.use { afd ->
                        if (afd.length > 0L) sizeBytes = afd.length
                    }
                } catch (_: Exception) {
                }
            }

            val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
            pickedList.add(
                mapOf(
                    "uri" to uri.toString(),
                    "name" to displayName,
                    "size" to sizeBytes,
                    "mimeType" to mimeType
                )
            )
        }

        callback.success(pickedList)
    }

    private fun emitUploadEvent(payload: Map<String, Any?>) {
        mainHandler.post {
            methodChannel?.invokeMethod("onUploadEvent", payload)
        }
    }

    private fun handleStartUpload(call: MethodCall, result: MethodChannel.Result) {
        val uploadId = call.argument<String>("uploadId")
        val uriStr = call.argument<String>("uri")
        val fileName = call.argument<String>("fileName") ?: "uploaded_file.bin"
        val fileSize = (call.argument<Number>("fileSize"))?.toLong() ?: 0L
        val uploadUrl = call.argument<String>("uploadUrl")

        if (uploadId.isNullOrBlank() || uriStr.isNullOrBlank() || uploadUrl.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Missing upload arguments", null)
            return
        }

        val active = ActiveUpload()
        activeUploads[uploadId] = active
        result.success(true)

        uploadExecutor.execute {
            runStreamingUpload(uploadId, uriStr, fileName, fileSize, uploadUrl, active)
        }
    }

    private fun runStreamingUpload(
        uploadId: String,
        uriStr: String,
        fileName: String,
        declaredSize: Long,
        uploadUrl: String,
        active: ActiveUpload
    ) {
        var conn: HttpURLConnection? = null
        var rawStream: InputStream? = null
        try {
            if (active.cancelled.get()) {
                emitUploadEvent(mapOf("uploadId" to uploadId, "status" to "cancelled"))
                return
            }

            val uri = Uri.parse(uriStr)
            rawStream = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Cannot read selected file from storage")
            active.inputStream = rawStream

            val boundary = "----OkAiBoundary${UUID.randomUUID().toString().replace("-", "")}"
            val safeName = fileName
                .replace("\"", "_")
                .replace("\r", "")
                .replace("\n", "")

            val headerStr = buildString {
                append("--").append(boundary).append("\r\n")
                append("Content-Disposition: form-data; name=\"file\"; filename=\"")
                    .append(safeName)
                    .append("\"\r\n")
                append("Content-Type: application/octet-stream\r\n\r\n")
            }
            val footerStr = "\r\n--$boundary--\r\n"

            val headerBytes = headerStr.toByteArray(Charsets.UTF_8)
            val footerBytes = footerStr.toByteArray(Charsets.UTF_8)

            conn = (URL(uploadUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doInput = true
                doOutput = true
                useCaches = false
                connectTimeout = 30_000
                readTimeout = 300_000
                setRequestProperty("Connection", "Keep-Alive")
                setRequestProperty("Accept", "application/json")
                setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
                if (declaredSize > 0L) {
                    val totalLen = headerBytes.size.toLong() + declaredSize + footerBytes.size.toLong()
                    setFixedLengthStreamingMode(totalLen)
                } else {
                    setChunkedStreamingMode(BUFFER_SIZE)
                }
            }

            active.connection = conn
            if (active.cancelled.get()) {
                conn.disconnect()
                emitUploadEvent(mapOf("uploadId" to uploadId, "status" to "cancelled"))
                return
            }

            val buf = ByteArray(BUFFER_SIZE)
            var uploaded = 0L
            var lastReportTime = System.currentTimeMillis()
            var lastReportBytes = 0L
            var smoothedSpeed = 0.0

            BufferedOutputStream(conn.outputStream, BUFFER_SIZE).use { out ->
                out.write(headerBytes)
                BufferedInputStream(rawStream, BUFFER_SIZE).use { input ->
                    while (!active.cancelled.get()) {
                        val maxToRead = if (declaredSize > 0L) {
                            val remaining = declaredSize - uploaded
                            if (remaining <= 0L) break
                            minOf(buf.size.toLong(), remaining).toInt()
                        } else {
                            buf.size
                        }

                        val readCount = input.read(buf, 0, maxToRead)
                        if (readCount == -1) break

                        out.write(buf, 0, readCount)
                        uploaded += readCount

                        val now = System.currentTimeMillis()
                        val elapsed = now - lastReportTime
                        if (elapsed >= 200L) {
                            val instantSpeed = ((uploaded - lastReportBytes) * 1000.0) / elapsed.toDouble()
                            smoothedSpeed = if (smoothedSpeed <= 0.0) {
                                instantSpeed
                            } else {
                                smoothedSpeed * 0.65 + instantSpeed * 0.35
                            }
                            lastReportTime = now
                            lastReportBytes = uploaded
                            emitUploadEvent(
                                mapOf(
                                    "uploadId" to uploadId,
                                    "status" to "uploading",
                                    "uploadedBytes" to uploaded,
                                    "totalBytes" to if (declaredSize > 0L) declaredSize else uploaded,
                                    "speed" to smoothedSpeed
                                )
                            )
                        }
                    }
                }

                if (active.cancelled.get()) {
                    emitUploadEvent(mapOf("uploadId" to uploadId, "status" to "cancelled"))
                    return
                }

                out.write(footerBytes)
                out.flush()
            }

            if (active.cancelled.get()) {
                emitUploadEvent(mapOf("uploadId" to uploadId, "status" to "cancelled"))
                return
            }

            val code = conn.responseCode
            val responseStream = if (code in 200..299) conn.inputStream else conn.errorStream
            val responseBody = responseStream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""

            if (code in 200..299) {
                val finalTotal = if (declaredSize > 0L) declaredSize else uploaded
                emitUploadEvent(
                    mapOf(
                        "uploadId" to uploadId,
                        "status" to "completed",
                        "uploadedBytes" to finalTotal,
                        "totalBytes" to finalTotal,
                        "speed" to 0.0,
                        "responseBody" to responseBody
                    )
                )
            } else {
                emitUploadEvent(
                    mapOf(
                        "uploadId" to uploadId,
                        "status" to "error",
                        "error" to "Upload failed (HTTP $code): ${responseBody.take(180)}"
                    )
                )
            }
        } catch (e: Exception) {
            if (active.cancelled.get()) {
                emitUploadEvent(mapOf("uploadId" to uploadId, "status" to "cancelled"))
            } else {
                emitUploadEvent(
                    mapOf(
                        "uploadId" to uploadId,
                        "status" to "error",
                        "error" to (e.message ?: "Upload interrupted")
                    )
                )
            }
        } finally {
            activeUploads.remove(uploadId)
            try {
                rawStream?.close()
            } catch (_: Exception) {
            }
            try {
                conn?.disconnect()
            } catch (_: Exception) {
            }
        }
    }

    private fun handleCancelUpload(call: MethodCall, result: MethodChannel.Result) {
        val uploadId = call.argument<String>("uploadId")
        if (!uploadId.isNullOrBlank()) {
            val active = activeUploads[uploadId]
            if (active != null) {
                active.cancelled.set(true)
                uploadExecutor.execute {
                    try {
                        active.inputStream?.close()
                    } catch (_: Exception) {
                    }
                    try {
                        active.connection?.disconnect()
                    } catch (_: Exception) {
                    }
                }
            }
        }
        result.success(true)
    }

    private fun handleCancelAllUploads(result: MethodChannel.Result) {
        val snapshot = activeUploads.values.toList()
        for (active in snapshot) {
            active.cancelled.set(true)
        }
        uploadExecutor.execute {
            for (active in snapshot) {
                try {
                    active.inputStream?.close()
                } catch (_: Exception) {
                }
                try {
                    active.connection?.disconnect()
                } catch (_: Exception) {
                }
            }
        }
        result.success(true)
    }

    private fun handleOpenExternalPlayer(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val fileName = call.argument<String>("fileName") ?: "Stream"
        val mimeType = call.argument<String>("mimeType") ?: "video/*"

        if (url.isNullOrBlank()) {
            result.error("INVALID_URL", "Stream URL is empty", null)
            return
        }

        try {
            val uri = Uri.parse(url)
            val probeIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                putExtra("title", fileName)
                putExtra(Intent.EXTRA_TITLE, fileName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            val resolved = packageManager.queryIntentActivities(probeIntent, 0)
            val players = resolved.filter { info ->
                info.activityInfo.packageName !in BROWSER_PACKAGES
            }

            if (players.size == 1) {
                val target = players[0].activityInfo
                probeIntent.setClassName(target.packageName, target.name)
                startActivity(probeIntent)
                result.success(true)
                return
            }

            if (players.size > 1) {
                val intents = players.map { info ->
                    Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, mimeType)
                        putExtra("title", fileName)
                        putExtra(Intent.EXTRA_TITLE, fileName)
                        setClassName(info.activityInfo.packageName, info.activityInfo.name)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                }.toMutableList()

                val primary = intents.removeAt(0)
                val chooser = Intent.createChooser(primary, "Open with Video Player").apply {
                    if (intents.isNotEmpty()) {
                        putExtra(Intent.EXTRA_INITIAL_INTENTS, intents.toTypedArray())
                    }
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(chooser)
                result.success(true)
                return
            }

            // Fallback: try generic video/* or audio/* MIME type
            val genericMime = if (mimeType.startsWith("audio/")) "audio/*" else "video/*"
            val genericIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, genericMime)
                putExtra("title", fileName)
                putExtra(Intent.EXTRA_TITLE, fileName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val genericPlayers = packageManager.queryIntentActivities(genericIntent, 0)
                .filter { it.activityInfo.packageName !in BROWSER_PACKAGES }

            if (genericPlayers.isNotEmpty()) {
                if (genericPlayers.size == 1) {
                    val t = genericPlayers[0].activityInfo
                    genericIntent.setClassName(t.packageName, t.name)
                    startActivity(genericIntent)
                } else {
                    val intents = genericPlayers.map { info ->
                        Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, genericMime)
                            putExtra("title", fileName)
                            putExtra(Intent.EXTRA_TITLE, fileName)
                            setClassName(info.activityInfo.packageName, info.activityInfo.name)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                    }.toMutableList()
                    val primary = intents.removeAt(0)
                    val chooser = Intent.createChooser(primary, "Open with Video Player").apply {
                        if (intents.isNotEmpty()) {
                            putExtra(Intent.EXTRA_INITIAL_INTENTS, intents.toTypedArray())
                        }
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(chooser)
                }
                result.success(true)
                return
            }

            // Final direct media-typed intent fallback for strict OEM ROMs
            startActivity(genericIntent)
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.error(
                "NO_VIDEO_PLAYER",
                "No video player app found. Please install VLC, MX Player, or another video player.",
                null
            )
        } catch (e: Exception) {
            result.error("PLAYER_ERROR", e.message ?: "Failed to launch video player", null)
        }
    }

    override fun onDestroy() {
        uploadExecutor.shutdownNow()
        super.onDestroy()
    }
}

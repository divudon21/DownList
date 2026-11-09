package com.example.ai_agent_downloader

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
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
import java.io.ByteArrayOutputStream
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
        private const val ICON_SIZE_PX = 96

        private val BROWSER_PACKAGES = setOf(
            "com.android.chrome",
            "com.chrome.beta",
            "com.chrome.dev",
            "com.chrome.canary",
            "org.chromium.chrome",
            "org.mozilla.firefox",
            "org.mozilla.firefox_beta",
            "org.mozilla.fenix",
            "org.mozilla.focus",
            "com.brave.browser",
            "com.brave.browser_beta",
            "com.microsoft.emmx",
            "com.opera.browser",
            "com.opera.mini.native",
            "com.opera.gx",
            "com.sec.android.app.sbrowser",
            "com.sec.android.app.sbrowser.beta",
            "com.UCMobile.intl",
            "com.uc.browser.en",
            "com.duckduckgo.mobile.android",
            "com.vivaldi.browser",
            "com.kiwibrowser.browser",
            "mark.via.gp",
            "mark.via",
            "com.mycompany.app.soulbrowser",
            "com.yandex.browser",
            "com.mi.globalbrowser",
            "com.android.browser",
            "com.heytap.browser",
            "com.coloros.browser",
            "com.vivo.browser",
            "com.transsion.phoenix",
            "com.jio.web",
            "com.aloha.browser",
            "com.android.documentsui",
            "com.google.android.documentsui"
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
                "getMediaPlayers" -> handleGetMediaPlayers(call, result)
                "launchMediaPlayer" -> handleLaunchMediaPlayer(call, result)
                "openExternalPlayer" -> handleOpenExternalPlayer(call, result)
                "openUrl" -> {
                    try {
                        val url = call.argument<String>("url") ?: ""
                        val uri = Uri.parse(url)
                        require(uri.scheme == "https" || uri.scheme == "http")
                        startActivity(Intent(Intent.ACTION_VIEW, uri))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_URL_FAILED", "Unable to open link.", null)
                    }
                }
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

            val boundary = "----DownListBoundary${UUID.randomUUID().toString().replace("-", "")}"
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

    private fun queryAllActivities(intent: Intent): List<ResolveInfo> {
        val combined = LinkedHashMap<String, ResolveInfo>()
        try {
            for (info in packageManager.queryIntentActivities(intent, PackageManager.MATCH_ALL)) {
                val key = "${info.activityInfo.packageName}/${info.activityInfo.name}"
                combined.putIfAbsent(key, info)
            }
        } catch (_: Exception) {
        }
        try {
            for (info in packageManager.queryIntentActivities(intent, 0)) {
                val key = "${info.activityInfo.packageName}/${info.activityInfo.name}"
                combined.putIfAbsent(key, info)
            }
        } catch (_: Exception) {
        }
        return combined.values.toList()
    }

    private fun discoverMediaPlayers(
        streamUrl: String,
        fileName: String,
        mimeType: String
    ): List<ResolveInfo> {
        val isAudio = mimeType.startsWith("audio/")
        val genericMime = if (isAudio) "audio/*" else "video/*"
        val fallbackExt = if (isAudio) "mp3" else "mp4"
        val rawExt = fileName.substringAfterLast('.', "").lowercase()
        val safeExt = if (rawExt.matches(Regex("[a-z0-9]{2,5}"))) rawExt else fallbackExt

        // Dynamically detect generic web browser activities (apps matching a plain webpage URL)
        val plainWebIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.example.com/"))
        val webBrowserActivities = queryAllActivities(plainWebIntent)
            .map { "${it.activityInfo.packageName}/${it.activityInfo.name}" }
            .toSet()

        val streamUri = Uri.parse(streamUrl)
        // Ordered from explicit network stream handlers -> generic video/audio players
        val probes = listOf(
            Intent(Intent.ACTION_VIEW).apply { setDataAndType(streamUri, mimeType) },
            Intent(Intent.ACTION_VIEW).apply { setDataAndType(streamUri, genericMime) },
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse("http://example.com/stream.$safeExt"), genericMime)
            },
            Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com/stream.$safeExt")),
            Intent(Intent.ACTION_VIEW).apply {
                val contentSample = if (isAudio) {
                    "content://media/external/audio/media/1"
                } else {
                    "content://media/external/video/media/1"
                }
                setDataAndType(Uri.parse(contentSample), genericMime)
            },
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse("file:///storage/emulated/0/stream.$safeExt"), genericMime)
            }
        )

        val selfPkg = applicationContext.packageName
        val byPackage = LinkedHashMap<String, ResolveInfo>()

        for (probe in probes) {
            for (info in queryAllActivities(probe)) {
                val ai = info.activityInfo ?: continue
                val pkg = ai.packageName ?: continue
                val actKey = "$pkg/${ai.name}"
                if (pkg == selfPkg) continue
                if (!ai.exported) continue
                if (pkg in BROWSER_PACKAGES) continue
                if (actKey in webBrowserActivities) continue

                byPackage.putIfAbsent(pkg, info)
            }
        }

        return byPackage.values.toList()
    }

    private fun drawableToPngBytes(drawable: Drawable): ByteArray {
        val bmp = Bitmap.createBitmap(ICON_SIZE_PX, ICON_SIZE_PX, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        drawable.setBounds(0, 0, ICON_SIZE_PX, ICON_SIZE_PX)
        drawable.draw(canvas)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        bmp.recycle()
        return out.toByteArray()
    }

    private fun handleGetMediaPlayers(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url") ?: ""
        val fileName = call.argument<String>("fileName") ?: "Stream"
        val mimeType = call.argument<String>("mimeType") ?: "video/*"

        if (url.isBlank()) {
            result.error("INVALID_URL", "Stream URL is empty", null)
            return
        }

        uploadExecutor.execute {
            try {
                val resolved = discoverMediaPlayers(url, fileName, mimeType)
                val items = resolved.map { info ->
                    val ai = info.activityInfo
                    val appLabel = info.loadLabel(packageManager)?.toString()?.trim()
                        ?.takeIf { it.isNotEmpty() }
                        ?: ai.applicationInfo.loadLabel(packageManager)?.toString()?.trim()
                        ?: ai.packageName
                    val iconBytes = try {
                        drawableToPngBytes(info.loadIcon(packageManager))
                    } catch (_: Exception) {
                        ByteArray(0)
                    }
                    Triple(
                        appLabel,
                        ai.packageName,
                        mapOf<String, Any>(
                            "packageName" to ai.packageName,
                            "activityName" to ai.name,
                            "label" to appLabel,
                            "icon" to iconBytes
                        )
                    )
                }.sortedBy { it.first.lowercase() }.map { it.third }

                mainHandler.post {
                    result.success(items)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("QUERY_ERROR", e.message ?: "Could not query media players", null)
                }
            }
        }
    }

    private fun buildStreamIntent(
        uri: Uri,
        fileName: String,
        mimeType: String,
        packageName: String? = null,
        activityName: String? = null
    ): Intent {
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            putExtra("title", fileName)
            putExtra(Intent.EXTRA_TITLE, fileName)
            putExtra("forcename", fileName)
            putExtra("secure_uri", true)
            if (!packageName.isNullOrBlank() && !activityName.isNullOrBlank()) {
                setClassName(packageName, activityName)
            } else if (!packageName.isNullOrBlank()) {
                setPackage(packageName)
            }
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private fun handleLaunchMediaPlayer(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val fileName = call.argument<String>("fileName") ?: "Stream"
        val mimeType = call.argument<String>("mimeType") ?: "video/*"
        val packageName = call.argument<String>("packageName")
        val activityName = call.argument<String>("activityName")

        if (url.isNullOrBlank() || packageName.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Missing player launch parameters", null)
            return
        }

        val uri = Uri.parse(url)
        val genericMime = if (mimeType.startsWith("audio/")) "audio/*" else "video/*"

        try {
            startActivity(buildStreamIntent(uri, fileName, mimeType, packageName, activityName))
            result.success(true)
            return
        } catch (_: Exception) {
        }

        try {
            startActivity(buildStreamIntent(uri, fileName, genericMime, packageName, activityName))
            result.success(true)
            return
        } catch (_: Exception) {
        }

        try {
            startActivity(buildStreamIntent(uri, fileName, genericMime, packageName, null))
            result.success(true)
        } catch (e: Exception) {
            result.error("PLAYER_ERROR", e.message ?: "Failed to launch selected player", null)
        }
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
            val players = discoverMediaPlayers(url, fileName, mimeType)
            if (players.isNotEmpty()) {
                val target = players[0].activityInfo
                startActivity(
                    buildStreamIntent(uri, fileName, mimeType, target.packageName, target.name)
                )
                result.success(true)
                return
            }

            val genericMime = if (mimeType.startsWith("audio/")) "audio/*" else "video/*"
            startActivity(buildStreamIntent(uri, fileName, genericMime))
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

package com.offlineaudio.app

import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File
import com.arthenica.ffmpegkit.FFmpegKit
import com.arthenica.ffmpegkit.ReturnCode
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "OfflineAudioPlugin"
        private const val METHOD_CHANNEL = "com.offlineaudio.app/ytdlp"
        private const val PROGRESS_CHANNEL = "com.offlineaudio.app/progress"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var progressHandler: ProgressStreamHandler? = null
    private var ytdlpReady = false
    private var initError: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // EventChannel: progreso de descargas (una sola stream, multiplexada
        // por taskId). Dart filtra eventos por taskId.
        progressHandler = ProgressStreamHandler()
        EventChannel(messenger, PROGRESS_CHANNEL).setStreamHandler(progressHandler)

        // MethodChannel: probe / download / cancel / transcode / status
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "probe" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("BAD_ARGS", "url is required", null); return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val info = probe(url)
                            mainHandler.post { result.success(info) }
                        } catch (e: Exception) {
                            Log.e(TAG, "probe failed: ${e.message}", e)
                            mainHandler.post { result.error("PROBE_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "download" -> {
                    val url = call.argument<String>("url")
                    val outputDir = call.argument<String>("outputDir")
                    val format = call.argument<String>("format") ?: "bestaudio/best"
                    val taskId = call.argument<String>("taskId")
                    if (url.isNullOrBlank() || outputDir.isNullOrBlank() || taskId.isNullOrBlank()) {
                        result.error("BAD_ARGS", "url, outputDir and taskId are required", null); return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val path = download(url, outputDir, format, taskId)
                            mainHandler.post { result.success(path) }
                        } catch (e: Exception) {
                            Log.e(TAG, "download failed: ${e.message}", e)
                            mainHandler.post { result.error("DL_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "cancelDownload" -> {
                    val taskId = call.argument<String>("taskId")
                    if (taskId.isNullOrBlank()) {
                        result.error("BAD_ARGS", "taskId is required", null); return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            YoutubeDL.getInstance().destroyProcessById(taskId)
                            mainHandler.post { result.success(true) }
                        } catch (e: Exception) {
                            Log.e(TAG, "cancel failed: ${e.message}", e)
                            mainHandler.post { result.error("CANCEL_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "transcode" -> {
                    val input = call.argument<String>("input")
                    val output = call.argument<String>("output")
                    val metadata = call.argument<Map<String, String>>("metadata") ?: emptyMap()
                    val bitrateKbps = call.argument<Int>("bitrateKbps") ?: 128
                    if (input.isNullOrBlank() || output.isNullOrBlank()) {
                        result.error("BAD_ARGS", "input and output are required", null); return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            transcode(input, output, metadata, bitrateKbps)
                            mainHandler.post { result.success(true) }
                        } catch (e: Exception) {
                            Log.e(TAG, "transcode failed: ${e.message}", e)
                            mainHandler.post { result.error("TRANSCODE_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "status" -> {
                    val map = mapOf(
                        "ready" to ytdlpReady,
                        "error" to initError,
                    )
                    result.success(map)
                }
                else -> result.notImplemented()
            }
        }

        // Inicialización: debe hacerse una sola vez, en hilo de fondo.
        Thread {
            try {
                YoutubeDL.getInstance().init(applicationContext)
                ytdlpReady = true
                Log.i(TAG, "youtubedl-android initialized")
            } catch (e: YoutubeDLException) {
                initError = e.message
                Log.e(TAG, "youtubedl-android init failed", e)
            } catch (e: Exception) {
                initError = e.message
                Log.e(TAG, "youtubedl-android init failed", e)
            }
        }.start()
    }

    /**
     * Obtiene metadata (probe) de una URL. Devuelve un Map con los campos
     * relevantes; Dart lo mapea al `ProbeInfo` del engine Rust.
     */
    private fun probe(url: String): Map<String, Any?> {
        if (!ytdlpReady) throw IllegalStateException("youtubedl-android not ready: $initError")
        val info = YoutubeDL.getInstance().getInfo(url)
        return mapOf(
            "id" to info.id,
            "title" to info.title,
            "url" to info.url,
            "thumbnail" to info.thumbnail,
            "duration" to info.duration,
            "extractor" to info.extractor,
            "webpage_url" to info.webpageUrl,
            "uploader" to info.uploader,
        )
    }

    /**
     * Descarga un stream a `outputDir` con el `format` dado. Reporta progreso
     * por el EventChannel asociado a [taskId]. Bloqueante; debe correr en hilo
     * de fondo. Lanza excepción si yt-dlp falla (exitCode != 0).
     */
    private fun download(url: String, outputDir: String, format: String, taskId: String): String {
        if (!ytdlpReady) throw IllegalStateException("youtubedl-android not ready: $initError")
        val request = YoutubeDLRequest(url)
        // El taskId evita caracteres inválidos del título y permite devolver
        // una ruta determinista al lado Dart después de terminar.
        request.addOption("-o", "$outputDir/$taskId.%(ext)s")
        request.addOption("-f", format)
        request.addOption("--no-playlist")
        request.addOption("--no-warnings")
        request.addOption("--force-ipv4")
        request.addOption("--socket-timeout", "30")
        request.addOption("--newline")
        request.addOption("--no-colors")
        // El callback recibe (progress, etaInSeconds, line). Reportamos solo
        // progress y eta; la línea raw puede usarse más adelante si hace falta.
        YoutubeDL.getInstance().execute(request, taskId) { progress, eta, _ ->
            progressHandler?.eventSink?.let { sink ->
                mainHandler.post {
                    sink.success(mapOf(
                        "taskId" to taskId,
                        "progress" to progress.toDouble(),
                        "eta" to eta,
                    ))
                }
            }
        }
        val downloaded = File(outputDir).listFiles()
            ?.filter { it.name.startsWith("$taskId.") && it.isFile && it.length() > 0 }
            ?.maxByOrNull { it.lastModified() }
            ?: throw IllegalStateException("yt-dlp no generó un archivo para $taskId")
        return downloaded.absolutePath
    }

    /**
     * Transcodifica `input` a `output` en Opus con metadatos. Usa ffmpeg-kit
     * (API async con listener). Bloquea hasta que ffmpeg termine.
     */
    private fun transcode(
        input: String,
        output: String,
        metadata: Map<String, String>,
        bitrateKbps: Int,
    ) {
        val args = buildList<String> {
            add("-y")
            add("-i"); add(input)
            add("-hide_banner")
            add("-loglevel"); add("error")
            add("-nostdin")
            add("-vn")
            add("-ac"); add("2")
            add("-c:a"); add("libopus")
            add("-b:a"); add("${bitrateKbps}k")
            add("-vbr"); add("on")
            add("-application"); add("audio")
            add("-threads"); add("0")
            for ((k, v) in metadata) {
                if (v.isNotBlank()) {
                    add("-metadata"); add("$k=$v")
                }
            }
            add("-f"); add("opus")
            add(output)
        }.joinToString(" ")
        val session = FFmpegKit.execute(args)
        val rc = session.returnCode
        if (!ReturnCode.isSuccess(rc)) {
            val output = session.output ?: "<no output>"
            throw RuntimeException("ffmpeg failed (rc=${rc?.value}): $output")
        }
    }

    /**
     * Handler del stream de progreso. Un único sink compartido; los eventos
     * llevan `taskId` para que Dart pueda filtrarlos.
     */
    private class ProgressStreamHandler : EventChannel.StreamHandler {
        @Volatile
        var eventSink: EventChannel.EventSink? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
        }

        override fun onCancel(arguments: Any?) {
            eventSink = null
        }
    }
}

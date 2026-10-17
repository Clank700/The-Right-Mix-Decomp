package org.decomp.the_right_mix

import android.content.Intent
import android.media.AudioAttributes
import android.media.SoundPool
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the two small native services the game needs: sound playback and opening web links.
 *
 * Sound uses SoundPool (decoded samples held in memory, low start latency, several overlapping streams) instead of
 * one MediaPlayer per sound, whose start latency is large and varies by device. Each Dart handle owns one sample and
 * at most one running stream (starting it again restarts it, like ActionScript's Sound.start on one object).
 */
class MainActivity : FlutterActivity() {
    private lateinit var pool: SoundPool
    private val sampleOf = HashMap<Int, Int>()      // Dart handle -> SoundPool sample id
    private val handleOfSample = HashMap<Int, Int>()
    private val loaded = HashSet<Int>()             // handles whose sample finished decoding
    private val streamOf = HashMap<Int, Int>()      // handle -> running stream id
    private val volumeOf = HashMap<Int, Float>()
    private val pendingLoop = HashMap<Int, Boolean>() // start requested before decoding finished

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_GAME)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        pool = SoundPool.Builder().setMaxStreams(24).setAudioAttributes(attrs).build()
        pool.setOnLoadCompleteListener { _, sampleId, status ->
            val handle = handleOfSample[sampleId] ?: return@setOnLoadCompleteListener
            if (status == 0) {
                loaded.add(handle)
                pendingLoop.remove(handle)?.let { startStream(handle, it) }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "org.decomp.therightmix/audio").setMethodCallHandler(::onAudioCall)
        MethodChannel(messenger, "org.decomp.therightmix/platform").setMethodCallHandler { call, result ->
            if (call.method == "filesDir") {
                result.success(filesDir.absolutePath)
            } else if (call.method == "openUrl") {
                val url = call.argument<String>("url")
                if (url != null) {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun startStream(handle: Int, loop: Boolean) {
        val sample = sampleOf[handle] ?: return
        streamOf.remove(handle)?.let { pool.stop(it) }
        val v = volumeOf[handle] ?: 1.0f
        val stream = pool.play(sample, v, v, 1, if (loop) -1 else 0, 1.0f)
        if (stream != 0) streamOf[handle] = stream
    }

    private fun onAudioCall(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("id") ?: -1
        when (call.method) {
            "load" -> {
                try {
                    val fd = assets.openFd(call.argument<String>("path")!!)
                    val sample = pool.load(fd, 1)
                    fd.close()
                    sampleOf[id] = sample
                    handleOfSample[sample] = id
                } catch (e: Exception) {
                    // A missing sound must never crash the game; it just stays silent.
                }
                result.success(null)
            }
            "play" -> {
                // (start offsets are not supported by SoundPool; the game always starts sounds at 0)
                val loop = call.argument<Boolean>("loop") ?: false
                if (id in loaded) startStream(id, loop) else if (id in sampleOf) pendingLoop[id] = loop
                result.success(null)
            }
            "stop" -> {
                pendingLoop.remove(id)
                streamOf.remove(id)?.let { pool.stop(it) }
                result.success(null)
            }
            "volume" -> {
                val v = (call.argument<Double>("v") ?: 1.0).toFloat()
                volumeOf[id] = v
                streamOf[id]?.let { pool.setVolume(it, v, v) }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Leaving the screen silences the game; coming back resumes the streams that were running. */
    override fun onStop() {
        pool.autoPause()
        super.onStop()
    }

    override fun onStart() {
        super.onStart()
        pool.autoResume()
    }

    override fun onDestroy() {
        pool.release()
        super.onDestroy()
    }
}

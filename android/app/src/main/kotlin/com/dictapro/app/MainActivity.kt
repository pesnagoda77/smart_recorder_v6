package com.dictapro.app

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val CHANNEL = "dictapro/convert"
    private val TAG = "DictaPro"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "convertToWav" -> {
                    val inputPath = call.argument<String>("inputPath")
                    val outputPath = call.argument<String>("outputPath")
                    if (inputPath == null || outputPath == null) {
                        result.error("INVALID_ARGUMENTS", "inputPath or outputPath is null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        Log.d(TAG, "Starting conversion: input=$inputPath")
                        convertAudioToWav(inputPath, outputPath, 16000, 1)
                        Log.d(TAG, "Conversion OK")
                        result.success(mapOf("success" to true))
                    } catch (e: Exception) {
                        Log.e(TAG, "Conversion FAILED", e)
                        result.success(mapOf("success" to false, "error" to e.message))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun convertAudioToWav(inputPath: String, outputPath: String, targetSampleRate: Int, targetChannels: Int) {
        Log.d(TAG, "Starting conversion: input=$inputPath, output=$outputPath")
        
        // Validate input file exists and is readable
        val inputFile = File(inputPath)
        if (!inputFile.exists() || !inputFile.canRead()) {
            throw Exception("Input file does not exist or is not readable: $inputPath")
        }
        if (inputFile.length() < 1024) {
            throw Exception("Input file too small (less than 1KB), likely corrupted")
        }
        
        val extractor = MediaExtractor()
        
        // Setup data source with error handling
        try {
            if (inputPath.startsWith("content://")) {
                val uri = Uri.parse(inputPath)
                contentResolver.openAssetFileDescriptor(uri, "r")?.use { afd ->
                    Log.d(TAG, "Content URI opened: offset=${afd.startOffset}, len=${afd.length}")
                    extractor.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                } ?: throw Exception("Cannot open content URI: $inputPath")
            } else {
                Log.d(TAG, "Direct file path: $inputPath")
                extractor.setDataSource(inputPath)
            }
        } catch (e: Exception) {
            extractor.release()
            Log.e(TAG, "MediaExtractor failed to open", e)
            throw Exception("Cannot open audio file: ${e.message}")
        }

        var audioTrackIndex = -1
        var inputSampleRate = 44100
        var inputChannels = 2
        var mimeType = "unknown"
        var format: MediaFormat? = null

        Log.d(TAG, "Track count: ${extractor.trackCount}")
        for (i in 0 until extractor.trackCount) {
            val trackFormat = extractor.getTrackFormat(i)
            val mime = trackFormat.getString(MediaFormat.KEY_MIME) ?: ""
            Log.d(TAG, "Track $i: mime=$mime")
            if (mime.startsWith("audio/")) {
                audioTrackIndex = i
                inputSampleRate = try { trackFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE) } catch (_: Exception) { 44100 }
                inputChannels = try { trackFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT) } catch (_: Exception) { 2 }
                mimeType = mime
                format = trackFormat
                Log.d(TAG, "Selected audio track $i: $inputSampleRate Hz, $inputChannels ch, mime=$mime")
                break
            }
        }

        if (audioTrackIndex == -1) {
            extractor.release()
            Log.e(TAG, "No audio track found in file")
            throw Exception("No audio track found — file may be corrupted or unsupported format")
        }

        extractor.selectTrack(audioTrackIndex)

        // Create decoder
        val codec: MediaCodec = try {
            MediaCodec.createDecoderByType(mimeType)
        } catch (e: Exception) {
            extractor.release()
            Log.e(TAG, "Failed to create decoder for $mimeType", e)
            throw Exception("Cannot decode this audio format ($mimeType): ${e.message}")
        }

        // Configure and start
        try {
            codec.configure(format, null, null, 0)
            codec.start()
        } catch (e: Exception) {
            codec.release()
            extractor.release()
            Log.e(TAG, "Codec configure/start failed", e)
            throw Exception("Codec initialization failed: ${e.message}")
        }

        val bufferInfo = MediaCodec.BufferInfo()
        val outputStream = java.io.ByteArrayOutputStream()
        var isEOS = false
        var hasOutput = false

        try {
            while (!isEOS) {
                val inputBufferId = codec.dequeueInputBuffer(10000)
                if (inputBufferId >= 0) {
                    val inputBuffer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        codec.getInputBuffer(inputBufferId)!!
                    } else {
                        @Suppress("DEPRECATION")
                        codec.inputBuffers[inputBufferId]
                    }
                    val sampleSize = extractor.readSampleData(inputBuffer, 0)
                    if (sampleSize < 0) {
                        codec.queueInputBuffer(inputBufferId, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        isEOS = true
                    } else {
                        codec.queueInputBuffer(inputBufferId, 0, sampleSize, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }

                var outputBufferId = codec.dequeueOutputBuffer(bufferInfo, 10000)
                while (outputBufferId >= 0) {
                    hasOutput = true
                    val outputBuffer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        codec.getOutputBuffer(outputBufferId)!!
                    } else {
                        @Suppress("DEPRECATION")
                        codec.outputBuffers[outputBufferId]
                    }
                    val chunk = ByteArray(bufferInfo.size)
                    outputBuffer.position(bufferInfo.offset)
                    outputBuffer.get(chunk)
                    outputStream.write(chunk)
                    codec.releaseOutputBuffer(outputBufferId, false)
                    outputBufferId = codec.dequeueOutputBuffer(bufferInfo, 10000)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Decode loop error", e)
            throw Exception("Decoding failed: ${e.message}")
        } finally {
            try { codec.stop() } catch (_: Exception) {}
            try { codec.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
        }

        if (!hasOutput) {
            throw Exception("No audio data decoded — file may be corrupted or in unsupported format")
        }

        val pcmData = outputStream.toByteArray()
        Log.d(TAG, "Decoded PCM: ${pcmData.size} bytes")

        if (pcmData.isEmpty()) {
            throw Exception("Decoded audio is empty")
        }

        val finalPcm = if (inputSampleRate != targetSampleRate || inputChannels != targetChannels) {
            Log.d(TAG, "Resampling: $inputSampleRate Hz ${inputChannels}ch -> $targetSampleRate Hz ${targetChannels}ch")
            resamplePcm16(pcmData, inputSampleRate, inputChannels, targetSampleRate, targetChannels)
        } else {
            pcmData
        }

        writeWavFile(outputPath, finalPcm, targetSampleRate, targetChannels, 16)
        Log.d(TAG, "WAV written: $outputPath")
    }

    private fun resamplePcm16(input: ByteArray, inRate: Int, inCh: Int, outRate: Int, outCh: Int): ByteArray {
        val inSamples = input.size / 2
        if (inSamples == 0) return ByteArray(0)

        val ratio = inRate.toDouble() / outRate.toDouble()
        val outSamples = kotlin.math.max(1, (inSamples.toDouble() / inCh / ratio).toInt())
        val output = ByteArray(outSamples * outCh * 2)
        val inBuf = ByteBuffer.wrap(input).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()

        for (i in 0 until outSamples) {
            val srcIdx = ((i * ratio).toInt() * inCh).coerceIn(0, inBuf.limit() - 1)
            val left = inBuf.get(srcIdx)
            val right = if (inCh == 2 && srcIdx + 1 < inBuf.limit()) {
                inBuf.get(srcIdx + 1)
            } else left
            val mono = ((left.toInt() + right.toInt()) / 2).toShort()
            
            val outIdx = i * outCh
            output[outIdx * 2] = (mono.toInt() and 0xFF).toByte()
            output[outIdx * 2 + 1] = ((mono.toInt() shr 8) and 0xFF).toByte()
            if (outCh == 2) {
                output[(outIdx + 1) * 2] = output[outIdx * 2]
                output[(outIdx + 1) * 2 + 1] = output[outIdx * 2 + 1]
            }
        }
        return output
    }

    private fun writeWavFile(path: String, pcmData: ByteArray, sampleRate: Int, channels: Int, bitsPerSample: Int) {
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val totalDataLen = pcmData.size + 36
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray())
        header.putInt(totalDataLen)
        header.put("WAVE".toByteArray())
        header.put("fmt ".toByteArray())
        header.putInt(16)
        header.putShort(1.toShort())
        header.putShort(channels.toShort())
        header.putInt(sampleRate)
        header.putInt(byteRate)
        header.putShort((channels * bitsPerSample / 8).toShort())
        header.putShort(bitsPerSample.toShort())
        header.put("data".toByteArray())
        header.putInt(pcmData.size)

        FileOutputStream(File(path)).use { fos ->
            fos.write(header.array())
            fos.write(pcmData)
        }
    }
}

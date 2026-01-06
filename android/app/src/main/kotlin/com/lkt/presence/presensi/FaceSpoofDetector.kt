package com.lkt.presence.presensi

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Rect
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.exp
import kotlin.math.min

class FaceSpoofDetectorNative(private val context: Context) {

    data class Result(
        val isSpoof: Boolean,
        val score: Float,
        val timeMillis: Long,
    )

    private val scale1 = 2.7f
    private val scale2 = 4.0f
    private val inputImageDim = 80
    private val outputDim = 3

    // ✅ PASTI Interpreter (bukan ByteBuffer)
    private val interpreter1: Interpreter
    private val interpreter2: Interpreter

    init {
        val options = Interpreter.Options().apply {
            numThreads = 4
        }

        val model1: ByteBuffer = loadModelBytes("models/spoof_model_scale_2_7.tflite")
        val model2: ByteBuffer = loadModelBytes("models/spoof_model_scale_4_0.tflite")

        interpreter1 = Interpreter(model1, options)
        interpreter2 = Interpreter(model2, options)
    }

    fun close() {
        interpreter1.close()
        interpreter2.close()
    }

    fun detectSpoof(imagePath: String, faceRect: Rect): Result {
        val bmp = BitmapFactory.decodeFile(imagePath)
            ?: throw IllegalArgumentException("Cannot decode image: $imagePath")

        val t0 = System.currentTimeMillis()

        val crop1 = toBgrBitmap(cropAndResize(bmp, faceRect, scale1, inputImageDim, inputImageDim))
        val crop2 = toBgrBitmap(cropAndResize(bmp, faceRect, scale2, inputImageDim, inputImageDim))

        val input1 = bitmapToFloatBufferBgr(crop1)
        val input2 = bitmapToFloatBufferBgr(crop2)

        val out1 = Array(1) { FloatArray(outputDim) }
        val out2 = Array(1) { FloatArray(outputDim) }

        // ✅ INI method Interpreter.run(...)
        interpreter1.run(input1, out1)
        interpreter2.run(input2, out2)

        val time = System.currentTimeMillis() - t0

        val sm1 = softmax(out1[0])
        val sm2 = softmax(out2[0])

        val merged = FloatArray(outputDim)
        for (i in 0 until outputDim) merged[i] = sm1[i] + sm2[i]

        var label = 0
        var best = merged[0]
        for (i in 1 until outputDim) {
            if (merged[i] > best) {
                best = merged[i]
                label = i
            }
        }

        val isSpoof = label != 1
        val score = best / 2f
        return Result(isSpoof, score, time)
    }

    private fun softmax(x: FloatArray): FloatArray {
        val maxV = x.maxOrNull() ?: 0f
        val exps = FloatArray(x.size)
        var sum = 0.0
        for (i in x.indices) {
            val v = exp((x[i] - maxV).toDouble())
            exps[i] = v.toFloat()
            sum += v
        }
        for (i in exps.indices) {
            exps[i] = (exps[i] / sum).toFloat()
        }
        return exps
    }

    private fun cropAndResize(orig: Bitmap, bbox: Rect, bboxScale: Float, targetW: Int, targetH: Int): Bitmap {
        val scaled = getScaledBox(orig.width, orig.height, bbox, bboxScale)
        val cropped = Bitmap.createBitmap(orig, scaled.left, scaled.top, scaled.width(), scaled.height())
        return Bitmap.createScaledBitmap(cropped, targetW, targetH, true)
    }

    private fun getScaledBox(srcW: Int, srcH: Int, box: Rect, bboxScale: Float): Rect {
        val x = box.left
        val y = box.top
        val w = box.width()
        val h = box.height()

        val scale = min(min((srcH - 1f) / h, (srcW - 1f) / w), bboxScale)
        val newW = w * scale
        val newH = h * scale
        val cx = w / 2f + x
        val cy = h / 2f + y

        var tlx = cx - newW / 2f
        var tly = cy - newH / 2f
        var brx = cx + newW / 2f
        var bry = cy + newH / 2f

        if (tlx < 0) { brx -= tlx; tlx = 0f }
        if (tly < 0) { bry -= tly; tly = 0f }
        if (brx > srcW - 1) { tlx -= (brx - (srcW - 1)); brx = (srcW - 1).toFloat() }
        if (bry > srcH - 1) { tly -= (bry - (srcH - 1)); bry = (srcH - 1).toFloat() }

        return Rect(tlx.toInt(), tly.toInt(), brx.toInt(), bry.toInt())
    }

    private fun toBgrBitmap(src: Bitmap): Bitmap {
        val out = src.copy(Bitmap.Config.ARGB_8888, true)
        for (x in 0 until out.width) {
            for (y in 0 until out.height) {
                val c = out.getPixel(x, y)
                out.setPixel(x, y, Color.rgb(Color.blue(c), Color.green(c), Color.red(c)))
            }
        }
        return out
    }

    private fun bitmapToFloatBufferBgr(bmp: Bitmap): ByteBuffer {
        val w = bmp.width
        val h = bmp.height
        val buf = ByteBuffer.allocateDirect(w * h * 3 * 4).order(ByteOrder.nativeOrder())
        for (y in 0 until h) {
            for (x in 0 until w) {
                val c = bmp.getPixel(x, y)
                buf.putFloat(Color.blue(c).toFloat())
                buf.putFloat(Color.green(c).toFloat())
                buf.putFloat(Color.red(c).toFloat())
            }
        }
        buf.rewind()
        return buf
    }

    private fun loadModelBytes(assetPath: String): ByteBuffer {
        val bytes = context.assets.open(assetPath).readBytes()
        val buf = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
        buf.put(bytes)
        buf.rewind()
        return buf
    }
}

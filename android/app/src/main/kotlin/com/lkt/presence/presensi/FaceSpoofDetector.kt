package com.lkt.presence.presensi

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Rect
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.support.common.ops.CastOp
import org.tensorflow.lite.support.common.ops.NormalizeOp
import org.tensorflow.lite.support.image.ImageProcessor
import org.tensorflow.lite.support.image.TensorImage
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.abs
import kotlin.math.sqrt

class FaceSpoofDetectorNative(private val context: Context) {

    data class Result(
        val isSpoof: Boolean,
        val score: Float,
        val timeMillis: Long,
        val moireScore: Float,
        val textureScore: Float,
        val detailMsg: String
    )

    private val scale1 = 2.7f
    private val scale2 = 4.0f
    private val inputImageDim = 80
    private val outputDim = 3

    private val interpreter1: Interpreter
    private val interpreter2: Interpreter

    // ✅ CRITICAL FIX: Proper image preprocessing seperti project referensi
    private val imageTensorProcessor = ImageProcessor.Builder()
        .add(CastOp(DataType.FLOAT32))
        .build()

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

        // ✅ Enhanced preprocessing
        val crop1 = preprocessForSpoof(bmp, faceRect, scale1)
        val crop2 = preprocessForSpoof(bmp, faceRect, scale2)

        // ✅ CRITICAL: Gunakan TensorImage API seperti project referensi
        val input1 = imageTensorProcessor.process(TensorImage.fromBitmap(crop1)).buffer
        val input2 = imageTensorProcessor.process(TensorImage.fromBitmap(crop2)).buffer

        val out1 = Array(1) { FloatArray(outputDim) }
        val out2 = Array(1) { FloatArray(outputDim) }

        interpreter1.run(input1, out1)
        interpreter2.run(input2, out2)

        val time = System.currentTimeMillis() - t0

        val sm1 = softmax(out1[0])
        val sm2 = softmax(out2[0])

        // Merge softmax outputs
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

        // === ADDITIONAL SPOOF CHECKS ===
        val largeCrop = cropAndResize(bmp, faceRect, 3.5f, 160, 160)
        val moireScore = detectMoirePattern(largeCrop)
        val textureScore = analyzeTexture(largeCrop)
        val sharpnessScore = analyzeSharpness(largeCrop)
        
        // === MULTI-CRITERIA DECISION ===
        val modelScore = best / 2f
        val isModelSpoof = label != 1
        
        // ✅ Adjusted thresholds - lebih sensitif
        val isMoireSpoof = moireScore > 0.30f      // Screen pattern
        val isTextureSpoof = textureScore < 0.35f  // Unnatural texture
        val isSharpnessAnomaly = sharpnessScore > 0.60f || sharpnessScore < 0.20f  // Too sharp/blurry
        
        val spoofIndicators = listOf(
            isModelSpoof,
            isMoireSpoof,
            isTextureSpoof,
            isSharpnessAnomaly
        ).count { it }
        
        val finalIsSpoof = when {
            // High confidence model decision
            modelScore > 0.85f && !isModelSpoof -> false
            modelScore > 0.85f && isModelSpoof -> true
            
            // Multiple indicators (2+)
            spoofIndicators >= 2 -> true
            
            // Low confidence + any indicator
            modelScore < 0.70f && spoofIndicators >= 1 -> true
            
            // Default to model
            else -> isModelSpoof
        }

        val detailMsg = buildString {
            append("Model: ${if (isModelSpoof) "SPOOF" else "REAL"} (${"%.2f".format(modelScore)})")
            append(" | Moiré: ${"%.2f".format(moireScore)}")
            append(" | Texture: ${"%.2f".format(textureScore)}")
            append(" | Sharpness: ${"%.2f".format(sharpnessScore)}")
            append(" | Indicators: $spoofIndicators/4")
        }

        return Result(
            isSpoof = finalIsSpoof,
            score = modelScore,
            timeMillis = time,
            moireScore = moireScore,
            textureScore = textureScore,
            detailMsg = detailMsg
        )
    }

    // ✅ Enhanced preprocessing dengan BGR conversion
    private fun preprocessForSpoof(orig: Bitmap, bbox: Rect, bboxScale: Float): Bitmap {
        val cropped = cropAndResize(orig, bbox, bboxScale, inputImageDim, inputImageDim)
        
        // Convert RGB to BGR (seperti project referensi)
        val bgr = Bitmap.createBitmap(cropped.width, cropped.height, Bitmap.Config.ARGB_8888)
        for (x in 0 until cropped.width) {
            for (y in 0 until cropped.height) {
                val pixel = cropped.getPixel(x, y)
                bgr.setPixel(
                    x, y,
                    Color.rgb(
                        Color.blue(pixel),
                        Color.green(pixel),
                        Color.red(pixel)
                    )
                )
            }
        }
        
        // Apply subtle contrast enhancement
        return enhanceContrast(bgr)
    }

    // ✅ NEW: Sharpness Analysis (screens tend to be over-sharp or blurry)
    private fun analyzeSharpness(bmp: Bitmap): Float {
        val w = bmp.width
        val h = bmp.height
        
        // Laplacian variance for sharpness
        var laplacianSum = 0f
        var count = 0
        
        for (y in 1 until h - 1) {
            for (x in 1 until w - 1) {
                val center = toGray(bmp.getPixel(x, y))
                val top = toGray(bmp.getPixel(x, y - 1))
                val bottom = toGray(bmp.getPixel(x, y + 1))
                val left = toGray(bmp.getPixel(x - 1, y))
                val right = toGray(bmp.getPixel(x + 1, y))
                
                val laplacian = abs(4 * center - top - bottom - left - right)
                laplacianSum += laplacian
                count++
            }
        }
        
        val variance = laplacianSum / count
        
        // Normalize to [0, 1]
        // Real faces: 20-60, Screens: <15 or >80
        return (variance / 100f).coerceIn(0f, 1f)
    }

    // ✅ Enhanced Moiré Pattern Detection
    private fun detectMoirePattern(bmp: Bitmap): Float {
        val w = bmp.width
        val h = bmp.height
        
        var highFreqSum = 0f
        var periodicityScore = 0f
        var repeatingPatterns = 0f
        
        // Analyze high-frequency components
        for (y in 1 until h - 1 step 2) {
            for (x in 1 until w - 1 step 2) {
                val center = bmp.getPixel(x, y)
                val right = bmp.getPixel(x + 1, y)
                val down = bmp.getPixel(x, y + 1)
                
                val centerGray = toGray(center)
                val rightGray = toGray(right)
                val downGray = toGray(down)
                
                val dx = abs(rightGray - centerGray)
                val dy = abs(downGray - centerGray)
                
                highFreqSum += (dx + dy)
                
                // Screen refresh lines detection
                if (dx > 12f || dy > 12f) {
                    periodicityScore += 1f
                }
                
                // Check for repeating patterns (moiré)
                if (y % 4 == 0 && x % 4 == 0 && x < w - 4 && y < h - 4) {
                    val block1 = toGray(bmp.getPixel(x, y))
                    val block2 = toGray(bmp.getPixel(x + 4, y))
                    val block3 = toGray(bmp.getPixel(x, y + 4))
                    
                    if (abs(block1 - block2) < 5f && abs(block1 - block3) < 5f) {
                        repeatingPatterns += 1f
                    }
                }
            }
        }
        
        val avgGradient = highFreqSum / (w * h / 4)
        val periodicityRatio = periodicityScore / (w * h / 4)
        val repetitionRatio = repeatingPatterns / (w * h / 16)
        
        // Weighted combination
        val moireScore = (avgGradient / 80f) * 0.4f + 
                        periodicityRatio * 0.3f + 
                        repetitionRatio * 0.3f
        
        return minOf(moireScore, 1f)
    }

    // ✅ Enhanced Texture Analysis
    private fun analyzeTexture(bmp: Bitmap): Float {
        val w = bmp.width
        val h = bmp.height
        
        var varianceSum = 0f
        var edgeStrength = 0f
        val windowSize = 5
        var windowCount = 0
        
        for (y in windowSize until h - windowSize step windowSize) {
            for (x in windowSize until w - windowSize step windowSize) {
                val pixels = mutableListOf<Float>()
                var localEdges = 0f
                
                for (dy in -windowSize..windowSize) {
                    for (dx in -windowSize..windowSize) {
                        val gray = toGray(bmp.getPixel(x + dx, y + dy))
                        pixels.add(gray)
                        
                        // Edge detection
                        if (dx == 0 && dy == 0) continue
                        val centerGray = toGray(bmp.getPixel(x, y))
                        if (abs(gray - centerGray) > 15f) {
                            localEdges += 1f
                        }
                    }
                }
                
                val mean = pixels.average().toFloat()
                val variance = pixels.map { (it - mean) * (it - mean) }.average().toFloat()
                varianceSum += sqrt(variance)
                edgeStrength += localEdges
                windowCount++
            }
        }
        
        val avgStdDev = varianceSum / windowCount
        val avgEdges = edgeStrength / windowCount
        
        // Real skin: stdDev 15-35, edges 20-50
        // Screen: stdDev <10 or >45, edges <15 or >60
        val stdDevScore = when {
            avgStdDev < 10f -> 0.2f
            avgStdDev > 45f -> 0.3f
            avgStdDev in 15f..35f -> 0.9f
            else -> 0.5f
        }
        
        val edgeScore = when {
            avgEdges < 15f -> 0.2f
            avgEdges > 60f -> 0.3f
            avgEdges in 20f..50f -> 0.9f
            else -> 0.5f
        }
        
        return (stdDevScore * 0.6f + edgeScore * 0.4f)
    }

    // ✅ Contrast Enhancement
    private fun enhanceContrast(bmp: Bitmap): Bitmap {
        val out = bmp.copy(Bitmap.Config.ARGB_8888, true)
        
        var minVal = 255f
        var maxVal = 0f
        
        for (y in 0 until out.height) {
            for (x in 0 until out.width) {
                val gray = toGray(out.getPixel(x, y))
                if (gray < minVal) minVal = gray
                if (gray > maxVal) maxVal = gray
            }
        }
        
        val range = maxVal - minVal
        if (range < 10f) return out
        
        for (y in 0 until out.height) {
            for (x in 0 until out.width) {
                val c = out.getPixel(x, y)
                val r = Color.red(c)
                val g = Color.green(c)
                val b = Color.blue(c)
                
                val newR = ((r - minVal) / range * 255f).toInt().coerceIn(0, 255)
                val newG = ((g - minVal) / range * 255f).toInt().coerceIn(0, 255)
                val newB = ((b - minVal) / range * 255f).toInt().coerceIn(0, 255)
                
                out.setPixel(x, y, Color.rgb(newR, newG, newB))
            }
        }
        
        return out
    }

    private fun toGray(color: Int): Float {
        return Color.red(color) * 0.299f + 
               Color.green(color) * 0.587f + 
               Color.blue(color) * 0.114f
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

    private fun loadModelBytes(assetPath: String): ByteBuffer {
        val bytes = context.assets.open(assetPath).readBytes()
        val buf = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
        buf.put(bytes)
        buf.rewind()
        return buf
    }
}
import 'dart:ui';

import 'package:flutter/services.dart';

class SpoofNativeService {
  static const MethodChannel _ch = MethodChannel('spoof_detector');

  Future<SpoofNativeResult> detectSpoof({
    required String imagePath,
    required Rect faceRect,
  }) async {
    final res = await _ch.invokeMapMethod<String, dynamic>('detectSpoof', {
      'imagePath': imagePath,
      'left': faceRect.left.round(),
      'top': faceRect.top.round(),
      'right': faceRect.right.round(),
      'bottom': faceRect.bottom.round(),
    });

    if (res == null) {
      throw Exception('Native spoof returned null');
    }

    return SpoofNativeResult(
      isSpoof: (res['isSpoof'] as bool),
      score: (res['score'] as num).toDouble(),
      timeMillis: (res['timeMillis'] as num).toInt(),
      moireScore: (res['moireScore'] as num?)?.toDouble() ?? 0.0,
      textureScore: (res['textureScore'] as num?)?.toDouble() ?? 0.0,
      detailMsg: (res['detailMsg'] as String?) ?? '',
    );
  }
}

class SpoofNativeResult {
  final bool isSpoof;
  final double score;
  final int timeMillis;
  final double moireScore;
  final double textureScore;
  final String detailMsg;

  SpoofNativeResult({
    required this.isSpoof,
    required this.score,
    required this.timeMillis,
    required this.moireScore,
    required this.textureScore,
    required this.detailMsg,
  });
}

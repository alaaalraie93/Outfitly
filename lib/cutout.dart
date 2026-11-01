import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Removes the background of a clothing photo on the phone (no internet needed
/// once Google Play services has downloaded the model).
/// Returns the path of a transparent PNG, or null if it could not be done.
Future<String?> removeBackground(String path) async {
  if (!Platform.isAndroid) return null;
  final segmenter = SubjectSegmenter(
    options: SubjectSegmenterOptions(
      enableForegroundBitmap: true,
      enableForegroundConfidenceMask: false,
      enableMultipleSubjects: SubjectResultOptions(enableConfidenceMask: false, enableSubjectBitmap: false),
    ),
  );
  try {
    final result = await segmenter.processImage(InputImage.fromFilePath(path)).timeout(const Duration(seconds: 25));
    final bytes = result.foregroundBitmap;
    if (bytes == null || bytes.isEmpty) return null;
    final trimmed = await compute(_trimAndShrink, bytes);
    if (trimmed == null) return null;
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/cutout-${DateTime.now().microsecondsSinceEpoch}.png');
    await out.writeAsBytes(trimmed, flush: true);
    return out.path;
  } catch (e) {
    debugPrint('Outfitly cutout failed: $e');
    return null;
  } finally {
    segmenter.close();
  }
}

Uint8List? _trimAndShrink(Uint8List png) {
  try {
    final decoded = img.decodePng(png);
    if (decoded == null) return null;
    // Count visible pixels on a small copy; give up if almost nothing is left.
    final probe = img.copyResize(decoded, width: 60);
    int visible = 0;
    for (final p in probe) {
      if (p.a > 128) visible++;
    }
    if (visible < probe.width * probe.height * 0.04) return null;
    var out = img.trim(decoded, mode: img.TrimMode.transparent);
    if (out.width > 900 || out.height > 900) {
      out = out.width >= out.height ? img.copyResize(out, width: 900) : img.copyResize(out, height: 900);
    }
    return img.encodePng(out);
  } catch (_) {
    return null;
  }
}

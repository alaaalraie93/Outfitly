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
  final ml = await _removeWithMlKit(path);
  if (ml != null) return ml;
  // Fallback for plain backgrounds (floor, bed, wall) when ML Kit is not ready yet.
  try {
    final bytes = await File(path).readAsBytes();
    final png = await compute(_plainBackgroundCutout, bytes);
    if (png == null) return null;
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/cutout-${DateTime.now().microsecondsSinceEpoch}.png');
    await out.writeAsBytes(png, flush: true);
    return out.path;
  } catch (_) {
    return null;
  }
}

/// Removes an even background by its difference from the border colour.
Uint8List? _plainBackgroundCutout(Uint8List bytes) {
  var src = img.decodeImage(bytes);
  if (src == null) return null;
  src = img.bakeOrientation(src);
  if (src.width > 900 || src.height > 900) {
    src = src.width >= src.height ? img.copyResize(src, width: 900) : img.copyResize(src, height: 900);
  }
  final w = src.width, h = src.height;
  // Border colour and how even it is.
  final border = <List<double>>[];
  for (int x = 0; x < w; x += 4) {
    for (final y in [0, 1, h - 2, h - 1]) {
      final p = src.getPixel(x, y);
      border.add([p.r.toDouble(), p.g.toDouble(), p.b.toDouble()]);
    }
  }
  for (int y = 0; y < h; y += 4) {
    for (final x in [0, 1, w - 2, w - 1]) {
      final p = src.getPixel(x, y);
      border.add([p.r.toDouble(), p.g.toDouble(), p.b.toDouble()]);
    }
  }
  final mean = [0.0, 0.0, 0.0];
  for (final c in border) {
    for (int i = 0; i < 3; i++) {
      mean[i] += c[i] / border.length;
    }
  }
  double spread = 0;
  for (final c in border) {
    spread += ((c[0] - mean[0]).abs() + (c[1] - mean[1]).abs() + (c[2] - mean[2]).abs()) / border.length;
  }
  if (spread > 60) return null; // busy background: keep the original photo
  final threshold = 40 + spread;
  final out = img.Image(width: w, height: h, numChannels: 4);
  int kept = 0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      final d = (p.r - mean[0]).abs() + (p.g - mean[1]).abs() + (p.b - mean[2]).abs();
      final keep = d > threshold;
      if (keep) kept++;
      out.setPixelRgba(x, y, p.r, p.g, p.b, keep ? 255 : 0);
    }
  }
  final share = kept / (w * h);
  if (share < 0.08 || share > 0.92) return null;
  return _trimAndShrink(img.encodePng(out));
}

Future<String?> _removeWithMlKit(String path) async {
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

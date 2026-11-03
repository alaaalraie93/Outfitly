import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'segment.dart';

/// Removes the background of a clothing photo on the phone (no internet needed
/// once Google Play services has downloaded the model).
/// Returns the path of a transparent PNG, or null if it could not be done.
Future<String?> removeBackground(String path) async {
  final ml = await _removeWithMlKit(path);
  if (ml != null) return ml;
  // Fallback that runs on the phone itself: works on plain and textured floors / beds.
  try {
    final bytes = await File(path).readAsBytes();
    final png = await compute(_smartCutout, bytes);
    if (png == null) return null;
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/cutout-${DateTime.now().microsecondsSinceEpoch}.png');
    await out.writeAsBytes(png, flush: true);
    return out.path;
  } catch (_) {
    return null;
  }
}

/// RGB bytes (w*h*3) of an image.
Uint8List rgbBytes(img.Image im) {
  final out = Uint8List(im.width * im.height * 3);
  int i = 0;
  for (int y = 0; y < im.height; y++) {
    for (int x = 0; x < im.width; x++) {
      final p = im.getPixel(x, y);
      out[i++] = p.r.toInt();
      out[i++] = p.g.toInt();
      out[i++] = p.b.toInt();
    }
  }
  return out;
}

img.Image fitInside(img.Image src, int max) {
  if (src.width <= max && src.height <= max) return src;
  return src.width >= src.height ? img.copyResize(src, width: max) : img.copyResize(src, height: max);
}

Uint8List? _smartCutout(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final src = fitInside(img.bakeOrientation(decoded), 900);
  final small = fitInside(src, 360);
  final mask = smartMask(rgbBytes(small), small.width, small.height);
  if (mask == null) return null;
  final alpha = upscaleMask(mask, small.width, small.height, src.width, src.height);
  final out = img.Image(width: src.width, height: src.height, numChannels: 4);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      out.setPixelRgba(x, y, p.r, p.g, p.b, alpha[y * src.width + x]);
    }
  }
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
    // Nothing left, or nothing removed: not a real cut-out.
    if (visible < probe.width * probe.height * 0.04 || visible > probe.width * probe.height * 0.97) return null;
    var out = img.trim(decoded, mode: img.TrimMode.transparent);
    if (out.width > 900 || out.height > 900) {
      out = out.width >= out.height ? img.copyResize(out, width: 900) : img.copyResize(out, height: 900);
    }
    return img.encodePng(out);
  } catch (_) {
    return null;
  }
}

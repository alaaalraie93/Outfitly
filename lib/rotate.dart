import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Saves a copy of the photo turned by 90 degrees and returns its path.
Future<String?> rotatePhoto(String path, bool clockwise) async {
  try {
    final bytes = await File(path).readAsBytes();
    final png = path.toLowerCase().endsWith('.png');
    final out = await compute(_rotate, _RotateInput(bytes, clockwise, png));
    if (out == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/turned-${DateTime.now().microsecondsSinceEpoch}.${png ? 'png' : 'jpg'}');
    await file.writeAsBytes(out, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}

class _RotateInput {
  final Uint8List bytes;
  final bool clockwise;
  final bool png;
  _RotateInput(this.bytes, this.clockwise, this.png);
}

Uint8List? _rotate(_RotateInput input) {
  final decoded = img.decodeImage(input.bytes);
  if (decoded == null) return null;
  final upright = img.bakeOrientation(decoded);
  final turned = img.copyRotate(upright, angle: input.clockwise ? 90 : -90);
  return input.png ? img.encodePng(turned) : img.encodeJpg(turned, quality: 92);
}

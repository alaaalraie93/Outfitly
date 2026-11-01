import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Saves the widget under [key] as a PNG and opens the share sheet
/// (WhatsApp, Instagram, save to gallery...).
Future<bool> shareCapture(GlobalKey key, {String? text}) async {
  try {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return false;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return false;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/outfitly-${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')], text: text);
    return true;
  } catch (e) {
    debugPrint('Outfitly share failed: $e');
    return false;
  }
}

/// Shares any file (used for backups).
Future<void> shareFile(String path, {String? text}) async {
  await Share.shareXFiles([XFile(path)], text: text);
}

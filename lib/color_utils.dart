import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Extracts the main colors of a clothing photo.
/// The border of the photo is treated as background and ignored,
/// so a piece photographed on a plain surface gives its real color.
Future<List<int>> analyzeImageColors(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    return await compute(_analyze, bytes);
  } catch (_) {
    return [0xFF808080];
  }
}

List<int> _analyze(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return [0xFF808080];
  final im = img.copyResize(decoded, width: 72);
  final w = im.width;
  final h = im.height;

  // A cut-out photo (transparent background): use only the visible pixels.
  bool cutout = false;
  if (im.hasAlpha) {
    int clear = 0;
    for (final p in im) {
      if (p.a < 128) clear++;
    }
    cutout = clear > w * h * 0.05;
  }

  // Background estimate from the border.
  double br = 0, bg = 0, bb = 0;
  int bn = 0;
  void addBorder(int x, int y) {
    final p = im.getPixel(x, y);
    br += p.r.toDouble();
    bg += p.g.toDouble();
    bb += p.b.toDouble();
    bn++;
  }

  for (int x = 0; x < w; x++) {
    addBorder(x, 0);
    addBorder(x, h - 1);
  }
  for (int y = 0; y < h; y++) {
    addBorder(0, y);
    addBorder(w - 1, y);
  }
  br /= bn;
  bg /= bn;
  bb /= bn;

  final counts = <int, int>{};
  final sr = <int, double>{};
  final sg = <int, double>{};
  final sb = <int, double>{};

  void collect(bool skipBackground) {
    final y0 = cutout ? 0 : (h * 0.12).floor(), y1 = cutout ? h : (h * 0.88).ceil();
    final x0 = cutout ? 0 : (w * 0.15).floor(), x1 = cutout ? w : (w * 0.85).ceil();
    for (int y = y0; y < y1; y++) {
      for (int x = x0; x < x1; x++) {
        final p = im.getPixel(x, y);
        if (cutout) {
          if (p.a < 128) continue;
          skipBackground = false;
        }
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        if (skipBackground) {
          final d = math.sqrt((r - br) * (r - br) + (g - bg) * (g - bg) + (b - bb) * (b - bb));
          if (d < 45) continue;
        }
        final key = ((r ~/ 32) << 6) | ((g ~/ 32) << 3) | (b ~/ 32);
        counts[key] = (counts[key] ?? 0) + 1;
        sr[key] = (sr[key] ?? 0.0) + r;
        sg[key] = (sg[key] ?? 0.0) + g;
        sb[key] = (sb[key] ?? 0.0) + b;
      }
    }
  }

  collect(true);
  if (counts.values.fold<int>(0, (a, b) => a + b) < 40) {
    counts.clear();
    sr.clear();
    sg.clear();
    sb.clear();
    collect(false);
  }
  if (counts.isEmpty) return [0xFF808080];

  final keys = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  final result = <int>[];
  for (final k in keys) {
    final n = counts[k]!;
    final r = (sr[k]! / n).round().clamp(0, 255);
    final g = (sg[k]! / n).round().clamp(0, 255);
    final b = (sb[k]! / n).round().clamp(0, 255);
    final v = 0xFF000000 | (r << 16) | (g << 8) | b;
    bool similar = false;
    for (final e in result) {
      final er = (e >> 16) & 0xFF, eg = (e >> 8) & 0xFF, eb = e & 0xFF;
      if ((er - r).abs() + (eg - g).abs() + (eb - b).abs() < 60) {
        similar = true;
        break;
      }
    }
    if (!similar) result.add(v);
    if (result.length >= 5) break;
  }
  return result;
}

/// Coarse color family used for matching rules and display names.
enum ColorFamily { black, white, grey, beige, brown, navy, red, orange, yellow, green, olive, teal, blue, purple, pink, burgundy }

ColorFamily colorFamily(Color c) {
  final hsl = HSLColor.fromColor(c);
  final h = hsl.hue, s = hsl.saturation, l = hsl.lightness;
  if (l < 0.13) return ColorFamily.black;
  if (l > 0.9 && s < 0.5) return ColorFamily.white;
  if (s < 0.12) return l > 0.75 ? ColorFamily.white : ColorFamily.grey;
  if (h >= 20 && h < 50 && s < 0.5 && l > 0.6) return ColorFamily.beige;
  // Olive / khaki green: dark yellow-green where green is nearly as strong as red.
  final r8 = (c.r * 255), g8 = (c.g * 255);
  if (l < 0.45 && h >= 35 && h < 95 && g8 >= r8 * 0.88) return ColorFamily.olive;
  if (h >= 10 && h < 45 && l < 0.45) return ColorFamily.brown;
  if (h >= 200 && h < 255 && l < 0.3) return ColorFamily.navy;
  if ((h >= 330 || h < 10) && l < 0.32) return ColorFamily.burgundy;
  if (h >= 45 && h < 80 && l < 0.4) return ColorFamily.olive;
  if (h < 12 || h >= 345) return ColorFamily.red;
  if (h < 40) return ColorFamily.orange;
  if (h < 65) return ColorFamily.yellow;
  if (h < 160) return ColorFamily.green;
  if (h < 195) return ColorFamily.teal;
  if (h < 255) return ColorFamily.blue;
  if (h < 290) return ColorFamily.purple;
  return ColorFamily.pink;
}

bool isNeutral(Color c) {
  final f = colorFamily(c);
  return f == ColorFamily.black ||
      f == ColorFamily.white ||
      f == ColorFamily.grey ||
      f == ColorFamily.beige ||
      f == ColorFamily.navy ||
      f == ColorFamily.olive ||
      f == ColorFamily.brown;
}

String colorKey(Color c) => 'c_${colorFamily(c).name}';

Color shade(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image/image.dart' as img;

import 'models.dart';

/// What the app guessed from a photo. Every field stays editable.
class Detected {
  final ClothCat category;
  final String subType;
  final StyleLevel style;
  final Season season;
  final bool patterned;
  final List<String> labels;
  const Detected(this.category, this.subType, this.style, this.season, this.patterned, this.labels);
}

/// Guesses category, type, style, season and pattern from a clothing photo.
/// Combines on-device ML Kit labels with the shape of the cut-out piece.
Future<Detected> classifyPhoto({required String originalPath, required String shapePath, required int mainColor, required BodyType body}) async {
  final labels = <String>[];
  if (Platform.isAndroid) {
    final labeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.55));
    try {
      final res = await labeler.processImage(InputImage.fromFilePath(originalPath)).timeout(const Duration(seconds: 15));
      for (final l in res) {
        labels.add(l.label.toLowerCase());
      }
    } catch (e) {
      debugPrint('Outfitly labeling failed: $e');
    } finally {
      labeler.close();
    }
  }
  _Shape shape;
  try {
    final bytes = await File(shapePath).readAsBytes();
    shape = await compute(_analyzeShape, _ShapeInput(bytes, mainColor));
  } catch (_) {
    shape = const _Shape.unknown();
  }
  return _decide(labels, shape, Color(mainColor), body);
}

bool _has(List<String> labels, List<String> keys) => labels.any(keys.contains);

Detected _decide(List<String> labels, _Shape s, Color color, BodyType body) {
  ClothCat cat;
  String sub;
  StyleLevel? style;

  final hsl = HSLColor.fromColor(color);
  final denimBlue = hsl.hue >= 195 && hsl.hue <= 235 && hsl.saturation > 0.15 && hsl.saturation < 0.7;

  if (_has(labels, ['sunglasses', 'glasses', 'goggles'])) {
    cat = ClothCat.accessory;
    sub = 'glasses';
  } else if (_has(labels, ['hat', 'cap', 'beanie', 'helmet'])) {
    cat = ClothCat.accessory;
    sub = 'hat';
  } else if (_has(labels, ['handbag', 'bag'])) {
    cat = ClothCat.accessory;
    sub = 'bag';
  } else if (_has(labels, ['necklace', 'jewellery', 'chain', 'bracelet', 'bangle', 'ring'])) {
    cat = ClothCat.accessory;
    sub = 'necklace';
  } else if (_has(labels, ['scarf'])) {
    cat = ClothCat.accessory;
    sub = 'scarf';
  } else if (_has(labels, ['shoe', 'sneakers']) || (s.known && s.aspect < 0.72 && !s.legGap && !s.sleeves)) {
    cat = ClothCat.shoes;
    if (s.known && s.aspect > 1.1) {
      sub = 'boots';
    } else if (s.known && s.fill < 0.42) {
      sub = 'sandals';
    } else if (_has(labels, ['sneakers'])) {
      sub = 'sneakers';
    } else {
      sub = hsl.lightness < 0.25 && hsl.saturation < 0.3 ? 'formal_shoes' : 'sneakers';
    }
  } else if (_has(labels, ['dress', 'gown', 'sari'])) {
    cat = ClothCat.dress;
    sub = 'dress';
  } else if (_has(labels, ['shorts'])) {
    cat = ClothCat.bottom;
    sub = 'shorts';
  } else if (_has(labels, ['jeans', 'denim']) && (s.legGap || !s.sleeves)) {
    cat = ClothCat.bottom;
    sub = 'jeans';
  } else if (_has(labels, ['tights', 'leggings'])) {
    cat = ClothCat.bottom;
    sub = 'trousers';
  } else if (_has(labels, ['jacket', 'blazer', 'outerwear', 'tuxedo'])) {
    cat = ClothCat.outer;
    sub = _has(labels, ['blazer', 'tuxedo']) ? 'blazer' : 'jacket';
    if (_has(labels, ['blazer', 'tuxedo'])) style = StyleLevel.formal;
  } else if (s.known && s.legGap) {
    cat = ClothCat.bottom;
    if (s.aspect < 1.2) {
      sub = 'shorts';
    } else {
      sub = denimBlue || _has(labels, ['denim']) ? 'jeans' : 'trousers';
    }
  } else if (s.known && s.widening > 1.25 && !s.sleeves) {
    if (s.aspect > 1.35) {
      cat = ClothCat.dress;
      sub = 'dress';
    } else {
      cat = ClothCat.bottom;
      sub = 'skirt';
    }
  } else {
    cat = ClothCat.top;
    if (s.longSleeves) {
      sub = _has(labels, ['pocket']) ? 'shirt' : (s.hood ? 'hoodie' : 'sweater');
    } else {
      sub = 'tshirt';
    }
    if (_has(labels, ['jersey'])) style = StyleLevel.sport;
  }

  // Respect the profile (e.g. no dresses for "Man").
  if (!categoriesFor(body).contains(cat)) {
    cat = ClothCat.top;
    sub = 'tshirt';
  }
  final allowed = subTypesFor(cat, body);
  if (!allowed.contains(sub)) sub = allowed.first;

  return Detected(cat, sub, style ?? defaultStyleFor(sub), defaultSeasonFor(sub), s.patterned, labels);
}

class _ShapeInput {
  final Uint8List bytes;
  final int mainColor;
  _ShapeInput(this.bytes, this.mainColor);
}

class _Shape {
  final bool known;
  final double aspect; // height / width of the piece
  final double fill; // share of the bounding box covered by the piece
  final double widening; // bottom width / top width
  final bool legGap; // a gap between two legs at the bottom
  final bool sleeves; // parts sticking out at the sides near the top
  final bool longSleeves;
  final bool hood;
  final bool patterned;

  const _Shape(this.known, this.aspect, this.fill, this.widening, this.legGap, this.sleeves, this.longSleeves, this.hood, this.patterned);

  const _Shape.unknown()
      : known = false,
        aspect = 1,
        fill = 1,
        widening = 1,
        legGap = false,
        sleeves = false,
        longSleeves = false,
        hood = false,
        patterned = false;
}

_Shape _analyzeShape(_ShapeInput input) {
  final decoded = img.decodeImage(input.bytes);
  if (decoded == null) return const _Shape.unknown();
  final im = img.copyResize(decoded, width: 64);
  final w = im.width, h = im.height;

  // Mask: transparent background for cut-outs, otherwise "different from the border".
  final mask = List.generate(h, (_) => List<bool>.filled(w, false));
  bool cut = false;
  if (im.hasAlpha) {
    int clear = 0;
    for (final p in im) {
      if (p.a < 128) clear++;
    }
    cut = clear > w * h * 0.05;
  }
  double br = 0, bg = 0, bb = 0;
  if (!cut) {
    int n = 0;
    for (int x = 0; x < w; x++) {
      for (final y in [0, h - 1]) {
        final p = im.getPixel(x, y);
        br += p.r.toDouble();
        bg += p.g.toDouble();
        bb += p.b.toDouble();
        n++;
      }
    }
    br /= n;
    bg /= n;
    bb /= n;
  }
  final mr = (input.mainColor >> 16) & 0xFF, mg = (input.mainColor >> 8) & 0xFF, mb = input.mainColor & 0xFF;
  int visible = 0, far = 0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = im.getPixel(x, y);
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      final on = cut ? p.a >= 128 : math.sqrt((r - br) * (r - br) + (g - bg) * (g - bg) + (b - bb) * (b - bb)) > 45;
      mask[y][x] = on;
      if (on) {
        visible++;
        final d = (r - mr).abs() + (g - mg).abs() + (b - mb).abs();
        if (d > 110) far++;
      }
    }
  }
  if (visible < 30) return const _Shape.unknown();

  // Bounding box.
  int x0 = w, x1 = -1, y0 = h, y1 = -1;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (mask[y][x]) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  final bw = (x1 - x0 + 1).toDouble(), bh = (y1 - y0 + 1).toDouble();
  final aspect = bh / bw;
  final fill = visible / (bw * bh);

  int rowAt(double f) => (y0 + (bh - 1) * f).round().clamp(0, h - 1);
  int widthAt(double f) {
    final y = rowAt(f);
    int l = -1, r = -1;
    for (int x = x0; x <= x1; x++) {
      if (mask[y][x]) {
        if (l < 0) l = x;
        r = x;
      }
    }
    return l < 0 ? 0 : r - l + 1;
  }

  int runsAt(double f) {
    final y = rowAt(f);
    int runs = 0;
    bool inRun = false;
    for (int x = x0; x <= x1; x++) {
      if (mask[y][x] && !inRun) runs++;
      inRun = mask[y][x];
    }
    return runs;
  }

  bool centerEmpty(double f) {
    final y = rowAt(f);
    final c0 = (x0 + bw * 0.44).floor(), c1 = (x0 + bw * 0.56).ceil();
    int on = 0, total = 0;
    for (int x = c0; x <= c1 && x < w; x++) {
      total++;
      if (mask[y][x]) on++;
    }
    return total > 0 && on / total < 0.25;
  }

  final legGap = centerEmpty(0.85) && centerEmpty(0.95) && runsAt(0.9) >= 2;
  final topW = widthAt(0.12).toDouble();
  final midW = widthAt(0.5).toDouble();
  final lowW = widthAt(0.88).toDouble();
  final widening = topW > 0 ? lowW / topW : 1.0;
  // Sleeves: wide shoulders compared with the body, or separate pieces at the sides.
  final sleeves = (topW > midW * 1.25) || runsAt(0.6) >= 3 || runsAt(0.75) >= 3;
  final longSleeves = sleeves && (runsAt(0.75) >= 3 || runsAt(0.85) >= 3 || widthAt(0.85) > bw * 0.85);
  // Hood: a narrow bump above the shoulders in the middle.
  final hood = widthAt(0.03) > 0 && widthAt(0.03) < topW * 0.6 && centerEmpty(0.03) == false;

  // Only trust the pattern guess on clean cut-outs; backgrounds fool it.
  return _Shape(true, aspect, fill, widening, legGap, sleeves, longSleeves, hood, cut && far / visible > 0.4);
}

import 'dart:math' as math;
import 'dart:typed_data';

/// Background removal that works on the phone without any model:
/// colours at the photo's edges describe the floor/bed, colours in the middle
/// describe the piece. Every pixel goes to the closer group, and only background
/// that touches the edge is removed. Handles textured floors (wood, carpet).
///
/// [rgb] holds w*h*3 bytes. Returns a mask (1 = piece) or null if unsure.
Uint8List? smartMask(Uint8List rgb, int w, int h) {
  final n = w * h;
  final b = _blur(rgb, w, h, 2);
  final m = math.max(2, (math.min(w, h) * 0.04).floor());

  final border = <int>[];
  final center = <int>[];
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (x < m || x >= w - m || y < m || y >= h - m) border.add(y * w + x);
      if (x >= w * 0.3 && x < w * 0.7 && y >= h * 0.3 && y < h * 0.7) center.add(y * w + x);
    }
  }
  if (border.isEmpty || center.isEmpty) return null;

  final bc = _kmeans(b, border, 6);
  final fc = _kmeans(b, center, 6);
  final bgc = <Float64List>[];
  final fgc = <Float64List>[];
  for (final c in bc) {
    if (c.weight > 0.03 && _freq(b, c.color, border) > _freq(b, c.color, center) * 1.3) bgc.add(c.color);
  }
  for (final c in fc) {
    if (c.weight > 0.03 && _freq(b, c.color, center) > _freq(b, c.color, border) * 1.3) fgc.add(c.color);
  }
  if (bgc.isEmpty || fgc.isEmpty) return null;

  final isBg = Uint8List(n);
  for (int i = 0; i < n; i++) {
    final r = b[i * 3], g = b[i * 3 + 1], bl = b[i * 3 + 2];
    double db = double.infinity, df = double.infinity;
    for (final c in bgc) {
      final d = _sq(r - c[0]) + _sq(g - c[1]) + _sq(bl - c[2]);
      if (d < db) db = d;
    }
    for (final c in fgc) {
      final d = _sq(r - c[0]) + _sq(g - c[1]) + _sq(bl - c[2]);
      if (d < df) df = d;
    }
    if (db < df) isBg[i] = 1;
  }

  // Background has to be connected to the photo's edge.
  final bg = _floodFromBorder(isBg, w, h);
  var fg = Uint8List(n);
  for (int i = 0; i < n; i++) {
    fg[i] = bg[i] == 1 ? 0 : 1;
  }
  fg = _open(fg, w, h, 2);
  fg = _largestComponent(fg, w, h);
  fg = _close(fg, w, h, 2);
  fg = fillHoles(fg, w, h);

  int count = 0;
  for (int i = 0; i < n; i++) {
    count += fg[i];
  }
  final share = count / n;
  if (share < 0.05 || share > 0.95) return null;
  // The piece should fill most of the photo's middle; if not, the guess is wrong.
  int inCenter = 0;
  for (final i in center) {
    inCenter += fg[i];
  }
  if (inCenter / center.length < 0.65) return null;
  return fg;
}

/// Scales a 0/1 mask to a new size, returning soft alpha (0..255) for smooth edges.
Uint8List upscaleMask(Uint8List mask, int w, int h, int outW, int outH) {
  final out = Uint8List(outW * outH);
  for (int y = 0; y < outH; y++) {
    final fy = ((y + 0.5) * h / outH - 0.5).clamp(0.0, h - 1.0);
    final y0 = fy.floor(), y1 = math.min(y0 + 1, h - 1);
    final ty = fy - y0;
    for (int x = 0; x < outW; x++) {
      final fx = ((x + 0.5) * w / outW - 0.5).clamp(0.0, w - 1.0);
      final x0 = fx.floor(), x1 = math.min(x0 + 1, w - 1);
      final tx = fx - x0;
      final v = (mask[y0 * w + x0] * (1 - tx) + mask[y0 * w + x1] * tx) * (1 - ty) +
          (mask[y1 * w + x0] * (1 - tx) + mask[y1 * w + x1] * tx) * ty;
      out[y * outW + x] = (((v - 0.35) / 0.3).clamp(0.0, 1.0) * 255).round();
    }
  }
  return out;
}

/// Pixels connected to (x, y) whose colour is close to the tapped colour.
/// Used by the manual "tap to erase / restore" tool. [rgb] is w*h*3 bytes.
List<int> similarRegion(Uint8List rgb, int w, int h, int x, int y, double tolerance) {
  final n = w * h;
  final seen = Uint8List(n);
  final start = y * w + x;
  final sr = rgb[start * 3], sg = rgb[start * 3 + 1], sb = rgb[start * 3 + 2];
  final tol = tolerance * tolerance * 3;
  final region = <int>[];
  final queue = <int>[start];
  seen[start] = 1;
  int head = 0;
  while (head < queue.length) {
    final i = queue[head++];
    region.add(i);
    final px = i % w, py = i ~/ w;
    for (final j in [if (px > 0) i - 1, if (px < w - 1) i + 1, if (py > 0) i - w, if (py < h - 1) i + w]) {
      if (seen[j] == 1) continue;
      seen[j] = 1;
      final d = _sq((rgb[j * 3] - sr).toDouble()) + _sq((rgb[j * 3 + 1] - sg).toDouble()) + _sq((rgb[j * 3 + 2] - sb).toDouble());
      if (d <= tol) queue.add(j);
    }
  }
  return region;
}

/// Turns enclosed background (holes inside the piece) into piece.
Uint8List fillHoles(Uint8List fg, int w, int h) {
  final inv = Uint8List(w * h);
  for (int i = 0; i < inv.length; i++) {
    inv[i] = fg[i] == 1 ? 0 : 1;
  }
  final outside = _floodFromBorder(inv, w, h);
  final out = Uint8List(w * h);
  for (int i = 0; i < out.length; i++) {
    out[i] = outside[i] == 1 ? 0 : 1;
  }
  return out;
}

// ---------------------------------------------------------------- helpers

double _sq(double v) => v * v;

class _Cluster {
  final Float64List color;
  final double weight;
  _Cluster(this.color, this.weight);
}

Float32List _blur(Uint8List rgb, int w, int h, int r) {
  final tmp = Float32List(w * h * 3);
  final out = Float32List(w * h * 3);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      double s0 = 0, s1 = 0, s2 = 0;
      int c = 0;
      for (int k = -r; k <= r; k++) {
        final xx = (x + k).clamp(0, w - 1);
        final i = (y * w + xx) * 3;
        s0 += rgb[i];
        s1 += rgb[i + 1];
        s2 += rgb[i + 2];
        c++;
      }
      final o = (y * w + x) * 3;
      tmp[o] = s0 / c;
      tmp[o + 1] = s1 / c;
      tmp[o + 2] = s2 / c;
    }
  }
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      double s0 = 0, s1 = 0, s2 = 0;
      int c = 0;
      for (int k = -r; k <= r; k++) {
        final yy = (y + k).clamp(0, h - 1);
        final i = (yy * w + x) * 3;
        s0 += tmp[i];
        s1 += tmp[i + 1];
        s2 += tmp[i + 2];
        c++;
      }
      final o = (y * w + x) * 3;
      out[o] = s0 / c;
      out[o + 1] = s1 / c;
      out[o + 2] = s2 / c;
    }
  }
  return out;
}

List<_Cluster> _kmeans(Float32List b, List<int> samples, int k) {
  final cents = List.generate(k, (i) {
    final p = samples[((samples.length - 1) * i / math.max(1, k - 1)).round()];
    return Float64List.fromList([b[p * 3], b[p * 3 + 1], b[p * 3 + 2]]);
  });
  final label = Int32List(samples.length);
  for (int it = 0; it < 12; it++) {
    final sums = List.generate(k, (_) => Float64List(3));
    final counts = Int32List(k);
    for (int s = 0; s < samples.length; s++) {
      final p = samples[s] * 3;
      int best = 0;
      double bd = double.infinity;
      for (int c = 0; c < k; c++) {
        final d = _sq(b[p] - cents[c][0]) + _sq(b[p + 1] - cents[c][1]) + _sq(b[p + 2] - cents[c][2]);
        if (d < bd) {
          bd = d;
          best = c;
        }
      }
      label[s] = best;
      sums[best][0] += b[p];
      sums[best][1] += b[p + 1];
      sums[best][2] += b[p + 2];
      counts[best]++;
    }
    for (int c = 0; c < k; c++) {
      if (counts[c] > 0) {
        cents[c][0] = sums[c][0] / counts[c];
        cents[c][1] = sums[c][1] / counts[c];
        cents[c][2] = sums[c][2] / counts[c];
      }
    }
  }
  final counts = Int32List(k);
  for (final l in label) {
    counts[l]++;
  }
  return [for (int c = 0; c < k; c++) _Cluster(cents[c], counts[c] / samples.length)];
}

double _freq(Float32List b, Float64List c, List<int> samples) {
  int near = 0;
  for (final s in samples) {
    final p = s * 3;
    if (_sq(b[p] - c[0]) + _sq(b[p + 1] - c[1]) + _sq(b[p + 2] - c[2]) < 784) near++;
  }
  return near / samples.length;
}

/// Marks pixels of [on] (1) that are connected to the image edge.
Uint8List _floodFromBorder(Uint8List on, int w, int h) {
  final out = Uint8List(w * h);
  final queue = <int>[];
  void seed(int i) {
    if (on[i] == 1 && out[i] == 0) {
      out[i] = 1;
      queue.add(i);
    }
  }

  for (int x = 0; x < w; x++) {
    seed(x);
    seed((h - 1) * w + x);
  }
  for (int y = 0; y < h; y++) {
    seed(y * w);
    seed(y * w + w - 1);
  }
  int head = 0;
  while (head < queue.length) {
    final i = queue[head++];
    final x = i % w, y = i ~/ w;
    if (x > 0) seed(i - 1);
    if (x < w - 1) seed(i + 1);
    if (y > 0) seed(i - w);
    if (y < h - 1) seed(i + w);
  }
  return out;
}

Uint8List _morph(Uint8List src, int w, int h, bool dilate) {
  final out = Uint8List(w * h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int v = dilate ? 0 : 1;
      for (int dy = -1; dy <= 1; dy++) {
        final yy = (y + dy).clamp(0, h - 1);
        for (int dx = -1; dx <= 1; dx++) {
          final xx = (x + dx).clamp(0, w - 1);
          final s = src[yy * w + xx];
          if (dilate && s == 1) v = 1;
          if (!dilate && s == 0) v = 0;
        }
      }
      out[y * w + x] = v;
    }
  }
  return out;
}

Uint8List _open(Uint8List m, int w, int h, int it) {
  var o = m;
  for (int i = 0; i < it; i++) {
    o = _morph(o, w, h, false);
  }
  for (int i = 0; i < it; i++) {
    o = _morph(o, w, h, true);
  }
  return o;
}

Uint8List _close(Uint8List m, int w, int h, int it) {
  var o = m;
  for (int i = 0; i < it; i++) {
    o = _morph(o, w, h, true);
  }
  for (int i = 0; i < it; i++) {
    o = _morph(o, w, h, false);
  }
  return o;
}

Uint8List _largestComponent(Uint8List m, int w, int h) {
  final label = Int32List(w * h);
  int next = 0, bestLabel = 0, bestSize = 0;
  for (int s = 0; s < m.length; s++) {
    if (m[s] == 0 || label[s] != 0) continue;
    next++;
    int size = 0;
    final queue = <int>[s];
    label[s] = next;
    int head = 0;
    while (head < queue.length) {
      final i = queue[head++];
      size++;
      final x = i % w, y = i ~/ w;
      for (final j in [if (x > 0) i - 1, if (x < w - 1) i + 1, if (y > 0) i - w, if (y < h - 1) i + w]) {
        if (m[j] == 1 && label[j] == 0) {
          label[j] = next;
          queue.add(j);
        }
      }
    }
    if (size > bestSize) {
      bestSize = size;
      bestLabel = next;
    }
  }
  final out = Uint8List(w * h);
  for (int i = 0; i < out.length; i++) {
    out[i] = label[i] == bestLabel && bestLabel != 0 ? 1 : 0;
  }
  return out;
}

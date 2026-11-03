import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../cutout.dart';
import '../l10n.dart';
import '../segment.dart';

/// Lets the user clean up the background by hand:
/// tap an area to erase everything similar connected to it, or paint with a brush.
/// "Restore" brings parts of the piece back. Returns the path of the new PNG.
class CutoutEditorScreen extends StatefulWidget {
  final String sourcePath;
  const CutoutEditorScreen({super.key, required this.sourcePath});

  @override
  State<CutoutEditorScreen> createState() => _CutoutEditorScreenState();
}

class _CutoutEditorScreenState extends State<CutoutEditorScreen> {
  _Prep? data;
  ui.Image? preview;
  bool loading = true;
  bool saving = false;
  bool erase = true;
  bool brush = false;
  double tolerance = 32;
  double brushSize = 28;
  final List<Uint8List> history = [];
  bool _renderQueued = false;
  bool _rendering = false;
  Offset? _lastBrush;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.sourcePath).readAsBytes();
      final prep = await compute(_prepare, bytes);
      if (!mounted) return;
      if (prep == null) {
        Navigator.pop(context);
        return;
      }
      data = prep;
      await _render();
    } catch (_) {
      if (mounted) Navigator.pop(context);
      return;
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _render() async {
    final d = data;
    if (d == null) return;
    if (_rendering) {
      _renderQueued = true;
      return;
    }
    _rendering = true;
    final rgba = Uint8List(d.w * d.h * 4);
    for (int i = 0, n = d.w * d.h; i < n; i++) {
      rgba[i * 4] = d.rgb[i * 3];
      rgba[i * 4 + 1] = d.rgb[i * 3 + 1];
      rgba[i * 4 + 2] = d.rgb[i * 3 + 2];
      rgba[i * 4 + 3] = d.alpha[i];
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final desc = ui.ImageDescriptor.raw(buffer, width: d.w, height: d.h, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    _rendering = false;
    if (!mounted) return;
    setState(() => preview = frame.image);
    if (_renderQueued) {
      _renderQueued = false;
      _render();
    }
  }

  void _saveUndo() {
    final d = data;
    if (d == null) return;
    history.add(Uint8List.fromList(d.alpha));
    if (history.length > 20) history.removeAt(0);
  }

  void _undo() {
    final d = data;
    if (d == null || history.isEmpty) return;
    d.alpha.setAll(0, history.removeLast());
    setState(() {});
    _render();
  }

  Future<void> _auto() async {
    final d = data;
    if (d == null) return;
    setState(() => loading = true);
    final alpha = await compute(_autoAlpha, d);
    if (!mounted) return;
    if (alpha != null) {
      _saveUndo();
      d.alpha.setAll(0, alpha);
      await _render();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('bg_failed')), behavior: SnackBarBehavior.floating));
    }
    if (mounted) setState(() => loading = false);
  }

  /// Converts a touch on the screen to a pixel of the working image.
  (int, int)? _toImage(Offset local, Size box) {
    final d = data;
    if (d == null) return null;
    final scale = math.min(box.width / d.w, box.height / d.h);
    final dx = (box.width - d.w * scale) / 2, dy = (box.height - d.h * scale) / 2;
    final x = ((local.dx - dx) / scale).floor(), y = ((local.dy - dy) / scale).floor();
    if (x < 0 || y < 0 || x >= d.w || y >= d.h) return null;
    return (x, y);
  }

  double _scale(Size box) {
    final d = data!;
    return math.min(box.width / d.w, box.height / d.h);
  }

  void _magic(Offset local, Size box) {
    final d = data;
    final p = _toImage(local, box);
    if (d == null || p == null) return;
    _saveUndo();
    final region = similarRegion(d.rgb, d.w, d.h, p.$1, p.$2, tolerance);
    final v = erase ? 0 : 255;
    for (final i in region) {
      d.alpha[i] = v;
    }
    _render();
  }

  void _paint(Offset local, Size box) {
    final d = data;
    if (d == null) return;
    final from = _lastBrush ?? local;
    _lastBrush = local;
    final r = brushSize / 2 / _scale(box);
    final v = erase ? 0 : 255;
    final steps = math.max(1, ((local - from).distance / (brushSize / 4)).ceil());
    for (int s = 1; s <= steps; s++) {
      final pt = Offset.lerp(from, local, s / steps)!;
      final p = _toImage(pt, box);
      if (p == null) continue;
      final rr = r.ceil();
      for (int y = math.max(0, p.$2 - rr); y <= math.min(d.h - 1, p.$2 + rr); y++) {
        for (int x = math.max(0, p.$1 - rr); x <= math.min(d.w - 1, p.$1 + rr); x++) {
          final ddx = x - p.$1, ddy = y - p.$2;
          if (ddx * ddx + ddy * ddy <= r * r) d.alpha[y * d.w + x] = v;
        }
      }
    }
    _render();
  }

  Future<void> _done() async {
    final d = data;
    if (d == null) return;
    setState(() => saving = true);
    final png = await compute(_export, d);
    if (!mounted) return;
    if (png == null) {
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('edit_bg_empty')), behavior: SnackBarBehavior.floating));
      return;
    }
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/edited-${DateTime.now().microsecondsSinceEpoch}.png');
    await out.writeAsBytes(png, flush: true);
    if (mounted) Navigator.pop(context, out.path);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = preview;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('edit_bg')),
        actions: [
          IconButton(tooltip: context.tr('undo'), onPressed: history.isEmpty ? null : _undo, icon: const Icon(Icons.undo)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(context.tr(brush ? 'edit_bg_hint_brush' : 'edit_bg_hint_magic'),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final box = c.biggest;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: brush ? null : (e) => _magic(e.localPosition, box),
                      onPanStart: brush
                          ? (e) {
                              _saveUndo();
                              _lastBrush = null;
                              _paint(e.localPosition, box);
                            }
                          : null,
                      onPanUpdate: brush ? (e) => _paint(e.localPosition, box) : null,
                      onPanEnd: brush ? (_) => _lastBrush = null : null,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const CustomPaint(painter: _Checker()),
                          if (image != null) RawImage(image: image, fit: BoxFit.contain),
                          if (loading || saving) const Center(child: CircularProgressIndicator()),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(value: true, icon: const Icon(Icons.auto_fix_off), label: Text(context.tr('erase'))),
                            ButtonSegment(value: false, icon: const Icon(Icons.auto_fix_high), label: Text(context.tr('restore'))),
                          ],
                          selected: {erase},
                          onSelectionChanged: (v) => setState(() => erase = v.first),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(value: false, icon: const Icon(Icons.touch_app_outlined), label: Text(context.tr('magic'))),
                            ButtonSegment(value: true, icon: const Icon(Icons.brush_outlined), label: Text(context.tr('brush'))),
                          ],
                          selected: {brush},
                          onSelectionChanged: (v) => setState(() => brush = v.first),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(context.tr(brush ? 'brush_size' : 'tolerance'), style: const TextStyle(fontSize: 13)),
                      ),
                      Expanded(
                        child: brush
                            ? Slider(min: 8, max: 80, value: brushSize, onChanged: (v) => setState(() => brushSize = v))
                            : Slider(min: 6, max: 90, value: tolerance, onChanged: (v) => setState(() => tolerance = v)),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: loading || saving ? null : _auto,
                          icon: const Icon(Icons.auto_awesome),
                          label: Text(context.tr('auto')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: loading || saving ? null : _done,
                          icon: const Icon(Icons.check),
                          label: Text(context.tr('done')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Checker extends CustomPainter {
  const _Checker();

  @override
  void paint(Canvas canvas, Size size) {
    const s = 14.0;
    final a = Paint()..color = const Color(0xFFEDEFF2);
    final b = Paint()..color = const Color(0xFFD9DDE3);
    canvas.drawRect(Offset.zero & size, a);
    for (double y = 0; y < size.height; y += s) {
      for (double x = ((y / s).floor() % 2) * s; x < size.width; x += s * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, s, s), b);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Checker oldDelegate) => false;
}

// ---------------------------------------------------------------- isolate work

class _Prep {
  final int w;
  final int h;
  final Uint8List rgb;
  final Uint8List alpha;
  _Prep(this.w, this.h, this.rgb, this.alpha);
}

_Prep? _prepare(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final src = fitInside(img.bakeOrientation(decoded), 720);
  final w = src.width, h = src.height;
  final rgb = rgbBytes(src);
  final alpha = Uint8List(w * h);
  // Already a cut-out: start from its transparency.
  int clear = 0;
  if (src.hasAlpha) {
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final a = src.getPixel(x, y).a.toInt();
        alpha[y * w + x] = a >= 128 ? 255 : 0;
        if (a < 128) clear++;
      }
    }
  }
  if (clear > w * h * 0.05) return _Prep(w, h, rgb, alpha);
  final auto = _autoAlpha(_Prep(w, h, rgb, alpha));
  if (auto != null) {
    alpha.setAll(0, auto);
  } else {
    alpha.fillRange(0, alpha.length, 255);
  }
  return _Prep(w, h, rgb, alpha);
}

Uint8List? _autoAlpha(_Prep p) {
  final src = img.Image.fromBytes(width: p.w, height: p.h, bytes: p.rgb.buffer, numChannels: 3);
  final small = fitInside(src, 360);
  final mask = smartMask(rgbBytes(small), small.width, small.height);
  if (mask == null) return null;
  final soft = upscaleMask(mask, small.width, small.height, p.w, p.h);
  final out = Uint8List(p.w * p.h);
  for (int i = 0; i < out.length; i++) {
    out[i] = soft[i] >= 128 ? 255 : 0;
  }
  return out;
}

Uint8List? _export(_Prep p) {
  final w = p.w, h = p.h;
  // Soften the edge a little.
  final soft = Uint8List(w * h);
  int visible = 0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int sum = 0, c = 0;
      for (int dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (int dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          sum += p.alpha[yy * w + xx];
          c++;
        }
      }
      final v = sum ~/ c;
      soft[y * w + x] = v;
      if (v >= 128) visible++;
    }
  }
  if (visible < w * h * 0.02) return null;
  var out = img.Image(width: w, height: h, numChannels: 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final i = y * w + x;
      out.setPixelRgba(x, y, p.rgb[i * 3], p.rgb[i * 3 + 1], p.rgb[i * 3 + 2], soft[i]);
    }
  }
  out = img.trim(out, mode: img.TrimMode.transparent);
  return img.encodePng(out);
}

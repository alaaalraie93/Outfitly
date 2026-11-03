import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../color_utils.dart';
import '../l10n.dart';

/// Common clothing colours to choose from quickly.
const List<int> kSwatches = [
  0xFF111111, 0xFF3A3A3A, 0xFF7D7D7D, 0xFFBDBDBD, 0xFFF5F5F2, 0xFFFFFFFF,
  0xFFEFE3CF, 0xFFD2BE9C, 0xFFB08D5E, 0xFF7A5230, 0xFF4E342E, 0xFF5B5A2E,
  0xFF4B5320, 0xFF6B7F3A, 0xFF2E6B3F, 0xFF1F7A7A, 0xFF9EC3E6, 0xFF3B5B8C,
  0xFF1F2A44, 0xFF2B4FA0, 0xFF6A4C93, 0xFFC8A2C8, 0xFFF4B6C2, 0xFFE0607E,
  0xFFC0392B, 0xFF7B1E2B, 0xFFE67E22, 0xFFF2C14E, 0xFFFFF2A8, 0xFFB5651D,
];

/// Opens the colour picker. Returns the chosen colour (ARGB) or null.
Future<int?> showColorPicker(BuildContext context, {required int initial, String? photoPath}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PickerSheet(initial: initial, photoPath: photoPath),
  );
}

class _PickerSheet extends StatefulWidget {
  final int initial;
  final String? photoPath;
  const _PickerSheet({required this.initial, this.photoPath});

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  late HSVColor hsv = HSVColor.fromColor(Color(widget.initial));
  _Pixels? pixels;

  @override
  void initState() {
    super.initState();
    final p = widget.photoPath;
    if (p != null) {
      File(p).readAsBytes().then((b) => compute(_decodeSmall, b)).then((v) {
        if (mounted) setState(() => pixels = v);
      }).catchError((_) {});
    }
  }

  void _pickAt(Offset local, Size box) {
    final px = pixels;
    if (px == null) return;
    final scale = math.min(box.width / px.w, box.height / px.h);
    final dx = (box.width - px.w * scale) / 2, dy = (box.height - px.h * scale) / 2;
    final cx = ((local.dx - dx) / scale).floor(), cy = ((local.dy - dy) / scale).floor();
    // Average a small area so fabric texture does not give odd colours.
    int r = 0, g = 0, b = 0, n = 0;
    for (int y = cy - 2; y <= cy + 2; y++) {
      for (int x = cx - 2; x <= cx + 2; x++) {
        if (x < 0 || y < 0 || x >= px.w || y >= px.h) continue;
        final i = (y * px.w + x) * 4;
        if (px.rgba[i + 3] < 128) continue;
        r += px.rgba[i];
        g += px.rgba[i + 1];
        b += px.rgba[i + 2];
        n++;
      }
    }
    if (n == 0) return;
    setState(() => hsv = HSVColor.fromColor(Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final color = hsv.toColor();
    final path = widget.photoPath;

    Widget slider(String label, double value, double max, ValueChanged<double> onChanged, List<Color> track) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              SizedBox(width: 72, child: Text(label, style: const TextStyle(fontSize: 13))),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 10,
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), gradient: LinearGradient(colors: track)),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                        thumbColor: Colors.white,
                        overlayColor: scheme.primary.withValues(alpha: 0.12),
                      ),
                      child: Slider(min: 0, max: max, value: value.clamp(0, max).toDouble(), onChanged: onChanged),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: scheme.outlineVariant, width: 2)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(context.tr(colorKey(color)), style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, color.toARGB32()),
                  child: Text(context.tr('choose')),
                ),
              ],
            ),
            if (path != null) ...[
              const SizedBox(height: 14),
              Text(context.tr('pick_from_photo'), style: text.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: scheme.surfaceContainerHighest,
                    child: LayoutBuilder(
                      builder: (context, c) => GestureDetector(
                        onTapDown: (e) => _pickAt(e.localPosition, c.biggest),
                        onPanUpdate: (e) => _pickAt(e.localPosition, c.biggest),
                        child: SizedBox.expand(child: Image.file(File(path), fit: BoxFit.contain)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(context.tr('pick_color'), style: text.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in kSwatches)
                  GestureDetector(
                    onTap: () => setState(() => hsv = HSVColor.fromColor(Color(s))),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(s),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.toARGB32() == s ? scheme.primary : scheme.outlineVariant,
                          width: color.toARGB32() == s ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            slider(context.tr('hue'), hsv.hue, 360, (v) => setState(() => hsv = hsv.withHue(v)), [
              for (int i = 0; i <= 6; i++) HSVColor.fromAHSV(1, i * 60.0 % 360, 1, 1).toColor(),
            ]),
            slider(context.tr('saturation'), hsv.saturation, 1, (v) => setState(() => hsv = hsv.withSaturation(v)), [
              hsv.withSaturation(0).toColor(),
              hsv.withSaturation(1).toColor(),
            ]),
            slider(context.tr('brightness'), hsv.value, 1, (v) => setState(() => hsv = hsv.withValue(v)), [
              Colors.black,
              hsv.withValue(1).toColor(),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Pixels {
  final int w;
  final int h;
  final Uint8List rgba;
  _Pixels(this.w, this.h, this.rgba);
}

_Pixels? _decodeSmall(Uint8List bytes) {
  final d = img.decodeImage(bytes);
  if (d == null) return null;
  var im = img.bakeOrientation(d);
  if (im.width > 400 || im.height > 400) {
    im = im.width >= im.height ? img.copyResize(im, width: 400) : img.copyResize(im, height: 400);
  }
  final out = Uint8List(im.width * im.height * 4);
  int i = 0;
  for (int y = 0; y < im.height; y++) {
    for (int x = 0; x < im.width; x++) {
      final p = im.getPixel(x, y);
      out[i++] = p.r.toInt();
      out[i++] = p.g.toInt();
      out[i++] = p.b.toInt();
      out[i++] = im.hasAlpha ? p.a.toInt() : 255;
    }
  }
  return _Pixels(im.width, im.height, out);
}

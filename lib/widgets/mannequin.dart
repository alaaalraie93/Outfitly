import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../color_utils.dart';
import '../l10n.dart';
import '../models.dart';
import 'sky.dart';

/// Loads and caches decoded images for painting.
class UiImageStore {
  static final Map<String, Future<ui.Image?>> _cache = {};

  static Future<ui.Image?> load(String? path, int width) {
    if (path == null || path.isEmpty) return Future.value(null);
    return _cache.putIfAbsent('$path@$width', () async {
      try {
        final f = File(path);
        if (!await f.exists()) return null;
        final bytes = await f.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
        final frame = await codec.getNextFrame();
        return frame.image;
      } catch (_) {
        return null;
      }
    });
  }

  static void evict(String? path) {
    if (path == null) return;
    _cache.removeWhere((k, _) => k.startsWith('$path@'));
  }
}

/// An interactive figure wearing a look. Drag sideways to turn it around.
/// Body proportions follow the profile's height, weight, age and body type.
class Mannequin extends StatefulWidget {
  final Profile profile;
  final Look look;
  final double height;

  const Mannequin({super.key, required this.profile, required this.look, this.height = 380});

  @override
  State<Mannequin> createState() => _MannequinState();
}

class _MannequinState extends State<Mannequin> with TickerProviderStateMixin {
  double angle = -0.35;
  bool photoTexture = false;
  ui.Image? face;
  final Map<String, ui.Image> textures = {};
  late final AnimationController _spin;
  late final AnimationController _idle;
  bool _touched = false;
  double _spinFrom = 0;
  double _spinTo = 0;
  String _loadedSig = '';

  String _sig() => '${widget.profile.facePath}|${widget.look.items.map((e) => '${e.id}:${e.imagePath}').join(',')}';

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..addListener(() {
        final t = Curves.easeInOutCubic.transform(_spin.value);
        setState(() => angle = _spinFrom + (_spinTo - _spinFrom) * t);
      });
    // A gentle idle sway and drifting clouds until the user turns the figure.
    _idle = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _loadImages();
  }

  double get _shownAngle => _touched ? angle : angle + math.sin(_idle.value * math.pi * 2) * 0.32;

  @override
  void didUpdateWidget(covariant Mannequin oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Profile and items are mutated in place, so compare against what was last loaded.
    if (_sig() != _loadedSig) {
      _loadImages();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _idle.dispose();
    super.dispose();
  }

  Future<void> _loadImages() async {
    final sig = _sig();
    _loadedSig = sig;
    final f = await UiImageStore.load(widget.profile.facePath, 320);
    final tex = <String, ui.Image>{};
    for (final it in widget.look.items) {
      final im = await UiImageStore.load(it.imagePath, 420);
      if (im != null) tex[it.id] = im;
    }
    if (!mounted || sig != _loadedSig) return;
    setState(() {
      face = f;
      textures
        ..clear()
        ..addAll(tex);
    });
  }

  void _spinAround() {
    if (!_touched) {
      angle = _shownAngle;
      _touched = true;
      _idle.stop();
    }
    _spinFrom = angle;
    _spinTo = angle + math.pi * 2;
    _spin.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          if (_spin.isAnimating) _spin.stop();
          if (!_touched) {
            angle = _shownAngle;
            _touched = true;
            _idle.stop();
          }
          final dir = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
          setState(() => angle += d.delta.dx * 0.013 * dir);
        },
        onDoubleTap: _spinAround,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _idle,
                builder: (context, _) {
                  final dark = Theme.of(context).brightness == Brightness.dark;
                  return CustomPaint(
                    painter: SkyPainter(dark: dark, drift: _idle.value),
                    foregroundPainter: MannequinPainter(
                      profile: widget.profile,
                      look: widget.look,
                      angle: _shownAngle,
                      photoTexture: photoTexture,
                      face: face,
                      textures: textures,
                      dark: dark,
                    ),
                  );
                },
              ),
            ),
            PositionedDirectional(
              start: 8,
              bottom: 8,
              child: IconButton.filledTonal(
                tooltip: photoTexture ? 'Color' : 'Photo',
                onPressed: () => setState(() => photoTexture = !photoTexture),
                icon: Icon(photoTexture ? Icons.palette_outlined : Icons.texture),
              ),
            ),
            PositionedDirectional(
              end: 12,
              bottom: 16,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.threesixty, size: 16, color: scheme.onSurfaceVariant),
                  if (widget.height >= 340) const SizedBox(width: 4),
                  if (widget.height >= 340) Text(context.tr('drag_rotate'), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MannequinPainter extends CustomPainter {
  final Profile profile;
  final Look look;
  final double angle;
  final bool photoTexture;
  final ui.Image? face;
  final Map<String, ui.Image> textures;
  final bool dark;

  MannequinPainter({
    required this.profile,
    required this.look,
    required this.angle,
    required this.photoTexture,
    required this.face,
    required this.textures,
    required this.dark,
  });

  // Geometry, set at the start of paint().
  late double _cx, _y0, _figH, _fx;

  double _x(double d) => _cx + d * _figH * _fx;
  double _y(double f) => _y0 + f * _figH;
  Offset _p(double dx, double fy) => Offset(_x(dx), _y(fy));
  double _w(double f) => f * _figH * (0.78 + 0.22 * _fx);

  @override
  void paint(Canvas canvas, Size size) {
    final kid = profile.bodyType == BodyType.kids || profile.age < 13;
    final female = profile.bodyType == BodyType.girl;
    final hCm = profile.heightCm.clamp(70.0, 215.0).toDouble();
    final wKg = profile.weightKg.clamp(12.0, 220.0).toDouble();
    final bmi = wKg / ((hCm / 100) * (hCm / 100));
    final wm = (bmi / 22).clamp(0.78, 1.55).toDouble();
    final bm = math.pow(wm, 0.85).toDouble();

    final heightScale = kid ? (hCm / 175).clamp(0.5, 0.95).toDouble() : (hCm / 192).clamp(0.78, 1.0).toDouble();
    _figH = size.height * 0.86 * heightScale;
    final footBase = size.height * 0.93;
    _y0 = footBase - _figH;
    _cx = size.width / 2;
    final c = math.cos(angle);
    final s = math.sin(angle);
    _fx = 0.42 + 0.58 * c.abs();
    final front = c >= 0;

    // ---- proportions (fractions of figure height) ----
    final headH = kid ? 0.165 : 0.125;
    final headW = headH * (kid ? 0.84 : 0.76);
    final neckHalf = headW * 0.25;
    final neckEnd = headH + 0.02;
    final shoulderY = headH + 0.04;
    final shoulderHalf = (kid ? 0.1 : (female ? 0.108 : 0.128)) * (0.9 + 0.1 * wm);
    final chestHalf = (kid ? 0.088 : (female ? 0.096 : 0.112)) * bm;
    final waistHalf = (kid ? 0.084 : (female ? 0.07 : 0.094)) * bm;
    final hipHalf = (kid ? 0.086 : (female ? 0.108 : 0.096)) * bm;
    final waistY = kid ? 0.46 : (female ? 0.385 : 0.40);
    final hipY = kid ? 0.55 : 0.495;
    final crotchY = kid ? 0.595 : 0.53;
    final kneeY = kid ? 0.78 : 0.735;
    const ankleY = 0.955;
    const footY = 1.0;
    final legCx = hipHalf * 0.5;
    final thigh = hipHalf * 0.5;
    final knee = 0.04 * math.pow(bm, 0.7).toDouble();
    const ankle = 0.026;

    final sh = shoulderHalf - 0.018;
    final armUpper = 0.033 * math.pow(bm, 0.65).toDouble();
    final armElbow = 0.027 * math.pow(bm, 0.6).toDouble();
    const armWrist = 0.02;

    Offset shoulderJ(int side) => Offset(side * sh, shoulderY + 0.018);
    Offset elbowJ(int side) => Offset(side * (sh + 0.024 + (wm - 1) * 0.03), waistY + 0.002);
    Offset wristJ(int side) => Offset(side * (sh + 0.04 + (wm - 1) * 0.045), crotchY - 0.012);
    Offset hipJ(int side) => Offset(side * legCx, crotchY - 0.04);
    Offset kneeJ(int side) => Offset(side * legCx * 0.86, kneeY);
    Offset ankleJ(int side) => Offset(side * legCx * 0.8, ankleY);

    final skin = profile.skin;
    final skinPaint = Paint()..color = skin;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black.withValues(alpha: 0.12);

    // floor shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx, footBase + 2), width: _figH * 0.34 * (0.6 + 0.4 * _fx), height: _figH * 0.035),
      Paint()..color = Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
    );

    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());

    // ---- hair behind (long hair) ----
    final hair = Paint()..color = const Color(0xFF3A2A21);
    if (female && !kid) {
      final r = Rect.fromLTRB(_x(-headW * 0.62), _y(0.01), _x(headW * 0.62), _y(shoulderY + 0.085));
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(_w(0.05))), hair);
    }

    // ---- body (skin) ----
    final body = Path();
    for (final side in const [-1, 1]) {
      body.addPath(_limb([hipJ(side), kneeJ(side), ankleJ(side)], [thigh, knee, ankle]), Offset.zero);
      body.addPath(_limb([shoulderJ(side), elbowJ(side), wristJ(side)], [armUpper, armElbow, armWrist]), Offset.zero);
      final w = wristJ(side);
      body.addOval(Rect.fromCenter(center: _p(w.dx, w.dy + 0.03), width: _w(0.045), height: _w(0.07)));
      body.addPath(_footPath(ankleJ(side).dx, ankleY, footY, 1.0), Offset.zero);
    }
    body.addPath(
      _smooth(_mirror([
        Offset(-neckHalf, neckEnd - 0.012),
        Offset(-neckHalf * 1.05, shoulderY - 0.004),
        Offset(-shoulderHalf, shoulderY + 0.014),
        Offset(-chestHalf, shoulderY + 0.09),
        Offset(-waistHalf, waistY),
        Offset(-hipHalf, hipY),
        Offset(-hipHalf * 0.9, crotchY),
      ], Offset(0, crotchY + 0.012))),
      Offset.zero,
    );
    body.addRect(Rect.fromLTRB(_x(-neckHalf), _y(headH * 0.8), _x(neckHalf), _y(shoulderY + 0.01)));
    canvas.drawPath(body, skinPaint);

    // ---- bottom / dress ----
    const e = 0.007;
    final dress = look.dress;
    final bottom = dress == null ? look.bottom : null;
    final top = dress == null ? look.top : null;

    if (dress != null) {
      final path = _smooth(_mirror([
        Offset(-neckHalf * 1.7, neckEnd + 0.004),
        Offset(-shoulderHalf * 0.82, shoulderY + 0.012),
        Offset(-chestHalf - e, shoulderY + 0.09),
        Offset(-waistHalf - e, waistY),
        Offset(-hipHalf - e, hipY),
        Offset(-hipHalf * 1.42, kneeY + 0.02),
        Offset(-hipHalf * 1.42, kneeY + 0.02),
      ], Offset(0, neckEnd + 0.05), bottomJoin: true));
      _fill(canvas, path, dress, false, outline);
    } else {
      final item = bottom;
      final sub = item?.subType ?? 'trousers';
      final placeholder = item == null;
      final waistTop = waistY + (female ? 0.02 : 0.012);
      if (sub == 'skirt') {
        final path = _smooth(_mirror([
          Offset(-waistHalf - e, waistTop),
          Offset(-hipHalf - e, hipY),
          Offset(-hipHalf * 1.32, kneeY - 0.025),
          Offset(-hipHalf * 1.32, kneeY - 0.025),
        ], Offset(0, waistTop), bottomJoin: true));
        _fill(canvas, path, item, placeholder, outline);
      } else {
        final path = Path();
        path.addPath(
          _smooth(_mirror([
            Offset(-waistHalf - e, waistTop),
            Offset(-hipHalf - e, hipY),
            Offset(-hipHalf * 0.95 - e, crotchY),
          ], Offset(0, crotchY + 0.012))),
          Offset.zero,
        );
        final extra = sub == 'sweatpants' ? 0.013 : (sub == 'jeans' ? 0.004 : 0.009);
        for (final side in const [-1, 1]) {
          if (sub == 'shorts') {
            final end = Offset.lerp(hipJ(side), kneeJ(side), 0.72)!;
            path.addPath(_limb([hipJ(side), end], [thigh + extra, (thigh + knee) / 2 + extra + 0.006], caps: false), Offset.zero);
          } else {
            final hem = Offset(ankleJ(side).dx, ankleY - 0.006);
            path.addPath(
              _limb([hipJ(side), kneeJ(side), hem], [thigh + extra, knee + extra, (sub == 'sweatpants' ? ankle + 0.004 : ankle + extra + 0.006)], caps: false),
              Offset.zero,
            );
          }
        }
        _fill(canvas, path, item, placeholder, outline);
      }
    }

    // ---- top ----
    if (dress == null) {
      final item = top;
      final sub = item?.subType ?? 'tshirt';
      final placeholder = item == null;
      final hemY = {
            'tshirt': hipY - 0.004,
            'blouse': hipY - 0.01,
            'shirt': hipY + 0.012,
            'sweater': hipY + 0.004,
            'hoodie': hipY + 0.022,
            'jacket': hipY + 0.04,
          }[sub] ??
          hipY;
      final vNeck = sub == 'shirt' || sub == 'blouse' || sub == 'jacket';
      final te = sub == 'jacket' ? 0.016 : (sub == 'hoodie' || sub == 'sweater' ? 0.012 : e);
      final hemHalf = hipHalf * 0.98 + te;
      final path = Path();
      path.addPath(
        _smooth(_mirror([
          Offset(-neckHalf * 1.3, neckEnd),
          Offset(-shoulderHalf - te, shoulderY + 0.01),
          Offset(-chestHalf - te, shoulderY + 0.09),
          Offset(-waistHalf - te, waistY),
          Offset(-hemHalf, hemY),
          Offset(-hemHalf, hemY),
        ], Offset(0, neckEnd + (vNeck ? 0.065 : 0.028)), bottomJoin: true)),
        Offset.zero,
      );
      final sleeveT = {'tshirt': 0.34, 'blouse': 0.72}[sub] ?? 0.96;
      for (final side in const [-1, 1]) {
        final pts = _alongArm(shoulderJ(side), elbowJ(side), wristJ(side), sleeveT);
        final widths = <double>[armUpper + te + 0.004];
        if (pts.length == 3) widths.add(armElbow + te + 0.002);
        widths.add((sleeveT < 0.5 ? armUpper : armWrist + 0.004) + te + 0.003);
        path.addPath(_limb(pts, widths, caps: false), Offset.zero);
        path.addOval(Rect.fromCircle(center: _p(shoulderJ(side).dx, shoulderJ(side).dy), radius: _w(armUpper + te + 0.004)));
      }
      _fill(canvas, path, item, placeholder, outline);

      if (item != null && front) {
        final detail = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = shade(item.color, -0.18).withValues(alpha: 0.7);
        if (sub == 'shirt' || sub == 'jacket') {
          canvas.drawLine(_p(0, neckEnd + 0.065), _p(0, hemY), detail);
        }
        if (sub == 'hoodie') {
          canvas.drawLine(_p(-0.012, neckEnd + 0.03), _p(-0.014, neckEnd + 0.1), detail);
          canvas.drawLine(_p(0.012, neckEnd + 0.03), _p(0.014, neckEnd + 0.1), detail);
          final pocket = Path()
            ..moveTo(_x(-waistHalf * 0.75), _y(hemY - 0.01))
            ..lineTo(_x(-waistHalf * 0.6), _y(waistY + 0.02))
            ..lineTo(_x(waistHalf * 0.6), _y(waistY + 0.02))
            ..lineTo(_x(waistHalf * 0.75), _y(hemY - 0.01));
          canvas.drawPath(pocket, detail);
        }
        if (sub == 'jacket') {
          final lapel = Paint()..color = shade(item.color, -0.12);
          for (final side in const [-1, 1]) {
            final l = Path()
              ..moveTo(_x(side * neckHalf * 1.3), _y(neckEnd))
              ..lineTo(_x(side * chestHalf * 0.55), _y(shoulderY + 0.06))
              ..lineTo(_x(0), _y(neckEnd + 0.12))
              ..close();
            canvas.drawPath(l, lapel);
          }
        }
      }
    }

    // ---- shoes ----
    final shoes = look.shoes;
    if (shoes != null) {
      for (final side in const [-1, 1]) {
        final ax = ankleJ(side).dx;
        switch (shoes.subType) {
          case 'boots':
            final shaft = _limb([Offset(ax, kneeY + 0.075), Offset(ax, ankleY)], [knee + 0.012, ankle + 0.012], caps: false);
            shaft.addPath(_footPath(ax, ankleY - 0.012, footY, 1.18), Offset.zero);
            _fill(canvas, shaft, shoes, false, outline);
            break;
          case 'sandals':
            final strap = Path()
              ..addRect(Rect.fromLTRB(_x(ax - 0.032), _y(ankleY + 0.008), _x(ax + 0.032), _y(ankleY + 0.016)))
              ..addRect(Rect.fromLTRB(_x(ax - 0.036), _y(ankleY + 0.026), _x(ax + 0.036), _y(ankleY + 0.034)))
              ..addRect(Rect.fromLTRB(_x(ax - 0.04), _y(footY - 0.006), _x(ax + 0.04), _y(footY + 0.002)));
            _fill(canvas, strap, shoes, false, outline);
            break;
          case 'heels':
            final heel = _footPath(ax, ankleY + 0.004, footY, 0.92);
            heel.addRect(Rect.fromLTRB(_x(ax - 0.008), _y(footY - 0.01), _x(ax + 0.008), _y(footY + 0.006)));
            _fill(canvas, heel, shoes, false, outline);
            break;
          default:
            final shoe = _footPath(ax, ankleY - 0.008, footY, 1.14);
            _fill(canvas, shoe, shoes, false, outline);
            if (shoes.subType == 'sneakers') {
              canvas.drawRect(
                Rect.fromLTRB(_x(ax - 0.041), _y(footY - 0.012), _x(ax + 0.041), _y(footY + 0.001)),
                Paint()..color = const Color(0xFFF4F2EE),
              );
            }
        }
      }
    }

    // ---- head ----
    final headRect = Rect.fromCenter(
      center: Offset(_cx, _y(headH / 2)),
      width: headW * _figH * (0.82 + 0.18 * _fx),
      height: headH * _figH,
    );
    canvas.drawOval(headRect, skinPaint);
    final faceImg = face;
    if (!front) {
      canvas.drawOval(headRect.inflate(1.5), hair);
    } else {
      if (faceImg != null && c > 0.25) {
        canvas.save();
        canvas.clipPath(Path()..addOval(headRect));
        final iw = faceImg.width.toDouble(), ih = faceImg.height.toDouble();
        final side = math.min(iw, ih) * 0.78;
        final src = Rect.fromCenter(center: Offset(iw / 2 - s * iw * 0.08, ih * 0.44), width: side * 0.82, height: side);
        final alpha = ((c - 0.25) / 0.45).clamp(0.0, 1.0).toDouble();
        canvas.drawImageRect(faceImg, src, headRect, Paint()..color = Colors.white.withValues(alpha: alpha)..filterQuality = FilterQuality.medium);
        canvas.restore();
      } else {
        final cap = Path()
          ..addArc(headRect.inflate(1.5), math.pi * 1.02, math.pi * 0.96)
          ..close();
        canvas.drawPath(cap, hair);
      }
    }

    // ---- accessory ----
    final acc = look.accessory;
    if (acc != null) {
      final ap = Paint()..color = acc.color;
      final dark2 = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = shade(acc.color, -0.25);
      final side = s >= 0 ? 1 : -1;
      switch (acc.subType) {
        case 'bag':
          final w = wristJ(side);
          final bag = RRect.fromRectAndRadius(
            Rect.fromLTRB(_x(w.dx - 0.035), _y(w.dy + 0.02), _x(w.dx + 0.075), _y(w.dy + 0.115)),
            Radius.circular(_w(0.014)),
          );
          canvas.drawLine(_p(w.dx, w.dy + 0.03), _p(w.dx - 0.02, w.dy + 0.02), dark2..strokeWidth = 2);
          canvas.drawLine(_p(w.dx, w.dy + 0.03), _p(w.dx + 0.06, w.dy + 0.02), dark2);
          canvas.drawRRect(bag, ap);
          canvas.drawRRect(bag, dark2..strokeWidth = 1.2);
          break;
        case 'watch':
          final w = wristJ(-side);
          final band = _limb([Offset(w.dx, w.dy - 0.012), Offset(w.dx, w.dy + 0.004)], [0.024, 0.024], caps: false);
          canvas.drawPath(band, ap);
          canvas.drawCircle(_p(w.dx, w.dy - 0.004), _w(0.011), Paint()..color = shade(acc.color, 0.3));
          canvas.drawCircle(_p(w.dx, w.dy - 0.004), _w(0.011), dark2);
          break;
        case 'belt':
          final by = waistY + (female ? 0.02 : 0.012);
          final belt = Rect.fromLTRB(_x(-waistHalf - 0.012), _y(by), _x(waistHalf + 0.012), _y(by + 0.018));
          canvas.drawRRect(RRect.fromRectAndRadius(belt, Radius.circular(_w(0.004))), ap);
          if (front) {
            canvas.drawRect(
              Rect.fromCenter(center: belt.center, width: _w(0.03), height: belt.height * 0.9),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = const Color(0xFFD9B44A),
            );
          }
          break;
        case 'scarf':
          final scarf = _smooth(_mirror([
            Offset(-neckHalf * 1.5, headH * 0.92),
            Offset(-neckHalf * 1.9, shoulderY + 0.012),
            Offset(-neckHalf * 0.6, shoulderY + 0.03),
          ], Offset(0, shoulderY + 0.035)));
          canvas.drawPath(scarf, ap);
          if (front) {
            final tail = Path()
              ..addRect(Rect.fromLTRB(_x(neckHalf * 0.2), _y(shoulderY + 0.02), _x(neckHalf * 1.3), _y(shoulderY + 0.13)));
            canvas.drawPath(tail, ap);
            canvas.drawPath(tail, dark2);
          }
          break;
        case 'necklace':
          if (front) {
            final chain = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..color = acc.color;
            final n = Path()
              ..moveTo(_x(-neckHalf * 1.1), _y(neckEnd))
              ..quadraticBezierTo(_x(0), _y(neckEnd + 0.09), _x(neckHalf * 1.1), _y(neckEnd));
            canvas.drawPath(n, chain);
            canvas.drawCircle(_p(0, neckEnd + 0.047), _w(0.009), ap);
          }
          break;
        case 'hat':
          final brim = Rect.fromCenter(center: Offset(headRect.center.dx, headRect.top + headRect.height * 0.3), width: headRect.width * 1.5, height: headRect.height * 0.16);
          final crown = Rect.fromLTRB(headRect.left + headRect.width * 0.12, headRect.top - headRect.height * 0.12, headRect.right - headRect.width * 0.12, brim.center.dy);
          canvas.drawRRect(RRect.fromRectAndCorners(crown, topLeft: Radius.circular(crown.width * 0.4), topRight: Radius.circular(crown.width * 0.4)), ap);
          canvas.drawOval(brim, ap);
          canvas.drawOval(brim, dark2);
          break;
        case 'glasses':
          if (front && c > 0.2) {
            final gy = headRect.top + headRect.height * 0.45;
            final r = headRect.width * 0.17;
            final frame = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2
              ..color = acc.color;
            final lens = Paint()..color = acc.color.withValues(alpha: 0.28);
            for (final k in const [-1, 1]) {
              final cc = Offset(headRect.center.dx + k * headRect.width * 0.22, gy);
              canvas.drawCircle(cc, r, lens);
              canvas.drawCircle(cc, r, frame);
            }
            canvas.drawLine(Offset(headRect.center.dx - headRect.width * 0.05, gy), Offset(headRect.center.dx + headRect.width * 0.05, gy), frame);
          }
          break;
      }
    }

    // ---- light & shade: turning the figure moves the light ----
    final left = _x(-0.3), right = _x(0.3);
    final shadeL = 0.06 + 0.2 * (1 + s) / 2;
    final shadeR = 0.06 + 0.2 * (1 - s) / 2;
    final light = Paint()
      ..blendMode = BlendMode.srcATop
      ..shader = ui.Gradient.linear(
        Offset(left, 0),
        Offset(right, 0),
        [
          Colors.black.withValues(alpha: shadeL),
          Colors.white.withValues(alpha: 0.07),
          Colors.black.withValues(alpha: shadeR),
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRect(bounds, light);
    canvas.restore();
  }

  // Mirror a left-side outline into a closed shape (left top→bottom, center, right bottom→top).
  List<Offset> _mirror(List<Offset> left, Offset center, {bool bottomJoin = false}) {
    final pts = <Offset>[...left];
    if (!bottomJoin) pts.add(center);
    pts.addAll(left.reversed.map((o) => Offset(-o.dx, o.dy)));
    if (bottomJoin) pts.add(center);
    return pts;
  }

  // Closed Catmull-Rom spline through model-space points.
  Path _smooth(List<Offset> model) {
    final pts = model.map((o) => _p(o.dx, o.dy)).toList();
    final n = pts.length;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < n; i++) {
      final p0 = pts[(i - 1 + n) % n];
      final p1 = pts[i];
      final p2 = pts[(i + 1) % n];
      final p3 = pts[(i + 2) % n];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  // A tapered limb through joints (model space), widths are half-widths.
  Path _limb(List<Offset> joints, List<double> widths, {bool caps = true}) {
    final path = Path();
    final pts = joints.map((o) => _p(o.dx, o.dy)).toList();
    final ws = widths.map(_w).toList();
    for (int i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final d = b - a;
      final len = d.distance;
      if (len == 0) continue;
      final nrm = Offset(-d.dy / len, d.dx / len);
      path.addPolygon([a + nrm * ws[i], b + nrm * ws[i + 1], b - nrm * ws[i + 1], a - nrm * ws[i]], true);
      if (caps || i + 1 < pts.length - 1) {
        path.addOval(Rect.fromCircle(center: b, radius: ws[i + 1]));
      }
      if (caps && i == 0) path.addOval(Rect.fromCircle(center: a, radius: ws[i]));
    }
    return path;
  }

  List<Offset> _alongArm(Offset s, Offset e, Offset w, double t) {
    if (t <= 0.5) return [s, Offset.lerp(s, e, t * 2)!];
    return [s, e, Offset.lerp(e, w, (t - 0.5) * 2)!];
  }

  Path _footPath(double ax, double topY, double bottomY, double scale) {
    final hw = 0.028 * scale;
    final bw = 0.037 * scale;
    return _smooth([
      Offset(ax - hw, topY),
      Offset(ax - bw, bottomY - 0.006),
      Offset(ax - bw * 0.9, bottomY),
      Offset(ax + bw * 0.9, bottomY),
      Offset(ax + bw, bottomY - 0.006),
      Offset(ax + hw, topY),
    ]);
  }

  void _fill(Canvas canvas, Path path, ClothingItem? item, bool placeholder, Paint outline) {
    final paint = Paint()..isAntiAlias = true;
    final b = path.getBounds();
    final tex = item == null ? null : textures[item.id];
    if (item != null && photoTexture && tex != null) {
      canvas.drawPath(path, Paint()..color = item.color);
      final iw = tex.width.toDouble(), ih = tex.height.toDouble();
      final scale = math.max(b.width / (iw * 0.62), b.height / (ih * 0.62));
      final tx = b.center.dx - scale * iw / 2;
      final ty = b.center.dy - scale * ih / 2;
      final m = Float64List.fromList([scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1]);
      paint.shader = ImageShader(tex, TileMode.clamp, TileMode.clamp, m);
    } else if (item != null) {
      paint.color = item.color;
    } else {
      paint.color = (dark ? const Color(0xFF8E8A84) : const Color(0xFFDCD8D1)).withValues(alpha: placeholder ? 0.9 : 1);
    }
    canvas.drawPath(path, paint);
    if (item != null && item.patterned && !photoTexture) {
      canvas.save();
      canvas.clipPath(path);
      final stripe = Paint()
        ..color = shade(item.color, HSLColor.fromColor(item.color).lightness > 0.5 ? -0.25 : 0.25).withValues(alpha: 0.55)
        ..strokeWidth = 2;
      for (double x = b.left - b.height; x < b.right; x += 9) {
        canvas.drawLine(Offset(x, b.bottom), Offset(x + b.height, b.top), stripe);
      }
      canvas.restore();
    }
    canvas.drawPath(path, outline);
  }

  @override
  bool shouldRepaint(covariant MannequinPainter old) => true;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Brand colors: a sky palette with a warm coral accent.
class Sky {
  static const blue = Color(0xFF1FA2E8);
  static const deep = Color(0xFF0A6FB8);
  static const light = Color(0xFFBDE7FF);
  static const mist = Color(0xFFEAF7FF);
  static const coral = Color(0xFFFF8A65);
  static const sun = Color(0xFFFFC857);
  static const night = Color(0xFF0B1B33);
  static const nightLow = Color(0xFF13305A);

  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5BC8FF), blue, deep],
  );
}

/// A soft sky: gradient, drifting clouds and a few sparkles (stars at night).
/// [drift] 0..1 moves the clouds slowly when animated.
class SkyPainter extends CustomPainter {
  final bool dark;
  final double drift;
  final double radius;
  SkyPainter({required this.dark, this.drift = 0, this.radius = 28});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? const [Sky.night, Sky.nightLow] : const [Color(0xFF9BDBFF), Sky.mist],
        ).createShader(rect),
    );

    // Sun / moon glow.
    final glowC = Offset(size.width * 0.82, size.height * 0.16);
    canvas.drawCircle(
      glowC,
      size.shortestSide * 0.32,
      Paint()
        ..shader = RadialGradient(
          colors: [(dark ? Colors.white : Sky.sun).withValues(alpha: dark ? 0.16 : 0.45), Colors.transparent],
        ).createShader(Rect.fromCircle(center: glowC, radius: size.shortestSide * 0.32)),
    );

    if (dark) {
      final rnd = math.Random(7);
      final star = Paint()..color = Colors.white.withValues(alpha: 0.7);
      for (int i = 0; i < 26; i++) {
        final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height * 0.6);
        canvas.drawCircle(p, rnd.nextDouble() * 1.4 + 0.4, star);
      }
    }

    // Clouds.
    final cloud = Paint()..color = Colors.white.withValues(alpha: dark ? 0.06 : 0.75);
    void puff(double cx, double cy, double s) {
      final x = (cx + drift * 0.12) % 1.25 - 0.12;
      final c = Offset(x * size.width, cy * size.height);
      final r = size.shortestSide * s;
      canvas.drawCircle(c, r, cloud);
      canvas.drawCircle(c + Offset(r * 0.9, r * 0.2), r * 0.75, cloud);
      canvas.drawCircle(c + Offset(-r * 0.9, r * 0.25), r * 0.7, cloud);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(c.dx - r * 1.5, c.dy, c.dx + r * 1.6, c.dy + r * 0.85), Radius.circular(r)),
        cloud,
      );
    }

    puff(0.18, 0.14, 0.07);
    puff(0.62, 0.30, 0.05);
    puff(0.95, 0.52, 0.06);
    puff(0.35, 0.62, 0.04);

    // Sparkles.
    final spark = Paint()..color = (dark ? Sky.sun : Colors.white).withValues(alpha: 0.9);
    for (final s in const [Offset(0.12, 0.42), Offset(0.88, 0.72), Offset(0.7, 0.08)]) {
      _sparkle(canvas, Offset(s.dx * size.width, s.dy * size.height), size.shortestSide * 0.025, spark);
    }
    canvas.restore();
  }

  void _sparkle(Canvas canvas, Offset c, double k, Paint p) {
    final path = Path()
      ..moveTo(c.dx, c.dy - k)
      ..lineTo(c.dx + k * 0.25, c.dy - k * 0.25)
      ..lineTo(c.dx + k, c.dy)
      ..lineTo(c.dx + k * 0.25, c.dy + k * 0.25)
      ..lineTo(c.dx, c.dy + k)
      ..lineTo(c.dx - k * 0.25, c.dy + k * 0.25)
      ..lineTo(c.dx - k, c.dy)
      ..lineTo(c.dx - k * 0.25, c.dy - k * 0.25)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant SkyPainter old) => old.dark != dark || old.drift != drift || old.radius != radius;
}

/// Full-screen sky behind a page.
class SkyBackground extends StatelessWidget {
  final Widget child;
  const SkyBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: SkyPainter(dark: dark, radius: 0))),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// Text painted with the brand gradient.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const GradientText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => const LinearGradient(colors: [Sky.blue, Color(0xFF7C6CF2), Sky.coral]).createShader(r),
      child: Text(text, style: style),
    );
  }
}

/// Page title used in app bars.
class BrandTitle extends StatelessWidget {
  final String text;
  const BrandTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return GradientText(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.3));
  }
}

/// The app logo: a hanger with a sparkle on the brand gradient.
class OutfitlyLogo extends StatelessWidget {
  final double size;
  const OutfitlyLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: Sky.brand,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [BoxShadow(color: Sky.blue.withValues(alpha: 0.35), blurRadius: size * 0.35, offset: Offset(0, size * 0.12))],
      ),
      child: Stack(
        children: [
          Center(child: Icon(Icons.checkroom_rounded, color: Colors.white, size: size * 0.56)),
          Positioned(
            right: size * 0.12,
            top: size * 0.1,
            child: Icon(Icons.auto_awesome, color: Sky.sun, size: size * 0.26),
          ),
        ],
      ),
    );
  }
}

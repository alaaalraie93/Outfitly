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

/// A calm, static sky-blue page background.
class SkyBackground extends StatelessWidget {
  final Widget child;
  const SkyBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? const [Sky.nightLow, Sky.night] : const [Color(0xFFD6F0FF), Color(0xFFF7FBFF)],
        ),
      ),
      child: child,
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

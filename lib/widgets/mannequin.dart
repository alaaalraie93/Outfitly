import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n.dart';
import '../models.dart';

/// Loads and caches decoded images (used for previews elsewhere).
class UiImageStore {
  static final Map<String, Future<ui.Image?>> _cache = {};

  static Future<ui.Image?> load(String? path, int width) {
    if (path == null || path.isEmpty) return Future.value(null);
    return _cache.putIfAbsent('$path@$width', () async {
      try {
        final f = File(path);
        if (!await f.exists()) return null;
        final codec = await ui.instantiateImageCodec(await f.readAsBytes(), targetWidth: width);
        return (await codec.getNextFrame()).image;
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

/// Every garment shape inside the 3D models (see tool/make_mannequin.py).
const List<String> kModelParts = [
  'skin',
  'hair',
  'top_short',
  'top_long',
  'top_jacket',
  'pants_long',
  'pants_short',
  'skirt',
  'dress',
  'shoes_low',
  'shoes_boot',
];

String? partFor(ClothingItem it) {
  switch (it.subType) {
    case 'tshirt':
    case 'blouse':
      return 'top_short';
    case 'shirt':
    case 'sweater':
    case 'hoodie':
      return 'top_long';
    case 'jacket':
      return 'top_jacket';
    case 'jeans':
    case 'trousers':
    case 'sweatpants':
      return 'pants_long';
    case 'shorts':
      return 'pants_short';
    case 'skirt':
      return 'skirt';
    case 'dress':
      return 'dress';
    case 'boots':
      return 'shoes_boot';
    case 'sneakers':
    case 'formal_shoes':
    case 'sandals':
    case 'heels':
      return 'shoes_low';
  }
  return null;
}

String _hex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0')}';
}

/// A real 3D figure (rotate with one finger) wearing the look.
/// Body type picks the model; height and weight scale it.
class Mannequin extends StatefulWidget {
  final Profile profile;
  final Look look;
  final double height;

  const Mannequin({super.key, required this.profile, required this.look, this.height = 400});

  @override
  State<Mannequin> createState() => _MannequinState();
}

class _MannequinState extends State<Mannequin> {
  WebViewController? _controller;
  bool _ready = false;
  String? _lastSent;

  bool get _kid => widget.profile.bodyType == BodyType.kids || widget.profile.age < 13;

  String get _model {
    if (_kid) return 'assets/models/kid.glb';
    return widget.profile.bodyType == BodyType.boy ? 'assets/models/male.glb' : 'assets/models/female.glb';
  }

  double get _baseHeight {
    if (_kid) return 1.30;
    return widget.profile.bodyType == BodyType.boy ? 1.80 : 1.70;
  }

  String _state() {
    final p = widget.profile;
    final parts = <String, String?>{for (final n in kModelParts) n: null};
    parts['skin'] = _hex(p.skin);
    parts['hair'] = '#3a2a21';
    final look = widget.look;
    for (final it in look.clothes) {
      final part = partFor(it);
      if (part != null) parts[part] = _hex(it.color);
    }
    // Neutral basics so the figure is never bare.
    final hasTop = look.dress != null || look.top != null;
    final hasBottom = look.dress != null || look.bottom != null;
    if (!hasTop) parts['top_short'] = '#e4e1dc';
    if (!hasBottom) parts['pants_short'] = '#cfcbc4';

    final h = p.heightCm.clamp(70.0, 215.0).toDouble() / 100;
    final w = p.weightKg.clamp(12.0, 220.0).toDouble();
    final bmi = w / (h * h);
    final sy = (h / _baseHeight).clamp(0.6, 1.3).toDouble();
    final sx = sy * math.sqrt((bmi / (_kid ? 17.0 : 22.0)).clamp(0.75, 1.6).toDouble());
    return jsonEncode({
      'parts': parts,
      'scale': [sx, sy, sx],
    });
  }

  Future<void> _send({bool force = false}) async {
    final c = _controller;
    if (c == null || !_ready) return;
    final s = _state();
    if (!force && s == _lastSent) return;
    _lastSent = s;
    try {
      await c.runJavaScript('window.outfitlyApply && window.outfitlyApply($s);');
    } catch (_) {
      _lastSent = null;
    }
  }

  @override
  void didUpdateWidget(covariant Mannequin oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  static const String _js = '''
(function () {
  var mv = document.getElementById('mv');
  var pending = null;
  var loaded = false;
  function apply(s) {
    if (!loaded || !mv.model) { pending = s; return; }
    var names = Object.keys(s.parts);
    for (var i = 0; i < names.length; i++) {
      var m = mv.model.getMaterialByName(names[i]);
      if (!m) continue;
      var c = s.parts[names[i]];
      if (c) {
        m.setAlphaMode('OPAQUE');
        m.pbrMetallicRoughness.setBaseColorFactor([1, 1, 1, 1]);
        m.pbrMetallicRoughness.setBaseColorFactor(c);
      } else {
        m.setAlphaMode('MASK');
        m.setAlphaCutoff(0.5);
        m.pbrMetallicRoughness.setBaseColorFactor([1, 1, 1, 0]);
      }
    }
    if (s.scale) mv.scale = s.scale.join(' ');
  }
  window.outfitlyApply = apply;
  mv.addEventListener('load', function () {
    loaded = true;
    if (pending) apply(pending);
    if (window.Outfitly) window.Outfitly.postMessage('ready');
  });
})();
''';

  void _onReady() {
    _ready = true;
    _send(force: true);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final model = _model;
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 0.9,
                    colors: dark ? const [Color(0xFF1D3A5C), Color(0xFF0E1A2B)] : const [Color(0xFFFFFFFF), Color(0xFFDDF1FF)],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: _ModelHost(
                key: ValueKey(model),
                model: model,
                js: _js,
                onReady: _onReady,
                onController: (c) {
                  _controller = c;
                  _ready = false;
                  _lastSent = null;
                },
              ),
            ),
            if (!_ready)
              const Positioned.fill(
                child: IgnorePointer(child: Center(child: CircularProgressIndicator())),
              ),
            PositionedDirectional(
              end: 12,
              bottom: 12,
              child: IgnorePointer(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.threesixty, size: 16, color: scheme.onSurfaceVariant),
                    if (widget.height >= 340) const SizedBox(width: 4),
                    if (widget.height >= 340)
                      Text(context.tr('drag_rotate'), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Holds the web view so it is created once per model and never rebuilt
/// when only the look changes (changes are pushed through JavaScript).
class _ModelHost extends StatefulWidget {
  final String model;
  final String js;
  final VoidCallback onReady;
  final ValueChanged<WebViewController> onController;

  const _ModelHost({super.key, required this.model, required this.js, required this.onReady, required this.onController});

  @override
  State<_ModelHost> createState() => _ModelHostState();
}

class _ModelHostState extends State<_ModelHost> {
  late final Widget _viewer = ModelViewer(
    id: 'mv',
    src: widget.model,
    alt: 'Outfitly',
    backgroundColor: Colors.transparent,
    cameraControls: true,
    disableZoom: true,
    disablePan: true,
    touchAction: TouchAction.panY,
    interactionPrompt: InteractionPrompt.none,
    cameraOrbit: '15deg 82deg auto',
    shadowIntensity: 1,
    shadowSoftness: 0.8,
    exposure: 1.05,
    debugLogging: false,
    relatedJs: widget.js,
    javascriptChannels: {
      JavascriptChannel('Outfitly', onMessageReceived: (_) => widget.onReady()),
    },
    onWebViewCreated: widget.onController,
  );

  @override
  Widget build(BuildContext context) => _viewer;
}

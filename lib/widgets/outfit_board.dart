import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';

/// How the pieces are arranged on the board.
enum BoardLayout { stack, collage }

/// The outfit shown as a styled board of the real photos (like a fashion
/// flat-lay): top, bottom and shoes from head to toe, accessory on the side.
class OutfitBoard extends StatefulWidget {
  final Look look;
  final double height;
  const OutfitBoard({super.key, required this.look, this.height = 420});

  @override
  State<OutfitBoard> createState() => _OutfitBoardState();
}

class _OutfitBoardState extends State<OutfitBoard> {
  static BoardLayout _layout = BoardLayout.stack; // remembered while the app runs

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final look = widget.look;
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark ? const [Color(0xFF1B2D45), Color(0xFF0F1B2C)] : const [Color(0xFFFFFFFF), Color(0xFFE6F4FF)],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  child: LayoutBuilder(
                    key: ValueKey('${_layout.name}|${look.key}'),
                    builder: (context, c) => _layout == BoardLayout.stack
                        ? _stack(context, look, c.biggest)
                        : _collage(context, look, c.biggest),
                  ),
                ),
              ),
              PositionedDirectional(
                start: 10,
                bottom: 10,
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _layoutButton(BoardLayout.stack, Icons.view_agenda_outlined, scheme),
                      _layoutButton(BoardLayout.collage, Icons.dashboard_outlined, scheme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _layoutButton(BoardLayout l, IconData icon, ColorScheme scheme) {
    final on = _layout == l;
    return IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: () => setState(() => _layout = l),
      icon: Icon(icon, size: 20, color: on ? scheme.primary : scheme.onSurfaceVariant),
    );
  }

  /// Head-to-toe: pieces overlap a little, like a styled flat-lay.
  Widget _stack(BuildContext context, Look look, Size size) {
    final w = size.width, h = size.height;
    final children = <Widget>[];
    final pad = 14.0;
    final mainW = w * 0.62;
    final cx = (w - mainW) / 2;

    if (look.dress != null) {
      children.add(Positioned(left: cx - w * 0.04, width: mainW + w * 0.08, top: pad, height: h * 0.74, child: _Piece(item: look.dress!)));
    } else {
      children.add(Positioned(
        left: cx,
        width: mainW,
        top: pad,
        height: h * 0.40,
        child: look.top != null ? _Piece(item: look.top!) : _EmptySlot(label: catLabel(context, ClothCat.top), icon: Icons.checkroom),
      ));
      children.add(Positioned(
        left: cx + mainW * 0.08,
        width: mainW * 0.84,
        top: h * 0.36,
        height: h * 0.44,
        child: look.bottom != null ? _Piece(item: look.bottom!) : _EmptySlot(label: catLabel(context, ClothCat.bottom), icon: Icons.straighten),
      ));
    }
    children.add(Positioned(
      left: cx + mainW * 0.18,
      width: mainW * 0.64,
      top: h * 0.78,
      height: h * 0.2,
      child: look.shoes != null ? _Piece(item: look.shoes!) : _EmptySlot(label: catLabel(context, ClothCat.shoes), icon: Icons.ice_skating_outlined),
    ));
    if (look.accessory != null) {
      children.add(PositionedDirectional(end: pad, top: h * 0.42, width: w * 0.2, height: w * 0.2, child: _Piece(item: look.accessory!)));
    }
    // Bottom first so the top overlaps the waistband.
    if (look.dress == null && children.length >= 2) {
      final topPiece = children.removeAt(0);
      children.insert(1, topPiece);
    }
    return Stack(children: children);
  }

  /// Magazine collage: big main piece on one side, the rest in a column.
  Widget _collage(BuildContext context, Look look, Size size) {
    final pieces = look.items;
    if (pieces.isEmpty) {
      return Center(child: _EmptySlot(label: catLabel(context, ClothCat.top), icon: Icons.checkroom));
    }
    final main = pieces.first;
    final rest = pieces.skip(1).toList();
    const gap = 10.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 56),
      child: Row(
        children: [
          Expanded(flex: 6, child: _Tile(child: _Piece(item: main))),
          if (rest.isNotEmpty) const SizedBox(width: gap),
          if (rest.isNotEmpty)
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  for (int i = 0; i < rest.length; i++) ...[
                    if (i > 0) const SizedBox(height: gap),
                    Expanded(child: _Tile(child: _Piece(item: rest[i]))),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String catLabel(BuildContext context, ClothCat c) => context.tr('cat_${c.name}');

class _Tile extends StatelessWidget {
  final Widget child;
  const _Tile({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(8),
      child: child,
    );
  }
}

/// One piece: cut-outs float with a soft shadow, other photos sit in a rounded frame.
class _Piece extends StatelessWidget {
  final ClothingItem item;
  const _Piece({required this.item});

  @override
  Widget build(BuildContext context) {
    final file = File(item.imagePath);
    final cut = item.imagePath.toLowerCase().endsWith('.png');
    Widget broken(BuildContext _, Object __, StackTrace? ___) =>
        Center(child: Icon(Icons.checkroom, size: 40, color: item.color));
    if (!cut) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.file(file, fit: BoxFit.cover, width: double.infinity, height: double.infinity, cacheWidth: 700, errorBuilder: broken),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // soft drop shadow that follows the piece's outline
        Transform.translate(
          offset: const Offset(4, 8),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.28), BlendMode.srcIn),
              child: Image.file(file, fit: BoxFit.contain, cacheWidth: 700, errorBuilder: broken),
            ),
          ),
        ),
        Image.file(file, fit: BoxFit.contain, cacheWidth: 700, errorBuilder: broken),
      ],
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final String label;
  final IconData icon;
  const _EmptySlot({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant, width: 1.5),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }
}

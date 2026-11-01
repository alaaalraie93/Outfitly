import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../color_utils.dart';
import '../l10n.dart';
import '../matching.dart';
import '../models.dart';
import '../state.dart';
import 'mannequin.dart';

Color scoreColor(int score) {
  if (score >= 80) return const Color(0xFF2E9E6A);
  if (score >= 60) return const Color(0xFFD99A2B);
  return const Color(0xFFD5524B);
}

String itemTitle(BuildContext context, ClothingItem it) {
  if (it.name.trim().isNotEmpty) return it.name.trim();
  return '${context.tr('sub_${it.subType}')} · ${context.tr(colorKey(it.color))}';
}

String catTitle(BuildContext context, ClothCat c) => context.tr('cat_${c.name}');

class ScoreRing extends StatelessWidget {
  final int score;
  final double size;
  const ScoreRing({super.key, required this.score, this.size = 72});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v / 100, scoreColor(score), scheme.surfaceContainerHighest, scheme.surface),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${v.round()}%', style: TextStyle(fontSize: size * 0.24, fontWeight: FontWeight.w800, color: scheme.onSurface)),
                Text(context.tr('match'), style: TextStyle(fontSize: size * 0.12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double t;
  final Color color, track, fill;
  _RingPainter(this.t, this.color, this.track, this.fill);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, r, Paint()..color = fill.withValues(alpha: 0.92));
    final stroke = r * 0.16;
    final rect = Rect.fromCircle(center: c, radius: r - stroke / 2 - 2);
    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * t.clamp(0.0, 1.0), false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = color);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.t != t || old.color != color;
}

class ItemImage extends StatelessWidget {
  final ClothingItem item;
  final double radius;
  const ItemImage({super.key, required this.item, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        color: item.color.withValues(alpha: 0.18),
        child: Image.file(
          File(item.imagePath),
          fit: BoxFit.cover,
          cacheWidth: 400,
          errorBuilder: (_, __, ___) => Center(child: Icon(Icons.checkroom, color: item.color)),
        ),
      ),
    );
  }
}

class ColorDot extends StatelessWidget {
  final Color color;
  final double size;
  const ColorDot(this.color, {super.key, this.size = 14});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      );
}

class ReasonsWrap extends StatelessWidget {
  final List<Reason> reasons;
  final int max;
  const ReasonsWrap(this.reasons, {super.key, this.max = 4});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final r in reasons.take(max))
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(r.good ? Icons.check_circle : Icons.error_outline, size: 18, color: r.good ? const Color(0xFF2E9E6A) : const Color(0xFFD5524B)),
            label: Text(context.tr(r.key), style: const TextStyle(fontSize: 12.5)),
          ),
      ],
    );
  }
}

/// Mannequin + score + reasons + actions for one look. Reused on every screen.
class OutfitStage extends StatelessWidget {
  final Look look;
  final double height;
  final bool actions;
  final Widget? extra;
  const OutfitStage({super.key, required this.look, this.height = 380, this.actions = true, this.extra});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final result = s.lookScore(look);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            Mannequin(profile: s.profile, look: look, height: height),
            if (result != null) PositionedDirectional(top: 12, end: 12, child: ScoreRing(score: result.score)),
            PositionedDirectional(
              top: 12,
              start: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final it in look.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SizedBox(width: 44, height: 44, child: ItemImage(item: it, radius: 12)),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (result != null) ...[
          const SizedBox(height: 10),
          ReasonsWrap(result.reasons),
        ],
        if (extra != null) ...[const SizedBox(height: 8), extra!],
        if (actions && look.items.length >= 2) ...[
          const SizedBox(height: 8),
          LookActions(look: look),
        ],
      ],
    );
  }
}

class LookActions extends StatelessWidget {
  final Look look;
  const LookActions({super.key, required this.look});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final saved = s.isSaved(look);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () {
            s.rate(look, true);
            showSnack(context, context.tr('thanks_feedback'));
          },
          icon: const Icon(Icons.thumb_up_alt_outlined),
          label: Text(context.tr('like')),
        ),
        OutlinedButton.icon(
          onPressed: () {
            s.rate(look, false);
            showSnack(context, context.tr('thanks_feedback'));
          },
          icon: const Icon(Icons.thumb_down_alt_outlined),
          label: Text(context.tr('dislike')),
        ),
        FilledButton.tonalIcon(
          onPressed: saved ? null : () => saveLookDialog(context, look),
          icon: Icon(saved ? Icons.bookmark : Icons.bookmark_add_outlined),
          label: Text(saved ? context.tr('saved') : context.tr('save_outfit')),
        ),
      ],
    );
  }
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

Future<void> saveLookDialog(BuildContext context, Look look) async {
  final s = AppScope.read(context);
  final ctrl = TextEditingController(text: '${translate(s.profile.lang, 'outfit_n')} ${s.outfits.length + 1}');
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('save_outfit')),
      content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: ctx.tr('outfit_name'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(ctx.tr('save'))),
      ],
    ),
  );
  if (name == null) return;
  s.saveOutfit(look, name.isEmpty ? translate(s.profile.lang, 'outfit_n') : name);
  if (context.mounted) showSnack(context, translate(s.profile.lang, 'saved'));
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 44, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Horizontal strip of pieces with their match percentage.
class MatchStrip extends StatelessWidget {
  final List<ScoredItem> matches;
  final String? selectedId;
  final ValueChanged<ClothingItem> onTap;
  const MatchStrip({super.key, required this.matches, required this.selectedId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(context.tr('no_items_in'), style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: matches.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final m = matches[i];
          final sel = m.item.id == selectedId;
          return GestureDetector(
            onTap: () => onTap(m.item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 108,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: sel ? scheme.primary : Colors.transparent, width: 2.5),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(child: ItemImage(item: m.item, radius: 14)),
                        PositionedDirectional(
                          top: 6,
                          end: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: scoreColor(m.result.score), borderRadius: BorderRadius.circular(10)),
                            child: Text('${m.result.score}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(itemTitle(context, m.item), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

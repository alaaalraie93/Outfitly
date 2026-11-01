import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';

/// Manual outfit builder with a live match percentage.
class MixScreen extends StatefulWidget {
  const MixScreen({super.key});

  @override
  State<MixScreen> createState() => _MixScreenState();
}

class _MixScreenState extends State<MixScreen> {
  Look look = const Look();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // Drop pieces that were deleted meanwhile.
    final valid = Look.fromItems(look.items.where((e) => s.itemById(e.id) != null));
    final cats = categoriesFor(s.profile.bodyType);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('tab_mix'), style: const TextStyle(fontWeight: FontWeight.w800))),
      body: s.items.isEmpty
          ? EmptyState(icon: Icons.auto_awesome, text: context.tr('empty_wardrobe'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                Text(context.tr('mix_hint'), style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                OutfitStage(look: valid, height: 380, extra: valid.items.length >= 2 ? _WearButton(look: valid) : null),
                for (final c in cats) ...[
                  const SizedBox(height: 16),
                  Text(catTitle(context, c), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 96,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _Pick(
                          selected: valid.slot(c) == null,
                          onTap: () => setState(() => look = valid.without(c)),
                          child: Center(child: Text(context.tr('none'), style: TextStyle(color: scheme.onSurfaceVariant))),
                        ),
                        for (final it in s.itemsIn(c))
                          _Pick(
                            selected: valid.slot(c)?.id == it.id,
                            onTap: () => setState(() => look = valid.withItem(it)),
                            child: ItemImage(item: it, radius: 14),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _Pick extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  const _Pick({required this.selected, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 84,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2.5),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _WearButton extends StatelessWidget {
  final Look look;
  const _WearButton({required this.look});

  @override
  Widget build(BuildContext context) {
    return Align(
      child: TextButton.icon(
        onPressed: () {
          AppScope.read(context).wear(look);
          showSnack(context, context.tr('worn_saved'));
        },
        icon: const Icon(Icons.event_available),
        label: Text(context.tr('wear_this')),
      ),
    );
  }
}

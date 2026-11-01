import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import '../widgets/sky.dart';
import 'calendar.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: BrandTitle(context.tr('tab_saved')),
          bottom: TabBar(tabs: [
            Tab(text: context.tr('saved_outfits')),
            Tab(text: context.tr('calendar')),
          ]),
        ),
        body: TabBarView(
          children: [
            s.outfits.isEmpty
                ? EmptyState(icon: Icons.bookmark_border, text: context.tr('no_saved'))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: s.outfits.length,
                    itemBuilder: (context, i) {
                      final o = s.outfits[i];
                      return _LookCard(
                        title: o.name,
                        look: s.lookOf(o),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OutfitViewScreen(outfitId: o.id))),
                      );
                    },
                  ),
            const CalendarView(),
          ],
        ),
      ),
    );
  }
}

class _LookCard extends StatelessWidget {
  final String title;
  final Look look;
  final VoidCallback onTap;
  const _LookCard({required this.title, required this.look, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final score = s.lookScore(look)?.score;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (final it in look.items)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SizedBox(width: double.infinity, child: ItemImage(item: it, radius: 12)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                if (score != null)
                  Text('$score%', style: TextStyle(color: scoreColor(score), fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class OutfitViewScreen extends StatelessWidget {
  final String outfitId;
  const OutfitViewScreen({super.key, required this.outfitId});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    Outfit? o;
    for (final x in s.outfits) {
      if (x.id == outfitId) o = x;
    }
    final outfit = o;
    if (outfit == null) return const Scaffold();
    final look = s.lookOf(outfit);
    return Scaffold(
      appBar: AppBar(
        title: Text(outfit.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              Navigator.pop(context);
              s.deleteOutfit(outfit);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutfitStage(look: look, height: 440),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () {
              s.wear(look);
              showSnack(context, context.tr('worn_saved'));
            },
            icon: const Icon(Icons.event_available),
            label: Text(context.tr('wear_this')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () async {
              final now = DateTime.now();
              final day = await showDatePicker(
                context: context,
                initialDate: now.add(const Duration(days: 1)),
                firstDate: now,
                lastDate: now.add(const Duration(days: 365)),
              );
              if (day == null) return;
              s.setPlan(day, look);
              if (context.mounted) showSnack(context, context.tr('planned_ok'));
            },
            icon: const Icon(Icons.event_note),
            label: Text(context.tr('plan_for_day')),
          ),
        ],
      ),
    );
  }
}

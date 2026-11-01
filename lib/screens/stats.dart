import 'package:flutter/material.dart';

import '../color_utils.dart';
import '../l10n.dart';
import '../models.dart';
import '../planner.dart';
import '../state.dart';
import '../widgets/common.dart';
import '../widgets/sky.dart';
import 'add_item.dart';
import 'item_detail.dart';

/// Wardrobe insights: what you wear, what you don't, colours, cost per wear,
/// and the one piece that would unlock the most new outfits.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  String _money(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (s.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: BrandTitle(context.tr('stats_title'))),
        body: EmptyState(icon: Icons.insights, text: context.tr('empty_wardrobe')),
      );
    }

    final counts = {for (final it in s.items) it.id: s.wearCount(it.id)};
    final mostWorn = [...s.items]..sort((a, b) => counts[b.id]!.compareTo(counts[a.id]!));
    final top5 = mostWorn.where((it) => counts[it.id]! > 0).take(5).toList();
    final never = s.items.where((it) => counts[it.id] == 0).toList();
    final priced = s.items.where((it) => it.price != null).toList();
    final value = priced.fold<double>(0, (a, it) => a + it.price!);
    final wearsOfPriced = priced.fold<int>(0, (a, it) => a + counts[it.id]!);

    // Colour families.
    final families = <ColorFamily, List<ClothingItem>>{};
    for (final it in s.items) {
      families.putIfAbsent(colorFamily(it.color), () => []).add(it);
    }
    final famList = families.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    final maxFam = famList.isEmpty ? 1 : famList.first.value.length;

    final missing = whatsMissing(s);

    Widget title(String t) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 10),
          child: Text(t, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        );

    Widget tile(String big, String small, IconData icon) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(height: 8),
                Text(big, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                Text(small, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: BrandTitle(context.tr('stats_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Row(
            children: [
              tile('${s.items.length}', context.tr('stats_pieces'), Icons.checkroom),
              const SizedBox(width: 10),
              tile('${s.history.length}', context.tr('stats_days'), Icons.event_available),
              const SizedBox(width: 10),
              tile('${s.outfits.length}', context.tr('saved_outfits'), Icons.bookmark),
            ],
          ),

          // ---- What's missing ----
          title('🛍️ ${context.tr('missing_title')}'),
          if (missing.isEmpty)
            Text(context.tr('missing_none'), style: TextStyle(color: scheme.onSurfaceVariant))
          else
            for (final m in missing)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(gradient: Sky.brand, borderRadius: BorderRadius.circular(18)),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: m.color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${context.tr('sub_${m.subType}')} · ${context.tr(colorKey(m.color))}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                          Text('+${m.newOutfits} ${context.tr('missing_new')}', style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

          // ---- Most worn ----
          title('🔥 ${context.tr('stats_most_worn')}'),
          if (top5.isEmpty)
            Text(context.tr('stats_no_wears'), style: TextStyle(color: scheme.onSurfaceVariant))
          else
            for (final it in top5)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(width: 52, height: 52, child: ItemImage(item: it, radius: 12)),
                title: Text(itemTitle(context, it)),
                subtitle: it.price != null
                    ? Text('${context.tr('stats_per_wear')}: ${_money(it.price! / counts[it.id]!)}')
                    : null,
                trailing: Text('×${counts[it.id]}', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: it.id))),
              ),

          // ---- Cost ----
          title('💶 ${context.tr('stats_value')}'),
          if (priced.isEmpty)
            Text(context.tr('stats_no_prices'), style: TextStyle(color: scheme.onSurfaceVariant))
          else
            Row(
              children: [
                tile(_money(value), '${context.tr('stats_total')} (${priced.length})', Icons.account_balance_wallet_outlined),
                const SizedBox(width: 10),
                tile(wearsOfPriced == 0 ? '–' : _money(value / wearsOfPriced), context.tr('stats_per_wear'), Icons.trending_down),
              ],
            ),

          // ---- Colours ----
          title('🎨 ${context.tr('stats_colors')}'),
          for (final e in famList)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(width: 74, child: Text(context.tr('c_${e.key.name}'), style: const TextStyle(fontSize: 13))),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          height: 18,
                          width: c.maxWidth * e.value.length / maxFam,
                          decoration: BoxDecoration(
                            color: e.value.first.color,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${e.value.length}'),
                ],
              ),
            ),

          // ---- Never worn ----
          title('🕸️ ${context.tr('stats_never')} (${never.length})'),
          if (never.isEmpty)
            Text(context.tr('stats_all_worn'), style: TextStyle(color: scheme.onSurfaceVariant))
          else
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: never.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: never[i].id))),
                  child: SizedBox(width: 92, child: ItemImage(item: never[i], radius: 14)),
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (priced.length < s.items.length)
            TextButton.icon(
              onPressed: () {
                final first = s.items.firstWhere((it) => it.price == null);
                Navigator.push(context, MaterialPageRoute(builder: (_) => AddItemScreen(existing: first)));
              },
              icon: const Icon(Icons.sell_outlined),
              label: Text(context.tr('stats_add_prices')),
            ),
        ],
      ),
    );
  }
}

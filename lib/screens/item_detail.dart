import 'package:flutter/material.dart';

import '../l10n.dart';
import '../matching.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import 'add_item.dart';

/// Opens one piece: the figure shows it with its best matches on top,
/// and every other category is ranked underneath by match percentage.
class ItemDetailScreen extends StatefulWidget {
  final String itemId;
  const ItemDetailScreen({super.key, required this.itemId});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  Look? look;

  Future<void> _delete(ClothingItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ctx.tr('delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final s = AppScope.read(context);
    Navigator.pop(context);
    await s.deleteItem(item);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final item = s.itemById(widget.itemId);
    if (item == null) return const Scaffold();

    // Keep the current look valid if pieces were edited or removed.
    var current = look ?? s.bestLookFor(item);
    if (current.items.any((e) => s.itemById(e.id) == null) || current.slot(item.category)?.id != item.id) {
      current = s.bestLookFor(item);
    }
    final targets = targetsFor(item.category, s.profile.bodyType)
        .where((c) => (c != ClothCat.accessory && c != ClothCat.outer) || s.itemsIn(c).isNotEmpty)
        .toList();
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(itemTitle(context, item)),
        actions: [
          IconButton(
            tooltip: context.tr('edit'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddItemScreen(existing: item))),
          ),
          IconButton(tooltip: context.tr('delete'), icon: const Icon(Icons.delete_outline), onPressed: () => _delete(item)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          OutfitStage(look: current, height: 400),
          const SizedBox(height: 8),
          for (final c in targets) ...[
            const SizedBox(height: 14),
            Text('${context.tr('best')} — ${catTitle(context, c)}', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            MatchStrip(
              matches: s.matchesFor(item, c),
              selectedId: current.slot(c)?.id,
              onTap: (picked) => setState(() {
                final sel = current.slot(c)?.id == picked.id;
                look = sel ? current.without(c) : current.withItem(picked);
                // Keep the opened piece in the look (a dress replaces top + bottom).
                if (look!.items.every((e) => e.id != item.id)) {
                  look = current;
                }
              }),
            ),
          ],
        ],
      ),
    );
  }
}

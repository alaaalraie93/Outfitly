import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import 'add_item.dart';
import 'item_detail.dart';

class WardrobeScreen extends StatelessWidget {
  const WardrobeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cats = categoriesFor(s.profile.bodyType);
    return DefaultTabController(
      key: ValueKey(cats.length),
      length: cats.length + 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('tab_wardrobe'), style: const TextStyle(fontWeight: FontWeight.w800)),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '${context.tr('all')} (${s.items.length})'),
              for (final c in cats) Tab(text: '${catTitle(context, c)} (${s.itemsIn(c).length})'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddItemScreen())),
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(context.tr('add_item')),
        ),
        body: TabBarView(
          children: [
            _Grid(items: s.items),
            for (final c in cats) _Grid(items: s.itemsIn(c)),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  final List<ClothingItem> items;
  const _Grid({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.checkroom,
        text: context.tr('empty_wardrobe'),
        action: FilledButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddItemScreen())),
          icon: const Icon(Icons.add),
          label: Text(context.tr('add_first')),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.74,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: it.id))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Hero(tag: 'item-${it.id}', child: SizedBox.expand(child: ItemImage(item: it, radius: 18)))),
              const SizedBox(height: 6),
              Row(
                children: [
                  ColorDot(it.color),
                  const SizedBox(width: 6),
                  Expanded(child: Text(itemTitle(context, it), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                ],
              ),
              Text(context.tr('style_${it.style.name}'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        );
      },
    );
  }
}

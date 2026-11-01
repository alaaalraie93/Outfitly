import 'package:flutter/material.dart';

import 'color_utils.dart';
import 'matching.dart';
import 'models.dart';
import 'state.dart';

// ======================================================================
// Trip packing: the fewest pieces that give a different outfit every day.
// ======================================================================

class PackPlan {
  final List<ClothingItem> pieces;
  final List<Look> days;
  const PackPlan(this.pieces, this.days);
}

const int _goodScore = 65;

PackPlan planTrip(AppState s, {required int days, required Season season, required Occasion occasion}) {
  final m = s.matcher;
  bool fits(ClothingItem it) => seasonFit(it.season, season) >= 70 && occasionFit(it.style, occasion) >= 55;
  List<ClothingItem> pool(ClothCat c) {
    final all = s.itemsIn(c);
    final ok = all.where(fits).toList();
    return ok.isNotEmpty ? ok : all;
  }

  final tops = pool(ClothCat.top);
  final bottoms = pool(ClothCat.bottom);
  final dresses = categoriesFor(s.profile.bodyType).contains(ClothCat.dress) ? pool(ClothCat.dress) : <ClothingItem>[];
  final shoes = pool(ClothCat.shoes);

  final pairScore = <String, int>{};
  int score(ClothingItem a, ClothingItem b) => pairScore.putIfAbsent('${a.id}|${b.id}', () => m.pair(a, b).score);

  final chosenTops = <ClothingItem>[];
  final chosenBottoms = <ClothingItem>[];
  final chosenDresses = <ClothingItem>[];

  // Start with the best pair.
  if (tops.isNotEmpty && bottoms.isNotEmpty) {
    ClothingItem? bt, bb;
    int best = -1;
    for (final t in tops) {
      for (final b in bottoms) {
        final sc = score(t, b);
        if (sc > best) {
          best = sc;
          bt = t;
          bb = b;
        }
      }
    }
    chosenTops.add(bt!);
    chosenBottoms.add(bb!);
  }

  int combos() {
    int n = 0;
    for (final t in chosenTops) {
      for (final b in chosenBottoms) {
        if (score(t, b) >= _goodScore) n++;
      }
    }
    return n + chosenDresses.length;
  }

  // Add the piece that unlocks the most new good outfits until every day is covered.
  while (combos() < days) {
    ClothingItem? pick;
    bool pickTop = true;
    int bestGain = 0;
    double bestAvg = 0;
    for (final t in tops.where((t) => !chosenTops.contains(t))) {
      final scores = chosenBottoms.map((b) => score(t, b)).toList();
      final gain = scores.where((x) => x >= _goodScore).length;
      final avg = scores.isEmpty ? 0.0 : scores.reduce((a, b) => a + b) / scores.length;
      if (gain > bestGain || (gain == bestGain && gain > 0 && avg > bestAvg)) {
        bestGain = gain;
        bestAvg = avg;
        pick = t;
        pickTop = true;
      }
    }
    for (final b in bottoms.where((b) => !chosenBottoms.contains(b))) {
      final scores = chosenTops.map((t) => score(t, b)).toList();
      final gain = scores.where((x) => x >= _goodScore).length;
      final avg = scores.isEmpty ? 0.0 : scores.reduce((a, b) => a + b) / scores.length;
      if (gain > bestGain || (gain == bestGain && gain > 0 && avg > bestAvg)) {
        bestGain = gain;
        bestAvg = avg;
        pick = b;
        pickTop = false;
      }
    }
    if (pick != null && bestGain > 0) {
      (pickTop ? chosenTops : chosenBottoms).add(pick);
      continue;
    }
    // No top/bottom helps any more: use dresses for the remaining days.
    final nextDress = dresses.where((d) => !chosenDresses.contains(d)).toList();
    if (nextDress.isEmpty) break;
    chosenDresses.add(nextDress.first);
  }

  // Shoes that go with most of the chosen clothes (a second pair for longer trips).
  final clothes = [...chosenTops, ...chosenBottoms, ...chosenDresses];
  final rankedShoes = [...shoes]
    ..sort((a, b) {
      double avg(ClothingItem sh) =>
          clothes.isEmpty ? 0 : clothes.map((c) => score(c, sh)).reduce((x, y) => x + y) / clothes.length;
      return avg(b).compareTo(avg(a));
    });
  final chosenShoes = rankedShoes.take(days > 4 ? 2 : 1).toList();

  // Day-by-day looks, best first, without wearing the same top two days running.
  final looks = <MapEntry<Look, int>>[];
  for (final t in chosenTops) {
    for (final b in chosenBottoms) {
      final sc = score(t, b);
      if (sc >= _goodScore || chosenTops.length * chosenBottoms.length <= 1) looks.add(MapEntry(Look(top: t, bottom: b), sc));
    }
  }
  for (final d in chosenDresses) {
    looks.add(MapEntry(Look(dress: d), 80));
  }
  looks.sort((a, b) => b.value.compareTo(a.value));
  final dayLooks = <Look>[];
  if (looks.isNotEmpty) {
    final queue = looks.map((e) => e.key).toList();
    int i = 0;
    while (dayLooks.length < days) {
      var next = queue[i % queue.length];
      if (dayLooks.isNotEmpty && queue.length > 1 && next.top != null && next.top?.id == dayLooks.last.top?.id) {
        next = queue[(i + 1) % queue.length];
        i++;
      }
      // best shoes for this look
      ClothingItem? sh;
      int bestShoe = -1;
      for (final c in chosenShoes) {
        final v = next.clothes.map((x) => score(x, c)).fold<int>(0, (a, b) => a + b);
        if (v > bestShoe) {
          bestShoe = v;
          sh = c;
        }
      }
      dayLooks.add(sh == null ? next : next.withItem(sh));
      i++;
    }
  }
  return PackPlan([...clothes, ...chosenShoes], dayLooks);
}

// ======================================================================
// What's missing: one new piece that unlocks the most new outfits.
// ======================================================================

class MissingSuggestion {
  final ClothCat category;
  final String subType;
  final Color color;
  final int newOutfits;
  const MissingSuggestion(this.category, this.subType, this.color, this.newOutfits);
}

const List<(ClothCat, String, int)> _candidates = [
  (ClothCat.top, 'tshirt', 0xFFF5F5F2),
  (ClothCat.top, 'tshirt', 0xFF1E1E1E),
  (ClothCat.top, 'shirt', 0xFFFFFFFF),
  (ClothCat.top, 'shirt', 0xFF9EC3E6),
  (ClothCat.top, 'sweater', 0xFF8C8C8C),
  (ClothCat.top, 'sweater', 0xFF1F2A44),
  (ClothCat.top, 'sweater', 0xFFD8C7A8),
  (ClothCat.top, 'jacket', 0xFF5A4632),
  (ClothCat.bottom, 'jeans', 0xFF3B5B8C),
  (ClothCat.bottom, 'jeans', 0xFF222222),
  (ClothCat.bottom, 'trousers', 0xFFD2BE9C),
  (ClothCat.bottom, 'trousers', 0xFF2B2B2B),
  (ClothCat.bottom, 'trousers', 0xFF8A8A8A),
  (ClothCat.bottom, 'trousers', 0xFF1F2A44),
  (ClothCat.shoes, 'sneakers', 0xFFF7F7F7),
  (ClothCat.shoes, 'boots', 0xFF5A3B26),
  (ClothCat.shoes, 'formal_shoes', 0xFF151515),
  (ClothCat.dress, 'dress', 0xFF151515),
  (ClothCat.bottom, 'skirt', 0xFF1F2A44),
];

List<MissingSuggestion> whatsMissing(AppState s, {int max = 3}) {
  final m = s.matcher;
  final body = s.profile.bodyType;
  final tops = s.itemsIn(ClothCat.top);
  final bottoms = s.itemsIn(ClothCat.bottom);
  final shoes = s.itemsIn(ClothCat.shoes);
  const good = 72;

  bool goodLook(List<ClothingItem> items) => (m.outfit(items)?.score ?? 0) >= good;
  bool anyShoeWorks(List<ClothingItem> clothes) =>
      shoes.isEmpty ? goodLook(clothes) : shoes.any((sh) => goodLook([...clothes, sh]));

  final results = <MissingSuggestion>[];
  for (final c in _candidates) {
    final cat = c.$1;
    if (!categoriesFor(body).contains(cat) || !subTypesFor(cat, body).contains(c.$2)) continue;
    final color = Color(c.$3);
    // Skip if a very similar piece is already owned.
    final owned = s.itemsIn(cat).any((it) => it.subType == c.$2 && colorFamily(it.color) == colorFamily(color));
    if (owned) continue;
    final fake = ClothingItem(
      id: '_candidate',
      imagePath: '',
      category: cat,
      subType: c.$2,
      colorValue: c.$3,
      style: defaultStyleFor(c.$2),
      season: Season.all,
      createdAt: 0,
    );
    int count = 0;
    switch (cat) {
      case ClothCat.top:
        for (final b in bottoms) {
          if (anyShoeWorks([fake, b])) count++;
        }
        break;
      case ClothCat.bottom:
        for (final t in tops) {
          if (anyShoeWorks([t, fake])) count++;
        }
        break;
      case ClothCat.shoes:
        for (final t in tops) {
          for (final b in bottoms) {
            if (!anyShoeWorks([t, b]) && goodLook([t, b, fake])) count++;
          }
        }
        break;
      case ClothCat.dress:
        count = shoes.isEmpty ? 1 : shoes.where((sh) => goodLook([fake, sh])).length;
        break;
      case ClothCat.accessory:
        break;
    }
    if (count > 0) results.add(MissingSuggestion(cat, c.$2, color, count));
  }
  results.sort((a, b) => b.newOutfits.compareTo(a.newOutfits));
  // Prefer variety: at most one suggestion per category.
  final picked = <MissingSuggestion>[];
  for (final r in results) {
    if (picked.any((p) => p.category == r.category)) continue;
    picked.add(r);
    if (picked.length >= max) break;
  }
  return picked;
}

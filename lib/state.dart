import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'matching.dart';
import 'models.dart';
import 'weather.dart';

/// All app data. Stored as one JSON file on the phone, works fully offline.
class AppState extends ChangeNotifier {
  Profile profile = Profile();
  final List<ClothingItem> items = [];
  final List<Outfit> outfits = [];
  final List<WearLog> history = [];
  final Map<String, double> pairPrefs = {};
  WeatherNow? weather;

  Directory? _dir;
  Future<void> _saving = Future.value();
  int _idCounter = 0;

  Matcher get matcher => Matcher(pairPrefs);

  String newId() {
    _idCounter++;
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$_idCounter';
  }

  Future<void> load() async {
    try {
      _dir = await getApplicationDocumentsDirectory();
      final f = File('${_dir!.path}/outfitly.json');
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        profile = Profile.fromJson((data['profile'] ?? <String, dynamic>{}) as Map<String, dynamic>);
        items
          ..clear()
          ..addAll(((data['items'] ?? const []) as List).map((e) => ClothingItem.fromJson(e as Map<String, dynamic>)));
        outfits
          ..clear()
          ..addAll(((data['outfits'] ?? const []) as List).map((e) => Outfit.fromJson(e as Map<String, dynamic>)));
        history
          ..clear()
          ..addAll(((data['history'] ?? const []) as List).map((e) => WearLog.fromJson(e as Map<String, dynamic>)));
        pairPrefs.clear();
        final p = (data['prefs'] ?? <String, dynamic>{}) as Map<String, dynamic>;
        p.forEach((k, v) => pairPrefs[k] = (v as num).toDouble());
        weather = WeatherNow.fromJson(data['weather']);
      }
    } catch (e) {
      debugPrint('Outfitly load error: $e');
    }
  }

  void _persist() {
    notifyListeners();
    final dir = _dir;
    if (dir == null) return;
    final json = jsonEncode({
      'profile': profile.toJson(),
      'items': items.map((e) => e.toJson()).toList(),
      'outfits': outfits.map((e) => e.toJson()).toList(),
      'history': history.map((e) => e.toJson()).toList(),
      'prefs': pairPrefs,
      'weather': weather?.toJson(),
    });
    _saving = _saving.then((_) async {
      try {
        final tmp = File('${dir.path}/outfitly.json.tmp');
        await tmp.writeAsString(json, flush: true);
        await tmp.rename('${dir.path}/outfitly.json');
      } catch (e) {
        debugPrint('Outfitly save error: $e');
      }
    });
  }

  /// Copies a picked photo into the app's private folder.
  Future<String> storeImage(String srcPath, String prefix) async {
    final dir = _dir ?? await getApplicationDocumentsDirectory();
    final imgDir = Directory('${dir.path}/images');
    if (!await imgDir.exists()) await imgDir.create(recursive: true);
    final ext = srcPath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final dest = '${imgDir.path}/$prefix-${newId()}.$ext';
    await File(srcPath).copy(dest);
    return dest;
  }

  Future<void> _deleteFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // ---------- profile ----------
  void updateProfile(void Function(Profile p) change) {
    change(profile);
    _persist();
  }

  Future<void> setFacePhoto(String? srcPath) async {
    final old = profile.facePath;
    profile.facePath = srcPath == null ? null : await storeImage(srcPath, 'face');
    await _deleteFile(old);
    _persist();
  }

  // ---------- items ----------
  ClothingItem? itemById(String id) {
    for (final it in items) {
      if (it.id == id) return it;
    }
    return null;
  }

  List<ClothingItem> itemsIn(ClothCat c) => items.where((e) => e.category == c).toList();

  void addItem(ClothingItem item) {
    items.insert(0, item);
    _persist();
  }

  void updateItem(ClothingItem item) {
    _persist();
  }

  Future<void> deleteItem(ClothingItem item) async {
    items.removeWhere((e) => e.id == item.id);
    outfits.removeWhere((o) => o.itemIds.contains(item.id));
    pairPrefs.removeWhere((k, _) => k.split('|').contains(item.id));
    await _deleteFile(item.imagePath);
    _persist();
  }

  // ---------- outfits ----------
  Look lookOf(Outfit o) => Look.fromItems(o.itemIds.map(itemById).whereType<ClothingItem>());

  void saveOutfit(Look look, String name) {
    outfits.insert(
      0,
      Outfit(id: newId(), itemIds: look.items.map((e) => e.id).toList(), name: name, createdAt: DateTime.now().millisecondsSinceEpoch),
    );
    _persist();
  }

  void deleteOutfit(Outfit o) {
    outfits.removeWhere((e) => e.id == o.id);
    _persist();
  }

  bool isSaved(Look look) => outfits.any((o) => Look.fromItems(o.itemIds.map(itemById).whereType<ClothingItem>()).key == look.key);

  // ---------- learning ----------
  void rate(Look look, bool liked) {
    final its = look.items;
    for (int i = 0; i < its.length; i++) {
      for (int j = i + 1; j < its.length; j++) {
        final k = Matcher.pairKey(its[i].id, its[j].id);
        final v = (pairPrefs[k] ?? 0.0) + (liked ? 0.5 : -0.5);
        pairPrefs[k] = v.clamp(-1.0, 1.0).toDouble();
      }
    }
    _persist();
  }

  // ---------- history ----------
  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void wear(Look look) {
    final today = dateKey(DateTime.now());
    history.removeWhere((h) => h.date == today);
    history.insert(0, WearLog(date: today, itemIds: look.items.map((e) => e.id).toList()));
    _persist();
  }

  /// How many of the last 3 days an item was worn.
  int recentWear(String itemId) {
    final now = DateTime.now();
    int n = 0;
    for (int d = 1; d <= 3; d++) {
      final key = dateKey(now.subtract(Duration(days: d)));
      for (final h in history) {
        if (h.date == key && h.itemIds.contains(itemId)) n++;
      }
    }
    return n;
  }

  // ---------- matching ----------
  MatchResult? lookScore(Look look) => matcher.outfit(look.items);

  List<ScoredItem> matchesFor(ClothingItem item, ClothCat target) {
    final m = matcher;
    final list = itemsIn(target).where((e) => e.id != item.id).map((e) => ScoredItem(e, m.pair(item, e))).toList();
    list.sort((a, b) => b.result.score.compareTo(a.result.score));
    return list;
  }

  /// Best look built around one piece.
  Look bestLookFor(ClothingItem item) {
    var look = Look.fromItems([item]);
    for (final c in targetsFor(item.category, profile.bodyType)) {
      if (c == ClothCat.dress) continue;
      if (look.dress != null && (c == ClothCat.top || c == ClothCat.bottom)) continue;
      final best = matchesFor(item, c);
      if (best.isNotEmpty) look = look.withItem(best.first.item);
    }
    return look;
  }

  Season targetSeason() {
    final w = weather;
    if (w != null && w.isToday) return seasonForTemp(w.tempC);
    return seasonForDate(DateTime.now());
  }

  /// Today's occasion (chosen on the Today screen).
  Occasion occasion = Occasion.any;

  void setOccasion(Occasion o) {
    occasion = o;
    notifyListeners();
  }

  /// Pieces not worn for [days] days (and owned at least that long).
  List<ClothingItem> forgottenItems({int days = 30}) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    final cutoffKey = dateKey(cutoff);
    final lastWorn = <String, String>{};
    for (final h in history) {
      for (final id in h.itemIds) {
        final prev = lastWorn[id];
        if (prev == null || h.date.compareTo(prev) > 0) lastWorn[id] = h.date;
      }
    }
    return items.where((it) {
      if (DateTime.fromMillisecondsSinceEpoch(it.createdAt).isAfter(cutoff)) return false;
      final lw = lastWorn[it.id];
      return lw == null || lw.compareTo(cutoffKey) < 0;
    }).toList();
  }

  /// Ranked daily suggestions for the given season and the current occasion.
  List<Look> suggestions(Season target, {int limit = 30}) {
    final tops = itemsIn(ClothCat.top);
    final bottoms = itemsIn(ClothCat.bottom);
    final dresses = categoriesFor(profile.bodyType).contains(ClothCat.dress) ? itemsIn(ClothCat.dress) : <ClothingItem>[];
    final shoes = itemsIn(ClothCat.shoes);
    if (shoes.isEmpty) return [];
    final candidates = <Look>[];
    for (final t in tops) {
      for (final b in bottoms) {
        for (final s in shoes) {
          candidates.add(Look(top: t, bottom: b, shoes: s));
          if (candidates.length > 6000) break;
        }
      }
    }
    for (final d in dresses) {
      for (final s in shoes) {
        candidates.add(Look(dress: d, shoes: s));
      }
    }
    final m = matcher;
    final scored = <MapEntry<Look, double>>[];
    for (final l in candidates) {
      final r = m.outfit(l.items);
      if (r == null) continue;
      final its = l.items;
      final fit = its.map((e) => seasonFit(e.season, target)).reduce((a, b) => a + b) / its.length;
      final occ = its.map((e) => occasionFit(e.style, occasion)).reduce((a, b) => a + b) / its.length;
      final worn = its.map((e) => recentWear(e.id)).reduce((a, b) => a + b);
      final value = occasion == Occasion.any
          ? r.score * 0.75 + fit * 0.25
          : r.score * 0.5 + fit * 0.2 + occ * 0.3;
      scored.add(MapEntry(l, value - worn * 6));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    // Small daily shuffle among near-equal options so the top pick changes day to day.
    final seed = DateTime.now().day + DateTime.now().month * 31;
    final rnd = math.Random(seed);
    final top = scored.take(limit).toList();
    for (int i = 0; i + 1 < top.length; i++) {
      if ((top[i].value - top[i + 1].value).abs() < 2 && rnd.nextBool()) {
        final tmp = top[i];
        top[i] = top[i + 1];
        top[i + 1] = tmp;
      }
    }
    // Finish each look with the accessory that suits it best.
    final accessories = itemsIn(ClothCat.accessory);
    return top.map((e) {
      final look = e.key;
      if (accessories.isEmpty) return look;
      ClothingItem? best;
      double bestScore = -1;
      for (final a in accessories) {
        final sc = look.items.map((it) => m.pair(it, a).score).reduce((x, y) => x + y) / look.items.length +
            occasionFit(a.style, occasion) * 0.2 +
            seasonFit(a.season, target) * 0.1;
        if (sc > bestScore) {
          bestScore = sc;
          best = a;
        }
      }
      return best == null ? look : look.withItem(best);
    }).toList();
  }

  Future<bool> refreshWeather() async {
    final lat = profile.lat, lon = profile.lon;
    if (lat == null || lon == null) return false;
    final w = await WeatherService.fetch(lat, lon);
    if (w == null) return false;
    weather = w;
    _persist();
    return true;
  }

  Future<bool> setCity(String city) async {
    final place = await WeatherService.geocode(city, profile.lang);
    if (place == null) return false;
    profile.city = place.name;
    profile.lat = place.lat;
    profile.lon = place.lon;
    _persist();
    await refreshWeather();
    return true;
  }

  Future<void> resetAll() async {
    for (final it in items) {
      await _deleteFile(it.imagePath);
    }
    await _deleteFile(profile.facePath);
    items.clear();
    outfits.clear();
    history.clear();
    pairPrefs.clear();
    weather = null;
    final lang = profile.lang;
    profile = Profile(lang: lang);
    _persist();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

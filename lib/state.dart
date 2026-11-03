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
  final List<WearLog> plans = []; // outfits planned for future days
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
        _applyData(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Outfitly load error: $e');
    }
  }

  void _applyData(Map<String, dynamic> data) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        ((data[key] ?? const []) as List).map((e) => f(e as Map<String, dynamic>)).toList();
    profile = Profile.fromJson((data['profile'] ?? <String, dynamic>{}) as Map<String, dynamic>);
    items
      ..clear()
      ..addAll(list('items', ClothingItem.fromJson));
    outfits
      ..clear()
      ..addAll(list('outfits', Outfit.fromJson));
    history
      ..clear()
      ..addAll(list('history', WearLog.fromJson));
    plans
      ..clear()
      ..addAll(list('plans', WearLog.fromJson));
    pairPrefs.clear();
    final p = (data['prefs'] ?? <String, dynamic>{}) as Map<String, dynamic>;
    p.forEach((k, v) => pairPrefs[k] = (v as num).toDouble());
    weather = WeatherNow.fromJson(data['weather']);
  }

  Map<String, dynamic> _data() => {
        'profile': profile.toJson(),
        'items': items.map((e) => e.toJson()).toList(),
        'outfits': outfits.map((e) => e.toJson()).toList(),
        'history': history.map((e) => e.toJson()).toList(),
        'plans': plans.map((e) => e.toJson()).toList(),
        'prefs': pairPrefs,
        'weather': weather?.toJson(),
      };

  void _persist() {
    notifyListeners();
    final dir = _dir;
    if (dir == null) return;
    final json = jsonEncode(_data());
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

  // ---------- backup ----------
  /// Writes everything (including photos) into one file and returns its path.
  Future<String> exportBackup() async {
    final data = _data();
    final photos = <String, String>{};
    Future<void> addPhoto(String? path) async {
      if (path == null || path.isEmpty || photos.containsKey(path)) return;
      final f = File(path);
      if (await f.exists()) photos[path] = base64Encode(await f.readAsBytes());
    }

    for (final it in items) {
      await addPhoto(it.imagePath);
    }
    await addPhoto(profile.facePath);
    data['photos'] = photos;
    data['backupVersion'] = 1;
    data['createdAt'] = DateTime.now().toIso8601String();
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/outfitly-backup-${dateKey(DateTime.now())}.json');
    await out.writeAsString(jsonEncode(data), flush: true);
    return out.path;
  }

  /// Replaces all data with a backup file. Returns false if the file is not a backup.
  Future<bool> importBackup(String path) async {
    try {
      final data = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      if (data['backupVersion'] == null || data['items'] == null) return false;
      final dir = _dir ?? await getApplicationDocumentsDirectory();
      final imgDir = Directory('${dir.path}/images');
      if (!await imgDir.exists()) await imgDir.create(recursive: true);
      final photos = (data['photos'] ?? <String, dynamic>{}) as Map<String, dynamic>;
      final moved = <String, String>{};
      for (final entry in photos.entries) {
        final ext = entry.key.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
        final dest = '${imgDir.path}/restored-${newId()}.$ext';
        await File(dest).writeAsBytes(base64Decode(entry.value as String), flush: true);
        moved[entry.key] = dest;
      }
      for (final it in (data['items'] as List)) {
        final m = it as Map<String, dynamic>;
        m['imagePath'] = moved[m['imagePath']] ?? m['imagePath'];
      }
      final prof = (data['profile'] ?? <String, dynamic>{}) as Map<String, dynamic>;
      if (prof['facePath'] != null) prof['facePath'] = moved[prof['facePath']];
      final lang = profile.lang;
      _applyData(data);
      if (profile.lang.isEmpty) profile.lang = lang;
      profile.onboarded = true;
      _persist();
      return true;
    } catch (e) {
      debugPrint('Outfitly import error: $e');
      return false;
    }
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
    plans.removeWhere((p) => p.date == today);
    _persist();
  }

  // ---------- planning ----------
  WearLog? planFor(DateTime day) {
    final key = dateKey(day);
    for (final p in plans) {
      if (p.date == key) return p;
    }
    return null;
  }

  WearLog? wornOn(DateTime day) {
    final key = dateKey(day);
    for (final h in history) {
      if (h.date == key) return h;
    }
    return null;
  }

  void setPlan(DateTime day, Look look) {
    final key = dateKey(day);
    plans.removeWhere((p) => p.date == key);
    plans.add(WearLog(date: key, itemIds: look.items.map((e) => e.id).toList()));
    _persist();
  }

  void clearPlan(DateTime day) {
    final key = dateKey(day);
    plans.removeWhere((p) => p.date == key);
    _persist();
  }

  void wearOn(DateTime day, Look look) {
    final key = dateKey(day);
    history.removeWhere((h) => h.date == key);
    history.add(WearLog(date: key, itemIds: look.items.map((e) => e.id).toList()));
    history.sort((a, b) => b.date.compareTo(a.date));
    plans.removeWhere((p) => p.date == key);
    _persist();
  }

  void clearWorn(DateTime day) {
    final key = dateKey(day);
    history.removeWhere((h) => h.date == key);
    _persist();
  }

  Look lookFromLog(WearLog log) => Look.fromItems(log.itemIds.map(itemById).whereType<ClothingItem>());

  int wearCount(String itemId) => history.where((h) => h.itemIds.contains(itemId)).length;

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
  MatchResult? lookScore(Look look) {
    final r = matcher.outfit(look.items);
    if (r == null || !look.missingUnderLayer) return r;
    // A jacket with nothing under it is not a finished outfit.
    return MatchResult((r.score - 15).clamp(0, 100), [const Reason('r_need_under', false), ...r.reasons]);
  }

  /// The jacket/coat that fits a look best, or null if none fits or it is too warm.
  ClothingItem? bestOuterFor(Look look, Season target, {bool force = false}) {
    if (!force && target == Season.summer) return null;
    final outers = itemsIn(ClothCat.outer);
    final clothes = look.clothes.where((e) => e.category != ClothCat.outer).toList();
    if (outers.isEmpty || clothes.isEmpty) return null;
    final m = matcher;
    ClothingItem? best;
    double bestScore = -1;
    double bestMatch = 0;
    for (final o in outers) {
      final match = clothes.map((c) => m.pair(c, o).score).reduce((a, b) => a + b) / clothes.length;
      final sc = match + seasonFit(o.season, target) * 0.3 + occasionFit(o.style, occasion) * 0.2 - recentWear(o.id) * 3;
      if (sc > bestScore) {
        bestScore = sc;
        best = o;
        bestMatch = match;
      }
    }
    if (best == null) return null;
    if (!force && target == Season.transitional && bestMatch < 70) return null;
    return best;
  }

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
      if (c == ClothCat.dress || c == ClothCat.outer) continue;
      if (look.dress != null && (c == ClothCat.top || c == ClothCat.bottom)) continue;
      final best = matchesFor(item, c);
      if (best.isNotEmpty) look = look.withItem(best.first.item);
    }
    // Add a jacket when the weather calls for one.
    if (item.category != ClothCat.outer) {
      final o = bestOuterFor(look, targetSeason());
      if (o != null) look = look.withItem(o);
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
    }).map((look) {
      // Cool day: put the best matching jacket or coat over it.
      final o = bestOuterFor(look, target);
      return o == null ? look : look.withItem(o);
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
    plans.clear();
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

import 'package:flutter/material.dart';

enum ClothCat { top, bottom, dress, shoes }

enum StyleLevel { sport, casual, smart, formal }

enum Season { all, summer, transitional, winter }

enum BodyType { girl, boy, kids }

const Map<ClothCat, List<String>> kSubTypes = {
  ClothCat.top: ['tshirt', 'shirt', 'blouse', 'sweater', 'hoodie', 'jacket'],
  ClothCat.bottom: ['jeans', 'trousers', 'sweatpants', 'shorts', 'skirt'],
  ClothCat.dress: ['dress'],
  ClothCat.shoes: ['sneakers', 'boots', 'formal_shoes', 'sandals', 'heels'],
};

/// Sub types hidden for the "boy" profile.
const Set<String> kFeminineOnly = {'blouse', 'skirt', 'heels', 'dress'};

List<ClothCat> categoriesFor(BodyType b) {
  if (b == BodyType.boy) return [ClothCat.top, ClothCat.bottom, ClothCat.shoes];
  return [ClothCat.top, ClothCat.bottom, ClothCat.dress, ClothCat.shoes];
}

List<String> subTypesFor(ClothCat c, BodyType b) {
  final all = kSubTypes[c]!;
  if (b != BodyType.boy) return all;
  return all.where((s) => !kFeminineOnly.contains(s)).toList();
}

StyleLevel defaultStyleFor(String sub) {
  switch (sub) {
    case 'hoodie':
    case 'sweatpants':
    case 'sneakers':
      return StyleLevel.sport;
    case 'shirt':
    case 'blouse':
    case 'trousers':
    case 'jacket':
    case 'boots':
    case 'dress':
    case 'skirt':
      return StyleLevel.smart;
    case 'formal_shoes':
    case 'heels':
      return StyleLevel.formal;
    default:
      return StyleLevel.casual;
  }
}

Season defaultSeasonFor(String sub) {
  switch (sub) {
    case 'shorts':
    case 'sandals':
    case 'tshirt':
      return Season.summer;
    case 'sweater':
    case 'boots':
      return Season.winter;
    case 'jacket':
    case 'hoodie':
      return Season.transitional;
    default:
      return Season.all;
  }
}

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

class ClothingItem {
  final String id;
  String imagePath;
  ClothCat category;
  String subType;
  int colorValue;
  List<int> palette;
  StyleLevel style;
  Season season;
  bool patterned;
  String name;
  final int createdAt;

  ClothingItem({
    required this.id,
    required this.imagePath,
    required this.category,
    required this.subType,
    required this.colorValue,
    this.palette = const [],
    required this.style,
    required this.season,
    this.patterned = false,
    this.name = '',
    required this.createdAt,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'imagePath': imagePath,
        'category': category.name,
        'subType': subType,
        'color': colorValue,
        'palette': palette,
        'style': style.name,
        'season': season.name,
        'patterned': patterned,
        'name': name,
        'createdAt': createdAt,
      };

  factory ClothingItem.fromJson(Map<String, dynamic> j) {
    final cat = enumByName(ClothCat.values, j['category'], ClothCat.top);
    return ClothingItem(
      id: j['id'] as String,
      imagePath: (j['imagePath'] ?? '') as String,
      category: cat,
      subType: (j['subType'] ?? kSubTypes[cat]!.first) as String,
      colorValue: (j['color'] ?? 0xFF808080) as int,
      palette: ((j['palette'] ?? const []) as List).map((e) => e as int).toList(),
      style: enumByName(StyleLevel.values, j['style'], StyleLevel.casual),
      season: enumByName(Season.values, j['season'], Season.all),
      patterned: (j['patterned'] ?? false) as bool,
      name: (j['name'] ?? '') as String,
      createdAt: (j['createdAt'] ?? 0) as int,
    );
  }
}

class Outfit {
  final String id;
  final List<String> itemIds;
  String name;
  final int createdAt;

  Outfit({required this.id, required this.itemIds, required this.name, required this.createdAt});

  Map<String, dynamic> toJson() => {'id': id, 'itemIds': itemIds, 'name': name, 'createdAt': createdAt};

  factory Outfit.fromJson(Map<String, dynamic> j) => Outfit(
        id: j['id'] as String,
        itemIds: ((j['itemIds'] ?? const []) as List).map((e) => e as String).toList(),
        name: (j['name'] ?? '') as String,
        createdAt: (j['createdAt'] ?? 0) as int,
      );
}

class WearLog {
  final String date; // yyyy-mm-dd
  final List<String> itemIds;

  WearLog({required this.date, required this.itemIds});

  Map<String, dynamic> toJson() => {'date': date, 'itemIds': itemIds};

  factory WearLog.fromJson(Map<String, dynamic> j) => WearLog(
        date: (j['date'] ?? '') as String,
        itemIds: ((j['itemIds'] ?? const []) as List).map((e) => e as String).toList(),
      );
}

const List<Color> kSkinTones = [
  Color(0xFFF6D7C3),
  Color(0xFFE8B996),
  Color(0xFFD19A6E),
  Color(0xFFA86F48),
  Color(0xFF6E4630),
];

class Profile {
  String name;
  BodyType bodyType;
  int age;
  double heightCm;
  double weightKg;
  int skinTone;
  String? facePath;
  String lang;
  String city;
  double? lat;
  double? lon;
  bool onboarded;

  Profile({
    this.name = '',
    this.bodyType = BodyType.girl,
    this.age = 25,
    this.heightCm = 168,
    this.weightKg = 62,
    this.skinTone = 1,
    this.facePath,
    this.lang = 'ar',
    this.city = '',
    this.lat,
    this.lon,
    this.onboarded = false,
  });

  Color get skin => kSkinTones[skinTone.clamp(0, kSkinTones.length - 1)];

  Map<String, dynamic> toJson() => {
        'name': name,
        'bodyType': bodyType.name,
        'age': age,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'skinTone': skinTone,
        'facePath': facePath,
        'lang': lang,
        'city': city,
        'lat': lat,
        'lon': lon,
        'onboarded': onboarded,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        name: (j['name'] ?? '') as String,
        bodyType: enumByName(BodyType.values, j['bodyType'], BodyType.girl),
        age: (j['age'] ?? 25) as int,
        heightCm: ((j['heightCm'] ?? 168) as num).toDouble(),
        weightKg: ((j['weightKg'] ?? 62) as num).toDouble(),
        skinTone: (j['skinTone'] ?? 1) as int,
        facePath: j['facePath'] as String?,
        lang: (j['lang'] ?? 'ar') as String,
        city: (j['city'] ?? '') as String,
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        onboarded: (j['onboarded'] ?? false) as bool,
      );
}

/// A set of pieces worn together. A dress replaces top + bottom.
class Look {
  final ClothingItem? top;
  final ClothingItem? bottom;
  final ClothingItem? dress;
  final ClothingItem? shoes;

  const Look({this.top, this.bottom, this.dress, this.shoes});

  factory Look.fromItems(Iterable<ClothingItem> items) {
    var l = const Look();
    for (final it in items) {
      l = l.withItem(it);
    }
    return l;
  }

  List<ClothingItem> get items => [
        if (dress != null) dress!,
        if (dress == null && top != null) top!,
        if (dress == null && bottom != null) bottom!,
        if (shoes != null) shoes!,
      ];

  bool get isEmpty => items.isEmpty;

  ClothingItem? slot(ClothCat c) {
    switch (c) {
      case ClothCat.top:
        return top;
      case ClothCat.bottom:
        return bottom;
      case ClothCat.dress:
        return dress;
      case ClothCat.shoes:
        return shoes;
    }
  }

  Look withItem(ClothingItem it) {
    switch (it.category) {
      case ClothCat.top:
        return Look(top: it, bottom: bottom, shoes: shoes);
      case ClothCat.bottom:
        return Look(top: top, bottom: it, shoes: shoes);
      case ClothCat.dress:
        return Look(dress: it, shoes: shoes);
      case ClothCat.shoes:
        return Look(top: top, bottom: bottom, dress: dress, shoes: it);
    }
  }

  Look without(ClothCat c) {
    switch (c) {
      case ClothCat.top:
        return Look(bottom: bottom, dress: dress, shoes: shoes);
      case ClothCat.bottom:
        return Look(top: top, dress: dress, shoes: shoes);
      case ClothCat.dress:
        return Look(top: top, bottom: bottom, shoes: shoes);
      case ClothCat.shoes:
        return Look(top: top, bottom: bottom, dress: dress);
    }
  }

  String get key => (items.map((e) => e.id).toList()..sort()).join('|');
}

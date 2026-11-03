import 'package:flutter/material.dart';

import 'color_utils.dart';
import 'models.dart';

class Reason {
  final String key;
  final bool good;
  const Reason(this.key, this.good);
}

class MatchResult {
  final int score;
  final List<Reason> reasons;
  const MatchResult(this.score, this.reasons);
}

class ScoredItem {
  final ClothingItem item;
  final MatchResult result;
  const ScoredItem(this.item, this.result);
}

/// Rule-based outfit scoring.
/// Score = 35% color + 25% style + 15% season + 15% pattern + 10% learned preference.
class Matcher {
  final Map<String, double> prefs;
  const Matcher(this.prefs);

  static String pairKey(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

  MatchResult pair(ClothingItem a, ClothingItem b) {
    final reasons = <Reason>[];
    final color = _color(a.color, b.color, reasons);
    final style = _style(a.style, b.style, reasons);
    final season = _season(a.season, b.season, reasons);
    final pattern = _pattern(a.patterned, b.patterned, reasons);
    final pref = _pref(a.id, b.id, reasons);
    final total = 0.35 * color + 0.25 * style + 0.15 * season + 0.15 * pattern + 0.10 * pref;
    return MatchResult(total.round().clamp(0, 100), reasons);
  }

  /// Score of a whole look: average of all pairs, reasons from the weakest pair first.
  MatchResult? outfit(List<ClothingItem> items) {
    if (items.length < 2) return null;
    final results = <MatchResult>[];
    double sum = 0, weights = 0;
    for (int i = 0; i < items.length; i++) {
      for (int j = i + 1; j < items.length; j++) {
        final r = pair(items[i], items[j]);
        // An accessory matters less than the main clothes.
        final w = (items[i].category == ClothCat.accessory || items[j].category == ClothCat.accessory) ? 0.5 : 1.0;
        results.add(r);
        sum += r.score * w;
        weights += w;
      }
    }
    final avg = sum / weights;
    results.sort((a, b) => a.score.compareTo(b.score));
    final seen = <String>{};
    final reasons = <Reason>[];
    // Problems first, then strengths.
    for (final r in results) {
      for (final reason in r.reasons.where((x) => !x.good)) {
        if (seen.add(reason.key)) reasons.add(reason);
      }
    }
    for (final r in results) {
      for (final reason in r.reasons.where((x) => x.good)) {
        if (seen.add(reason.key)) reasons.add(reason);
      }
    }
    return MatchResult(avg.round(), reasons);
  }

  double _color(Color a, Color b, List<Reason> out) {
    final na = isNeutral(a), nb = isNeutral(b);
    final ha = HSLColor.fromColor(a), hb = HSLColor.fromColor(b);
    final lightDiff = (ha.lightness - hb.lightness).abs();
    if (na || nb) {
      if (na && nb && lightDiff < 0.08 && colorFamily(a) == colorFamily(b)) {
        out.add(const Reason('r_low_contrast', false));
        return 72;
      }
      out.add(const Reason('r_color_neutral', true));
      return na && nb ? 88 : 92;
    }
    var d = (ha.hue - hb.hue).abs();
    if (d > 180) d = 360 - d;
    final bothLoud = ha.saturation > 0.7 && hb.saturation > 0.7 && ha.lightness > 0.35 && hb.lightness > 0.35;
    double score;
    if (d < 15) {
      if (lightDiff < 0.1) {
        out.add(const Reason('r_low_contrast', false));
        score = 70;
      } else {
        out.add(const Reason('r_color_mono', true));
        score = 88;
      }
    } else if (d < 45) {
      out.add(const Reason('r_color_analog', true));
      score = 84;
    } else if (d < 100) {
      out.add(const Reason('r_color_clash', false));
      score = 45;
    } else if (d < 150) {
      out.add(const Reason('r_color_triad', true));
      score = 68;
    } else {
      out.add(const Reason('r_color_complement', true));
      score = 78;
    }
    if (bothLoud && d >= 15) {
      out.add(const Reason('r_color_loud', false));
      score -= 15;
    }
    return score.clamp(0, 100).toDouble();
  }

  double _style(StyleLevel a, StyleLevel b, List<Reason> out) {
    final d = (a.index - b.index).abs();
    switch (d) {
      case 0:
        out.add(const Reason('r_style_match', true));
        return 100;
      case 1:
        out.add(const Reason('r_style_near', true));
        return 78;
      case 2:
        out.add(const Reason('r_style_far', false));
        return 35;
      default:
        out.add(const Reason('r_style_far', false));
        return 10;
    }
  }

  double _season(Season a, Season b, List<Reason> out) {
    if (a == Season.all || b == Season.all || a == b) return 100;
    if ((a == Season.summer && b == Season.winter) || (a == Season.winter && b == Season.summer)) {
      out.add(const Reason('r_season_clash', false));
      return 30;
    }
    return 80;
  }

  double _pattern(bool a, bool b, List<Reason> out) {
    if (a && b) {
      out.add(const Reason('r_pattern_both', false));
      return 40;
    }
    if (a || b) out.add(const Reason('r_pattern_ok', true));
    return 100;
  }

  double _pref(String a, String b, List<Reason> out) {
    final v = prefs[pairKey(a, b)] ?? 0.0;
    if (v > 0.2) out.add(const Reason('r_liked', true));
    if (v < -0.2) out.add(const Reason('r_disliked', false));
    return v >= 0 ? 70 + 30 * v : 70 + 50 * v;
  }
}

/// Which categories should be suggested under an opened piece.
List<ClothCat> targetsFor(ClothCat c, BodyType body) {
  final cats = categoriesFor(body);
  final dress = cats.contains(ClothCat.dress);
  switch (c) {
    case ClothCat.top:
      return [ClothCat.bottom, ClothCat.shoes, ClothCat.outer, ClothCat.accessory];
    case ClothCat.outer:
      // A jacket always gets something under it.
      return [ClothCat.top, ClothCat.bottom, ClothCat.shoes, if (dress) ClothCat.dress, ClothCat.accessory];
    case ClothCat.bottom:
      return [ClothCat.top, ClothCat.shoes, ClothCat.outer, ClothCat.accessory];
    case ClothCat.dress:
      return [ClothCat.shoes, ClothCat.outer, ClothCat.accessory];
    case ClothCat.shoes:
      return [ClothCat.top, ClothCat.bottom, if (dress) ClothCat.dress, ClothCat.outer, ClothCat.accessory];
    case ClothCat.accessory:
      return [ClothCat.top, ClothCat.bottom, if (dress) ClothCat.dress, ClothCat.outer, ClothCat.shoes];
  }
}

Season seasonForTemp(double t) {
  if (t >= 23) return Season.summer;
  if (t <= 11) return Season.winter;
  return Season.transitional;
}

Season seasonForDate(DateTime d) {
  if (d.month >= 6 && d.month <= 8) return Season.summer;
  if (d.month == 12 || d.month <= 2) return Season.winter;
  return Season.transitional;
}

double seasonFit(Season item, Season target) {
  if (item == Season.all || item == target) return 100;
  if ((item == Season.summer && target == Season.winter) || (item == Season.winter && target == Season.summer)) return 25;
  return 70;
}

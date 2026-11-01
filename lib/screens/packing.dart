import 'package:flutter/material.dart';

import '../l10n.dart';
import '../matching.dart';
import '../models.dart';
import '../planner.dart';
import '../state.dart';
import '../weather.dart';
import '../widgets/common.dart';
import '../widgets/outfit_board.dart';
import '../widgets/sky.dart';

/// Trip packing: how many days, where, what for -> a small capsule and a plan per day.
class PackingScreen extends StatefulWidget {
  const PackingScreen({super.key});

  @override
  State<PackingScreen> createState() => _PackingScreenState();
}

class _PackingScreenState extends State<PackingScreen> {
  int days = 5;
  Season season = seasonForDate(DateTime.now());
  Occasion occasion = Occasion.any;
  final city = TextEditingController();
  bool checking = false;
  String? weatherNote;
  PackPlan? plan;

  @override
  void dispose() {
    city.dispose();
    super.dispose();
  }

  Future<void> _checkCity() async {
    final q = city.text.trim();
    if (q.isEmpty) return;
    setState(() {
      checking = true;
      weatherNote = null;
    });
    final s = AppScope.read(context);
    final place = await WeatherService.geocode(q, s.profile.lang);
    double? avg;
    if (place != null) avg = await WeatherService.averageHigh(place.lat, place.lon, days: days);
    if (!mounted) return;
    setState(() {
      checking = false;
      if (place != null && avg != null) {
        season = seasonForTemp(avg);
        weatherNote = '${place.name}: ~${avg.round()}°C';
      } else {
        weatherNote = context.tr('city_not_found');
      }
    });
  }

  void _pack() {
    final s = AppScope.read(context);
    setState(() => plan = planTrip(s, days: days, season: season, occasion: occasion));
  }

  Future<void> _addToCalendar() async {
    final p = plan;
    if (p == null || p.days.isEmpty) return;
    final now = DateTime.now();
    final start = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (start == null || !mounted) return;
    final s = AppScope.read(context);
    for (int i = 0; i < p.days.length; i++) {
      s.setPlan(start.add(Duration(days: i)), p.days[i]);
    }
    showSnack(context, context.tr('planned_ok'));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final p = plan;

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(t, style: text.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
        );

    return Scaffold(
      appBar: AppBar(title: BrandTitle(context.tr('packing_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          Text(context.tr('packing_sub'), style: TextStyle(color: scheme.onSurfaceVariant)),
          label(context.tr('packing_days')),
          Row(
            children: [
              IconButton.filledTonal(onPressed: days > 1 ? () => setState(() => days--) : null, icon: const Icon(Icons.remove)),
              Expanded(
                child: Text('$days', textAlign: TextAlign.center, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              IconButton.filledTonal(onPressed: days < 21 ? () => setState(() => days++) : null, icon: const Icon(Icons.add)),
            ],
          ),
          label(context.tr('packing_where')),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: city,
                  decoration: InputDecoration(hintText: context.tr('city_hint'), border: const OutlineInputBorder()),
                  onSubmitted: (_) => _checkCity(),
                ),
              ),
              const SizedBox(width: 8),
              checking
                  ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                  : FilledButton.tonal(onPressed: _checkCity, child: Text(context.tr('find'))),
            ],
          ),
          if (weatherNote != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(weatherNote!)),
          label(context.tr('season')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final se in Season.values.where((x) => x != Season.all))
                ChoiceChip(label: Text(context.tr('season_${se.name}')), selected: season == se, onSelected: (_) => setState(() => season = se)),
            ],
          ),
          label(context.tr('occasion')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in Occasion.values)
                ChoiceChip(label: Text(context.tr('occ_${o.name}')), selected: occasion == o, onSelected: (_) => setState(() => occasion = o)),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: _pack,
            icon: const Icon(Icons.luggage),
            label: Text(context.tr('packing_go')),
          ),
          if (p != null) ...[
            const SizedBox(height: 24),
            if (p.days.isEmpty)
              Text(context.tr('need_more_items'))
            else ...[
              Text('${context.tr('packing_pieces')}: ${p.pieces.length}', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(
                '${p.pieces.length} → ${p.days.length} ${context.tr('packing_looks')}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final it in p.pieces)
                    SizedBox(
                      width: 92,
                      child: Column(
                        children: [
                          SizedBox(width: 92, height: 92, child: ItemImage(item: it, radius: 14)),
                          const SizedBox(height: 4),
                          Text(itemTitle(context, it), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              for (int i = 0; i < p.days.length; i++) ...[
                Text('${context.tr('packing_day')} ${i + 1}', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                OutfitBoard(look: p.days[i], height: 260),
                const SizedBox(height: 14),
              ],
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _addToCalendar,
                icon: const Icon(Icons.event_note),
                label: Text(context.tr('packing_to_calendar')),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

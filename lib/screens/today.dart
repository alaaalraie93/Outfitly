import 'package:flutter/material.dart';

import '../l10n.dart';
import '../state.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/sky.dart';
import 'item_detail.dart';
import 'packing.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  int pick = 0;
  bool loadingWeather = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final s = AppScope.read(context);
    if (s.profile.lat == null) return;
    final w = s.weather;
    if (w != null && w.isToday && DateTime.now().difference(w.fetched).inMinutes < 60) return;
    setState(() => loadingWeather = true);
    await s.refreshWeather();
    if (mounted) setState(() => loadingWeather = false);
  }

  IconData _weatherIcon(AppState s) {
    final w = s.weather;
    if (w == null) return Icons.calendar_month;
    if (w.snowy) return Icons.ac_unit;
    if (w.rainy) return Icons.umbrella;
    if (w.cloudy) return Icons.wb_cloudy_outlined;
    return Icons.wb_sunny_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final season = s.targetSeason();
    final list = s.suggestions(season);
    final planLog = s.planFor(DateTime.now());
    final planned = planLog == null ? null : s.lookFromLog(planLog);
    final hasPlan = planned != null && planned.clothes.isNotEmpty;
    final Look? look = (hasPlan && pick == 0)
        ? planned
        : (list.isNotEmpty ? list[(hasPlan ? pick - 1 : pick) % list.length] : null);
    final showingPlan = hasPlan && pick == 0;
    final w = s.weather;
    final name = s.profile.name.trim();
    final forgotten = s.forgottenItems().take(12).toList();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Row(
                children: [
                  const OutfitlyLogo(size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.isEmpty ? context.tr('hello') : '${context.tr('hello')} $name 👋',
                            style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
                        GradientText(context.tr('today_title'), style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: Sky.brand,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Sky.blue.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
                      child: loadingWeather
                          ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Icon(_weatherIcon(s), size: 30, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (w != null && w.isToday)
                            Text('${w.tempC.round()}°C · ${s.profile.city}',
                                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white))
                          else
                            Text(
                              s.profile.lat == null ? context.tr('weather_add_city') : context.tr('weather_offline'),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          Text('${context.tr('picked_for')} ${context.tr('season_${season.name}')}',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(context.tr('occasion'), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final o in Occasion.values)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          avatar: Text(_occasionEmoji(o)),
                          label: Text(context.tr('occ_${o.name}')),
                          selected: s.occasion == o,
                          showCheckmark: false,
                          onSelected: (_) {
                            s.setOccasion(o);
                            setState(() => pick = 0);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (look == null)
                EmptyState(icon: Icons.wb_sunny_outlined, text: context.tr('need_more_items'))
              else ...[
                if (showingPlan)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Chip(
                      avatar: const Icon(Icons.event_note, size: 18),
                      label: Text(context.tr('planned_today')),
                    ),
                  ),
                OutfitStage(look: look, height: 420),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        onPressed: (list.length > 1 || (hasPlan && list.isNotEmpty)) ? () => setState(() => pick++) : null,
                        icon: const Icon(Icons.shuffle),
                        label: Text(context.tr('another')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        onPressed: () {
                          s.wear(look);
                          showSnack(context, context.tr('worn_saved'));
                        },
                        icon: const Icon(Icons.event_available),
                        label: Text(context.tr('wear_this')),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PackingScreen())),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      const Text('🧳', style: TextStyle(fontSize: 30)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.tr('packing_title'),
                                style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onTertiaryContainer)),
                            Text(context.tr('packing_sub'), style: TextStyle(color: scheme.onTertiaryContainer.withValues(alpha: 0.85))),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: scheme.onTertiaryContainer),
                    ],
                  ),
                ),
              ),
              if (forgotten.isNotEmpty) ...[
                const SizedBox(height: 26),
                Text('${context.tr('forgotten_title')} 🕸️', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text(context.tr('forgotten_sub'), style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: forgotten.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: forgotten[i].id))),
                      child: SizedBox(width: 96, child: ItemImage(item: forgotten[i], radius: 18)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _occasionEmoji(Occasion o) {
  switch (o) {
    case Occasion.any:
      return '✨';
    case Occasion.work:
      return '💼';
    case Occasion.university:
      return '📚';
    case Occasion.outing:
      return '☕';
    case Occasion.wedding:
      return '💍';
    case Occasion.sport:
      return '🏃';
    case Occasion.evening:
      return '🌙';
  }
}

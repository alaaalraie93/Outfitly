import 'package:flutter/material.dart';

import '../l10n.dart';
import '../state.dart';
import '../widgets/common.dart';

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
    final look = list.isEmpty ? null : list[pick % list.length];
    final w = s.weather;
    final name = s.profile.name.trim();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(name.isEmpty ? context.tr('hello') : '${context.tr('hello')} $name', style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
              Text(context.tr('today_title'), style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    loadingWeather
                        ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Icon(_weatherIcon(s), size: 30, color: scheme.onSecondaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (w != null && w.isToday)
                            Text('${w.tempC.round()}°C · ${s.profile.city}',
                                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSecondaryContainer))
                          else
                            Text(
                              s.profile.lat == null ? context.tr('weather_add_city') : context.tr('weather_offline'),
                              style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
                            ),
                          Text('${context.tr('picked_for')} ${context.tr('season_${season.name}')}',
                              style: TextStyle(color: scheme.onSecondaryContainer.withValues(alpha: 0.8))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (look == null)
                EmptyState(icon: Icons.wb_sunny_outlined, text: context.tr('need_more_items'))
              else ...[
                OutfitStage(look: look, height: 420),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        onPressed: list.length > 1 ? () => setState(() => pick++) : null,
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
            ],
          ),
        ),
      ),
    );
  }
}

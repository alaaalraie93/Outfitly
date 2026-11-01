import 'package:flutter/material.dart';

import '../l10n.dart';
import '../matching.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import '../widgets/outfit_board.dart';

/// Month calendar: what you wore (solid) and what you planned (dashed).
class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  static const _monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  static const _monthsAr = ['كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول'];
  static const _daysEn = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
  static const _daysAr = ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final ar = s.profile.lang == 'ar';
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final offset = first.weekday - 1; // Monday first
    final cells = offset + daysInMonth;
    final rows = (cells / 7).ceil();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${(ar ? _monthsAr : _monthsEn)[month.month - 1]} ${month.year}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final d in (ar ? _daysAr : _daysEn))
              Expanded(
                child: Center(child: Text(d, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (int r = 0; r < rows; r++)
          Row(
            children: [
              for (int c = 0; c < 7; c++)
                Expanded(
                  child: Builder(builder: (context) {
                    final index = r * 7 + c - offset + 1;
                    if (index < 1 || index > daysInMonth) return const SizedBox(height: 64);
                    final day = DateTime(month.year, month.month, index);
                    return _DayCell(
                      day: day,
                      isToday: AppState.dateKey(day) == AppState.dateKey(today),
                      onTap: () => showDaySheet(context, day),
                    );
                  }),
                ),
            ],
          ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _Legend(solid: true, label: context.tr('cal_worn')),
            _Legend(solid: false, label: context.tr('cal_planned')),
          ],
        ),
        const SizedBox(height: 8),
        Text(context.tr('cal_hint'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final VoidCallback onTap;
  const _DayCell({required this.day, required this.isToday, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final worn = s.wornOn(day);
    final plan = worn == null ? s.planFor(day) : null;
    final log = worn ?? plan;
    final look = log == null ? null : s.lookFromLog(log);
    final thumb = look == null || look.isEmpty ? null : look.items.first;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isToday ? scheme.primaryContainer : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            border: plan != null
                ? Border.all(color: scheme.primary, width: 1.5, strokeAlign: BorderSide.strokeAlignInside)
                : null,
          ),
          child: Column(
            children: [
              const SizedBox(height: 3),
              Text('${day.day}', style: TextStyle(fontSize: 12, fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
              const SizedBox(height: 2),
              if (thumb != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                    child: Opacity(opacity: plan != null ? 0.7 : 1, child: ItemImage(item: thumb, radius: 8)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final bool solid;
  final String label;
  const _Legend({required this.solid, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: solid ? scheme.secondary : Colors.transparent,
            border: Border.all(color: scheme.primary, width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

/// What happened (or is planned) on one day, with actions.
Future<void> showDaySheet(BuildContext context, DateTime day) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _DaySheet(day: day),
  );
}

class _DaySheet extends StatelessWidget {
  final DateTime day;
  const _DaySheet({required this.day});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final todayKey = AppState.dateKey(DateTime.now());
    final key = AppState.dateKey(day);
    final future = key.compareTo(todayKey) > 0;
    final worn = s.wornOn(day);
    final plan = s.planFor(day);
    final log = worn ?? plan;
    final look = log == null ? null : s.lookFromLog(log);
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(key, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(
              worn != null ? context.tr('cal_worn') : (plan != null ? context.tr('cal_planned') : context.tr('cal_nothing')),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (look != null && !look.isEmpty) OutfitBoard(look: look, height: 300),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    final chosen = await pickLook(context, day);
                    if (chosen == null) return;
                    if (future) {
                      s.setPlan(day, chosen);
                    } else {
                      s.wearOn(day, chosen);
                    }
                  },
                  icon: Icon(future ? Icons.event_note : Icons.checkroom),
                  label: Text(context.tr(future ? 'cal_plan' : 'cal_set_worn')),
                ),
                if (plan != null && !future && worn == null)
                  OutlinedButton.icon(
                    onPressed: () => s.wearOn(day, s.lookFromLog(plan)),
                    icon: const Icon(Icons.check),
                    label: Text(context.tr('cal_wore_plan')),
                  ),
                if (log != null)
                  TextButton.icon(
                    onPressed: () {
                      if (worn != null) {
                        s.clearWorn(day);
                      } else {
                        s.clearPlan(day);
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: Text(context.tr('remove')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the user choose a look: today's suggestions for that day's season, or a saved outfit.
Future<Look?> pickLook(BuildContext context, DateTime day) {
  final s = AppScope.read(context);
  final suggestions = s.suggestions(seasonForDate(day), limit: 8);
  final saved = s.outfits.map(s.lookOf).where((l) => l.clothes.isNotEmpty).toList();
  return showModalBottomSheet<Look>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (suggestions.isNotEmpty) ...[
            Text(ctx.tr('cal_suggested'), style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final l in suggestions) _LookRow(look: l, onTap: () => Navigator.pop(ctx, l)),
          ],
          if (saved.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(ctx.tr('saved_outfits'), style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final l in saved) _LookRow(look: l, onTap: () => Navigator.pop(ctx, l)),
          ],
          if (suggestions.isEmpty && saved.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(ctx.tr('need_more_items'))),
        ],
      ),
    ),
  );
}

class _LookRow extends StatelessWidget {
  final Look look;
  final VoidCallback onTap;
  const _LookRow({required this.look, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final score = s.lookScore(look)?.score;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              for (final it in look.items)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: SizedBox(width: 48, height: 48, child: ItemImage(item: it, radius: 10)),
                ),
              const Spacer(),
              if (score != null)
                Text('$score%', style: TextStyle(fontWeight: FontWeight.w800, color: scoreColor(score))),
            ],
          ),
        ),
      ),
    );
  }
}

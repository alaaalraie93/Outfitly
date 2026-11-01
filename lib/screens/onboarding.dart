import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/sky.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final name = TextEditingController();
  final age = TextEditingController(text: '25');
  final height = TextEditingController(text: '168');
  final weight = TextEditingController(text: '62');

  @override
  void dispose() {
    name.dispose();
    age.dispose();
    height.dispose();
    weight.dispose();
    super.dispose();
  }

  void _setBody(BodyType b) {
    final s = AppScope.read(context);
    s.updateProfile((p) => p.bodyType = b);
    if (b == BodyType.kids) {
      age.text = '8';
      height.text = '128';
      weight.text = '26';
    } else if (b == BodyType.boy) {
      age.text = '25';
      height.text = '178';
      weight.text = '75';
    } else {
      age.text = '25';
      height.text = '165';
      weight.text = '60';
    }
  }

  void _start() {
    final s = AppScope.read(context);
    s.updateProfile((p) {
      p.name = name.text.trim();
      p.age = int.tryParse(age.text.trim()) ?? p.age;
      p.heightCm = double.tryParse(height.text.trim()) ?? p.heightCm;
      p.weightKg = double.tryParse(weight.text.trim()) ?? p.weightKg;
      p.onboarded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            const Align(alignment: AlignmentDirectional.centerStart, child: OutfitlyLogo(size: 84)),
            const SizedBox(height: 22),
            GradientText(context.tr('welcome_title'), style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(context.tr('welcome_sub'), style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
            Text(context.tr('tagline'), style: text.bodyMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 28),
            Text(context.tr('choose_language'), style: text.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ar', label: Text('العربية')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {s.profile.lang},
              onSelectionChanged: (v) => s.updateProfile((p) => p.lang = v.first),
            ),
            const SizedBox(height: 24),
            Text(context.tr('choose_profile'), style: text.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final b in BodyType.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _BodyCard(
                        icon: b == BodyType.girl ? Icons.woman : (b == BodyType.boy ? Icons.man : Icons.child_care),
                        label: context.tr(b.name),
                        selected: s.profile.bodyType == b,
                        onTap: () => _setBody(b),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(controller: name, decoration: InputDecoration(labelText: context.tr('your_name'), border: const OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _num(age, context.tr('age'))),
                const SizedBox(width: 8),
                Expanded(child: _num(height, context.tr('height_cm'))),
                const SizedBox(width: 8),
                Expanded(child: _num(weight, context.tr('weight_kg'))),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: _start,
              child: Text(context.tr('start'), style: const TextStyle(fontSize: 17)),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _num(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      );
}

class _BodyCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _BodyCard({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? null : scheme.surface.withValues(alpha: 0.85),
          gradient: selected ? Sky.brand : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.transparent : scheme.outlineVariant, width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: selected ? Colors.white : scheme.onSurfaceVariant),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : scheme.onSurface)),
          ],
        ),
      ),
    );
  }
}

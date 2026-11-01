import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import '../widgets/sky.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController name;
  late final TextEditingController age;
  late final TextEditingController height;
  late final TextEditingController weight;
  late final TextEditingController city;
  bool findingCity = false;

  @override
  void initState() {
    super.initState();
    final p = AppScope.read(context).profile;
    name = TextEditingController(text: p.name);
    age = TextEditingController(text: p.age.toString());
    height = TextEditingController(text: p.heightCm.round().toString());
    weight = TextEditingController(text: p.weightKg.round().toString());
    city = TextEditingController(text: p.city);
  }

  @override
  void dispose() {
    name.dispose();
    age.dispose();
    height.dispose();
    weight.dispose();
    city.dispose();
    super.dispose();
  }

  void _saveNumbers() {
    AppScope.read(context).updateProfile((p) {
      p.name = name.text.trim();
      p.age = int.tryParse(age.text.trim()) ?? p.age;
      p.heightCm = double.tryParse(height.text.trim()) ?? p.heightCm;
      p.weightKg = double.tryParse(weight.text.trim()) ?? p.weightKg;
    });
  }

  Future<void> _pickFace() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 900, imageQuality: 90);
    if (x == null || !mounted) return;
    final s = AppScope.read(context);
    await s.setFacePhoto(x.path);
  }

  Future<void> _findCity() async {
    final q = city.text.trim();
    if (q.isEmpty) return;
    setState(() => findingCity = true);
    final s = AppScope.read(context);
    final ok = await s.setCity(q);
    if (!mounted) return;
    setState(() => findingCity = false);
    if (ok) city.text = s.profile.city;
    showSnack(context, context.tr(ok ? 'city_found' : 'city_not_found'));
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ctx.tr('reset_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('delete'))),
        ],
      ),
    );
    if (ok == true && mounted) await AppScope.read(context).resetAll();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.profile;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final face = p.facePath;

    Widget title(String t) => Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 8),
          child: Text(t, style: text.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
        );

    Widget num(TextEditingController c, String label) => TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          onChanged: (_) => _saveNumbers(),
        );

    return Scaffold(
      appBar: AppBar(title: BrandTitle(context.tr('profile_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Container(
                  height: 230,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(gradient: Sky.brand, borderRadius: BorderRadius.circular(24)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        p.bodyType == BodyType.girl ? Icons.woman : (p.bodyType == BodyType.boy ? Icons.man : Icons.child_care),
                        color: Colors.white,
                        size: 44,
                      ),
                      const Spacer(),
                      Text(p.name.isEmpty ? context.tr(p.bodyType.name) : p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('${p.heightCm.round()} cm · ${p.weightKg.round()} kg · ${p.age}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                      Text('${s.items.length} · ${context.tr('tab_wardrobe')}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('face_photo'), style: text.titleSmall),
                    const SizedBox(height: 8),
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: scheme.surfaceContainerHighest,
                      backgroundImage: face == null ? null : FileImage(File(face)),
                      child: face == null ? Icon(Icons.face, size: 40, color: scheme.onSurfaceVariant) : null,
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonal(onPressed: _pickFace, child: Text(context.tr('change_photo'))),
                    if (face != null)
                      TextButton(
                        onPressed: () {
                          s.setFacePhoto(null);
                        },
                        child: Text(context.tr('remove')),
                      ),
                    const SizedBox(height: 6),
                    Text(context.tr('face_tip'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          title(context.tr('language')),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ar', label: Text('العربية')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {p.lang},
            onSelectionChanged: (v) => s.updateProfile((x) => x.lang = v.first),
          ),
          title(context.tr('choose_profile')),
          SegmentedButton<BodyType>(
            segments: [
              for (final b in BodyType.values) ButtonSegment(value: b, label: Text(context.tr(b.name))),
            ],
            selected: {p.bodyType},
            onSelectionChanged: (v) => s.updateProfile((x) => x.bodyType = v.first),
          ),
          title(context.tr('body')),
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: context.tr('your_name'), border: const OutlineInputBorder()),
            onChanged: (_) => _saveNumbers(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: num(age, context.tr('age'))),
              const SizedBox(width: 8),
              Expanded(child: num(height, context.tr('height_cm'))),
              const SizedBox(width: 8),
              Expanded(child: num(weight, context.tr('weight_kg'))),
            ],
          ),
          title(context.tr('skin_tone')),
          Wrap(
            spacing: 12,
            children: [
              for (int i = 0; i < kSkinTones.length; i++)
                GestureDetector(
                  onTap: () => s.updateProfile((x) => x.skinTone = i),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: kSkinTones[i],
                      shape: BoxShape.circle,
                      border: Border.all(color: p.skinTone == i ? scheme.primary : scheme.outlineVariant, width: p.skinTone == i ? 4 : 1),
                    ),
                  ),
                ),
            ],
          ),
          title(context.tr('city')),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: city,
                  decoration: InputDecoration(hintText: context.tr('city_hint'), border: const OutlineInputBorder()),
                  onSubmitted: (_) => _findCity(),
                ),
              ),
              const SizedBox(width: 8),
              findingCity
                  ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                  : FilledButton(onPressed: _findCity, child: Text(context.tr('find'))),
            ],
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
            onPressed: _reset,
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text(context.tr('reset_all')),
          ),
          const SizedBox(height: 12),
          Center(child: Text('Outfitly v1.4.0', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12))),
        ],
      ),
    );
  }
}

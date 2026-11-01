import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../color_utils.dart';
import '../classify.dart';
import '../cutout.dart';
import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/mannequin.dart';

/// Add a new piece, or edit an existing one when [existing] is given.
class AddItemScreen extends StatefulWidget {
  final ClothingItem? existing;
  const AddItemScreen({super.key, this.existing});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  String? photoPath;
  String? originalPath;
  String? cutoutPath;
  bool analyzing = false;
  bool removingBg = false;
  bool detecting = false;
  bool autoFilled = false;
  List<int> palette = [];
  int? color;
  ClothCat category = ClothCat.top;
  String subType = 'tshirt';
  StyleLevel style = StyleLevel.casual;
  Season season = Season.summer;
  bool patterned = false;
  final name = TextEditingController();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      photoPath = e.imagePath;
      palette = e.palette.isEmpty ? [e.colorValue] : List.of(e.palette);
      color = e.colorValue;
      category = e.category;
      subType = e.subType;
      style = e.style;
      season = e.season;
      patterned = e.patterned;
      name.text = e.name;
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 1400, imageQuality: 88);
      if (x == null) return;
      setState(() {
        originalPath = x.path;
        cutoutPath = null;
        photoPath = x.path;
        removingBg = true;
      });
      final cut = await removeBackground(x.path);
      if (!mounted) return;
      setState(() {
        removingBg = false;
        cutoutPath = cut;
        if (cut != null) photoPath = cut;
      });
      if (cut == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('bg_failed')), behavior: SnackBarBehavior.floating));
      }
      await _analyze();
      await _autoFill();
    } catch (e) {
      if (mounted) {
        setState(() {
          analyzing = false;
          removingBg = false;
        });
      }
    }
  }

  Future<void> _analyze() async {
    final path = photoPath;
    if (path == null) return;
    setState(() => analyzing = true);
    final colors = await analyzeImageColors(path);
    if (!mounted) return;
    setState(() {
      palette = colors;
      color = colors.first;
      analyzing = false;
    });
  }

  /// Fills category, type, style, season and pattern from the photo.
  Future<void> _autoFill() async {
    final orig = originalPath, shape = photoPath, c = color;
    if (orig == null || shape == null || c == null) return;
    setState(() => detecting = true);
    final body = AppScope.read(context).profile.bodyType;
    final d = await classifyPhoto(originalPath: orig, shapePath: shape, mainColor: c, body: body);
    if (!mounted) return;
    setState(() {
      detecting = false;
      autoFilled = true;
      category = d.category;
      subType = d.subType;
      style = d.style;
      season = d.season;
      patterned = d.patterned;
    });
  }

  void _usePhoto(String? path) {
    if (path == null || path == photoPath) return;
    setState(() => photoPath = path);
    _analyze();
  }

  void _setCategory(ClothCat c) {
    final body = AppScope.read(context).profile.bodyType;
    setState(() {
      category = c;
      _setSub(subTypesFor(c, body).first);
    });
  }

  void _setSub(String sub) {
    subType = sub;
    style = defaultStyleFor(sub);
    season = defaultSeasonFor(sub);
  }

  Future<void> _save() async {
    final path = photoPath;
    final c = color;
    if (path == null || c == null) return;
    setState(() => saving = true);
    final s = AppScope.read(context);
    final e = widget.existing;
    if (e == null) {
      final stored = await s.storeImage(path, 'item');
      s.addItem(ClothingItem(
        id: s.newId(),
        imagePath: stored,
        category: category,
        subType: subType,
        colorValue: c,
        palette: palette,
        style: style,
        season: season,
        patterned: patterned,
        name: name.text.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
    } else {
      if (path != e.imagePath) {
        final old = e.imagePath;
        e.imagePath = await s.storeImage(path, 'item');
        UiImageStore.evict(old);
        try {
          await File(old).delete();
        } catch (_) {}
      }
      e
        ..category = category
        ..subType = subType
        ..colorValue = c
        ..palette = palette
        ..style = style
        ..season = season
        ..patterned = patterned
        ..name = name.text.trim();
      s.updateItem(e);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final body = s.profile.bodyType;
    final cats = categoriesFor(body);
    final subs = subTypesFor(category, body);
    final path = photoPath;

    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(title, style: text.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)), const SizedBox(height: 8), child],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? context.tr('add_item') : context.tr('edit'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                color: scheme.surfaceContainerHighest,
                child: path == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined, size: 48, color: scheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.icon(onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera), label: Text(context.tr('camera'))),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: Text(context.tr('gallery'))),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(context.tr('photo_tip'), textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                          ),
                        ],
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          if (path.toLowerCase().endsWith('.png'))
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(colors: [scheme.primaryContainer.withValues(alpha: 0.7), scheme.surfaceContainerHighest]),
                              ),
                              child: Padding(padding: const EdgeInsets.all(24), child: Image.file(File(path), fit: BoxFit.contain)),
                            )
                          else
                            Image.file(File(path), fit: BoxFit.cover),
                          if (cutoutPath != null && originalPath != null)
                            PositionedDirectional(
                              top: 12,
                              start: 12,
                              child: SegmentedButton<String>(
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment(value: cutoutPath!, label: Text(context.tr('photo_cutout'))),
                                  ButtonSegment(value: originalPath!, label: Text(context.tr('photo_original'))),
                                ],
                                selected: {path},
                                onSelectionChanged: (v) => _usePhoto(v.first),
                              ),
                            ),
                          if (removingBg)
                            Container(
                              color: Colors.black.withValues(alpha: 0.35),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(color: Colors.white),
                                    const SizedBox(height: 12),
                                    Text(context.tr('removing_bg'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          PositionedDirectional(
                            bottom: 12,
                            end: 12,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.filledTonal(onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera)),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library)),
                              ],
                            ),
                          ),
                          if (analyzing) const Center(child: CircularProgressIndicator()),
                        ],
                      ),
              ),
            ),
          ),
          if (palette.isNotEmpty)
            section(
              context.tr('detected_colors'),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final p in palette)
                    GestureDetector(
                      onTap: () => setState(() => color = p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Color(p),
                          shape: BoxShape.circle,
                          border: Border.all(color: color == p ? scheme.primary : scheme.outlineVariant, width: color == p ? 4 : 1),
                        ),
                      ),
                    ),
                  if (color != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(context.tr(colorKey(Color(color!))), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          if (detecting || autoFilled)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    detecting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Icon(Icons.auto_awesome, color: scheme.onPrimaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(context.tr(detecting ? 'detecting' : 'auto_filled'),
                          style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          section(
            context.tr('category'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in cats)
                  ChoiceChip(label: Text(context.tr('cat_${c.name}')), selected: category == c, onSelected: (_) => _setCategory(c)),
              ],
            ),
          ),
          section(
            context.tr('type'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sub in subs)
                  ChoiceChip(label: Text(context.tr('sub_$sub')), selected: subType == sub, onSelected: (_) => setState(() => _setSub(sub))),
              ],
            ),
          ),
          section(
            context.tr('style'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final st in StyleLevel.values)
                  ChoiceChip(label: Text(context.tr('style_${st.name}')), selected: style == st, onSelected: (_) => setState(() => style = st)),
              ],
            ),
          ),
          section(
            context.tr('season'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final se in Season.values)
                  ChoiceChip(label: Text(context.tr('season_${se.name}')), selected: season == se, onSelected: (_) => setState(() => season = se)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('patterned')),
            value: patterned,
            onChanged: (v) => setState(() => patterned = v),
          ),
          const SizedBox(height: 8),
          TextField(controller: name, decoration: InputDecoration(labelText: context.tr('name_optional'), border: const OutlineInputBorder())),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: (path == null || color == null || analyzing || removingBg || detecting || saving) ? null : _save,
            icon: const Icon(Icons.check),
            label: Text(context.tr('save')),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/about_repository.dart';
import '../../../domain/models/about_um_model.dart';
import '../../widgets/form_input.dart';
import '../../widgets/tag_input.dart';

class AboutUmScreen extends StatefulWidget {
  const AboutUmScreen({super.key});

  @override
  State<AboutUmScreen> createState() => _AboutUmScreenState();
}

class _AboutUmScreenState extends State<AboutUmScreen> {
  final _repo = AboutRepository();

  final _mission = TextEditingController();
  final _vision = TextEditingController();
  final _founded = TextEditingController();
  final _campusSize = TextEditingController();
  final _location = TextEditingController();
  final _ranking = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _facebook = TextEditingController();
  final _instagram = TextEditingController();
  final _twitter = TextEditingController();
  List<String> _coreValues = [];

  bool _loading = true;
  bool _saving = false;
  Object? _error;
  String? _existingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _mission,
      _vision,
      _founded,
      _campusSize,
      _location,
      _ranking,
      _phone,
      _email,
      _website,
      _facebook,
      _instagram,
      _twitter,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final about = await _repo.get();
      if (about != null) {
        _existingId = about.id;
        _mission.text = about.mission ?? '';
        _vision.text = about.vision ?? '';
        _founded.text = about.founded?.toString() ?? '';
        _campusSize.text = about.campusSize ?? '';
        _location.text = about.location ?? '';
        _ranking.text = about.ranking ?? '';
        _phone.text = about.phone ?? '';
        _email.text = about.email ?? '';
        _website.text = about.website ?? '';
        _facebook.text = about.facebook ?? '';
        _instagram.text = about.instagram ?? '';
        _twitter.text = about.twitter ?? '';
        _coreValues = List.of(about.coreValues);
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final model = AboutUmModel(
        id: _existingId,
        mission: _mission.text.trim(),
        vision: _vision.text.trim(),
        coreValues: _coreValues,
        founded: int.tryParse(_founded.text.trim()),
        campusSize: _campusSize.text.trim(),
        location: _location.text.trim(),
        ranking: _ranking.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        website: _website.text.trim(),
        facebook: _facebook.text.trim(),
        instagram: _instagram.text.trim(),
        twitter: _twitter.text.trim(),
      );
      final saved = await _repo.upsert(model);
      setState(() => _existingId = saved.id);
      if (mounted) context.showSuccess('About UM info saved successfully!');
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error.toString()),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: _form()),
        const SizedBox(width: 20),
        SizedBox(width: 320, child: _preview()),
      ],
    );
  }

  Widget _form() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section('Mission & Vision', [
            FormInput(label: 'Mission', controller: _mission, maxLines: 3),
            const SizedBox(height: 12),
            FormInput(label: 'Vision', controller: _vision, maxLines: 3),
          ]),
          _section('Core Values', [
            TagInput(
              label: 'Core Values',
              initialTags: _coreValues,
              onChanged: (v) => setState(() => _coreValues = v),
            ),
          ]),
          _section('Key Facts', [
            Row(
              children: [
                Expanded(child: FormInput(label: 'Founded', controller: _founded)),
                const SizedBox(width: 12),
                Expanded(
                    child: FormInput(
                        label: 'Campus Size', controller: _campusSize)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: FormInput(label: 'Location', controller: _location)),
                const SizedBox(width: 12),
                Expanded(
                    child: FormInput(label: 'Ranking', controller: _ranking)),
              ],
            ),
          ]),
          _section('Contact Info', [
            Row(
              children: [
                Expanded(child: FormInput(label: 'Phone', controller: _phone)),
                const SizedBox(width: 12),
                Expanded(child: FormInput(label: 'Email', controller: _email)),
              ],
            ),
            const SizedBox(height: 12),
            FormInput(label: 'Website', controller: _website),
          ]),
          _section('Social Media', [
            FormInput(label: 'Facebook', controller: _facebook),
            const SizedBox(height: 12),
            FormInput(label: 'Instagram', controller: _instagram),
            const SizedBox(height: 12),
            FormInput(label: 'Twitter / X', controller: _twitter),
          ]),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save, size: 18),
              label: Text(_saving ? 'Saving…' : 'Save All'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _preview() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Mobile App Preview',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.backgroundGray,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryMaroon,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('About UM Matina',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                _previewBlock('Mission', _mission.text),
                _previewBlock('Vision', _vision.text),
                if (_coreValues.isNotEmpty) ...[
                  const Text('Core Values',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final v in _coreValues)
                        Chip(
                          label: Text(v, style: const TextStyle(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                _previewBlock('Founded', _founded.text),
                _previewBlock('Location', _location.text),
                _previewBlock('Contact', _phone.text),
                _previewBlock('Email', _email.text),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewBlock(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

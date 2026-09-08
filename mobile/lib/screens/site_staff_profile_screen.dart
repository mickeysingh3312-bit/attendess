import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/site_staff_api.dart';

class SiteStaffProfileScreen extends StatefulWidget {
  final VoidCallback? onProfileSaved;
  const SiteStaffProfileScreen({super.key, this.onProfileSaved});

  @override
  State<SiteStaffProfileScreen> createState() => _SiteStaffProfileScreenState();
}

class _SiteStaffProfileScreenState extends State<SiteStaffProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _dob = TextEditingController();
  final _address = TextEditingController();
  final _whiteCard = TextEditingController();
  final _hrwNumber = TextEditingController();
  final _hrwExpiry = TextEditingController();
  final _silica = TextEditingController();
  final _kin = TextEditingController();
  final _kinMobile = TextEditingController();
  final _medical = TextEditingController();

  Map<String, dynamic>? _profile;
  Map<String, dynamic> _options = {};
  String? _subcontractorId;
  String? _photoIdType;
  final Set<String> _roles = {};
  final Set<String> _statuses = {'ACTIVE'};
  final Map<String, PlatformFile?> _files = {};
  final Map<String, bool> _remove = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _updating => _profile != null;
  bool get _isLabourer => _roles.contains('Labourer - Site Construction');
  bool get _isScaffolder => _roles.contains('Scaffolder & HRW ticket holders');
  bool get _needsHrw => _isLabourer || _isScaffolder;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [_name, _email, _mobile, _dob, _address, _whiteCard, _hrwNumber, _hrwExpiry, _silica, _kin, _kinMobile, _medical]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await SiteStaffApi().profile();
      final profile = data['profile'] is Map ? Map<String, dynamic>.from(data['profile'] as Map) : null;
      final options = data['options'] is Map ? Map<String, dynamic>.from(data['options'] as Map) : <String, dynamic>{};
      _profile = profile;
      _options = options;
      _email.text = (data['verified_email'] ?? profile?['email'] ?? '').toString();
      if (profile != null) _fill(profile);
    } catch (e) {
      _error = _clean(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fill(Map<String, dynamic> p) {
    _name.text = (p['site_access_staff_name'] ?? '').toString();
    _mobile.text = (p['mobile'] ?? '').toString();
    _dob.text = (p['date_of_birth'] ?? '').toString();
    _address.text = (p['home_address'] ?? '').toString();
    _whiteCard.text = (p['white_card_number'] ?? '').toString();
    _hrwNumber.text = (p['hrw_number'] ?? '').toString();
    _hrwExpiry.text = (p['hrw_expiry_date'] ?? '').toString();
    _silica.text = (p['silica_certificate_number'] ?? '').toString();
    _kin.text = (p['next_of_kin'] ?? '').toString();
    _kinMobile.text = (p['next_of_kin_mobile'] ?? '').toString();
    _medical.text = (p['medical_conditions'] ?? '').toString();
    _photoIdType = (p['photo_id_type'] ?? '').toString().isEmpty ? null : p['photo_id_type'].toString();
    _roles..clear()..addAll(_stringList(p['scaffolder_or_labourer']));
    _statuses..clear()..addAll(_stringList(p['status']));
    if (_statuses.isEmpty) _statuses.add('ACTIVE');
    final subs = _stringList(p['subcontractor_record_ids']);
    _subcontractorId = subs.isEmpty ? null : subs.first;
    _files.clear();
    _remove.clear();
  }

  List<String> _stringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    return const [];
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _pick(String key) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf']);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    if (f.size > 5 * 1024 * 1024) {
      _show('Each attachment must be 5 MB or smaller.');
      return;
    }
    setState(() { _files[key] = f; _remove[key == 'photo_id' ? 'remove_photo_id' : 'remove_$key'] = false; });
  }

  Future<void> _pickDate(TextEditingController controller, {bool future = false}) async {
    final now = DateTime.now();
    DateTime initial = DateTime.tryParse(controller.text) ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: future ? DateTime(now.year - 1) : DateTime(1940),
      lastDate: future ? DateTime(now.year + 20) : now,
    );
    if (date != null) controller.text = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_roles.isEmpty) { _show('Please select a staff role.'); return; }
    if (_subcontractorId == null || _subcontractorId!.isEmpty) { _show('Please select your subcontractor.'); return; }
    if (!_updating && _files['photo_id'] == null) { _show('Photo ID is required.'); return; }
    if (_isLabourer && !_updating && _files['white_card_photo'] == null) { _show('White Card Photo is required.'); return; }
    if (_needsHrw && !_updating && _files['hrw_photo'] == null) { _show('HRW Photo is required.'); return; }

    setState(() { _saving = true; _error = null; });
    try {
      final fields = <String, String>{
        'site_access_staff_name': _name.text.trim(),
        'mobile': _mobile.text.trim(),
        'subcontractor_record_id': _subcontractorId!,
        'scaffolder_or_labourer': jsonEncode(_roles.toList()),
        'status': jsonEncode(_statuses.isEmpty ? ['ACTIVE'] : _statuses.toList()),
        'photo_id_type': _photoIdType ?? '',
        'date_of_birth': _dob.text.trim(),
        'home_address': _address.text.trim(),
        'white_card_number': _whiteCard.text.trim(),
        'hrw_number': _hrwNumber.text.trim(),
        'hrw_expiry_date': _hrwExpiry.text.trim(),
        'silica_certificate_number': _silica.text.trim(),
        'next_of_kin': _kin.text.trim(),
        'next_of_kin_mobile': _kinMobile.text.trim(),
        'medical_conditions': _medical.text.trim(),
      };
      final data = await SiteStaffApi().saveProfile(updating: _updating, fields: fields, files: _files, removeFlags: _remove);
      final p = data['profile'];
      if (p is Map) _profile = Map<String, dynamic>.from(p);
      if (_profile != null) _fill(_profile!);
      if (!mounted) return;
      _show(_updating ? 'Profile updated in Airtable.' : 'Profile created in Airtable.');
      widget.onProfileSaved?.call();
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();
  void _show(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;

  Widget _text(String label, TextEditingController controller, {bool required = false, int lines = 1, TextInputType? keyboard}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      maxLines: lines,
      keyboardType: keyboard,
      validator: required ? _required : null,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    ),
  );

  Widget _date(String label, TextEditingController controller, {bool required = false, bool future = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      readOnly: true,
      validator: required ? _required : null,
      onTap: () => _pickDate(controller, future: future),
      decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_month), border: const OutlineInputBorder()),
    ),
  );

  Widget _fileField(String key, String label, dynamic existing, {bool required = false}) {
    final existingFiles = _mapList(existing);
    final selected = _files[key];
    final removeKey = key == 'photo_id' ? 'remove_photo_id' : 'remove_$key';
    final removed = _remove[removeKey] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('$label${required ? ' *' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (existingFiles.isNotEmpty && !removed) ...[
            const SizedBox(height: 8),
            for (final file in existingFiles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.attach_file),
                title: Text((file['filename'] ?? 'Attachment').toString()),
                trailing: IconButton(
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () async { final url = Uri.tryParse((file['url'] ?? '').toString()); if (url != null) await launchUrl(url, mode: LaunchMode.externalApplication); },
                ),
              ),
          ],
          if (selected != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Selected: ${selected.name}', style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _saving ? null : () => _pick(key), icon: const Icon(Icons.upload_file), label: Text(existingFiles.isEmpty ? 'Choose file' : 'Replace file')),
          if (_updating && existingFiles.isNotEmpty)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: removed,
              onChanged: _saving ? null : (v) => setState(() => _remove[removeKey] = v == true),
              title: const Text('Remove current attachment'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _options.isEmpty) {
      return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(18), children: [const SizedBox(height: 70), const Icon(Icons.cloud_off, size: 52), const SizedBox(height: 16), Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 14), FilledButton(onPressed: _load, child: const Text('Retry'))]));
    }

    final roles = _stringList(_options['roles']);
    final photoTypes = _stringList(_options['photo_id_types']);
    final subcontractors = _mapList(_options['subcontractors']);
    final p = _profile ?? const <String, dynamic>{};

    return RefreshIndicator(
      onRefresh: _load,
      child: Form(
        key: _formKey,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
          children: [
            Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_updating ? 'My Site Access profile' : 'Complete your Site Access profile', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(_updating ? 'This information is loaded from Airtable. Changes are saved directly back to Airtable.' : 'Your email is verified. Complete this form before automatic attendance is enabled.'),
            ]))),
            const SizedBox(height: 16),
            _text('Site Access Staff Name', _name, required: true),
            TextFormField(controller: _email, readOnly: true, decoration: const InputDecoration(labelText: 'Verified email', prefixIcon: Icon(Icons.verified), border: OutlineInputBorder())),
            const SizedBox(height: 14),
            _text('Mobile', _mobile, keyboard: TextInputType.phone),
            DropdownButtonFormField<String>(
              value: subcontractors.any((e) => e['id']?.toString() == _subcontractorId) ? _subcontractorId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Subcontractor', border: OutlineInputBorder()),
              items: subcontractors.map((e) => DropdownMenuItem(value: e['id'].toString(), child: Text(e['name'].toString(), overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _saving ? null : (v) => setState(() => _subcontractorId = v),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 18),
            Text('Role *', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final role in roles)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _roles.contains(role),
                title: Text(role),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: _saving ? null : (v) => setState(() { if (v == true) { _roles.add(role); } else { _roles.remove(role); } }),
              ),
            const SizedBox(height: 10),
            _fileField('photo_id', 'Photo ID', p['photo_id'], required: true),
            DropdownButtonFormField<String>(
              value: photoTypes.contains(_photoIdType) ? _photoIdType : null,
              decoration: const InputDecoration(labelText: 'Photo ID Type', border: OutlineInputBorder()),
              items: photoTypes.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
              onChanged: _saving ? null : (v) => setState(() => _photoIdType = v),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            _date('Date of Birth', _dob, required: true),
            _text('Home Address', _address, required: true, lines: 3),
            if (_isLabourer) ...[
              _text('White Card Number', _whiteCard, required: true),
              _fileField('white_card_photo', 'White Card Photo', p['white_card_photo'], required: true),
            ],
            if (_needsHrw) ...[
              _text('HRW Number', _hrwNumber, required: true, lines: 2),
              _date('HRW Expiry Date', _hrwExpiry, required: true, future: true),
              _fileField('hrw_photo', 'HRW Photo', p['hrw_photo'], required: true),
              _text('Silica Certificate Number', _silica),
              _fileField('silica_certificate', 'Silica Certificate', p['silica_certificate']),
              _fileField('other_tickets_and_licenses', 'Other Tickets and Licenses', p['other_tickets_and_licenses']),
              _text('Next of Kin', _kin),
              _text('Next of Kin Mobile', _kinMobile, keyboard: TextInputType.phone),
              _text('Medical Conditions', _medical, required: true, lines: 3),
            ],
            const SizedBox(height: 4),
            Text('Status', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: _statuses.contains('ACTIVE'), title: const Text('ACTIVE'), controlAffinity: ListTileControlAffinity.leading, onChanged: _saving ? null : (v) => setState(() { _statuses.clear(); if (v == true) _statuses.add('ACTIVE'); })),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: _statuses.contains('INACTIVE'), title: const Text('INACTIVE'), controlAffinity: ListTileControlAffinity.leading, onChanged: _saving ? null : (v) => setState(() { _statuses.clear(); if (v == true) _statuses.add('INACTIVE'); })),
            if (_error != null) Container(margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)), child: Text(_error!)),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
              label: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(_saving ? 'Saving...' : (_updating ? 'Save changes to Airtable' : 'Create Site Access profile'))),
            ),
          ],
        ),
      ),
    );
  }
}

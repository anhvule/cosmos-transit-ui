import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/user_profile.dart';
import '../../services/prediction_api_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/place_autocomplete_field.dart';

/// Saved-profiles manager.
///
/// Lists every profile the user has saved locally; the active one (the
/// chart the rest of the app uses) is highlighted. Tapping a row makes it
/// active. Long-press / trailing menu deletes. The "+" button opens a
/// modal form to add a new profile, prefilled with sensible defaults so
/// the user can save the request data with minimal typing.
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  late List<MapEntry<String, UserProfile>> _profiles;
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _profiles = StorageService.getAllProfiles();
      _activeId = StorageService.getActiveProfileId();
    });
  }

  Future<void> _activate(String id) async {
    await StorageService.setActiveProfileId(id);
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Active profile updated')),
    );
  }

  Future<void> _delete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1840),
        title: const Text('Delete profile?',
            style: TextStyle(color: Colors.white)),
        content: Text('Remove "$name" from saved profiles?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await StorageService.deleteProfile(id);
    _reload();
  }

  Future<void> _openForm({String? editingId, UserProfile? initial}) async {
    final saved = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1840),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ProfileForm(initial: initial),
    );
    if (saved == null) return;
    if (editingId != null) {
      await StorageService.updateProfile(editingId, saved);
    } else {
      await StorageService.addProfile(saved);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0B2E),
        elevation: 0,
        title: const Text('Saved Profiles',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _profiles.isEmpty
          ? _empty()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _profiles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final entry = _profiles[i];
                final p = entry.value;
                final isActive = entry.key == _activeId;
                return _profileTile(entry.key, p, isActive);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF7C4DFF),
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add profile'),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🌌', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          const Text(
            'No saved profiles yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Save a chart so you don\'t have to re-enter birth data every time.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileTile(String id, UserProfile p, bool isActive) {
    final tzLabel = p.timezone >= 0 ? 'UTC+${p.timezone}' : 'UTC${p.timezone}';
    final dateStr = DateFormat('yyyy-MM-dd').format(p.birthDate);
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF7C4DFF).withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? const Color(0xFF7C4DFF)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Row(
          children: [
            Expanded(
              child: Text(
                p.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            if (isActive)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$dateStr · ${p.birthTime} · ${p.birthCity} · $tzLabel',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
            ),
          ),
        ),
        trailing: PopupMenuButton<String>(
          color: const Color(0xFF1A1840),
          icon: const Icon(Icons.more_vert, color: Colors.white70),
          onSelected: (value) {
            if (value == 'edit') _openForm(editingId: id, initial: p);
            if (value == 'delete') _delete(id, p.name);
            if (value == 'activate') _activate(id);
          },
          itemBuilder: (_) => [
            if (!isActive)
              const PopupMenuItem(
                value: 'activate',
                child: Text('Set active',
                    style: TextStyle(color: Colors.white)),
              ),
            const PopupMenuItem(
              value: 'edit',
              child: Text('Edit', style: TextStyle(color: Colors.white)),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        onTap: isActive ? null : () => _activate(id),
      ),
    );
  }
}

/// Add/edit form, opened as a modal bottom sheet. Returns the saved
/// UserProfile via Navigator.pop, or null on cancel.
class _ProfileForm extends StatefulWidget {
  final UserProfile? initial;

  const _ProfileForm({this.initial});

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  late final TextEditingController _name;
  late DateTime _birthDate;
  late TimeOfDay _birthTime;
  late final TextEditingController _city;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late final TextEditingController _tz;

  /// Topics the user wants this profile to show in the predictions tabs.
  /// Stored as `PredictionArea.name` strings to round-trip into Hive
  /// without needing a custom adapter for the enum.
  late Set<String> _topics;

  String? _tzError;
  String? _coordError;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    // Defaults for "save new profile" tap from a fresh app are taken from
    // the user's most recent API request payload — minimum friction to
    // capture what they were already typing into the predictions form.
    _name = TextEditingController(text: p?.name ?? 'A');
    _birthDate = p?.birthDate ?? DateTime(1991, 9, 13);
    _birthTime = p != null ? _parseTime(p.birthTime) : const TimeOfDay(hour: 15, minute: 30);
    _city = TextEditingController(text: p?.birthCity ?? 'Pangasinan');
    _lat = TextEditingController(text: p?.latitude.toString() ?? '16.0427');
    _lng = TextEditingController(text: p?.longitude.toString() ?? '120.7946');
    _tz = TextEditingController(text: (p?.timezone ?? 8).toString());
    // Empty list (legacy default) means "all topics enabled".
    final initialTopics = p?.topics ?? const <String>[];
    _topics = initialTopics.isEmpty
        ? PredictionArea.values.map((a) => a.name).toSet()
        : initialTopics.toSet();
  }

  static TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return TimeOfDay(hour: h, minute: m);
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _lat.dispose();
    _lng.dispose();
    _tz.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _pickTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _birthTime);
    if (picked != null) setState(() => _birthTime = picked);
  }

  int? _parseTimezone() {
    final raw = _tz.text.trim().replaceFirst(RegExp(r'^\+'), '');
    if (raw.isEmpty) {
      setState(() => _tzError = 'Required');
      return null;
    }
    final n = int.tryParse(raw);
    if (n == null) {
      setState(() => _tzError = 'Whole number only (e.g. 7)');
      return null;
    }
    if (n < -12 || n > 14) {
      setState(() => _tzError = 'Range -12 to 14');
      return null;
    }
    setState(() => _tzError = null);
    return n;
  }

  void _save() {
    final tz = _parseTimezone();
    if (tz == null) return;
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null) {
      setState(() => _coordError = 'Latitude and longitude must be numbers');
      return;
    }
    setState(() => _coordError = null);
    final timeStr =
        '${_birthTime.hour.toString().padLeft(2, '0')}:${_birthTime.minute.toString().padLeft(2, '0')}';
    // If every topic is selected, store an empty list (= "all") so the
    // model stays compact and the legacy/default reading keeps working.
    final allCount = PredictionArea.values.length;
    final topicsToSave = _topics.length == allCount
        ? const <String>[]
        : _topics.toList();
    final profile = UserProfile(
      name: _name.text.trim().isEmpty ? 'Untitled' : _name.text.trim(),
      birthDate: _birthDate,
      birthTime: timeStr,
      birthCity: _city.text.trim(),
      latitude: lat,
      longitude: lng,
      timezone: tz,
      topics: topicsToSave,
    );
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? 'Add profile' : 'Edit profile',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _field('Name', _name),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _readonlyField(
                    label: 'Birth date',
                    value: DateFormat('yyyy-MM-dd').format(_birthDate),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _readonlyField(
                    label: 'Birth time',
                    value:
                        '${_birthTime.hour.toString().padLeft(2, '0')}:${_birthTime.minute.toString().padLeft(2, '0')}',
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // City autocomplete (Photon / OpenStreetMap). Picking a
            // suggestion auto-fills lat/lng below — same UX as the
            // predictions form so the user doesn't have to "Find" first.
            PlaceAutocompleteField(
              controller: _city,
              label: 'Birth city',
              onPicked: (s) {
                setState(() {
                  _lat.text = s.latitude.toStringAsFixed(7);
                  _lng.text = s.longitude.toStringAsFixed(7);
                });
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _field('Latitude', _lat,
                      keyboard: const TextInputType.numberWithOptions(
                          signed: true, decimal: true)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _field('Longitude', _lng,
                      keyboard: const TextInputType.numberWithOptions(
                          signed: true, decimal: true)),
                ),
              ],
            ),
            if (_coordError != null) ...[
              const SizedBox(height: 4),
              Text(_coordError!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            _field(
              'UTC offset (h)',
              _tz,
              keyboard: const TextInputType.numberWithOptions(signed: true),
              error: _tzError,
              helper: 'e.g. 7 for Vietnam, 8 for Philippines, -5 for US Eastern',
            ),
            const SizedBox(height: 18),
            // Topic multi-select. The predictions screen filters its tabs
            // to only the topics this profile has enabled — leave them
            // all on if you want the full set.
            const Text(
              'Topics shown in predictions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PredictionArea.values.map((a) {
                final selected = _topics.contains(a.name);
                return FilterChip(
                  label: Text(a.label),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _topics.add(a.name);
                    } else {
                      _topics.remove(a.name);
                    }
                  }),
                  showCheckmark: false,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  selectedColor: const Color(0xFF7C4DFF).withValues(alpha: 0.35),
                  side: BorderSide(
                    color: selected
                        ? const Color(0xFF7C4DFF)
                        : Colors.white.withValues(alpha: 0.2),
                  ),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
            if (_topics.isEmpty) ...[
              const SizedBox(height: 4),
              const Text(
                'Pick at least one topic.',
                style: TextStyle(color: Colors.red, fontSize: 11),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _topics.isEmpty ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C4DFF),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          const Color(0xFF7C4DFF).withValues(alpha: 0.3),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {TextInputType? keyboard, String? error, String? helper}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: Colors.white70, fontSize: 12),
        helperText: helper,
        helperStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
        errorText: error,
        errorStyle: const TextStyle(fontSize: 11),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF7C4DFF)),
        ),
      ),
    );
  }

  Widget _readonlyField(
      {required String label, required String value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

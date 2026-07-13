import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/favourite.dart';
import '../../services/prediction_api_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/cosmic_loader.dart';

/// Per-user transit-date bookmarks with a memory note. Backed by
/// /api/favourites — list, add, delete. Identity is the device key from
/// StorageService (no auth).
class FavouritesScreen extends StatefulWidget {
  /// Optional pre-filled date for the "add" dialog when this screen is opened
  /// from another screen with a date in context (e.g. tapping a bookmark
  /// icon on a transit-detail view in the future).
  final DateTime? prefilledDate;

  const FavouritesScreen({super.key, this.prefilledDate});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  late final String _userKey;
  bool _loading = false;
  String? _error;
  List<Favourite> _items = const [];

  @override
  void initState() {
    super.initState();
    _userKey = StorageService.getDeviceKey();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refresh();
      if (!mounted) return;
      if (widget.prefilledDate != null) {
        _openAddDialog(initialDate: widget.prefilledDate);
      }
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await PredictionApiService.listFavourites(_userKey);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openAddDialog({DateTime? initialDate}) async {
    final result = await showDialog<_NewFavourite>(
      context: context,
      builder: (_) => _AddFavouriteDialog(initialDate: initialDate),
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      await PredictionApiService.createFavourite(
        userKey: _userKey,
        transitDate: _formatDate(result.date),
        title: result.title,
        description: result.description,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to favourites')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  Future<void> _delete(Favourite f) async {
    try {
      await PredictionApiService.deleteFavourite(id: f.id, userKey: _userKey);
      if (!mounted) return;
      setState(() => _items = _items.where((x) => x.id != f.id).toList());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed “${f.title ?? f.transitDate}”'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    }
  }

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1745),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Favourite Transits'),
        actions: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _refresh,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.refresh, color: Colors.white70),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddDialog(),
        backgroundColor: const Color(0xFF7C4DFF),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: SafeArea(top: false, bottom: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CosmicLoader(message: 'Loading your favourites…'),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🌌', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _refresh,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('💫', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 14),
              const Text(
                'No favourite dates yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Save any transit date with a note to remember the moment — '
                'eclipses, returns, exact aspects, anything that mattered.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _openAddDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Add your first'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return RefreshIndicator(
      color: const Color(0xFF7C4DFF),
      onRefresh: _refresh,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 96 + bottomInset),
        itemCount: _items.length,
        itemBuilder: (_, i) => _FavouriteTile(
          favourite: _items[i],
          onDelete: () => _delete(_items[i]),
        ),
      ),
    );
  }
}

class _FavouriteTile extends StatelessWidget {
  final Favourite favourite;
  final VoidCallback onDelete;

  const _FavouriteTile({required this.favourite, required this.onDelete});

  String _formatDateLabel(String iso) {
    try {
      final d = DateTime.parse(iso);
      return DateFormat('EEE, MMM d, yyyy').format(d);
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(favourite.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1A1745),
                title: const Text('Delete favourite?',
                    style: TextStyle(color: Colors.white)),
                content: Text(
                  'Remove “${favourite.title ?? favourite.transitDate}” from your list?',
                  style: const TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: InkWell(
        onTap: () {
          // Returning the transit-date string to the parent route lets the
          // PredictionsScreen prefill its inputs and refetch every tab.
          Navigator.of(context).pop(favourite.transitDate);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1745).withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _formatDateLabel(favourite.transitDate),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Delete',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline,
                      color: Colors.white.withValues(alpha: 0.5)),
                  onPressed: onDelete,
                ),
              ],
            ),
            if (favourite.title != null && favourite.title!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                favourite.title!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            if (favourite.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                favourite.description,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  height: 1.5,
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

// ─── Add dialog ─────────────────────────────────────────────────────────────

class _NewFavourite {
  final DateTime date;
  final String? title;
  final String description;
  _NewFavourite(
      {required this.date, required this.title, required this.description});
}

class _AddFavouriteDialog extends StatefulWidget {
  final DateTime? initialDate;
  const _AddFavouriteDialog({this.initialDate});

  @override
  State<_AddFavouriteDialog> createState() => _AddFavouriteDialogState();
}

class _AddFavouriteDialogState extends State<_AddFavouriteDialog> {
  late DateTime _date;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF7C4DFF),
            surface: Color(0xFF1A1745),
            onSurface: Colors.white,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF0D0B2E)),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1745),
      titleTextStyle: const TextStyle(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      title: const Text('Save a transit date'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date row — read-only field with a tap-to-pick gesture.
            const Text('Date',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            InkWell(
              onTap: _pickDate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 16, color: Colors.white70),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('EEE, MMM d, yyyy').format(_date),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Title (optional)',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(
              controller: _titleController,
              maxLength: 200,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                  hint: 'e.g. Saturn return exact'),
            ),
            const SizedBox(height: 6),
            const Text('Memory',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(
              controller: _descriptionController,
              maxLines: 5,
              minLines: 3,
              maxLength: 4000,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                  hint: 'What happened? How did it feel?'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final desc = _descriptionController.text.trim();
            if (desc.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Memory cannot be empty')),
              );
              return;
            }
            Navigator.of(context).pop(_NewFavourite(
              date: _date,
              title: _titleController.text.trim().isEmpty
                  ? null
                  : _titleController.text.trim(),
              description: desc,
            ));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C4DFF),
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({required String hint}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: Color(0xFF7C4DFF), width: 1.4),
        ),
      );
}

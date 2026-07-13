import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// One Photon (OpenStreetMap) autocomplete suggestion.
class PlaceSuggestion {
  final String displayName;
  final double latitude;
  final double longitude;

  const PlaceSuggestion(this.displayName, this.latitude, this.longitude);

  @override
  String toString() => displayName;
}

/// City/place picker built on Photon (https://photon.komoot.io). Free, no
/// API key. The field calls [onPicked] with the chosen suggestion's
/// coordinates so callers can update lat/lng without a second round-trip.
///
/// Reused by the predictions form and the profiles add/edit form so both
/// share the same UA, debounce, and place-type filtering.
class PlaceAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? errorText;
  final void Function(PlaceSuggestion suggestion) onPicked;
  /// Called when the user types — caller can clear stale lat/lng if the
  /// current text no longer matches a previously-picked suggestion.
  final void Function(String text)? onChanged;

  const PlaceAutocompleteField({
    super.key,
    required this.controller,
    required this.onPicked,
    this.focusNode,
    this.label = 'Birth city',
    this.errorText,
    this.onChanged,
  });

  @override
  State<PlaceAutocompleteField> createState() => _PlaceAutocompleteFieldState();
}

class _PlaceAutocompleteFieldState extends State<PlaceAutocompleteField> {
  // Latest in-flight query — used to discard stale Photon responses when
  // the user keeps typing.
  String _latestQuery = '';
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void dispose() {
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  Future<Iterable<PlaceSuggestion>> _search(String query) async {
    final q = query.trim();
    _latestQuery = q;
    if (q.length < 2) return const [];
    // Small debounce — collapses keystroke bursts into one network call.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (q != _latestQuery) return const [];
    try {
      final url = Uri.parse(
        'https://photon.komoot.io/api/'
        '?q=${Uri.encodeQueryComponent(q)}'
        '&limit=8&lang=en',
      );
      // Photon blocks requests with the default Dart UA per its fair-use
      // policy; identify the app explicitly.
      final res = await http.get(
        url,
        headers: const {
          'User-Agent':
              'CosmicTransit/1.0 (https://github.com/anhvule/cosmos-transit-ui)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));
      if (q != _latestQuery) return const [];
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body);
      final features = (body is Map && body['features'] is List)
          ? body['features'] as List
          : const [];
      // Place-type filter — Photon also returns offices, amenities, houses
      // etc., which are noise for a birth-city picker.
      const placeKeys = {'place', 'boundary'};
      const placeTypes = {
        'city',
        'town',
        'village',
        'hamlet',
        'municipality',
        'county',
        'state',
        'region',
        'province',
        'country',
        'administrative',
      };
      final results = <PlaceSuggestion>[];
      for (final f in features) {
        if (f is! Map) continue;
        final geometry = f['geometry'];
        final properties = f['properties'];
        if (geometry is! Map || properties is! Map) continue;
        final osmKey = (properties['osm_key'] ?? '').toString();
        final type = (properties['type'] ?? '').toString();
        if (!placeKeys.contains(osmKey) && !placeTypes.contains(type)) {
          continue;
        }
        final coords = geometry['coordinates'];
        if (coords is! List || coords.length < 2) continue;
        final lng = (coords[0] as num?)?.toDouble();
        final lat = (coords[1] as num?)?.toDouble();
        if (lng == null || lat == null) continue;
        final name = (properties['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final state = (properties['state'] ?? '').toString();
        final country = (properties['country'] ?? '').toString();
        final parts = <String>[name];
        if (state.isNotEmpty && state != name) parts.add(state);
        if (country.isNotEmpty) parts.add(country);
        results.add(PlaceSuggestion(parts.join(', '), lat, lng));
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<PlaceSuggestion>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: (s) => s.displayName,
      optionsBuilder: (tev) => _search(tev.text),
      onSelected: (s) {
        widget.onPicked(s);
      },
      fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: widget.onChanged,
          onSubmitted: (_) => onSubmit(),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
            errorText: widget.errorText,
            errorStyle: const TextStyle(fontSize: 11),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF7C4DFF)),
            ),
          ),
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: const Color(0xFF1F1B4F),
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final opt = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(opt),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Text(
                        opt.displayName,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

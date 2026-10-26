import 'package:flutter/material.dart';

import '../../features/shade_route/services/city_trip_service.dart';
import 'saved_places.dart';
import 'saved_places_widgets.dart';

class PlaceSearchSheet extends StatefulWidget {
  const PlaceSearchSheet({
    super.key,
    required this.service,
    required this.start,
    required this.initial,
    required this.locationAvailable,
    required this.onSelect,
    this.onMyLocation,
    this.onMap,
  });
  final CityTripService service;
  final bool start, locationAvailable;
  final String initial;
  final ValueChanged<CityPlace> onSelect;
  final VoidCallback? onMyLocation, onMap;
  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
  late final _query = TextEditingController(text: widget.initial);
  List<CityPlace> _places = [];
  String? _error;
  bool _busy = false, _searched = false;
  int _request = 0, _visible = 20;
  @override
  void dispose() {
    _request++;
    _query.dispose();
    super.dispose();
  }

  Future<void> _search({bool online = false}) async {
    FocusScope.of(context).unfocus();
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _searched = false;
      _places = [];
    });
    try {
      final places = await (online
          ? widget.service.searchOnline(_query.text)
          : widget.service.search(_query.text));
      if (mounted && request == _request) {
        setState(() {
          _places = places;
          _visible = 20;
          _searched = true;
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(
          () => _error = e is FormatException
              ? e.message.toString()
              : 'Place search unavailable. Try a map pin or coordinates.',
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height:
          MediaQuery.sizeOf(context).height *
          (MediaQuery.sizeOf(context).height < 500 ? .92 : .65),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.start
                        ? 'Choose starting point'
                        : 'Choose destination',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close place search',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              onChanged: (_) {
                _request++;
                setState(() {
                  _busy = false;
                  _searched = false;
                  _places = [];
                  _error = null;
                });
              },
              decoration: InputDecoration(
                labelText: widget.start
                    ? 'Start place or address'
                    : 'Destination place or address',
                helperText: 'Press Search, then choose a matching place.',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search places',
                  onPressed: _busy ? null : _search,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                if (_searched)
                  TextButton.icon(
                    onPressed: _busy ? null : () => _search(online: true),
                    icon: const Icon(Icons.travel_explore),
                    label: const Text('Search online for more places'),
                  ),
                if (widget.start && widget.locationAvailable)
                  ListTile(
                    leading: const Icon(Icons.my_location),
                    title: const Text('Your location'),
                    onTap: widget.onMyLocation,
                  ),
                if (widget.onMap != null)
                  ListTile(
                    leading: const Icon(Icons.map_outlined),
                    title: const Text('Choose on map'),
                    onTap: widget.onMap,
                  ),
                SavedPlaceSuggestions(
                  query: _query.text,
                  onSelect: widget.onSelect,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!),
                  ),
                if (_searched && _places.isEmpty)
                  const ListTile(
                    title: Text('No matches. Try another name or a map pin.'),
                  ),
                for (final p in _places.take(_visible))
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(p.name),
                    subtitle: Text(p.address),
                    trailing: FavoriteButton(place: SavedPlace.fromCity(p)),
                    onTap: () => widget.onSelect(p),
                  ),
                if (_places.length > _visible)
                  TextButton(
                    onPressed: () => setState(() => _visible += 20),
                    child: Text(
                      'Show more places (${_places.length - _visible} remaining)',
                    ),
                  ),
                if (_searched && _places.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Place data © OpenStreetMap contributors · ODbL',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

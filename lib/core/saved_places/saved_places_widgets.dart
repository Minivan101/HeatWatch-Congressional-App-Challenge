import 'package:flutter/material.dart';

import '../../features/shade_route/services/city_trip_service.dart';
import '../../features/cool_spots/models/cooling_destination.dart';
import 'place_search_sheet.dart';
import 'saved_places.dart';

class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.place, this.endpoint});
  final SavedPlace place;

  final String? endpoint;
  @override
  Widget build(BuildContext context) {
    final saved = SavedPlacesScope.maybeOf(context);
    if (saved == null) return const SizedBox.shrink();
    final favorite = saved.isFavorite(place);
    return IconButton(
      tooltip: endpoint == null
          ? '${favorite ? 'Remove from' : 'Add to'} favorites: ${place.name}'
          : '${favorite ? 'Unsave' : 'Save'} $endpoint: ${place.name}',
      isSelected: favorite,
      onPressed: !saved.loaded || saved.restoreFailed
          ? null
          : () async {
              await saved.toggleFavorite(place);
              if (context.mounted && saved.error != null) {
                ScaffoldMessenger.maybeOf(context)
                    ?.showSnackBar(SnackBar(content: Text(saved.error!)));
              }
            },
      icon: const Icon(Icons.favorite_border),
      selectedIcon: Icon(
        Icons.favorite,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

Future<CityPlace?> _pickPlace(BuildContext context, CityTripService service) =>
    showModalBottomSheet<CityPlace>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => PlaceSearchSheet(
        service: service,
        start: false,
        initial: '',
        locationAvailable: false,
        onSelect: (place) => Navigator.pop(sheet, place),
      ),
    );

class SavedPlacesSection extends StatelessWidget {
  const SavedPlacesSection({
    super.key,
    required this.service,
    required this.onSelect,
  });
  final CityTripService service;
  final ValueChanged<CoolingDestination> onSelect;
  @override
  Widget build(BuildContext context) {
    final saved = SavedPlacesScope.maybeOf(context);
    if (saved == null) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Saved places',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () => _manage(context),
                  child: const Text('View all'),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final label in PlaceLabel.values)
                  ActionChip(
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    avatar: Icon(
                      label == PlaceLabel.home
                          ? Icons.home_outlined
                          : Icons.work_outline,
                      size: 18,
                    ),
                    label: Text(label == PlaceLabel.home ? 'Home' : 'Work'),
                    onPressed: !saved.loaded || saved.restoreFailed
                        ? null
                        : () async {
                            final existing = saved.labeled(label);
                            if (existing != null) {
                              onSelect(existing.destination);
                              return;
                            }
                            final place = await _pickPlace(context, service);
                            if (place != null) {
                              await saved.setLabel(
                                label,
                                SavedPlace.fromCity(place),
                              );
                            }
                          },
                  ),
                ActionChip(
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  avatar: const Icon(Icons.favorite_border, size: 18),
                  label: Text(
                    'Favorites${saved.favorites.isEmpty ? '' : ' · ${saved.favorites.length}'}',
                  ),
                  onPressed: () => _manage(context),
                ),
              ],
            ),
            if (saved.favorites.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Heart a place to find it here.',
                  style: TextStyle(fontSize: 12),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final place in saved.favorites.take(3))
                      ActionChip(
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        label: Text(
                          place.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () => onSelect(place.destination),
                      ),
                  ],
                ),
              ),
            if (saved.error != null) _SavedError(saved: saved),
          ],
        ),
      ),
    );
  }

  void _manage(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => SavedPlacesSheet(
        service: service,
        onSelect: (place) {
          Navigator.pop(sheet);
          onSelect(place.destination);
        },
      ),
    );
  }
}

class SavedPlacesSheet extends StatelessWidget {
  const SavedPlacesSheet({
    super.key,
    required this.service,
    required this.onSelect,
  });
  final CityTripService service;
  final ValueChanged<SavedPlace> onSelect;
  @override
  Widget build(BuildContext context) {
    final saved = SavedPlacesScope.maybeOf(context)!;
    final enabled = saved.loaded && !saved.restoreFailed;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Saved places',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Close saved places',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Saved on this device. Tap a place for a route.'),
          ),
          if (!saved.loaded) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                if (saved.error != null) _SavedError(saved: saved),
                for (final label in PlaceLabel.values)
                  _labelRow(context, saved, label, enabled),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Favorites',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (saved.favorites.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Your favorite places will appear here.'),
                  ),
                for (final place in saved.favorites)
                  ListTile(
                    leading: const Icon(Icons.favorite),
                    title: Text(place.title),
                    subtitle: Text(
                      place.address.isEmpty ? place.name : place.address,
                    ),
                    onTap: () => onSelect(place),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Edit ${place.title}',
                      onSelected: (value) async {
                        switch (value) {
                          case 'home':
                            await saved.setLabel(PlaceLabel.home, place);
                          case 'work':
                            await saved.setLabel(PlaceLabel.work, place);
                          case 'remove':
                            await saved.toggleFavorite(place);
                          case 'rename':
                            if (context.mounted) {
                              await _rename(context, saved, place);
                            }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('Edit label'),
                        ),
                        PopupMenuItem(
                          value: 'home',
                          child: Text('Set as Home'),
                        ),
                        PopupMenuItem(
                          value: 'work',
                          child: Text('Set as Work'),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove favorite'),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add a favorite'),
                    onPressed: !enabled
                        ? null
                        : () async {
                            final place = await _pickPlace(context, service);
                            if (place != null) {
                              final entry = SavedPlace.fromCity(place);
                              if (!saved.isFavorite(entry)) {
                                await saved.toggleFavorite(entry);
                              }
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelRow(
    BuildContext context,
    SavedPlaces saved,
    PlaceLabel label,
    bool enabled,
  ) {
    final place = saved.labeled(label), home = label == PlaceLabel.home;
    Future<void> edit() async {
      final selected = await _pickPlace(context, service);
      if (selected != null) {
        await saved.setLabel(label, SavedPlace.fromCity(selected));
      }
    }

    return ListTile(
      leading: Icon(home ? Icons.home_outlined : Icons.work_outline),
      title: Text(home ? 'Home' : 'Work'),
      subtitle: Text(place?.title ?? 'Set address'),
      onTap: !enabled
          ? null
          : () {
              if (place == null) {
                edit();
              } else {
                onSelect(place);
              }
            },
      trailing: place == null
          ? IconButton(
              tooltip: home ? 'Set Home' : 'Set Work',
              onPressed: enabled ? edit : null,
              icon: const Icon(Icons.add),
            )
          : PopupMenuButton<String>(
              tooltip: home ? 'Edit Home' : 'Edit Work',
              onSelected: (value) {
                if (value == 'edit') {
                  edit();
                } else {
                  saved.setLabel(label, null);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Change address')),
                PopupMenuItem(value: 'remove', child: Text('Remove address')),
              ],
            ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    SavedPlaces saved,
    SavedPlace place,
  ) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _PlaceLabelDialog(initial: place.title),
    );
    if (value != null) await saved.rename(place, value);
  }
}

class SavedPlaceSuggestions extends StatelessWidget {
  const SavedPlaceSuggestions({
    super.key,
    required this.onSelect,
    this.query = '',
  });
  final ValueChanged<CityPlace> onSelect;
  final String query;
  @override
  Widget build(BuildContext context) {
    final saved = SavedPlacesScope.maybeOf(context);
    if (saved == null) return const SizedBox.shrink();
    final term = query.trim().toLowerCase();
    bool matches(SavedPlace p, String label) =>
        term.isEmpty ||
        '$label ${p.title} ${p.address}'.toLowerCase().contains(term);
    return Column(
      children: [
        for (final label in PlaceLabel.values)
          if (saved.labeled(label) case final place?)
            if (matches(place, label.name))
              ListTile(
                leading: Icon(
                  label == PlaceLabel.home
                      ? Icons.home_outlined
                      : Icons.work_outline,
                ),
                title: Text(label == PlaceLabel.home ? 'Home' : 'Work'),
                subtitle: Text(place.title),
                onTap: () => onSelect(place.cityPlace),
              ),
        for (final place in saved.favorites.where(
          (p) => matches(p, 'favorite'),
        ))
          ListTile(
            leading: const Icon(Icons.favorite),
            title: Text(place.title),
            subtitle: Text(place.address),
            onTap: () => onSelect(place.cityPlace),
            trailing: FavoriteButton(place: place),
          ),
      ],
    );
  }
}

class _SavedError extends StatelessWidget {
  const _SavedError({required this.saved});
  final SavedPlaces saved;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(saved.error!),
        TextButton(
          onPressed: saved.restoreFailed ? saved.load : saved.retrySave,
          child: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _PlaceLabelDialog extends StatefulWidget {
  const _PlaceLabelDialog({required this.initial});
  final String initial;
  @override
  State<_PlaceLabelDialog> createState() => _PlaceLabelDialogState();
}

class _PlaceLabelDialogState extends State<_PlaceLabelDialog> {
  late final input = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit label'),
    content: TextField(
      controller: input,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: 'Place label'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, input.text),
        child: const Text('Save'),
      ),
    ],
  );
}

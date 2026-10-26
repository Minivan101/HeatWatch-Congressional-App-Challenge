import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../saved_places/saved_places_widgets.dart';
import '../location/app_location.dart';
import '../settings/settings_sheet.dart';

import '../../features/cool_spots/presentation/cool_spots_page.dart';
import '../../features/cool_spots/models/cooling_destination.dart';
import '../../features/heat_guard/presentation/heat_guard_page.dart';
import '../../features/heat_guard/services/weather_repository.dart';
import '../../features/heat_guard/presentation/home_header.dart';
import '../../features/shade_route/presentation/shade_route_page.dart';
import '../../features/shade_route/services/city_trip_service.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.promptLocation = true,
    this.walkingService,
    this.weatherRepository,
    this.mapTilesEnabled = true,
    this.demoControls,
  });
  final bool promptLocation, mapTilesEnabled;
  final CityTripService? walkingService;
  final WeatherRepository? weatherRepository;
  final Widget? demoControls;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final _tabSlide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
    value: 1,
  );
  Animation<Offset> _tabPosition = const AlwaysStoppedAnimation(Offset.zero);
  late final _search = widget.walkingService ?? CityTripService();
  bool _locationStarted = false;
  AppLocation? _location;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _tabSlide.dispose();
    if (widget.walkingService == null) _search.client.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _location = LocationScope.maybeOf(context);
    final settings = SettingsScope.maybeOf(context);
    if (widget.promptLocation &&
        !_locationStarted &&
        settings?.loaded == true &&
        _location != null) {
      _locationStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_location!.choice == LocationChoice.ask) {
          showLocationChoice(context, _location!);
        } else if (_location!.choice == LocationChoice.everyOpen) {
          _location!.refresh();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _locationStarted &&
        _location?.choice == LocationChoice.everyOpen) {
      _location!.refresh();
    }
  }

  void _selectTab(int index) {
    FocusScope.of(context).unfocus();
    if (_index == index) return;
    final direction = index > _index ? 1.0 : -1.0;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    setState(() {
      _index = index;
      _tabPosition = reducedMotion
          ? const AlwaysStoppedAnimation(Offset.zero)
          : _tabSlide
                .drive(CurveTween(curve: Curves.easeOutCubic))
                .drive(
                  Tween(begin: Offset(direction * .045, 0), end: Offset.zero),
                );
    });
    if (reducedMotion) {
      _tabSlide.value = 1;
    } else {
      _tabSlide.forward(from: 0);
    }
  }

  void _chooseDestination(CoolingDestination destination) {
    setState(() => _tripDestination = destination);
    _selectTab(1);
  }

  int _index = 0;
  CoolingDestination? _tripDestination;
  late final WeatherRepository _weather =
      widget.weatherRepository ?? WeatherRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context)
            .scale(60)
            .clamp(92, 160)
            .toDouble(),
        titleSpacing: 16,
        excludeHeaderSemantics: true,
        title: HomeHeaderLocation(onHome: () => _selectTab(0)),
        actions: [
          HomeHeaderTemperature(
            onOpen: () => _selectTab(0),
            clock: _weather.clock,
          ),
          if (SettingsScope.maybeOf(context) case final settings?)
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => LocationScope(
                  location: _location!,
                  child: SettingsSheet(settings: settings),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.demoControls != null) widget.demoControls!,
          if (_location != null && _index != 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _location!.status,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ClipRect(
              child: SlideTransition(
                position: _tabPosition,
                child: IndexedStack(
                  index: _index,
                  children: [
                    HeatGuardPage(
                      savedPlaces: SavedPlacesSection(
                        service: _search,
                        onSelect: _chooseDestination,
                      ),
                      destination: _tripDestination,
                      repository: _weather,
                      active: _index == 0,
                      autoStart: true,
                      keepOverviewUpdated: true,
                      onShade: () => _selectTab(1),
                      onCool: () => _selectTab(2),
                    ),
                    ShadeRoutePage(
                      walkingService: widget.walkingService,
                      mapTilesEnabled: widget.mapTilesEnabled,
                      coolingDestination: _tripDestination,
                      weatherRepository: _weather,
                      active: _index == 1,
                      onChooseDestination: () => _selectTab(2),
                      onDestinationSelected: (destination) =>
                          setState(() => _tripDestination = destination),
                      onClearDestination: () =>
                          setState(() => _tripDestination = null),
                    ),
                    CoolSpotsPage(
                      mapTilesEnabled: widget.mapTilesEnabled,
                      onDestinationSelected: _chooseDestination,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        animationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 110),
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(icon: Icon(Icons.route), label: 'ShadeMap'),
          NavigationDestination(icon: Icon(Icons.ac_unit), label: 'CoolSpots'),
        ],
      ),
    );
  }
}

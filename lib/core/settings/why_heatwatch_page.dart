import 'package:flutter/material.dart';

import '../../features/heat_guard/presentation/weather_guidance.dart';
import '../../features/heat_guard/presentation/weather_overview.dart';

class WhyHeatWatchPage extends StatelessWidget {
  const WhyHeatWatchPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Why HeatWatch'),
      actions: const [CurrentTemperatureDisplay(compact: true)],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'A cooler way to care for our community',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'We are developing HeatWatch to help people in Las Vegas make better-informed choices about heat, sunlight and places to cool down. A useful forecast should help you decide what to do next: when to walk, where to find shade, and where to take a cooling break.',
        ),
        const _WhySection(
          title: 'UV & skin cancer prevention',
          introduction: 'Too much ultraviolet radiation can damage skin and increase skin cancer risk. UV protection matters on cool or cloudy days too.',
          points: [
            'Make the UV index easy to see and understand, with a number, color and risk category.',
            'Encourage shade, skin-covering clothing, hats, sunglasses and sunscreen as everyday habits.',
            'Compare estimated shade along a walk. Shade is useful, but its percentage is not a measure of UV protection.',
          ],
        ),
        const _WhySection(
          title: 'Heat exhaustion & heat stroke',
          introduction: 'Hot conditions can strain the body and lead to heat-related illness. Heat exhaustion can involve dizziness, nausea or weakness; heat stroke is a medical emergency.',
          points: [
            'Show temperature and feels-like conditions alongside short reminders about water, rest and cooling breaks.',
            'Help people locate documented drinking-water stops or indoor cooling options before a trip.',
            'Support earlier planning and awareness. If heat stroke is suspected, call 911 rather than relying on an app.',
          ],
        ),
        const _WhySection(
          title: 'Warning gaps & access to information',
          introduction: 'The National Weather Service already issues official heat warnings and advisories. HeatWatch brings those alerts together with practical trip information. We do not want people to have to wait for a warning to plan a cooler walk.',
          points: [
            'Make official information easier to find for people who may miss a warning or not know where to look.',
            'Connect a regional warning to everyday choices about walking time, estimated shade and nearby cooling places.',
            'Keep current alerts visible. No returned alert is not an all-clear, and HeatWatch does not replace official instructions.',
          ],
        ),
        const _WhySection(
          title: 'Everyday oversights',
          introduction: 'Planning a trip often means checking several separate places for weather, directions and cooling information. Important details can be easy to overlook.',
          points: [
            'Put weather, UV, walking routes and cooling locations in one app, while keeping heat and UV clearly distinct.',
            'Show access conditions and source details so a water fountain, outdoor park and air-conditioned venue are not treated as the same kind of cooling.',
            'Help users notice practical questions: Is there shade at this time? Is the stop in the right direction? What are its published hours?',
          ],
        ),
        const _WhySection(
          title: 'People experiencing homelessness',
          introduction: 'People without reliable housing or access to cooling can face greater exposure to dangerous heat. Finding water, shade and an accessible indoor break can be especially important.',
          points: [
            'Help residents and outreach workers find official cooling locations and documented community alternatives, with their access conditions.',
            'Make useful information available in the current free prototype without requiring a paid membership.',
            'Recognize that a phone app cannot reach everyone. Housing, accessible cooling spaces, water and in-person community support remain essential.',
          ],
        ),
        const _WhySection(
          title: 'Our community goals',
          introduction: 'Start with Las Vegas and improve with the people who live, work and walk here.',
          points: [
            'Support students, older adults, outdoor workers, families and neighbors who spend time outside.',
            'Learn from residents and outreach teams, review cooling information, and measure shade predictions against real observations.',
            'Help make heat and sun protection a routine part of planning, while documenting where better information or cooling access is needed.',
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Our intended impact is less avoidable exposure and easier access to cooling. We have not yet measured reductions in heat illness or skin cancer. See Warnings & safety for practical limitations.',
        ),
        const SizedBox(height: 20),
        Text(
          'Health & community sources',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SourceLink(
          label: 'CDC · UV and sun protection',
          url: 'https://www.cdc.gov/skin-cancer/sun-safety/',
        ),
        const SourceLink(
          label: 'CDC · heat-related illnesses',
          url: 'https://www.cdc.gov/niosh/heat-stress/about/illnesses.html',
        ),
        const SourceLink(
          label: 'NWS · understanding heat alerts',
          url: 'https://www.weather.gov/safety/heat-ww',
        ),
        const SourceLink(
          label: 'UKHSA · homelessness and heat (UK guidance)',
          url: 'https://www.gov.uk/guidance/supporting-vulnerable-people-before-and-during-hot-weather-people-experiencing-homelessness-and-sleeping-rough',
        ),
        const SourceLink(
          label: 'US study · heat illness and homelessness',
          url: 'https://pubmed.ncbi.nlm.nih.gov/40489135/',
        ),
      ],
    ),
  );
}

class _WhySection extends StatelessWidget {
  const _WhySection({
    required this.title,
    required this.introduction,
    required this.points,
  });
  final String title, introduction;
  final List<String> points;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(introduction),
        const SizedBox(height: 6),
        for (final point in points)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(point)),
              ],
            ),
          ),
      ],
    ),
  );
}

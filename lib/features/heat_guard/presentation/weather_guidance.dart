import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class SourceLink extends StatelessWidget {
  const SourceLink({super.key, required this.label, required this.url});
  final String label;
  final String url;
  @override
  Widget build(BuildContext context) => Wrap(
    children: [
      TextButton(
        onPressed: () async {
          var opened = false;
          try {
            opened = await launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            );
          } catch (_) {
            // show the link error below
          }
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Link unavailable here. Copy the source URL from the report.',
                ),
              ),
            );
          }
        },
        child: Text(label),
      ),
      IconButton(
        tooltip: 'Copy $label link',
        icon: const Icon(Icons.copy),
        onPressed: () => Clipboard.setData(ClipboardData(text: url)),
      ),
    ],
  );
}

class WeatherGuidance extends StatelessWidget {
  const WeatherGuidance({super.key, this.uv});
  final double? uv;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'General preparation — HeatWatch',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const Text(
        'Follow official warnings first. Seek cooler places, stay hydrated and reduce time in intense heat.',
      ),
      if (uv != null)
        Text(
          uv! < 3
              ? 'Forecast UV is in the EPA low band. Individual protection needs still vary.'
              : uv! < 8
              ? 'Sun protection is recommended: shade, protective clothing and sunscreen.'
              : 'Extra sun protection is needed at this forecast UV level. Limit midday exposure.',
        ),
      const Text(
        'This is general guidance, not a personal risk score or medical advice. Shade coverage does not establish UV protection or a temperature reduction.',
      ),
      const SourceLink(
        label: 'EPA UV guidance',
        url: 'https://www.epa.gov/sunsafety/uv-index-scale-0',
      ),
      const SelectableText('https://www.epa.gov/sunsafety/uv-index-scale-0'),
      const SourceLink(
        label: 'CDC heat guidance',
        url: 'https://www.cdc.gov/heat-health/about/index.html',
      ),
      const SelectableText('https://www.cdc.gov/heat-health/about/index.html'),
    ],
  );
}

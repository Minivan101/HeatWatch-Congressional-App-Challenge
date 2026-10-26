import 'dart:convert';
import 'dart:io';

import 'package:heatwatch/features/cool_spots/models/official_cooling_directory.dart';

void main() {
  final source = File('data/cooling_centers/official_directory.json');
  final directory = OfficialCoolingDirectory.parse(
    jsonDecode(source.readAsStringSync()),
  );
  final output = Directory('release/cooling-feed')..createSync(recursive: true);
  File('${output.path}/official-directory.json')
      .writeAsStringSync(jsonEncode(directory.data));
  File('${output.path}/README.txt').writeAsStringSync(
    'HeatWatch reviewed official cooling directory, revision ${directory.revision}.\n'
    'Opening status is unverified. This is public source information only.\n',
  );
  File('${output.path}/_headers').writeAsStringSync(
    '/official-directory.json\n'
    '  Content-Type: application/json; charset=utf-8\n'
    '  Access-Control-Allow-Origin: *\n'
    '  Cache-Control: public, max-age=300\n'
    '  X-Content-Type-Options: nosniff\n'
    '/*\n'
    '  Referrer-Policy: no-referrer\n',
  );
  File('${output.path}/index.html').writeAsStringSync(
    '<!doctype html><html lang="en"><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    '<title>HeatWatch cooling directory</title><main>'
    '<h1>HeatWatch cooling directory</h1>'
    '<p>Revision ${directory.revision}: ${directory.stations.length} reviewed locations. '
    'Current cooling activation, opening and pedestrian entrances are unverified. '
    'Contact the facility before visiting.</p>'
    '<p><a href="official-directory.json">Public reviewed directory JSON</a></p>'
    '</main></html>',
  );
  stdout.writeln(
    'Prepared ${output.path}/official-directory.json. Nothing published.',
  );
}

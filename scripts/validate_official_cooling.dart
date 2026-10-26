import 'dart:convert';
import 'dart:io';

import 'package:heatwatch/features/cool_spots/models/official_cooling_directory.dart';

void main(List<String> args) {
  if (args.isEmpty ||
      (args.length != 1 && args.length != 3) ||
      (args.length == 3 && args[1] != '--install')) {
    stderr.writeln(
      'Usage: dart scripts/validate_official_cooling.dart candidate.json [--install target.json]',
    );
    exitCode = 2;
    return;
  }
  File? staged;
  try {
    final candidate = File(args[0]);
    final content = candidate.readAsStringSync();
    final parsed = OfficialCoolingDirectory.parse(jsonDecode(content));
    if (args.length == 3) {
      final target = File(args[2]);
      if (candidate.absolute.path == target.absolute.path) {
        throw const FormatException(
          'Candidate must differ from installed file',
        );
      }
      if (target.existsSync()) {
        final previous = OfficialCoolingDirectory.parse(
          jsonDecode(target.readAsStringSync()),
        );
        if (parsed.revision <= previous.revision) {
          throw const FormatException(
            'Revision must increase; installed snapshot retained',
          );
        }
      }
      staged = File('${target.path}.staged.$pid');
      staged.writeAsStringSync(content, flush: true);
      staged.renameSync(target.path);
    }
    stdout.writeln(
      'Validated ${parsed.stations.length} stations, revision ${parsed.revision}.',
    );
  } catch (error) {
    if (staged?.existsSync() ?? false) staged!.deleteSync();
    stderr.writeln('Rejected: $error. Installed snapshot unchanged.');
    exitCode = 1;
  }
}

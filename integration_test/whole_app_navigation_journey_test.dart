library;

import 'package:integration_test/integration_test.dart';

import '../test/whole_app_navigation_test.dart' as journey;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  journey.main(native: true);
}

import 'package:integration_test/integration_test.dart';

import '../test/saved_places_ui_test.dart' as saved;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  saved.main(native: true);
}

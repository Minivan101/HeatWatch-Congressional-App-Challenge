import 'package:integration_test/integration_test.dart';

import '../test/route_preference_ui_test.dart' as routes;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  routes.main(native: true);
}

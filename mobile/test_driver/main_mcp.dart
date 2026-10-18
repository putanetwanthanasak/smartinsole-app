// Debug entrypoint for UI checks through the Dart MCP server: enables the
// Flutter Driver extension so the agent can tap and take screenshots.
// Lives outside lib/ so flutter_driver stays a dev dependency.
//
//   flutter run -d <emulator-id> -t test_driver/main_mcp.dart --print-dtd
import 'package:flutter_driver/driver_extension.dart';
import 'package:smartinsole/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}

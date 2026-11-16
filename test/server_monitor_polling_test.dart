import 'package:b_code/servers/server_monitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('port polling starts on demand and is reference counted', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final monitor = ServerMonitor(prefs);

    expect(monitor.isPolling, isFalse);

    monitor.startPolling();
    expect(monitor.isPolling, isTrue);

    // A second screen opening keeps the first screen's polling alive.
    monitor.startPolling();
    monitor.stopPolling();
    expect(monitor.isPolling, isTrue);

    monitor.stopPolling();
    expect(monitor.isPolling, isFalse);

    monitor.dispose();
  });
}

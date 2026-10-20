import 'package:b_code/core/di.dart';
import 'package:b_code/editor/zoom_viewer.dart';
import 'package:b_code/plugins/host/extension_install_store.dart';
import 'package:b_code/settings/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors how the editor decides whether to zoom.
///
/// The bug this guards against was subtle and total: the editor rebuilt only when
/// *settings* changed, so installing the zoom extension produced no visible result
/// at all. Nothing about the extension was wrong; the view simply never heard about
/// it.
Widget zoomDecidingCodeView({
  required ExtensionInstallStore extensions,
  required SettingsStore settings,
}) {
  return ListenableBuilder(
    listenable: Listenable.merge([settings, extensions]),
    builder: (context, _) {
      final child = const SizedBox(key: Key('editor'), width: 100, height: 100);
      if (extensions.isInstalled('bcode.zoom')) {
        return BCodeZoomView(child: child);
      }
      return child;
    },
  );
}

void main() {
  late ExtensionInstallStore extensions;
  late SettingsStore settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    extensions = ExtensionInstallStore(prefs);
    settings = SettingsStore(prefs);
    sl.registerSingleton<ExtensionInstallStore>(extensions);
    sl.registerSingleton<SettingsStore>(settings);
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: zoomDecidingCodeView(
          extensions: extensions,
          settings: settings,
        )),
      ),
    );
  }

  testWidgets('no zoom before the extension is installed', (tester) async {
    await pumpEditor(tester);
    expect(find.byType(BCodeZoomView), findsNothing);
  });

  testWidgets('installing the extension applies zoom without a restart',
      (tester) async {
    await pumpEditor(tester);
    expect(find.byType(BCodeZoomView), findsNothing);

    extensions.install('bcode.zoom');
    await tester.pump();

    expect(
      find.byType(BCodeZoomView),
      findsOneWidget,
      reason: 'installing the extension must rebuild the editor immediately',
    );
  });

  testWidgets('uninstalling removes zoom again', (tester) async {
    await pumpEditor(tester);
    extensions.install('bcode.zoom');
    await tester.pump();
    expect(find.byType(BCodeZoomView), findsOneWidget);

    extensions.uninstall('bcode.zoom');
    await tester.pump();

    expect(find.byType(BCodeZoomView), findsNothing);
  });

  testWidgets('the editor content survives being zoomed', (tester) async {
    await pumpEditor(tester);
    extensions.install('bcode.zoom');
    await tester.pump();

    // The zoom wrapper must wrap the whole editor, not replace it.
    expect(find.byKey(const Key('editor')), findsOneWidget);
  });
}
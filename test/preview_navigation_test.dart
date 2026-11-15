import 'package:b_code/editor/preview/preview_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final policy = PreviewNavigationPolicy(Uri.parse('http://127.0.0.1:5173'));

  test('the previewed origin stays in the WebView', () {
    expect(policy.decide('http://127.0.0.1:5173/index.html'), PreviewNavigation.navigate);
    expect(policy.decide('http://127.0.0.1:5173/src/main.tsx'), PreviewNavigation.navigate);
  });

  test('OAuth providers and BaaS hosts are allowed in-frame', () {
    expect(
      policy.decide('https://abcdefg.supabase.co/auth/v1/authorize?provider=github'),
      PreviewNavigation.navigate,
    );
    expect(policy.decide('https://accounts.google.com/o/oauth2/v2/auth'), PreviewNavigation.navigate);
    expect(policy.decide('https://my-app.firebaseapp.com/__/auth/handler'), PreviewNavigation.navigate);
    expect(policy.decide('https://github.com/login/oauth/authorize'), PreviewNavigation.navigate);
  });

  test('a lookalike host is not treated as a trusted suffix', () {
    expect(policy.decide('https://evilsupabase.co/auth'), PreviewNavigation.external);
    expect(policy.decide('https://supabase.co.evil.example/auth'), PreviewNavigation.external);
  });

  test('other web origins go to the system browser, not a trusted-looking frame', () {
    expect(policy.decide('https://example.com/docs'), PreviewNavigation.external);
    expect(policy.decide('http://127.0.0.1:9999/'), PreviewNavigation.external);
  });

  test('local files, javascript and intent URLs are refused', () {
    expect(policy.decide('file:///data/data/com.bcode.editor/token'), PreviewNavigation.block);
    expect(policy.decide('content://com.android.providers/x'), PreviewNavigation.block);
    expect(policy.decide('javascript:alert(1)'), PreviewNavigation.block);
    expect(policy.decide('intent://scan/#Intent;scheme=zxing;end'), PreviewNavigation.block);
    expect(policy.decide('data:text/html,<h1>x</h1>'), PreviewNavigation.block);
  });

  test('mail and telephone links are handed to the system', () {
    expect(policy.decide('mailto:dev@example.com'), PreviewNavigation.external);
    expect(policy.decide('tel:+10000000000'), PreviewNavigation.external);
  });
}

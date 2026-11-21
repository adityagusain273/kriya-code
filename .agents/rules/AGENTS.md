# kriya_code Flutter Development Guidelines

## Project Context
This is a Flutter application. Follow Effective Dart and modern Flutter architecture guidelines.

## Development Rules
- Use `dart analyze` and `flutter test` for static analysis and testing.
- Maintain responsive layouts across varying screen densities using `LayoutBuilder` / `MediaQuery`.
- Separate UI widgets, business logic (BLoC / Provider / Riverpod), and data repositories.
- Use `dart-mcp-server` tools (`hot_reload`, `analyze_files`, `widget_inspector`) when running or debugging the app.

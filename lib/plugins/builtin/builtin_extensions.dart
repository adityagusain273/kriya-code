import '../api/extension.dart';
import 'c/c_extension.dart';
import 'cpp/cpp_extension.dart';
import 'java/java_extension.dart';
import 'python/python_extension.dart';
import 'web/css_extension.dart';
import 'web/html_extension.dart';
import 'web/javascript_extension.dart';
import 'web/json_extension.dart';
import 'web/typescript_extension.dart';

final List<BCodeExtension> builtinExtensions = [
  CExtension(),
  CppExtension(),
  JavaExtension(),
  PythonExtension(),
  JavascriptExtension(),
  TypescriptExtension(),
  HtmlExtension(),
  CssExtension(),
  JsonExtension(),
];

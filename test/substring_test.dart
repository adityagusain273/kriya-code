// ignore_for_file: avoid_print, unused_catch_stack
void main() {
  try {
    '"'.substring(1, 0);
  } catch (e, stack) {
    print('1, 0 Error: $e');
  }
}

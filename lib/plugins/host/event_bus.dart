import 'dart:async';

enum BCodeEventType { documentOpened, documentSaved, documentClosed, appReady }

class BCodeEvent {
  final BCodeEventType type;
  final Map<String, Object?> payload;

  const BCodeEvent(this.type, {this.payload = const {}});
}

class BCodeEventBus {
  final _controller = StreamController<BCodeEvent>.broadcast();

  Stream<BCodeEvent> get stream => _controller.stream;

  void emit(BCodeEvent event) => _controller.add(event);

  Future<void> dispose() => _controller.close();
}

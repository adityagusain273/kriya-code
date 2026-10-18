typedef Factory<T> = T Function();

class ServiceLocator {
  final _singletons = <Type, Object>{};
  final _factories = <Type, Factory<Object>>{};

  void registerSingleton<T extends Object>(T instance) {
    _singletons[T] = instance;
  }

  void registerLazy<T extends Object>(Factory<T> factory) {
    _factories[T] = () => factory() as Object;
  }

  T get<T extends Object>() {
    final existing = _singletons[T];
    if (existing != null) return existing as T;
    final factory = _factories[T];
    if (factory == null) {
      throw StateError('No service registered for type $T');
    }
    final instance = factory();
    _singletons[T] = instance;
    return instance as T;
  }

  T call<T extends Object>() => get<T>();

  bool isRegistered<T extends Object>() =>
      _singletons.containsKey(T) || _factories.containsKey(T);

  void reset() {
    _singletons.clear();
    _factories.clear();
  }
}

final sl = ServiceLocator();

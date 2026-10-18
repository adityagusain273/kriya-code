class Entitlements {
  final bool proTier;

  const Entitlements({required this.proTier});

  static const free = Entitlements(proTier: false);
}

abstract class EntitlementService {
  Future<Entitlements> current();
}

class FreeEntitlementService implements EntitlementService {
  const FreeEntitlementService();

  @override
  Future<Entitlements> current() async => Entitlements.free;
}

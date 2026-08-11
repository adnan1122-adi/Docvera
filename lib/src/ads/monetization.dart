/// Monetization seams for the app.
///
/// Today the build is fully free: every entitlement is granted and the only
/// advertising is the banner slots wired in the home and editor screens. When
/// paid tiers or rewarded ads ship, the implementation behind
/// [AdService.entitlements] can be swapped for a real one without touching any
/// screen code.
enum Entitlement {
  /// Everything the free build ships with.
  basic,

  /// Reserved for a future paid tier (subscriptions / in-app purchases).
  pro,
}

/// Decides what a given user may access.
abstract class EntitlementManager {
  const EntitlementManager();

  /// Whether the user is entitled to [entitlement].
  bool has(Entitlement entitlement);
}

/// Free build: every feature is unlocked for everyone.
class FreeEntitlementManager extends EntitlementManager {
  const FreeEntitlementManager();

  @override
  bool has(Entitlement entitlement) => true;
}
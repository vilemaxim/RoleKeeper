/// One configured LARP for switcher UI (keyed by [tenantKey]).
class UserGameOption {
  const UserGameOption({required this.tenantKey, required this.label});
  final String tenantKey;
  final String label;

  @Deprecated('Use tenantKey')
  String get gameId => tenantKey;
}

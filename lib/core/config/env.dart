/// Build-time environment, selected via `--dart-define=ENV=production`
/// (defaults to development when not specified, e.g. plain `flutter run`).
enum Environment { development, production }

abstract final class Env {
  static const Environment current =
      bool.fromEnvironment('dart.vm.product') || _isProductionDefine
      ? Environment.production
      : Environment.development;

  static const bool _isProductionDefine = bool.fromEnvironment('IS_PRODUCTION');

  static bool get isDevelopment => current == Environment.development;
  static bool get isProduction => current == Environment.production;
}

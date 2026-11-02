/// Runtime configuration, supplied at build time via
/// `--dart-define-from-file=env/<env>.json`.
///
/// Only the PUBLISHABLE key may ever be shipped in the app. A secret key
/// (`sb_secret_...`) is rejected at startup.
class AppConfig {
  AppConfig({
    required this.supabaseUrl,
    required this.publishableKey,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 15),
  });

  /// Reads `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` from compile-time
  /// environment declarations. Throws [AppConfigException] if they are missing
  /// or invalid.
  factory AppConfig.fromEnvironment() {
    const rawUrl = String.fromEnvironment('SUPABASE_URL');
    const rawKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

    final url = rawUrl.trim();
    final key = rawKey.trim();

    if (url.isEmpty) {
      throw const AppConfigException(
        'SUPABASE_URL is not set. Run with --dart-define-from-file=env/local.json',
      );
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw AppConfigException('SUPABASE_URL is not a valid http(s) URL: $url');
    }

    if (key.isEmpty) {
      throw const AppConfigException(
        'SUPABASE_PUBLISHABLE_KEY is not set. Run with --dart-define-from-file=env/local.json',
      );
    }
    if (key.startsWith('sb_secret_')) {
      throw const AppConfigException(
        'A secret key was supplied. Only the publishable key may be used in the app.',
      );
    }

    return AppConfig(supabaseUrl: uri, publishableKey: key);
  }

  final Uri supabaseUrl;
  final String publishableKey;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  /// Base URL for Edge Functions, always ending with a slash:
  /// `https://<project>.supabase.co/functions/v1/`
  String get functionsBaseUrl {
    final base = supabaseUrl.toString().replaceAll(RegExp(r'/+$'), '');
    return '$base/functions/v1/';
  }

  @override
  String toString() => 'AppConfig(supabaseUrl: $supabaseUrl)';
}

class AppConfigException implements Exception {
  const AppConfigException(this.message);

  final String message;

  @override
  String toString() => 'AppConfigException: $message';
}

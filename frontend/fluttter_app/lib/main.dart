import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Web: clean URLs (/join?code=...) instead of /#/join.
  usePathUrlStrategy();

  final AppConfig config;
  try {
    config = AppConfig.fromEnvironment();
  } on AppConfigException catch (e) {
    runApp(_ConfigErrorApp(message: e.message));
    return;
  }

  runApp(
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(config)],
      child: const SecretSantaApp(),
    ),
  );
}

/// Shown instead of the app when the build was started without a valid
/// environment file.
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Configuration error:\n$message', textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

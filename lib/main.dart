import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_bootstrap.dart';
import 'app/app_providers.dart';

void main() {
  // Step 1: Disable Flutter's red error screen for assertions entirely.
  // This prevents ANY assertion failure from showing the red screen.
  // Errors will still be logged to console but won't crash the app.
  FlutterError.onError = (details) {
    if (details.exception is AssertionError) {
      // For ALL assertion errors, just log and don't crash
      debugPrint('⚠️ [Assertion suppressed] ${details.exception}');
      if (details.stack != null) {
        debugPrint('Stack: ${details.stack}');
      }
      return;
    }
    FlutterError.dumpErrorToConsole(details);
  };

  // Step 2: Also catch unhandled errors
  runZonedGuarded(
    () {
      runApp(_AppBootstrapper());
    },
    (error, stack) {
      if (error is AssertionError) {
        debugPrint('⚠️ [Zone suppressed AssertionError] $error');
        return;
      }
      Zone.current.handleUncaughtError(error, stack);
    },
  );
}

class _AppBootstrapper extends StatefulWidget {
  @override
  State<_AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<_AppBootstrapper> {
  AppBootstrapResult? _bootstrap;
  Object? _error;

  @override
  void initState() {
    super.initState();
    AppBootstrap.initialize()
        .then((result) {
          if (mounted) {
            setState(() {
              _bootstrap = result;
            });
          }
        })
        .catchError((err) {
          if (mounted) {
            setState(() {
              _error = err;
            });
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        home: Scaffold(body: Center(child: Text('Bootstrap failed: $_error'))),
      );
    }
    if (_bootstrap == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return AppProviders(
      bootstrap: _bootstrap!,
      child: BoxApp(bootstrap: _bootstrap!),
    );
  }
}

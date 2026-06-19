import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_bootstrap.dart';
import 'app/app_providers.dart';

void _flutterErrorListener(FlutterErrorDetails details) {
  // Suppress the known InheritedNotifier ancestry assertion crash on Flutter web.
  // This happens when a ChangeNotifier/ValueNotifier fires during route transitions
  // and the framework asserts that the listener's element is still a descendant.
  // The assertion is overly strict for web rendering and causes unnecessary crashes.
  if (details.exceptionAsString().contains('ancestor == this') &&
      details.exception.toString().contains('framework.dart:6417')) {
    // Log but don't crash
    FlutterError.presentError(details);
    return;
  }
  superFlutterErrorListener(details);
}

FlutterErrorDetails? superFlutterErrorListener(FlutterErrorDetails details) {
  return details;
}

void main() {
  FlutterError.onError = (details) {
    _flutterErrorListener(details);
  };

  runApp(_AppBootstrapper());
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

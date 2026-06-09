import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/app_bootstrap.dart';
import 'app/app_providers.dart';
import 'utils/app_logger.dart';

Future<void> main() async {
  final bootstrap = await AppBootstrap.initialize();

  runZonedGuarded(
    () {
      runApp(
        AppProviders(
          bootstrap: bootstrap,
          child: BoxApp(bootstrap: bootstrap),
        ),
      );
    },
    (error, stack) {
      AppLogger.instance.logError(error, stack, 'ZONE');
    },
  );
}

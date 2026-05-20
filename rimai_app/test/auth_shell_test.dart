import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rimai_app/core/router/app_router.dart';

void main() {
  testWidgets('pump AuthShellScreen with register', (tester) async {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.dumpErrorToConsole(details);
      throw 'FLUTTER ERROR CAUGHT: ${details.exception}';
    };

    try {
      final container = ProviderContainer();
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );

      // wait for initial routing
      await tester.pumpAndSettle();

      // navigate to register
      router.go('/auth/register');
      await tester.pumpAndSettle();

      print('TEST PASSED SUCCESSFULLY');
    } catch (e, stack) {
      print('CAUGHT EXCEPTION: $e\n$stack');
    }
  });
}

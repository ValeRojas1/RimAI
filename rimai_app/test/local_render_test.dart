import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rimai_app/adapters/input/screens/auth/register_screen.dart';

void main() {
  testWidgets('pump register screen', (tester) async {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.dumpErrorToConsole(details);
      throw 'FLUTTER ERROR CAUGHT: ${details.exception}';
    };

    try {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RegisterScreen(),
              ),
            ),
          ),
        ),
      );
      print('TEST PASSED SUCCESSFULLY');
    } catch (e, stack) {
      print('CAUGHT EXCEPTION: $e\n$stack');
    }
  });
}

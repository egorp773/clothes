import 'package:clothes/core/app_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary page transitions have zero push and pop duration', () {
    final theme = buildAppTheme(Brightness.light);

    for (final platform in TargetPlatform.values) {
      final builder = theme.pageTransitionsTheme.builders[platform];
      expect(builder, isA<InstantPageTransitionsBuilder>());
      expect(builder!.transitionDuration, Duration.zero);
      expect(builder.reverseTransitionDuration, Duration.zero);
    }
  });

  testWidgets('a MaterialPageRoute replaces the previous page in one frame', (
    tester,
  ) async {
    late MaterialPageRoute<void> route;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            key: const Key('instant-route-underlay'),
            body: TextButton(
              key: const Key('open-instant-route'),
              onPressed: () {
                route = MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(key: Key('instant-route-destination')),
                );
                Navigator.of(context).push(route);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-instant-route')));
    await tester.pump();

    expect(route.animation, isNotNull);
    expect(route.animation!.isCompleted, isTrue);
    expect(find.byKey(const Key('instant-route-destination')), findsOneWidget);
    expect(find.byKey(const Key('instant-route-underlay')), findsNothing);
  });

  testWidgets('instant routes retain the rightward edge back swipe', (
    tester,
  ) async {
    late MaterialPageRoute<void> route;
    final theme = buildAppTheme(
      Brightness.light,
    ).copyWith(platform: TargetPlatform.iOS);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) => Scaffold(
            key: const Key('swipe-route-underlay'),
            body: TextButton(
              key: const Key('open-swipe-route'),
              onPressed: () {
                route = MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(key: Key('swipe-route-destination')),
                );
                Navigator.of(context).push(route);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-swipe-route')));
    await tester.pump();
    expect(route.animation!.value, 1);

    final gesture = await tester.startGesture(const Offset(1, 300));
    await gesture.moveBy(const Offset(500, 0));
    await tester.pump();

    expect(route.popGestureInProgress, isTrue);
    expect(route.animation!.value, lessThan(0.5));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('swipe-route-destination')), findsNothing);
    expect(find.byKey(const Key('swipe-route-underlay')), findsOneWidget);
  });
}

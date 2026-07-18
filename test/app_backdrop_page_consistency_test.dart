import 'dart:io';

import 'package:clothes/core/app_appearance.dart';
import 'package:clothes/widgets/app_appearance_background.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _onePixelWallpaper =
    'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

enum _LogicalPage { catalog, profile, messages, product }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shared app backdrop', () {
    for (final settings in <AppAppearanceSettings>[
      const AppAppearanceSettings(
        theme: AppThemePreference.custom,
        customDark: true,
        background: AppBackgroundStyle.plain,
        backgroundColorValue: 0xFF314054,
      ),
      const AppAppearanceSettings(
        theme: AppThemePreference.custom,
        customDark: true,
        background: AppBackgroundStyle.pattern,
        backgroundColorValue: 0xFF314054,
        pattern: AppPatternStyle.waves,
        patternColorValue: 0xFFE8EDF5,
        patternIntensity: 0.72,
      ),
      const AppAppearanceSettings(
        theme: AppThemePreference.custom,
        customDark: true,
        background: AppBackgroundStyle.photo,
        backgroundColorValue: 0xFF314054,
        wallpaperPath: _onePixelWallpaper,
        photoDim: 0.32,
      ),
    ]) {
      testWidgets(
        '${settings.background.name} has the same bare-area luminance on '
        'catalog, profile, messages and product',
        (tester) async {
          final page = ValueNotifier(_LogicalPage.catalog);
          addTearDown(page.dispose);

          await tester.pumpWidget(
            _BackdropProbe(settings: settings, page: page),
          );
          await tester.pump();

          final baseColorByPage = <_LogicalPage, Color>{};
          for (final logicalPage in _LogicalPage.values) {
            page.value = logicalPage;
            await tester.pump();
            final rootFinder = find.byKey(
              ValueKey('page-root-${logicalPage.name}'),
            );
            final backdrop = tester.element(rootFinder).appBackdrop;
            final pagePaint = switch (tester.widget(rootFinder)) {
              Scaffold scaffold => scaffold.backgroundColor!,
              ColoredBox coloredBox => coloredBox.color,
              final widget => throw TestFailure(
                'Unexpected ${widget.runtimeType} for ${logicalPage.name}',
              ),
            };

            if (backdrop.hasWallpaper) {
              expect(
                pagePaint.a,
                0,
                reason:
                    '${logicalPage.name} must not tint photo/pattern pixels a '
                    'second time',
              );
            }
            baseColorByPage[logicalPage] = Color.alphaBlend(
              pagePaint,
              backdrop.rootColor,
            );
          }

          final catalogBase = baseColorByPage[_LogicalPage.catalog]!;
          for (final logicalPage in _LogicalPage.values.skip(1)) {
            expect(
              baseColorByPage[logicalPage],
              catalogBase,
              reason:
                  '${logicalPage.name} added a page-wide tint over the shared '
                  '${settings.background.name} backdrop',
            );
            expect(
              baseColorByPage[logicalPage]!.computeLuminance(),
              closeTo(catalogBase.computeLuminance(), 0.000001),
            );
          }
        },
      );
    }

    test(
      'production page roots keep the shared-backdrop ownership contract',
      () {
        final appShell = File('lib/main.dart').readAsStringSync();
        final profile = File(
          'lib/screens/profile_screen.dart',
        ).readAsStringSync();
        final messages = File(
          'lib/screens/messages_screen.dart',
        ).readAsStringSync();
        final product = File(
          'lib/screens/product_screen.dart',
        ).readAsStringSync();

        // Catalog is hosted by AppShell, so the shell owns its page background.
        expect(appShell, contains('CatalogScreen('));
        expect(
          appShell,
          contains('backgroundColor: context.appBackdrop.scaffoldColor'),
        );
        expect(
          profile,
          contains('backgroundColor: context.appBackdrop.scaffoldColor'),
        );
        expect(messages, contains('color: context.appBackdrop.scaffoldColor'));

        // The product route deliberately exposes the still-painted catalog in
        // its top gap. Giving this outer scaffold its own color would recreate
        // the blank/solid backdrop regression during route transitions.
        expect(product, contains('key: productScreenScaffoldKey'));
        expect(product, contains('backgroundColor: Colors.transparent'));
      },
    );
  });
}

class _BackdropProbe extends StatelessWidget {
  const _BackdropProbe({required this.settings, required this.page});

  final AppAppearanceSettings settings;
  final ValueListenable<_LogicalPage> page;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildAppTheme(Brightness.dark, settings: settings),
      home: RepaintBoundary(
        child: AppAppearanceBackground(
          settings: settings,
          child: ValueListenableBuilder<_LogicalPage>(
            valueListenable: page,
            builder: (context, value, _) => _LogicalPageRoot(page: value),
          ),
        ),
      ),
    );
  }
}

class _LogicalPageRoot extends StatelessWidget {
  const _LogicalPageRoot({required this.page});

  final _LogicalPage page;

  @override
  Widget build(BuildContext context) {
    final color = context.appBackdrop.scaffoldColor;
    const body = SizedBox.expand();
    final rootKey = ValueKey('page-root-${page.name}');
    return switch (page) {
      // Catalog inherits the shell's Scaffold.
      _LogicalPage.catalog => Scaffold(
        key: rootKey,
        backgroundColor: color,
        body: body,
      ),
      _LogicalPage.profile => Scaffold(
        key: rootKey,
        backgroundColor: color,
        body: body,
      ),
      _LogicalPage.messages => ColoredBox(
        key: rootKey,
        color: color,
        child: body,
      ),
      // Product's outer route must expose the already painted root/underlay.
      _LogicalPage.product => Scaffold(
        key: rootKey,
        backgroundColor: Colors.transparent,
        body: body,
      ),
    };
  }
}

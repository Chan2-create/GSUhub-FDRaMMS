import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/features/settings/presentation/settings_screen.dart';

import '../support/fake_admin_backend.dart';
import '../support/fake_config_repository.dart';

/// Settings: the classification keywords (Objective 4.A).
void main() {
  Future<FakeConfigRepository> pump(
    WidgetTester tester, {
    FakeConfigRepository? config,
    Size size = const Size(1440, 2400),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = config ?? FakeConfigRepository();
    await tester.pumpWidget(
      fakeAdminScope(
        config: repository,
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  /// The add field of the [index]th damage type, in DamageCategory order.
  Finder addField(DamageCategory category) => find
      .widgetWithText(TextField, 'Add a keyword or phrase')
      .at(DamageCategory.values.indexOf(category));

  Future<void> add(
    WidgetTester tester,
    DamageCategory category,
    String keyword,
  ) async {
    await tester.enterText(addField(category), keyword);
    await tester.ensureVisible(find.byTooltip('Add to ${category.label}'));
    await tester.tap(find.byTooltip('Add to ${category.label}'));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('fits', () {
    double topOf(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    testWidgets('a laptop screen, the try box beside the keywords', (
      tester,
    ) async {
      // 1366 wide, less the 305-pixel sidebar.
      await pump(tester, size: const Size(1061, 2400));

      expect(tester.takeException(), isNull);
      expect(
        topOf(tester, 'Try a description'),
        topOf(tester, 'Classification keywords'),
      );
    });

    testWidgets('a narrow window, the try box below', (tester) async {
      await pump(tester, size: const Size(700, 3600));

      expect(tester.takeException(), isNull);
      expect(
        topOf(tester, 'Try a description'),
        greaterThan(topOf(tester, 'Classification keywords')),
      );
    });
  });

  testWidgets("lists each damage type's saved keywords", (tester) async {
    await pump(tester);

    expect(find.text('Classification keywords'), findsOneWidget);
    for (final category in DamageCategory.values) {
      expect(find.text(category.label), findsOneWidget);
    }
    expect(find.widgetWithText(InputChip, 'exposed wire'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'flooding'), findsOneWidget);
    expect(find.textContaining('Last saved'), findsOneWidget);
    expect(find.text('All changes saved.'), findsOneWidget);

    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save keywords'),
    );
    expect(save.onPressed, isNull, reason: 'nothing to save');
  });

  testWidgets('adds a keyword and saves the list, as the administrator', (
    tester,
  ) async {
    final config = await pump(tester);

    await add(tester, DamageCategory.plumbing, '  Burst   PIPE ');

    expect(find.widgetWithText(InputChip, 'burst pipe'), findsOneWidget);
    expect(find.textContaining('Unsaved changes'), findsOneWidget);

    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Save keywords'),
    );

    final saved = config.savedKeywordLists.single;
    expect(
      saved.keywordsByCategory[DamageCategory.plumbing],
      contains('burst pipe'),
    );
    expect(saved.updatedBy, fakeAdminUser.uid);
    expect(
      find.text(
        'Keywords saved. Reports filed from now on are classified with them.',
      ),
      findsOneWidget,
    );
    expect(find.text('All changes saved.'), findsOneWidget);
  });

  testWidgets("refuses another damage type's keyword, and says whose", (
    tester,
  ) async {
    await pump(tester);

    await add(tester, DamageCategory.plumbing, 'Exposed wire');

    expect(
      find.text(
        '"exposed wire" is already a keyword for Electrical. A keyword can '
        'point to one damage type only.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(InputChip, 'exposed wire'), findsOneWidget);
    expect(find.text('All changes saved.'), findsOneWidget);
  });

  testWidgets('removes a keyword, and discarding brings it back', (
    tester,
  ) async {
    final config = await pump(tester);

    await tapVisible(tester, find.byTooltip('Remove "flooding"'));

    expect(find.widgetWithText(InputChip, 'flooding'), findsNothing);
    expect(find.textContaining('Unsaved changes'), findsOneWidget);

    await tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Discard changes'),
    );

    expect(find.widgetWithText(InputChip, 'flooding'), findsOneWidget);
    expect(config.savedKeywordLists, isEmpty);
  });

  testWidgets("says when the manuscript's list is not saved yet", (
    tester,
  ) async {
    // A live project before any administrator saves a list: the app uses
    // Table 3.3's keywords.
    final config = await pump(
      tester,
      config: FakeConfigRepository(savedKeywords: false),
    );

    expect(find.text('Not saved yet'), findsOneWidget);
    expect(
      find.textContaining("These are the manuscript's keywords"),
      findsOneWidget,
    );
    expect(find.widgetWithText(InputChip, 'exposed wire'), findsOneWidget);

    // Saving the list unchanged is allowed: it keeps it in the project.
    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Save keywords'),
    );

    expect(config.savedKeywordLists, hasLength(1));
    expect(find.text('Not saved yet'), findsNothing);
    expect(find.textContaining('Last saved'), findsOneWidget);
  });

  testWidgets('a refused save is reported, and the edits are kept', (
    tester,
  ) async {
    await pump(
      tester,
      config: FakeConfigRepository(
        saveFailure: const PermissionFailure(
          'You do not have permission to do that.',
        ),
      ),
    );

    await add(tester, DamageCategory.plumbing, 'burst pipe');
    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Save keywords'),
    );

    expect(find.text('You do not have permission to do that.'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'burst pipe'), findsOneWidget);
    expect(find.textContaining('Unsaved changes'), findsOneWidget);
  });

  testWidgets('tries a description against the keywords being edited', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(
      find.widgetWithText(
        TextField,
        'e.g. Water is leaking from the pipe '
        'under the sink and the floor is flooding.',
      ),
      'A burst pipe in the chemistry lab',
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No keyword matched, so an administrator would classify it.'),
      findsOneWidget,
    );

    // Unsaved, and already applied to the try box.
    await add(tester, DamageCategory.plumbing, 'burst pipe');

    expect(find.text('Classified as Plumbing.'), findsOneWidget);
    expect(find.text('Plumbing: "burst pipe"'), findsOneWidget);
  });
}

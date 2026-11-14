import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/features/classification/data/models/prioritization_config.dart';
import 'package:gsuhub/features/classification/presentation/keyword_settings_section.dart';
import 'package:gsuhub/features/classification/presentation/scoring_settings_section.dart';
import 'package:gsuhub/features/settings/presentation/settings_screen.dart';

import '../support/app_fonts.dart';
import '../support/fake_admin_backend.dart';
import '../support/fake_config_repository.dart';

/// Settings: the classification keywords (Objective 4.A).
/// [finder], within the keyword section: the page's other sections
/// (Objective 7.A) say "Last saved" and "All changes saved." too.
Finder inKeywords(Finder finder) =>
    find.descendant(of: find.byType(KeywordSettingsSection), matching: finder);

void main() {
  // The app's real fonts, so whether a tab fits is measured as a browser
  // would draw it.
  setUpAll(loadAppFonts);

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

  /// Opens the tab named [label].
  Future<void> openTab(WidgetTester tester, String label) async {
    // On a phone the tab row scrolls sideways.
    await tester.ensureVisible(find.text(label).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  /// Adds [keyword] to [category]: Add keyword opens the box for it.
  Future<void> add(
    WidgetTester tester,
    DamageCategory category,
    String keyword,
  ) async {
    final open = find.byTooltip('Add a keyword to ${category.label}');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a keyword or phrase'),
      keyword,
    );
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

    testWidgets('every tab, on a phone and on a tablet', (tester) async {
      for (final size in const [Size(320, 2600), Size(768, 2600)]) {
        await pump(tester, size: size);
        for (final tab in [
          'Priority scoring',
          'Duplicate detection',
          'Keywords',
        ]) {
          await openTab(tester, tab);
          expect(
            tester.takeException(),
            isNull,
            reason: '$tab at ${size.width.toInt()} wide',
          );
        }
      }
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
    expect(inKeywords(find.textContaining('Last saved')), findsOneWidget);
    expect(inKeywords(find.text('All changes saved.')), findsOneWidget);

    final save = tester.widget<FilledButton>(
      inKeywords(find.widgetWithText(FilledButton, 'Save changes')),
    );
    expect(save.onPressed, isNull, reason: 'nothing to save');
  });

  testWidgets('adds a keyword and saves the list, as the administrator', (
    tester,
  ) async {
    final config = await pump(tester);

    await add(tester, DamageCategory.plumbing, '  Burst   PIPE ');

    expect(find.widgetWithText(InputChip, 'burst pipe'), findsOneWidget);
    expect(inKeywords(find.textContaining('Unsaved changes')), findsOneWidget);

    await tapVisible(
      tester,
      inKeywords(find.widgetWithText(FilledButton, 'Save changes')),
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
    expect(inKeywords(find.text('All changes saved.')), findsOneWidget);
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
    expect(inKeywords(find.text('All changes saved.')), findsOneWidget);
  });

  testWidgets('removes a keyword, and discarding brings it back', (
    tester,
  ) async {
    final config = await pump(tester);

    await tapVisible(tester, find.byTooltip('Remove "flooding"'));

    expect(find.widgetWithText(InputChip, 'flooding'), findsNothing);
    expect(inKeywords(find.textContaining('Unsaved changes')), findsOneWidget);

    await tapVisible(
      tester,
      inKeywords(find.widgetWithText(OutlinedButton, 'Discard changes')),
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

    expect(inKeywords(find.text('Not saved yet')), findsOneWidget);
    expect(
      find.textContaining('These are the default keywords'),
      findsOneWidget,
    );
    expect(find.widgetWithText(InputChip, 'exposed wire'), findsOneWidget);

    // Saving the list unchanged is allowed: it keeps it in the project.
    await tapVisible(
      tester,
      inKeywords(find.widgetWithText(FilledButton, 'Save changes')),
    );

    expect(config.savedKeywordLists, hasLength(1));
    expect(inKeywords(find.text('Not saved yet')), findsNothing);
    expect(inKeywords(find.textContaining('Last saved')), findsOneWidget);
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
      inKeywords(find.widgetWithText(FilledButton, 'Save changes')),
    );

    expect(find.text('You do not have permission to do that.'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'burst pipe'), findsOneWidget);
    expect(inKeywords(find.textContaining('Unsaved changes')), findsOneWidget);
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

  // ------------------------------------------------- scoring (Objective 7.A)

  Finder inPriority(Finder finder) => find.descendant(
    of: find.byType(PrioritySettingsSection),
    matching: finder,
  );
  Finder inDuplicates(Finder finder) => find.descendant(
    of: find.byType(DuplicateSettingsSection),
    matching: finder,
  );

  testWidgets('priority scoring keeps both sets of weights and shows the one '
      'in use', (tester) async {
    await pump(tester);
    await openTab(tester, 'Priority scoring');

    expect(
      inPriority(find.textContaining('The study gives two sets')),
      findsOneWidget,
    );
    expect(inPriority(find.text('Formula weights')), findsOneWidget);
    expect(inPriority(find.text('Table weights')), findsOneWidget);
    // The sample score reads with the saved settings.
    expect(inPriority(find.textContaining('would score 2.70')), findsOneWidget);

    // Four boxes, the formula's: the other set shows when it is chosen.
    final severity = inPriority(find.widgetWithText(TextField, 'Severity'));
    expect(severity, findsOneWidget);
    expect(tester.widget<TextField>(severity).controller!.text, '0.4');
    await tester.tap(inPriority(find.text('Table weights')));
    await tester.pumpAndSettle();
    expect(severity, findsOneWidget);
    expect(tester.widget<TextField>(severity).controller!.text, '3');
  });

  testWidgets('score bands out of order are refused before saving', (
    tester,
  ) async {
    final config = await pump(tester);
    await openTab(tester, 'Priority scoring');

    await tester.enterText(
      inPriority(find.widgetWithText(TextField, 'CRITICAL')),
      '2',
    );
    await tester.pumpAndSettle();

    expect(
      inPriority(find.text('The score bands must fall from Critical to Low.')),
      findsOneWidget,
    );
    final save = inPriority(find.widgetWithText(FilledButton, 'Save changes'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(config.savedPrioritizations, isEmpty);
  });

  testWidgets('choosing the table weights and saving keeps them', (
    tester,
  ) async {
    final config = await pump(tester);
    await openTab(tester, 'Priority scoring');

    await tester.ensureVisible(inPriority(find.text('Table weights')));
    await tester.tap(inPriority(find.text('Table weights')));
    await tester.pumpAndSettle();
    final save = inPriority(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(config.savedPrioritizations, hasLength(1));
    expect(
      config.savedPrioritizations.single.activeScheme,
      PrioritizationScheme.integerWeights,
    );
    expect(config.savedPrioritizations.single.updatedBy, fakeAdminUser.uid);
  });

  testWidgets('the duplicate rules save, with the window in hours', (
    tester,
  ) async {
    final config = await pump(tester);
    await openTab(tester, 'Duplicate detection');

    final hours = inDuplicates(
      find.widgetWithText(TextField, 'Window, in hours'),
    );
    await tester.ensureVisible(hours);
    await tester.enterText(hours, '48');
    await tester.pumpAndSettle();
    final save = inDuplicates(
      find.widgetWithText(FilledButton, 'Save changes'),
    );
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(config.savedDuplicateSettings.single.timeWindowHours, 48);
  });

  // ------------------------------------------------- the tabs (2026-11-14)

  group('tabs', () {
    testWidgets('one topic at a time, opening on Keywords', (tester) async {
      await pump(tester);

      expect(find.text('Classification keywords'), findsOneWidget);
      expect(find.text('Priority levels'), findsNothing);
      expect(find.text('Compare on'), findsNothing);

      await openTab(tester, 'Priority scoring');
      expect(find.text('Priority levels'), findsOneWidget);
      expect(find.text('Classification keywords'), findsNothing);

      await openTab(tester, 'Duplicate detection');
      expect(find.text('Compare on'), findsOneWidget);
      expect(find.text('Priority levels'), findsNothing);
    });

    testWidgets('every tab ends in the same two buttons', (tester) async {
      await pump(tester);

      for (final tab in [
        'Keywords',
        'Priority scoring',
        'Duplicate detection',
      ]) {
        await openTab(tester, tab);
        expect(
          find.widgetWithText(OutlinedButton, 'Discard changes'),
          findsOneWidget,
          reason: tab,
        );
        expect(
          find.widgetWithText(FilledButton, 'Save changes'),
          findsOneWidget,
          reason: tab,
        );
      }
    });

    testWidgets('a tab with unsaved edits is marked, and keeps them while '
        'another is open', (tester) async {
      await pump(tester);
      expect(find.byTooltip('Unsaved changes'), findsNothing);

      await add(tester, DamageCategory.plumbing, 'burst pipe');
      expect(find.byTooltip('Unsaved changes'), findsOneWidget);

      // A look at another tab loses nothing.
      await openTab(tester, 'Duplicate detection');
      expect(find.widgetWithText(InputChip, 'burst pipe'), findsNothing);
      expect(find.byTooltip('Unsaved changes'), findsOneWidget);
      await openTab(tester, 'Keywords');
      expect(find.widgetWithText(InputChip, 'burst pipe'), findsOneWidget);

      // Discarded, the mark goes.
      await tapVisible(
        tester,
        inKeywords(find.widgetWithText(OutlinedButton, 'Discard changes')),
      );
      expect(find.byTooltip('Unsaved changes'), findsNothing);
    });

    testWidgets('the box for a new keyword opens on Add keyword, and closes', (
      tester,
    ) async {
      await pump(tester);

      // No empty box under every damage type.
      final box = find.widgetWithText(TextField, 'Add a keyword or phrase');
      expect(box, findsNothing);

      await tapVisible(tester, find.byTooltip('Add a keyword to Plumbing'));
      expect(box, findsOneWidget);

      await tapVisible(tester, find.byTooltip('Done adding to Plumbing'));
      expect(box, findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/routing/route_paths.dart';

import '../support/app_fonts.dart';
import '../support/fake_requestor_app.dart';

/// The sign-in and sign-up pages fit the phone they are on (2026-11-13):
/// nothing to scroll, nothing cut off, from a small phone to a large one.
/// With the app's real fonts, so the measurements are the phone's.
void main() {
  setUpAll(loadAppFonts);

  // Width x height in logical pixels, as phones report them.
  const phones = <String, Size>{
    'small (320x568)': Size(320, 568),
    'compact, short (360x640)': Size(360, 640),
    'compact (360x800)': Size(360, 800),
    'common, short (375x667)': Size(375, 667),
    'common (375x812)': Size(375, 812),
    'modern (390x844)': Size(390, 844),
    'large (430x932)': Size(430, 932),
  };

  const pages = <String, String>{
    'sign-in': RoutePaths.staffLogin,
    'sign-up': RoutePaths.staffSignUp,
  };

  /// A status bar and a gesture bar, as a real phone has.
  void notches(WidgetTester tester) {
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 16);
    tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 16);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
  }

  Future<void> open(WidgetTester tester, String path, Size phone) async {
    final app = RequestorHarness(signedIn: null);
    await app.pump(tester, start: path);
    tester.view.physicalSize = phone;
    await tester.pumpAndSettle();
  }

  final university = find.text('DAVAO ORIENTAL STATE UNIVERSITY');

  for (final MapEntry(key: page, value: path) in pages.entries) {
    group(page, () {
      for (final MapEntry(key: name, value: phone) in phones.entries) {
        testWidgets('fits a $name phone without scrolling', (tester) async {
          notches(tester);
          await open(tester, path, phone);

          final scroll = Scrollable.of(tester.element(university)).position;
          expect(scroll.maxScrollExtent, 0, reason: 'nothing to scroll');

          // The whole page is on the glass: the mark at the top, the
          // footer line at the bottom, the card inside the sides.
          final logo = tester.getRect(find.bySemanticsLabel('GSUhub'));
          final footer = tester.getRect(
            find.textContaining('GSU', findRichText: true).last,
          );
          expect(logo.top, greaterThanOrEqualTo(0));
          expect(footer.bottom, lessThanOrEqualTo(phone.height));
          final fields = tester.getRect(find.byType(TextField).first);
          expect(fields.left, greaterThan(0));
          expect(fields.right, lessThan(phone.width));
        });
      }
    });
  }

  testWidgets('with the keyboard up, the field being typed in stays in view', (
    tester,
  ) async {
    notches(tester);
    const phone = Size(360, 640);
    await open(tester, RoutePaths.staffSignUp, phone);

    final confirm = find.byType(TextField).last;
    await tester.showKeyboard(confirm);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final field = tester.getRect(confirm);
    expect(field.bottom, lessThanOrEqualTo(phone.height - 280));
    expect(field.top, greaterThanOrEqualTo(0));
    // And the page is not shrunk to fit above the keyboard: it scrolls.
    final scroll = Scrollable.of(tester.element(university)).position;
    expect(scroll.maxScrollExtent, greaterThan(0));
  });
}

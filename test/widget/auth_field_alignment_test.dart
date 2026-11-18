import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/features/auth/presentation/widgets/mobile_auth_layout.dart';

import '../support/app_fonts.dart';
import '../support/fake_requestor_app.dart';

/// The text in a phone sign-in or Create Account field sits in the middle
/// of its box: typed, masked, shown, and with the eye beside it
/// (2026-11-17). Measured with the app's real fonts, on phones of several
/// sizes, as the boxes are drawn.
void main() {
  setUpAll(loadAppFonts);

  const phones = {
    'small': Size(320, 568),
    'compact': Size(360, 640),
    'common': Size(375, 812),
    'modern': Size(390, 844),
    'large': Size(430, 932),
  };

  Finder fieldWithHint(String hint) => find.widgetWithText(TextField, hint);

  /// The box an input is drawn in.
  Rect boxOf(WidgetTester tester, Finder field) => tester.getRect(
    find.ancestor(of: field, matching: find.byType(AuthFieldBox)).first,
  );

  /// Where the text is laid out: the field's editable line.
  Rect textOf(WidgetTester tester, Finder field) => tester.getRect(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );

  /// How far the text's middle is from the box's middle, in the box's own
  /// terms: the page is scaled to fit, so pixels are divided out.
  double offCentre(WidgetTester tester, Finder field) {
    final box = boxOf(tester, field);
    final text = textOf(tester, field);
    return (text.center.dy - box.center.dy).abs() / box.height;
  }

  for (final MapEntry(key: name, value: phone) in phones.entries) {
    testWidgets('Create Account on a $name phone: every field centred, '
        'hidden or shown', (tester) async {
      final app = RequestorHarness(signedIn: null);
      await app.pump(tester, start: RoutePaths.staffSignUp);
      tester.view.physicalSize = phone;
      await tester.pumpAndSettle();

      final email = fieldWithHint('juan.dc@dorsu.edu.ph');
      final password = fieldWithHint('••••••••').at(0);
      final confirm = fieldWithHint('••••••••').at(1);

      await tester.enterText(password, 'Gsuhub#2026');
      await tester.enterText(confirm, 'Gsuhub#2026');
      await tester.pump();

      // A plain field, and both password fields, masked.
      for (final (label, field) in [
        ('email', email),
        ('password', password),
        ('confirm', confirm),
      ]) {
        expect(
          offCentre(tester, field),
          lessThan(0.02),
          reason: '$label text is off the middle of its box',
        );
      }
      // The two password fields alike, to the pixel.
      expect(
        textOf(tester, password).top - boxOf(tester, password).top,
        closeTo(textOf(tester, confirm).top - boxOf(tester, confirm).top, 0.5),
      );
      // And the same as a field with no eye.
      expect(
        textOf(tester, password).top - boxOf(tester, password).top,
        closeTo(textOf(tester, email).top - boxOf(tester, email).top, 0.5),
      );

      // The eye is in the middle of the box too, at its right.
      final eye = tester.getRect(find.byTooltip('Show password').first);
      final box = boxOf(tester, password);
      expect(
        (eye.center.dy - box.center.dy).abs() / box.height,
        lessThan(0.02),
      );
      expect(eye.right, lessThanOrEqualTo(box.right));
      expect(eye.left, greaterThan(textOf(tester, password).left));

      // Shown, it stays where it was.
      final before = textOf(tester, password);
      await tester.tap(find.byTooltip('Show password').first);
      await tester.pump();
      expect(tester.widget<TextField>(password).obscureText, isFalse);
      expect(textOf(tester, password).top, closeTo(before.top, 0.5));
      expect(offCentre(tester, password), lessThan(0.02));

      // The cursor sits on the text's line.
      await tester.tap(password);
      await tester.pump();
      final editable = tester.state<EditableTextState>(
        find.descendant(of: password, matching: find.byType(EditableText)),
      );
      final caret = editable.renderEditable.getLocalRectForCaret(
        const TextPosition(offset: 3),
      );
      final line = editable.renderEditable.size.height;
      expect(
        (caret.center.dy - line / 2).abs() / line,
        lessThan(0.15),
        reason: 'the cursor is on the middle of the line',
      );
    });
  }

  testWidgets('sign-in: the password and its eye centred as the email is', (
    tester,
  ) async {
    final app = RequestorHarness(signedIn: null);
    await app.pump(tester);

    final email = fieldWithHint('e.g. juan.dc@dorsu.edu.ph');
    final password = fieldWithHint('••••••••');
    await tester.enterText(password, 'Gsuhub#2026');
    await tester.pump();

    expect(offCentre(tester, email), lessThan(0.02));
    expect(offCentre(tester, password), lessThan(0.02));
    final eye = tester.getRect(find.byTooltip('Show password'));
    final box = boxOf(tester, password);
    expect((eye.center.dy - box.center.dy).abs() / box.height, lessThan(0.02));
  });
}

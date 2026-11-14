import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/shells/app_viewport.dart';

import '../support/fake_personnel_app.dart';
import '../support/fake_requestor_app.dart';

/// The phone apps keep their 390-wide design on every phone (2026-11-12):
/// a narrower phone shows it scaled to fit, and the phone's font-size
/// setting cannot make text larger than drawn. Found on a 360-wide phone
/// at 115% text, where the sign-in button wrapped and the page read as
/// zoomed in. The administrator console is not touched.
void main() {
  /// What a page inside the app is told about the screen.
  MediaQueryData inside(WidgetTester tester, Finder page) =>
      MediaQuery.of(tester.element(page));

  void phoneTextSize(WidgetTester tester, double scale) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> signInPage(WidgetTester tester, Size phone) async {
    final app = RequestorHarness(signedIn: null);
    await app.pump(tester, start: RoutePaths.staffLogin);
    tester.view.physicalSize = phone;
    await tester.pumpAndSettle();
  }

  test('knows the phone apps from the console', () {
    expect(AppViewport.isPhonePage(RoutePaths.staffLogin), isTrue);
    expect(AppViewport.isPhonePage(RoutePaths.staffHome), isTrue);
    expect(AppViewport.isPhonePage(RoutePaths.personnelDashboard), isTrue);
    expect(AppViewport.isPhonePage(RoutePaths.adminDashboard), isFalse);
    expect(AppViewport.isPhonePage(RoutePaths.adminLogin), isFalse);
    expect(AppViewport.isPhonePage(''), isFalse);
  });

  testWidgets('a 360-wide phone shows the 390 design, scaled to fit', (
    tester,
  ) async {
    phoneTextSize(tester, 1.15);
    await signInPage(tester, const Size(360, 811));

    final media = inside(tester, find.text('Welcome back'));
    expect(media.size.width, AppViewport.phoneDesignWidth);
    // The same shape, in the design's units.
    expect(media.size.height, closeTo(811 * 390 / 360, 0.01));
    // Larger text than drawn is not let in.
    expect(media.textScaler.scale(10), 10);

    // On the glass it still fills the phone exactly, edge to edge.
    final onGlass = tester.getRect(find.byType(Scaffold).first);
    expect(onGlass.width, closeTo(360, 0.01));
    expect(onGlass.height, closeTo(811, 0.01));
    // And the sign-in button reads on one line: it wrapped before.
    expect(
      tester.getSize(find.text('LOGIN TO DASHBOARD')).height,
      lessThan(22),
    );
  });

  testWidgets('a phone at the design width or wider is not scaled', (
    tester,
  ) async {
    phoneTextSize(tester, 1.3);
    await signInPage(tester, const Size(412, 915));

    final media = inside(tester, find.text('Welcome back'));
    expect(media.size, const Size(412, 915));
    expect(media.textScaler.scale(10), 10);
  });

  testWidgets('smaller text than drawn is honoured', (tester) async {
    phoneTextSize(tester, 0.85);
    await signInPage(tester, const Size(390, 844));

    expect(
      inside(tester, find.text('Welcome back')).textScaler.scale(10),
      closeTo(8.5, 0.001),
    );
  });

  testWidgets('a field under the keyboard is measured in the design\'s '
      'units too', (tester) async {
    await signInPage(tester, const Size(360, 811));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(
      // Read at the page itself: a Scaffold takes the keyboard out of
      // what it tells its body.
      inside(tester, find.byType(Scaffold).first).viewInsets.bottom,
      closeTo(300 * 390 / 360, 0.01),
    );
  });

  testWidgets('a dropdown opens where it is pressed on a fitted phone: '
      'Building, then Room', (tester) async {
    const phone = Size(320, 640);
    final app = RequestorHarness();
    await app.pump(tester, start: RoutePaths.staffSubmitReport);
    tester.view.physicalSize = phone;
    await tester.pumpAndSettle();

    Future<void> choose(String current, String choice) async {
      await tester.ensureVisible(find.text(current));
      await tester.pumpAndSettle();
      await tester.tap(find.text(current));
      await tester.pumpAndSettle();
      // The menu is on the glass, where a finger can reach it.
      final item = tester.getRect(find.text(choice).last);
      expect(item.left, greaterThanOrEqualTo(0));
      expect(item.right, lessThanOrEqualTo(phone.width));
      expect(item.top, greaterThanOrEqualTo(0));
      expect(item.bottom, lessThanOrEqualTo(phone.height));
      await tester.tap(find.text(choice).last);
      await tester.pumpAndSettle();
    }

    await choose('Select Building', 'Main Library');
    await choose('Select Room', 'Level 2');
    expect(find.text('Main Library'), findsOneWidget);
    expect(find.text('Level 2'), findsOneWidget);
  });

  // The console (2026-11-13): drawn at 90% on anything wider than a
  // phone, in a window that much larger, so more of every page is on
  // screen. It read as zoomed in at the Figma sizes on a 1536px laptop.
  group('the administrator console', () {
    Future<void> console(WidgetTester tester, Size window) async {
      final app = PersonnelHarness(signedIn: fakeAdministrator);
      await app.data.addPersonnel(fakeAdministrator.uid, role: UserRole.admin);
      await app.pump(
        tester,
        start: RoutePaths.adminNotifications,
        size: window,
      );
    }

    test('is 90% from 720 wide, full size on a phone', () {
      double at(double width) =>
          AppViewport.scaleFor(phonePage: false, width: width);
      expect(at(1536), AppViewport.consoleScale);
      expect(at(720), AppViewport.consoleScale);
      expect(at(719), 1);
      expect(at(360), 1);
      expect(AppViewport.consoleScale, 0.9);
    });

    testWidgets('on a laptop is laid out in a larger window and fills the '
        'glass', (tester) async {
      phoneTextSize(tester, 1.1);
      await console(tester, const Size(1536, 734));

      final media = inside(tester, find.byType(Scaffold).first);
      expect(media.size.width, closeTo(1536 / 0.9, 0.01));
      expect(media.size.height, closeTo(734 / 0.9, 0.01));
      // The browser's own text size is still followed.
      expect(media.textScaler.scale(10), closeTo(11, 0.001));

      final onGlass = tester.getRect(find.byType(Scaffold).first);
      expect(onGlass.left, closeTo(0, 0.01));
      expect(onGlass.width, closeTo(1536, 0.01));
      expect(onGlass.height, closeTo(734, 0.01));
    });

    testWidgets('on a phone-width window keeps its phone layout at full size', (
      tester,
    ) async {
      phoneTextSize(tester, 1.1);
      await console(tester, const Size(360, 900));

      final media = inside(tester, find.byType(Scaffold).first);
      expect(media.size, const Size(360, 900));
      expect(media.textScaler.scale(10), closeTo(11, 0.001));
    });
  });
}

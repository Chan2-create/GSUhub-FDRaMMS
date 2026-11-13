import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/routing/route_paths.dart';

import '../support/app_fonts.dart';
import '../support/fake_notifications.dart';
import '../support/fake_personnel_app.dart';
import '../support/fake_requestor_app.dart';

/// Both phone apps, every page, on every size of phone (2026-11-13): a
/// small one, the compact and common Android and iPhone sizes, a large
/// one, and a tablet. Nothing overflows and nothing throws: either fails
/// the test by itself, naming the widget. With the app's real fonts, so
/// the room text takes is the phone's.
void main() {
  setUpAll(loadAppFonts);

  const screens = <String, Size>{
    '320x568': Size(320, 568),
    '360x640': Size(360, 640),
    '375x667': Size(375, 667),
    '390x844': Size(390, 844),
    '430x932': Size(430, 932),
    'tablet 768x1024': Size(768, 1024),
  };

  /// A status bar and a gesture bar, as a real phone has.
  void notches(WidgetTester tester) {
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 16);
    tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 16);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
  }

  /// The page fills the screen edge to edge, and no wider.
  void fillsTheScreen(WidgetTester tester, Size screen) {
    final page = tester.getRect(find.byType(Scaffold).first);
    expect(page.left, closeTo(0, 0.01));
    expect(page.width, closeTo(screen.width, 0.01));
  }

  group('faculty and staff', () {
    const pages = <String, String>{
      'Sign in': RoutePaths.staffLogin,
      'Sign up': RoutePaths.staffSignUp,
      'Home': RoutePaths.staffHome,
      'Report damage': RoutePaths.staffSubmitReport,
      'My reports': RoutePaths.staffMyReports,
      'Report tracking': '/staff/reports/r-1',
      'Rate the service': '/staff/reports/r-2/rate',
      'Notifications': RoutePaths.staffAlerts,
      'Profile': RoutePaths.staffProfile,
    };

    for (final MapEntry(key: name, value: path) in pages.entries) {
      for (final MapEntry(key: label, value: screen) in screens.entries) {
        testWidgets('$name fits $label', (tester) async {
          notches(tester);
          final signedOut =
              path == RoutePaths.staffLogin || path == RoutePaths.staffSignUp;
          final app = RequestorHarness(
            signedIn: signedOut ? null : fakeRequestor,
            reports: [
              fakeMyReport(
                'r-1',
                status: ReportStatus.inProgress,
                location:
                    'College of Engineering and Technology Building, '
                    'Room 302',
                title: 'Air conditioner leaking water onto the projector',
                workOrderId: 'wo-1',
              ),
              fakeMyReport(
                'r-2',
                status: ReportStatus.completed,
                workOrderId: 'wo-2',
              ),
              fakeMyReport(
                'r-3',
                status: ReportStatus.rejected,
                rejectionReason: 'Already reported by another faculty member.',
              ),
            ],
            notices: [
              fakeNotice('n-1', reportId: 'r-1'),
              fakeNotice('n-2'),
            ],
          );
          await app.pump(tester, start: path);
          tester.view.physicalSize = screen;
          await tester.pumpAndSettle();

          fillsTheScreen(tester, screen);
        });
      }
    }
  });

  group('maintenance personnel', () {
    const pages = <String, String>{
      'Dashboard': RoutePaths.personnelDashboard,
      'Tasks': RoutePaths.personnelTasks,
      'Work orders': RoutePaths.personnelWorkOrders,
      'Work order': '/personnel/work-orders/wo-1',
      'Record materials': '/personnel/work-orders/wo-1/materials',
      'Materials and tools': RoutePaths.personnelMaterials,
      'Scanner': RoutePaths.personnelScanning,
      'Notifications': RoutePaths.personnelAlerts,
      'Profile': RoutePaths.personnelProfile,
    };

    for (final MapEntry(key: name, value: path) in pages.entries) {
      for (final MapEntry(key: label, value: screen) in screens.entries) {
        testWidgets('$name fits $label', (tester) async {
          notches(tester);
          final app = PersonnelHarness();
          await app.seedJob();
          await app.pump(tester, start: path, size: screen);

          fillsTheScreen(tester, screen);
        });
      }
    }
  });
}

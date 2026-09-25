import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/widgets/filter_select.dart';

/// The "All …" option is how a filter is cleared, and it carries no value.
/// A popup menu treats a null selection as a cancel, so the option has to
/// reach [FilterSelect.onChanged] some other way.
void main() {
  testWidgets('choosing the "all" option clears the filter', (tester) async {
    String? selected = 'plumbing';
    final changes = <String?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FilterSelect<String>(
              placeholder: 'Damage Type',
              value: selected,
              onChanged: (value) => setState(() {
                changes.add(value);
                selected = value;
              }),
              options: const [
                FilterOption(value: null, label: 'All damage types'),
                FilterOption(value: 'plumbing', label: 'Plumbing'),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Plumbing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All damage types').last);
    await tester.pumpAndSettle();

    expect(changes, [null]);
    expect(find.text('Damage Type'), findsOneWidget);
  });
}

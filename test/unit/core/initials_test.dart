import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/utils/initials.dart';

/// One monogram per person, whichever screen shows them. The assignment
/// panel and the Kanban cards used to compute this separately and
/// disagreed on names with a particle.
void main() {
  test('two names give both initials', () {
    expect(initialsOf('Ricardo Dalisay'), 'RD');
  });

  test('a single name gives one initial', () {
    expect(initialsOf('Madonna'), 'M');
  });

  test('a particle does not displace the surname', () {
    // The board's old copy took the second word and returned "JD".
    expect(initialsOf('Juan Dela Cruz'), 'JC');
    expect(initialsOf('Maria Teresa Dela Rosa'), 'MR');
  });

  test('extra whitespace is ignored', () {
    expect(initialsOf('  Ricardo   Dalisay  '), 'RD');
  });

  test('a blank name does not throw', () {
    // AppUser rejects a blank name, so this is a guard, not a case that
    // reaches the screens — but the old copy threw a StateError on it.
    expect(initialsOf('   '), '?');
    expect(initialsOf(''), '?');
  });
}

import 'package:characters/characters.dart';

/// The two-letter monogram shown in an avatar circle.
///
/// "Ricardo Dalisay" becomes "RD"; a single name becomes its first letter.
/// Names with a particle — "Juan Dela Cruz" — take the first and last
/// parts, so the surname is what shows rather than the particle.
///
/// Shared by the assignment panel and the Kanban cards: the same person
/// must not appear as two different monograms depending on the screen.
String initialsOf(String fullName) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  // AppUser rejects a blank name, so this is a guard rather than a case
  // that happens — but it is one `characters.first` would throw on.
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first)
      .toUpperCase();
}

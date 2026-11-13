import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the app's real fonts into a widget test.
///
/// Tests otherwise draw every letter as a square the size of the font,
/// about twice as wide as Public Sans, so anything that depends on how
/// much room text takes (does this page fit the phone, does this label
/// wrap) would be measured wrong. Call it once, in `setUpAll`.
Future<void> loadAppFonts() async {
  const families = {
    'Public Sans': ['Regular', 'Medium', 'SemiBold', 'Bold'],
    'Poppins': ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold'],
    'Roboto Mono': ['Regular'],
  };
  for (final MapEntry(key: family, value: weights) in families.entries) {
    final loader = FontLoader(family);
    final file = family.replaceAll(' ', '');
    for (final weight in weights) {
      final bytes = File('assets/fonts/$file-$weight.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

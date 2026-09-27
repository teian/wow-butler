import 'dart:math';

final _random = Random.secure();

/// Random 16 character hex identifier.
String newId() => List.generate(
  8,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

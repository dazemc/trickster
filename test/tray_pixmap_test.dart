import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/status_notifier.dart';

void main() {
  Uint8List bytes(List<int> values) => Uint8List.fromList(values);

  test('identical and equal-copy pixmaps are equal with equal hashes', () {
    final rgba = bytes(<int>[255, 0, 0, 255, 0, 255, 0, 255]);
    final first = SystemTrayIconPixmap(width: 2, height: 1, rgba: rgba);
    final copy = SystemTrayIconPixmap(
      width: 2,
      height: 1,
      rgba: bytes(<int>[255, 0, 0, 255, 0, 255, 0, 255]),
    );

    expect(first == first, isTrue);
    expect(first == copy, isTrue);
    expect(copy == first, isTrue);
    expect(first.hashCode, copy.hashCode);
  });

  test('different bytes with the same dimensions are unequal', () {
    final first = SystemTrayIconPixmap(
      width: 2,
      height: 1,
      rgba: bytes(<int>[255, 0, 0, 255, 0, 255, 0, 255]),
    );
    final second = SystemTrayIconPixmap(
      width: 2,
      height: 1,
      rgba: bytes(<int>[255, 0, 0, 255, 0, 0, 255, 255]),
    );

    expect(first == second, isFalse);
    expect(first.hashCode == second.hashCode, isFalse);
  });

  test('a forced digest collision still compares full bytes', () {
    final first = SystemTrayIconPixmap.withDigest(
      width: 2,
      height: 1,
      rgba: bytes(<int>[255, 0, 0, 255, 0, 255, 0, 255]),
      digest: 0x12345678,
    );
    final sameBytes = SystemTrayIconPixmap.withDigest(
      width: 2,
      height: 1,
      rgba: bytes(<int>[255, 0, 0, 255, 0, 255, 0, 255]),
      digest: 0x12345678,
    );
    final differentBytes = SystemTrayIconPixmap.withDigest(
      width: 2,
      height: 1,
      rgba: bytes(<int>[255, 0, 0, 255, 0, 0, 255, 255]),
      digest: 0x12345678,
    );

    expect(first == sameBytes, isTrue);
    expect(first == differentBytes, isFalse);
    expect(first.hashCode, sameBytes.hashCode);
  });

  test('different dimensions never compare equal', () {
    final wide = SystemTrayIconPixmap(
      width: 2,
      height: 1,
      rgba: bytes(<int>[0, 0, 0, 255, 0, 0, 0, 255]),
    );
    final tall = SystemTrayIconPixmap(
      width: 1,
      height: 2,
      rgba: bytes(<int>[0, 0, 0, 255, 0, 0, 0, 255]),
    );

    expect(wide == tall, isFalse);
  });
}

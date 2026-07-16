import 'package:ascona_returns_scanner/domain/barcode_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cleanScannedValue', () {
    test('trims whitespace and scanner control characters', () {
      expect(cleanScannedValue('\u0002480381351623\r\n'), '480381351623');
    });

    test('keeps order URL intact', () {
      const value = 'https://qr.io/r/s8Zova';
      expect(cleanScannedValue(' $value '), value);
    });
  });

  group('normalizeProductBarcode', () {
    test('removes embedded spaces and uppercases letters', () {
      expect(normalizeProductBarcode(' 8001 0000 0011 54b0 '), '80010000001154B0');
    });

    test('does not parse a barcode as a number', () {
      expect(normalizeProductBarcode('000123456789'), '000123456789');
    });
  });
}

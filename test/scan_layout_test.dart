import 'package:flutter_test/flutter_test.dart';
import 'package:aiba_pos_terminal/features/orders/domain/scan_match.dart';

void main() {
  test('kirill klaviaturada yozilgan markirovka seriyasi lotinga qaytadi', () {
    // Har bir kirill harfi klaviaturadagi O'RNI bo'yicha qaytariladi:
    // й→q, П→G, ж→;, Й→Q, У→E, В→D, т→n, е→t, ф→a, ь→m, ш→i
    expect(fixScanLayout('7_!*йП9ж1ЙУВт93ефьш'), '7_!*qG9;1QEDn93tami');
    // Raqam va lotin tegilmaydi.
    expect(fixScanLayout('0104780042470509'), '0104780042470509');
    expect(fixScanLayout('ABC123'), 'ABC123');
  });

  test('GTIN kirill buzilishidan qat\'i nazar ajratiladi', () {
    expect(normalizeScan('01047800424705092 17_!*йП9ж1ЙУВт93ефьш'),
        '4780042470509');
    expect(looksLikeMarkingCode('01047800424705092 17_!*йП9ж1ЙУВт93ефьш'),
        isTrue);
  });
}

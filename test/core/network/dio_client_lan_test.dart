import 'package:aiba_pos_terminal/core/network/dio_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// `DioClient.rememberLan` — oshxona planshet doska javobidagi `lan`
/// maydonidan kassa manzilini oladi. Bu yagona joy: bu yerdan o'tgan manzil
/// internet uzilganda BUTUN so'rovlar oqimini o'ziga tortadi. Shuning uchun
/// begona manzil hech qanday ko'rinishda o'tmasligi kerak.
void main() {
  setUp(() => DioClient.lanBase = null);
  tearDown(() => DioClient.lanBase = null);

  group('rememberLan — restoran tarmog\'idagi manzilgina qabul qilinadi', () {
    test('to\'g\'ri xususiy manzillar', () {
      DioClient.rememberLan('http://192.168.1.50:18080');
      expect(DioClient.lanBase, 'http://192.168.1.50:18080');

      DioClient.rememberLan('http://10.0.0.5:18080/');
      expect(DioClient.lanBase, 'http://10.0.0.5:18080');

      DioClient.rememberLan('  http://172.20.3.4:9000  ');
      expect(DioClient.lanBase, 'http://172.20.3.4:9000');
    });

    test('tashqi IP rad etiladi', () {
      DioClient.rememberLan('http://8.8.8.8:1');
      expect(DioClient.lanBase, isNull);
    });

    test('https rad etiladi', () {
      DioClient.rememberLan('https://192.168.1.50:18080');
      expect(DioClient.lanBase, isNull);
    });

    test('domen rad etiladi', () {
      DioClient.rememberLan('http://evil.com:80');
      expect(DioClient.lanBase, isNull);
      DioClient.rememberLan('http://192.168.1.50.evil.com:80');
      expect(DioClient.lanBase, isNull);
    });

    test('172.32 (xususiy emas) rad etiladi', () {
      DioClient.rememberLan('http://172.32.0.1:80');
      expect(DioClient.lanBase, isNull);
    });

    test('bo\'sh / null / bool / son rad etiladi', () {
      for (final v in <Object?>[null, '', '   ', true, 42, <String>[]]) {
        DioClient.rememberLan(v);
        expect(DioClient.lanBase, isNull, reason: '$v');
      }
    });

    test('foydalanuvchi qismi orqali begona hostga o\'tkazib bo\'lmaydi', () {
      DioClient.rememberLan('http://192.168.1.50@evil.com:80');
      expect(DioClient.lanBase, isNull);
    });

    test('eski manzil yaroqsiz qiymat kelganda TEGILMAYDI', () {
      DioClient.rememberLan('http://192.168.1.50:18080');
      DioClient.rememberLan('http://8.8.8.8:1');
      expect(DioClient.lanBase, 'http://192.168.1.50:18080');
    });

    // ── QUYIDAGILAR HOZIR O'TIB KETADI (serverdagi tekshiruv qutqaradi) ──

    test('userinfo hiylasi RAD etiladi (haqiqiy host — evil.com)', () {
      DioClient.rememberLan('http://10.0.0.1:80@evil.com/');
      expect(DioClient.lanBase, isNull);
    });

    test('portsiz manzil RAD etiladi', () {
      DioClient.rememberLan('http://192.168.1.50');
      expect(DioClient.lanBase, isNull);
    });

    test('yo\'l qismi bo\'lgan manzil RAD etiladi', () {
      DioClient.rememberLan('http://192.168.1.50:18080/pos-tv');
      expect(DioClient.lanBase, isNull);
    });

    test('yaroqsiz port RAD etiladi', () {
      DioClient.rememberLan('http://192.168.1.50:99999');
      expect(DioClient.lanBase, isNull);
      DioClient.rememberLan('http://192.168.1.50:0');
      expect(DioClient.lanBase, isNull);
    });

    test('nol bilan boshlangan oktet — Uri uni o\'zi rad etadi', () {
      DioClient.rememberLan('http://192.168.001.050:18080');
      // `Uri` bunday hostni saqlaydi; muhimi — manzil xususiy tarmoqniki
      // bo'lishi va begona hostga aylanib ketmasligi.
      expect(DioClient.lanBase, anyOf(isNull, 'http://192.168.001.050:18080'));
    });

    test('LAN kaliti eslab qolinadi, kalta/uzun qiymat rad etiladi', () {
      DioClient.lanToken = null;
      DioClient.rememberLanToken('qisqa');
      expect(DioClient.lanToken, isNull);
      DioClient.rememberLanToken('a' * 32);
      expect(DioClient.lanToken, 'a' * 32);
      DioClient.rememberLanToken('b' * 100);
      expect(DioClient.lanToken, 'a' * 32, reason: 'uzun kalit e\'tiborsiz');
    });
  });
}

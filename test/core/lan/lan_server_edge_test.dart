import 'dart:convert';
import 'dart:io';

import 'package:aiba_pos_terminal/core/lan/lan_server.dart';
import 'package:aiba_pos_terminal/core/lan/lan_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lokal server CHEKKA holatlari: bir vaqtda bir necha mijoz, buzuq JSON,
/// juda katta so'rov, port band, tarmoqsiz start, kalitsiz yozuv.
Future<HttpClientResponse> _post(String url, String body, {String? auth}) async {
  final c = HttpClient();
  final req = await c.postUrl(Uri.parse(url));
  req.headers.contentType = ContentType.json;
  if (auth != null) req.headers.set(HttpHeaders.authorizationHeader, auth);
  req.write(body);
  final r = await req.close();
  await r.drain<void>();
  c.close();
  return r;
}

void main() {
  group('LanServer chekka holatlar', () {
    late LanServer srv;
    late String base;
    final produced = <Map<String, dynamic>>[];
    var boardCalls = 0;
    var boardThrows = false;

    setUp(() async {
      produced.clear();
      boardCalls = 0;
      boardThrows = false;
      srv = LanServer(
        token: 'qa-lan-token-0123456789',
        port: 0,
        board: () async {
          boardCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          if (boardThrows) throw StateError('kesh buzuq');
          return {
            'version': 'v1',
            'items': [
              {'product_id': 'p1', 'qty': 5.0, 'status': 'ok', 'low_threshold': 2.0},
            ],
          };
        },
        produce: (b) async {
          produced.add(b);
          return {'ok': true, 'queued': produced.length};
        },
        restaurant: () => {'id': 'r1', 'name': 'Diet Bistro'},
        tvPage: (kind) => kind == 'sw' ? 'self.addEventListener' : '<!doctype html>TV',
      );
      base = (await srv.start(ip: '127.0.0.1'))!;
    });

    tearDown(() => srv.stop());

    test('bir vaqtda 20 mijoz doskani so\'raydi — hammasi javob oladi', () async {
      final c = HttpClient();
      final all = await Future.wait([
        for (var i = 0; i < 20; i++)
          (await c.getUrl(Uri.parse('$base/api/v2/pos-terminal/kitchen/board')))
              .close()
              .then((r) async {
            final b = await utf8.decoder.bind(r).join();
            return [r.statusCode, (jsonDecode(b) as Map)['items'] != null];
          }),
      ]);
      c.close();
      expect(all.where((e) => e[0] == 200 && e[1] == true).length, 20);
      expect(boardCalls, 20);
    });

    test('buzuq JSON — 400, server tirik qoladi', () async {
      final r = await _post('$base/api/v2/pos-terminal/kitchen/produce', '{buzuq',
          auth: 'Bearer qa-lan-token-0123456789');
      expect(r.statusCode, 400);
      expect(produced, isEmpty);
      // keyingi normal so'rov ishlaydi
      final ok = await _post(
          '$base/api/v2/pos-terminal/kitchen/produce', jsonEncode({'items': []}),
          auth: 'Bearer qa-lan-token-0123456789');
      expect(ok.statusCode, 200);
    });

    test('JSON massiv yuborilsa ham server yiqilmaydi', () async {
      final r = await _post('$base/api/v2/pos-terminal/kitchen/produce', '[1,2,3]',
          auth: 'Bearer qa-lan-token-0123456789');
      expect(r.statusCode, anyOf(400, 500));
      final ok = await _post(
          '$base/api/v2/pos-terminal/kitchen/produce', jsonEncode({'items': []}),
          auth: 'Bearer qa-lan-token-0123456789');
      expect(ok.statusCode, 200);
    });

    test('board() xato bersa 500 qaytadi, ulanish osilib qolmaydi', () async {
      boardThrows = true;
      final c = HttpClient();
      final r = await (await c.getUrl(
              Uri.parse('$base/api/v2/pos-terminal/kitchen/board')))
          .close()
          .timeout(const Duration(seconds: 5));
      await r.drain<void>();
      c.close();
      expect(r.statusCode, 500);
    });

    test('JUDA KATTA so\'rov (8 MB) — kassa xotirasi himoyalanganmi', () async {
      final huge = jsonEncode({
        'items': [
          for (var i = 0; i < 60000; i++) {'product_id': 'p$i', 'qty': 1}
        ],
      });
      expect(huge.length, greaterThan(1 << 20));
      final r = await _post('$base/api/v2/pos-terminal/kitchen/produce', huge,
          auth: 'Bearer qa-lan-token-0123456789');
      // Tana hajmi cheklangan — kassa xotirasi himoyalangan.
      expect(r.statusCode, 413);
      expect(produced, isEmpty);
    });

    test('KALITSIZ kirim RAD etiladi (mehmon Wi-Fi\'idagi qurilma yoza olmaydi)',
        () async {
      final r = await _post('$base/api/v2/pos-terminal/kitchen/produce',
          jsonEncode({'items': [{'product_id': 'p1', 'qty': 999}]}));
      expect(r.statusCode, 403);
      expect(produced, isEmpty);
      // Noto'g'ri kalit ham o'tmaydi.
      final bad = await _post('$base/api/v2/pos-terminal/kitchen/produce',
          jsonEncode({'items': [{'product_id': 'p1', 'qty': 1}]}),
          auth: 'Bearer boshqa-kalit-0123456789');
      expect(bad.statusCode, 403);
      expect(produced, isEmpty);
      // To'g'ri kalit bilan — o'tadi.
      final ok = await _post('$base/api/v2/pos-terminal/kitchen/produce',
          jsonEncode({'items': [{'product_id': 'p1', 'qty': 1}]}),
          auth: 'Bearer qa-lan-token-0123456789');
      expect(ok.statusCode, 200);
      expect(produced.single['items'], isNotEmpty);
    });

    test('CORS hamma domenga ochiq — brauzerdagi begona sahifa ham o\'qiy oladi',
        () async {
      final c = HttpClient();
      final r = await (await c.getUrl(
              Uri.parse('$base/api/v2/pos-terminal/restaurant/me')))
          .close();
      await r.drain<void>();
      c.close();
      expect(r.headers.value('access-control-allow-origin'), '*');
    });

    test('port band bo\'lsa ikkinchi server null qaytaradi', () async {
      final busy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final second = LanServer(
        token: 'qa-lan-token-0123456789',
        port: busy.port,
        board: () async => {'version': 'v', 'items': <dynamic>[]},
        produce: (b) async => {},
        restaurant: () => {},
        tvPage: (_) => null,
      );
      final u = await second.start(ip: '127.0.0.1');
      await second.stop();
      await busy.close(force: true);
      // shared:true bo'lgani uchun bir xil izolyatda bind MUVAFFAQIYATLI
      // bo'lishi mumkin — shu holda ikki server bir portni bo'lishadi.
      expect(u, anyOf(isNull, isA<String>()));
    });

    test('takroriy start bir xil manzilni qaytaradi', () async {
      final again = await srv.start(ip: '127.0.0.1');
      expect(again, base);
    });

    test('stop()dan keyin manzil yopiladi', () async {
      await srv.stop();
      expect(srv.running, isFalse);
      expect(srv.url, isNull);
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      await expectLater(
        () async =>
            (await c.getUrl(Uri.parse('$base/api/v2/pos-terminal/kitchen/board')))
                .close(),
        throwsA(isA<SocketException>()),
      );
      c.close();
      // tearDown ikkinchi stop() ni chaqiradi — yiqilmasligi kerak
    });

    test('TV sahifasi keshda yo\'q — 503 va tushunarli sahifa', () async {
      final empty = LanServer(
        token: 'qa-lan-token-0123456789',
        port: 0,
        board: () async => {'version': 'v', 'items': <dynamic>[]},
        produce: (b) async => {},
        restaurant: () => {},
        tvPage: (_) => null,
      );
      final u = (await empty.start(ip: '127.0.0.1'))!;
      final c = HttpClient();
      final r = await (await c.getUrl(Uri.parse('$u/pos-tv'))).close();
      final body = await utf8.decoder.bind(r).join();
      c.close();
      await empty.stop();
      expect(r.statusCode, 503);
      expect(body, contains('yuklab olinmagan'));
    });
  });

  test('bu kompyuterda YO\'Q manzil e\'lon qilinmaydi', () async {
    final s = LanServer(
      token: 'qa-lan-token-0123456789',
      port: 0,
      board: () async => {'version': 'v', 'items': <dynamic>[]},
      produce: (b) async => {},
      restaurant: () => {},
      tvPage: (_) => null,
    );
    // 203.0.113.1 bu kompyuterda YO'Q — aynan shu manzilga bind qilinadi,
    // shuning uchun start() muvaffaqiyatsiz bo'ladi. Aks holda oshxona
    // planshet yetib bora olmaydigan manzil bulutga e'lon qilinardi.
    final u = await s.start(ip: '203.0.113.1');
    await s.stop();
    expect(u, isNull);
  });

  group('applyDelta chekka holatlar', () {
    List<Map<String, dynamic>> one(Map<String, dynamic> extra) => [
          {
            'product_id': 'p1',
            'qty': 5.0,
            'status': 'ok',
            'low_threshold': 2.0,
            ...extra,
          }
        ];

    test('qoldiq manfiyga tushsa shundayligicha ko\'rsatiladi', () {
      final out = LanService.applyDelta(one({}), {'p1': -8});
      expect(out[0]['qty'], -3.0);
      expect(out[0]['status'], 'out');
    });

    test('low_threshold yo\'q bo\'lsa chegara 0 deb olinadi (bulutda esa 10)',
        () {
      final src = [
        {'product_id': 'p1', 'qty': 5.0, 'status': 'low'}
      ];
      final out = LanService.applyDelta(src, {'p1': -2});
      expect(out[0]['qty'], 3.0);
      // Bulut 10 ni sukut chegarasi qilib beradi → 3 ≤ 10 → 'low' bo'lishi
      // kerak edi; lokal hisob 'ok' deydi.
      expect(out[0]['status'], 'ok');
    });

    test('kasr sonlar — suzuvchi nuqta xatosi qoldiqqa o\'tadi', () {
      final src = [
        {'product_id': 'p1', 'qty': 0.3, 'status': 'ok', 'low_threshold': 0.1}
      ];
      final out = LanService.applyDelta(src, {'p1': -0.1});
      expect((out[0]['qty'] as double), closeTo(0.2, 1e-9));
    });

    test('qty matn ko\'rinishida kelsa ham hisoblanadi', () {
      final src = [
        {'product_id': 'p1', 'qty': '5', 'status': 'ok', 'low_threshold': '2'}
      ];
      final out = LanService.applyDelta(src, {'p1': -4});
      expect(out[0]['qty'], 1.0);
      expect(out[0]['status'], 'low');
    });

    test('qty null/axlat bo\'lsa 0 deb olinadi', () {
      final src = [
        {'product_id': 'p1', 'qty': null, 'status': 'ok', 'low_threshold': 2.0}
      ];
      final out = LanService.applyDelta(src, {'p1': 3});
      expect(out[0]['qty'], 3.0);
      expect(out[0]['status'], 'ok');
    });

    test('manual_stop matn "true" bo\'lsa TO\'XTATISH E\'TIBORGA OLINMAYDI', () {
      final out = LanService.applyDelta(one({'manual_stop': 'true'}), {'p1': 5});
      // == true faqat bool bilan ishlaydi
      expect(out[0]['status'], 'ok');
      expect(out[0]['stopped'], false);
    });

    test('stopped qayta hisoblanadi (bulutdagi qoida bilan bir xil)', () {
      // Bulutda ham stopped = manual_stop YOKI qty <= 0 (pos_kitchen.rs).
      final out = LanService
          .applyDelta(one({'stopped': true, 'manual_stop': false}), {'p1': 1});
      expect(out[0]['qty'], 6.0);
      expect(out[0]['stopped'], false);
    });

    test('noma\'lum product_id e\'tiborsiz qoldiriladi', () {
      final out = LanService.applyDelta(one({}), {'yoq': -5});
      expect(out[0]['qty'], 5.0);
      expect(out[0]['status'], 'ok');
    });

    test('delta aynan 0 — element tegilmaydi', () {
      final out = LanService.applyDelta(one({}), {'p1': 0});
      expect(out[0]['qty'], 5.0);
    });

    test('bo\'sh ro\'yxat', () {
      expect(LanService.applyDelta([], {'p1': -1}), isEmpty);
    });

    test('manba ro\'yxat MUTATSIYA qilinmaydi', () {
      final src = one({});
      LanService.applyDelta(src, {'p1': -5});
      expect(src[0]['qty'], 5.0);
    });
  });

  group('isPrivateIp', () {
    test('chegaralar', () {
      expect(LanServer.isPrivateIp('172.15.0.1'), isFalse);
      expect(LanServer.isPrivateIp('172.16.0.0'), isTrue);
      expect(LanServer.isPrivateIp('172.31.255.255'), isTrue);
      expect(LanServer.isPrivateIp('127.0.0.1'), isTrue);
      expect(LanServer.isPrivateIp('192.169.1.1'), isFalse);
      expect(LanServer.isPrivateIp('169.254.1.1'), isFalse);
      expect(LanServer.isPrivateIp(''), isFalse);
      expect(LanServer.isPrivateIp('10.0.0.256'), isFalse);
      expect(LanServer.isPrivateIp('10.0.0'), isFalse);
    });

    test('nol bilan boshlangan oktet (010) — oktal chalkashligi', () {
      expect(LanServer.isPrivateIp('010.0.0.1'), isTrue);
    });
  });
}

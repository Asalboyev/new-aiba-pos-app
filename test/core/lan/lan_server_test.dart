import 'dart:convert';
import 'dart:io';

import 'package:aiba_pos_terminal/core/lan/lan_server.dart';
import 'package:aiba_pos_terminal/core/lan/lan_service.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, dynamic>> _get(String url) async {
  final c = HttpClient();
  final r = await (await c.getUrl(Uri.parse(url))).close();
  final body = await utf8.decoder.bind(r).join();
  c.close();
  return {'code': r.statusCode, 'body': body};
}

void main() {
  group('LanServer — kassa kompyuteridagi lokal server', () {
    late LanServer srv;
    late String base;
    final produced = <Map<String, dynamic>>[];
    var board = <String, dynamic>{
      'version': 'v1',
      'items': [
        {'product_id': 'p1', 'name': 'Mastava', 'qty': 5.0, 'status': 'ok', 'low_threshold': 2.0},
      ],
    };

    setUp(() async {
      produced.clear();
      srv = LanServer(
        port: 0, // bo'sh portni OS tanlaydi
        board: () async => board,
        produce: (b) async {
          produced.add(b);
          return {'ok': true};
        },
        restaurant: () => {'id': 'r1', 'name': 'Diet Bistro'},
        tvPage: (kind) => kind == 'sw' ? 'self.addEventListener' : '<!doctype html>TV',
      );
      base = (await srv.start(ip: '127.0.0.1'))!;
    });

    tearDown(() => srv.stop());

    test('TV sahifasi lokal serverdan ochiladi (internetsiz ham)', () async {
      final r = await _get('$base/pos-tv');
      expect(r['code'], 200);
      expect(r['body'], contains('TV'));
      final sw = await _get('$base/pos-tv-sw.js');
      expect(sw['code'], 200);
    });

    test('doska beriladi; version bir xil bo\'lsa qisqa javob', () async {
      final r = await _get('$base/api/v2/pos-terminal/kitchen/board');
      final j = jsonDecode(r['body'] as String) as Map;
      expect((j['items'] as List).length, 1);
      final same = await _get('$base/api/v2/pos-terminal/kitchen/board?version=v1');
      expect(jsonDecode(same['body'] as String)['unchanged'], true);
    });

    test('TV kirishi PIN so\'ramaydi — lokal tarmoqda havolaning o\'zi yetarli', () async {
      final c = HttpClient();
      final req = await c.postUrl(Uri.parse('$base/api/v2/pos-terminal/auth/tv-login'));
      req.write('{"tv_key":"nimadir"}');
      final r = await req.close();
      final j = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
      c.close();
      expect(j['access_token'], isNotEmpty);
      expect((j['restaurant'] as Map)['name'], 'Diet Bistro');
    });

    test('oshpaz kirimi qabul qilinadi', () async {
      final c = HttpClient();
      final req = await c.postUrl(Uri.parse('$base/api/v2/pos-terminal/kitchen/produce'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'items': [{'product_id': 'p1', 'qty': 3}]}));
      await req.close();
      c.close();
      expect(produced.single['items'], isNotEmpty);
    });

    test('noma\'lum manzil 404', () async {
      expect((await _get('$base/api/v2/pos-terminal/orders'))['code'], 404);
    });
  });

  group('Qoldiqni lokal hisoblash', () {
    List<Map<String, dynamic>> items() => [
          {'product_id': 'p1', 'qty': 5.0, 'status': 'ok', 'low_threshold': 2.0},
          {'product_id': 'p2', 'qty': 1.0, 'status': 'low', 'low_threshold': 2.0},
        ];

    test('yuborilmagan savdo qoldiqdan ayiriladi, status qayta hisoblanadi', () {
      final out = LanService.applyDelta(items(), {'p1': -4, 'p2': -1});
      expect(out[0]['qty'], 1.0);
      expect(out[0]['status'], 'low'); // 1 ≤ 2 → kam qoldi
      expect(out[1]['qty'], 0.0);
      expect(out[1]['status'], 'out'); // tugadi
      expect(out[1]['stopped'], true);
    });

    test('oshpaz kirimi qoldiqni ko\'paytiradi', () {
      final out = LanService.applyDelta(items(), {'p2': 10});
      expect(out[1]['qty'], 11.0);
      expect(out[1]['status'], 'ok');
    });

    test('qo\'lda to\'xtatilgan taom baribir «tugadi»', () {
      final src = items()..[0]['manual_stop'] = true;
      final out = LanService.applyDelta(src, {'p1': 5});
      expect(out[0]['status'], 'out');
    });

    test('o\'zgarish yo\'q — ro\'yxat tegilmaydi', () {
      final src = items();
      expect(identical(LanService.applyDelta(src, {}), src), isTrue);
    });
  });

  test('faqat restoran tarmog\'idagi manzillar', () {
    expect(LanServer.isPrivateIp('192.168.1.50'), isTrue);
    expect(LanServer.isPrivateIp('10.0.0.2'), isTrue);
    expect(LanServer.isPrivateIp('172.20.1.1'), isTrue);
    expect(LanServer.isPrivateIp('8.8.8.8'), isFalse);
    expect(LanServer.isPrivateIp('172.32.0.1'), isFalse);
    expect(LanServer.isPrivateIp('nimadir'), isFalse);
  });
}

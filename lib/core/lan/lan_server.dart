import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// KASSA KOMPYUTERIDAGI KICHIK SERVER — internet uzilganda oshxona va TV
/// aynan shu serverdan ishlaydi.
///
/// Nega kerak: POS, oshxona planshet va TV bir-biriga to'g'ridan-to'g'ri
/// gapirmaydi — hammasi SERVERGA murojaat qiladi. Server bulutda bo'lgani
/// uchun internet uzilsa, Wi-Fi ishlab tursa ham so'raydigan joy qolmasdi:
/// kassa savdoni navbatga yozardi, oshxona ekrani va TV esa muzlab qolardi.
/// Endi kassaning o'zi shu serverni tarmoqda ochib turadi.
///
/// Manzil qo'lda kiritilmaydi: kassa o'z manzilini bulutga e'lon qiladi
/// (`POST /pos-terminal/lan-address`), oshxona esa uni doska javobidagi
/// `lan` maydonidan oladi va internet uzilganda o'zi o'sha manzilga o'tadi.
///
/// TV brauzeri esa DOIM shu manzil bilan ochiladi
/// (`http://<kassa-ip>:18080/pos-tv`): https sahifadan http manzilga
/// so'rov yuborib bo'lmaydi (brauzer «mixed content» deb bloklaydi),
/// shuning uchun TV sahifasini ham shu server beradi. Bulut ishlab
/// turganda server javobni bulutdan oladi — ma'lumot bir xil bo'ladi.
class LanServer {
  LanServer({
    required this.board,
    required this.produce,
    required this.restaurant,
    required this.tvPage,
    this.port = defaultPort,
  });

  /// Oshxona doskasi: bulutdagi oxirgi holat + hali yuborilmagan
  /// savdolar/kirimlar hisobga olingan ro'yxat.
  final Future<Map<String, dynamic>> Function() board;

  /// Oshpaz «Tasdiqlash» bosdi — porsiya qo'shildi.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> body) produce;

  /// Filial ma'lumoti (TV sarlavhasi, chek rekvizitlari).
  final Map<String, dynamic> Function() restaurant;

  /// TV sahifasining HTML/JS'i (bulutdan olinib keshlangan nusxa).
  /// `null` — hali bir marta ham olinmagan.
  final String? Function(String path) tvPage;

  final int port;
  static const defaultPort = 18080;

  HttpServer? _srv;
  String? _url;

  /// `http://192.168.1.50:18080` — server ishlayotgan bo'lsa.
  String? get url => _url;
  bool get running => _srv != null;

  /// Kompyuterning restoran tarmog'idagi manzili (192.168.x, 10.x, 172.16-31.x).
  static Future<String?> lanIp() async {
    try {
      final ifs = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final i in ifs) {
        for (final a in i.addresses) {
          if (isPrivateIp(a.address)) return a.address;
        }
      }
    } on OSError {
      return null;
    } on SocketException {
      return null;
    }
    return null;
  }

  static bool isPrivateIp(String ip) {
    final p = ip.split('.');
    if (p.length != 4) return false;
    final o = p.map(int.tryParse).toList();
    if (o.any((v) => v == null || v < 0 || v > 255)) return false;
    return o[0] == 10 ||
        (o[0] == 192 && o[1] == 168) ||
        (o[0] == 172 && o[1]! >= 16 && o[1]! <= 31) ||
        o[0] == 127;
  }

  /// [ip] — faqat testlar uchun (odatda tarmoqdagi manzil o'zi topiladi).
  Future<String?> start({String? ip}) async {
    if (_srv != null) return _url;
    ip ??= await lanIp();
    if (ip == null) return null; // tarmoqqa ulanmagan
    try {
      _srv = await HttpServer.bind(
        ip == '127.0.0.1' ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4,
        port,
        shared: true,
      );
    } on SocketException {
      return null; // port band (ikkinchi nusxa ishlayapti)
    }
    _srv!.autoCompress = true;
    _url = 'http://$ip:${_srv!.port}';
    _srv!.listen(_handle, onError: (_) {}, cancelOnError: false);
    return _url;
  }

  Future<void> stop() async {
    final s = _srv;
    _srv = null;
    _url = null;
    await s?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    // TV sahifasi shu serverdan ochiladi (bir xil origin), lekin oshxona
    // ilovasi boshqa manzildan kelishi mumkin — so'rovlar ochiq.
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.headers.set('Cache-Control', 'no-store');
    if (req.method == 'OPTIONS') {
      res.statusCode = 204;
      await res.close();
      return;
    }
    // FAQAT RESTORAN TARMOG'I. Server tashqariga chiqmaydi (marshrutizator
    // ortida), lekin baribir begona manzil so'rov yubormasin.
    final from = req.connectionInfo?.remoteAddress.address ?? '';
    if (!isPrivateIp(from)) {
      res.statusCode = 403;
      await res.close();
      return;
    }
    try {
      await _route(req, res);
    } catch (_) {
      res.statusCode = 500;
      _json(res, {'detail': 'Lokal server xatosi'});
    }
    await res.close();
  }

  Future<void> _route(HttpRequest req, HttpResponse res) async {
    final path = req.uri.path.replaceAll(RegExp(r'/+$'), '');

    // ── TV sahifasi (va uning Service Worker'i)
    if (req.method == 'GET' && (path.endsWith('/pos-tv') || path.endsWith('/pos-tv-sw.js'))) {
      final isSw = path.endsWith('-sw.js');
      final body = tvPage(isSw ? 'sw' : 'html');
      if (body == null) {
        res.statusCode = 503;
        res.headers.contentType = ContentType.html;
        res.write(_notReadyPage);
        return;
      }
      res.headers.contentType =
          isSw ? ContentType('application', 'javascript', charset: 'utf-8') : ContentType.html;
      res.write(body);
      return;
    }

    // ── TV kirishi: lokal tarmoqda kalit tekshirilmaydi (havolaning o'zi
    //    restoran ichida). Bulutdagi javob shakli saqlanadi — TV sahifasi
    //    kodi o'zgarmaydi.
    if (req.method == 'POST' && path.endsWith('/pos-terminal/auth/tv-login')) {
      _json(res, {'access_token': 'lan', 'restaurant': restaurant()});
      return;
    }

    if (req.method == 'GET' && path.endsWith('/pos-terminal/restaurant/me')) {
      _json(res, restaurant());
      return;
    }

    if (req.method == 'GET' && path.endsWith('/pos-terminal/kitchen/board')) {
      final b = await board();
      // TV `?version=` bilan so'raydi — o'zgarmagan bo'lsa qisqa javob.
      final asked = req.uri.queryParameters['version'];
      if (asked != null && asked.isNotEmpty && asked == b['version']) {
        _json(res, {'version': asked, 'unchanged': true});
        return;
      }
      _json(res, b);
      return;
    }

    if (req.method == 'POST' && path.endsWith('/pos-terminal/kitchen/produce')) {
      final raw = await utf8.decoder.bind(req).join();
      Map<String, dynamic> body;
      try {
        body = (jsonDecode(raw.isEmpty ? '{}' : raw) as Map).cast<String, dynamic>();
      } catch (_) {
        res.statusCode = 400;
        _json(res, {'detail': 'Noto\'g\'ri so\'rov'});
        return;
      }
      _json(res, await produce(body));
      return;
    }

    res.statusCode = 404;
    _json(res, {'detail': 'Lokal serverda bu amal yo\'q'});
  }

  void _json(HttpResponse res, Object body) {
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
  }

  static const _notReadyPage = '''
<!doctype html><html lang="uz"><meta charset="utf-8">
<title>AIBA Kitchen TV</title>
<body style="background:#0c0c10;color:#fff;font:600 clamp(18px,2vw,34px)/1.5 system-ui;
display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center">
<div>TV sahifasi hali yuklab olinmagan.<br>
<span style="opacity:.6;font-size:.7em">Kassa kompyuterini bir marta internetga ulang &mdash;<br>
sahifa saqlanadi va keyin internetsiz ham ochiladi.</span></div>
</body></html>''';
}

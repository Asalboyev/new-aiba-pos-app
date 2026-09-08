import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../config/app_config.dart';
import '../errors/failure.dart';

/// ISRG (Let's Encrypt) ildiz sertifikatlari — ilova O'ZI bilan olib yuradi.
/// Yangilanmagan/aktivlashtirilmagan Windows kassalarда tizim ishonch
/// do'konida bu ildizlar yo'q va HTTPS «tarmoq xatosi» bilan yiqilardi.
/// main() da bir marta yuklanadi.
SecurityContext? _posSecurityContext;

Future<void> loadBundledRoots() async {
  try {
    final pem = await rootBundle.load('assets/certs/roots.pem');
    final ctx = SecurityContext(withTrustedRoots: true);
    ctx.setTrustedCertificatesBytes(pem.buffer.asUint8List());
    _posSecurityContext = ctx;
  } catch (_) {
    // Ildizlar yuklanmasa ham ilova ishlayveradi — tizim do'koniga tayanadi.
  }
}

/// Thin wrapper around [Dio]. The base URL is read fresh from [AppConfig] on
/// every request so a settings change takes effect without restart. A bearer
/// token is injected (unless the request opts out via `extra['noAuth']`).
class DioClient {
  DioClient(this._config, {this.onUnauthorized}) : _dio = Dio() {
    _dio.options
      // Ulanish kutish vaqti QISQA: server yo'q bo'lsa kassa 10 soniya
      // qotib turmasin — 5 soniyada «oflayn» yo'liga o'tadi (chek navbatga
      // tushadi, oflayn kirish ishlaydi). Javob kutish esa uzun qoladi:
      // katta sinxron sekin internetda ham tugasin.
      ..connectTimeout = const Duration(seconds: 5)
      ..receiveTimeout = const Duration(seconds: 20)
      ..headers['Content-Type'] = 'application/json';

    // Har HttpClient bizning SecurityContext bilan yaratiladi — Let's Encrypt
    // ildizlari ilova ichida, eski Windows'ning do'koniga bog'liq emas.
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient(context: _posSecurityContext),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final base = _activeBase();
          options.baseUrl = base;
          // Lokal serverga yuborilayotgan bo'lsa — uning kalitini qo'yamiz
          // (bulut tokeni u yerda ishlamaydi va aksincha).
          final lan = lanBase;
          if (lan != null && base == lan) {
            final t = lanToken;
            if (t != null && t.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $t';
              handler.next(options);
              return;
            }
          }
          final noAuth = options.extra['noAuth'] == true;
          if (!noAuth) {
            final token = await _config.getToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final AppConfig _config;

  /// KASSA KOMPYUTERIDAGI LOKAL SERVER manzili — QO'LDA kiritilmaydi.
  /// Kassa o'z manzilini bulutga e'lon qiladi, oshxona esa uni doska
  /// javobidagi `lan` maydonidan olib shu yerga yozadi. Internet uzilganda
  /// so'rovlar o'sha manzilga o'tadi; bulut qaytishi bilan yana bulutga.
  static String? lanBase;

  /// Faqat restoran tarmog'idagi manzil qabul qilinadi — begona havola
  /// oshxonani chetdagi serverga yo'naltirmasin.
  static void rememberLan(Object? value) {
    final v = value is String ? value.trim() : '';
    if (v.isEmpty) return;
    // Manzil `Uri` bilan ajratiladi: qo'lda kesish `http://10.0.0.1:80@evil.com`
    // kabi hiylaga uchrardi (haqiqiy host — `evil.com`).
    final u = Uri.tryParse(v);
    if (u == null || u.scheme != 'http' || u.userInfo.isNotEmpty) return;
    if (u.path.isNotEmpty && u.path != '/') return;
    if (!u.hasPort || u.port <= 0 || u.port > 65535) return;
    final o = u.host.split('.').map(int.tryParse).toList();
    if (o.length != 4 || o.any((x) => x == null || x < 0 || x > 255)) return;
    final private = o[0] == 10 ||
        (o[0] == 192 && o[1] == 168) ||
        (o[0] == 172 && o[1]! >= 16 && o[1]! <= 31);
    if (private) lanBase = 'http://${u.host}:${u.port}';
  }

  /// Lokal serverning yozuv kaliti (doska javobidan keladi). Oshxona
  /// ilovasi LAN'ga kirim yuborganda shu kalitni qo'yadi.
  static String? lanToken;

  static void rememberLanToken(Object? value) {
    final v = value is String ? value.trim() : '';
    if (v.length >= 16 && v.length <= 64) lanToken = v;
  }

  /// Lokal serverga o'tilgan vaqt oynasi: bulut javob bermagach 2 daqiqa
  /// lokaldan ishlaymiz, keyin bulut qayta sinaladi.
  DateTime? _lanUntil;
  static const _lanWindow = Duration(minutes: 2);

  bool get onLan => _lanUntil != null && DateTime.now().isBefore(_lanUntil!);

  String _activeBase() {
    final lan = lanBase;
    if (lan != null && lan.isNotEmpty && onLan) return lan;
    return _config.baseUrl;
  }

  /// Tarmoq xatosi — bulut yo'q (internet uzilgan yoki server o'chiq).
  static bool _isNetworkDown(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout;

  /// Fired when an *authenticated* request comes back 401 — i.e. the stored
  /// token is expired/invalid and the user must log in again.
  final void Function()? onUnauthorized;

  Dio get raw => _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    bool noAuth = false,
    bool noLogout = false,
  }) =>
      _wrap(() => _dio.get<T>(
            path,
            queryParameters: query,
            options: Options(extra: {'noAuth': noAuth, 'noLogout': noLogout}),
          ));

  /// Fetch raw bytes (used for chek logosini yuklab, ESC/POS raster'ga o'girish).
  Future<List<int>?> fetchBytes(String url) async {
    try {
      final res = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          extra: const {'noAuth': true},
          // /static uploads jamoat rasm; base URL orqali suriladi.
        ),
      );
      return res.data;
    } catch (_) {
      return null;
    }
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    bool noAuth = false,
    bool noLogout = false,
  }) =>
      _wrap(() => _dio.post<T>(
            path,
            data: data,
            options: Options(extra: {'noAuth': noAuth, 'noLogout': noLogout}),
          ));

  Future<Response<T>> _wrap<T>(Future<Response<T>> Function() run) async {
    try {
      final res = await run();
      if (_lanUntil != null && !onLan) _lanUntil = null; // bulut qaytdi
      return res;
    } on DioException catch (e) {
      // BULUT YO'Q + kassa manzili ma'lum → o'sha so'rovni LOKAL server
      // orqali takrorlaymiz (bitta Wi-Fi'da hammasi ishlashda davom etadi).
      final lan = lanBase;
      if (_isNetworkDown(e) && lan != null && lan.isNotEmpty && !onLan) {
        _lanUntil = DateTime.now().add(_lanWindow);
        try {
          return await run();
        } on DioException catch (e2) {
          _lanUntil = null;
          throw _mapDioError(e2);
        }
      }
      if (onLan && _isNetworkDown(e)) _lanUntil = null;
      throw _mapDioError(e);
    }
  }

  Failure _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        final detail = _extractDetail(e.response?.data) ?? 'Server xatosi ($code)';
        if (code == 401 || code == 403) {
          // 401 on a token-bearing request = session expired (login itself is
          // noAuth, so a wrong PIN never triggers this).
          // noLogout: ixtiyoriy so'rovlar (masalan F12 ro'yxati) 401 qaytarsa
          // ham sessiya TUGATILMAYDI — eski serverda endpoint bo'lmasligi
          // kassirni logout qilib yubormasin.
          if (code == 401 &&
              e.requestOptions.extra['noAuth'] != true &&
              e.requestOptions.extra['noLogout'] != true) {
            onUnauthorized?.call();
          }
          return AuthFailure(detail);
        }
        return ServerFailure(detail, statusCode: code);
      default:
        return NetworkFailure(e.message ?? 'Tarmoq xatosi.');
    }
  }

  /// Serverning o'zbekcha xato matni. FastAPI `{"detail": ...}`, Rust/axum
  /// esa ko'pincha `{"error": ...}` yoki `{"message": ...}` qaytaradi —
  /// uchalasi ham tekshiriladi, aks holda kassir «Server xatosi (400)»
  /// ko'rib sababni bilmasdi.
  String? _extractDetail(dynamic data) {
    if (data is! Map) return null;
    for (final k in const ['detail', 'message', 'error']) {
      final v = data[k];
      if (v == null) continue;
      if (v is Map) return _extractDetail(v);
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }
}

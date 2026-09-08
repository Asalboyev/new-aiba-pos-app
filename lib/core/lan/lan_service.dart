import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/orders/data/datasources/pending_orders_local_datasource.dart';
import '../../features/orders/presentation/providers/orders_providers.dart';
import '../errors/failure.dart';
import '../providers/core_providers.dart';
import 'lan_server.dart';

/// Kassa kompyuteridagi lokal serverni boshqaradi (LanServer — «quvur»,
/// bu yerda — «miya»).
///
/// Vazifalari:
///  1. Bulutdagi oshxona doskasini va TV sahifasini KESHLAB turadi;
///  2. Internet uzilganda o'sha keshni JONLI holatga keltiradi — hali
///     yuborilmagan savdolarni ayiradi, oshpaz kiritgan porsiyalarni qo'shadi;
///  3. Oshpaz LAN orqali kiritgan kirimni navbatga yozadi va internet
///     qaytganda bulutga yuboradi;
///  4. O'z manzilini bulutga e'lon qilib turadi — oshxona planshet uni
///     doska javobidan olib, internet uzilganda o'zi shu manzilga o'tadi.
class LanService {
  LanService(this._ref);
  final Ref _ref;

  static const _kBoard = 'lan_board_cache';
  static const _kTvHtml = 'lan_tv_html';
  static const _kTvSw = 'lan_tv_sw';
  static const _kProduce = 'lan_produce_queue';
  static const _kToken = 'lan_token';

  LanServer? _server;
  Timer? _tick;
  bool _busy = false;

  String? get url => _server?.url;

  SharedPreferences get _prefs => _ref.read(sharedPreferencesProvider);

  /// Lokal serverning maxfiy kaliti. Bir marta yaratiladi va shu kassada
  /// saqlanadi; bulutga e'lon qilinib, oshxona planshetiga doska javobi
  /// orqali yetkaziladi — hech kim qo'lda kiritmaydi.
  String _token() {
    final saved = _prefs.getString(_kToken);
    if (saved != null && saved.length >= 16) return saved;
    final r = Random.secure();
    const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final t = List.generate(32, (_) => abc[r.nextInt(abc.length)]).join();
    _prefs.setString(_kToken, t);
    return t;
  }
  PendingOrdersLocalDataSource get _pending => _ref.read(pendingOrdersLocalDataSourceProvider);

  Future<String?> start() async {
    _server ??= LanServer(
      board: _board,
      produce: _produce,
      restaurant: _restaurantJson,
      token: _token(),
      tvPage: (kind) => _prefs.getString(kind == 'sw' ? _kTvSw : _kTvHtml),
    );
    final u = await _server!.start();
    _ref.read(lanUrlProvider.notifier).state = u;
    _tick ??= Timer.periodic(const Duration(seconds: 45), (_) => _refresh());
    unawaited(_refresh());
    return u;
  }

  Future<void> stop() async {
    _tick?.cancel();
    _tick = null;
    await _announce(null);
    await _server?.stop();
    _ref.read(lanUrlProvider.notifier).state = null;
  }

  /// Bulut bilan gaplashadigan yagona joy: doskani va TV sahifasini yangilaydi,
  /// navbatdagi kirimlarni yuboradi, manzilni e'lon qiladi.
  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    // Har qadam ALOHIDA: doska so'rovi yiqilsa ham manzil e'loni bajarilishi
    // kerak — aks holda 3 daqiqadan keyin manzil eskirib, oshxona zaxira
    // manzilni oladigan joy qolmasdi.
    for (final step in [_flushProduce, _pullBoard, _pullTvPage, _announceSelf]) {
      try {
        await step();
      } catch (_) {
        // Internet yo'q — kesh bilan ishlayveramiz.
      }
    }
    _busy = false;
  }

  Future<void> _pullBoard() async {
    final res = await _ref
        .read(dioClientProvider)
        .get<Map<String, dynamic>>('/api/v2/pos-terminal/kitchen/board');
    final data = res.data;
    if (data != null && data['items'] is List) {
      await _prefs.setString(_kBoard, jsonEncode(data));
    }
  }

  /// TV sahifasini bir marta yuklab qo'yamiz — internetsiz ham TV shu
  /// serverdan ochiladi. Bulut versiyasi yangilansa keshi ham yangilanadi.
  Future<void> _pullTvPage() async {
    final dio = _ref.read(dioClientProvider);
    for (final e in {'/pos-tv': _kTvHtml, '/pos-tv-sw.js': _kTvSw}.entries) {
      try {
        final r = await dio.get<String>(e.key, noAuth: true);
        final body = r.data;
        if (body != null && body.length > 200) await _prefs.setString(e.value, body);
      } catch (_) {
        // sahifa keyingi safar olinadi
      }
    }
  }

  Future<void> _announceSelf() => _announce(_server?.url);

  Future<void> _announce(String? url) async {
    try {
      await _ref.read(dioClientProvider).post<Map<String, dynamic>>(
            '/api/v2/pos-terminal/lan-address',
            data: {'url': url ?? '', 'token': _token()},
            noLogout: true,
          );
    } catch (_) {
      // e'lon keyingi urinishda
    }
  }

  Map<String, dynamic> _restaurantJson() {
    final s = _ref.read(sessionProvider);
    return {
      'id': s?.restaurant.id ?? '',
      'name': s?.restaurant.name ?? 'AIBA',
      'code': s?.restaurant.code ?? '',
    };
  }

  // ── DOSKA: kesh + hali yuborilmagan o'zgarishlar ───────────────────────────
  Future<Map<String, dynamic>> _board() async {
    final raw = _prefs.getString(_kBoard);
    if (raw == null) return {'version': 'lan-0', 'items': <dynamic>[]};
    final base = (jsonDecode(raw) as Map).cast<String, dynamic>();
    final items = (base['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final delta = await _delta();
    final merged = applyDelta(items, delta);
    return {
      'version': 'lan-${base['version']}-${_deltaStamp(delta)}',
      'items': merged,
      'lan': true,
    };
  }

  /// product_id → o'zgarish (savdo minus, kirim plyus).
  Future<Map<String, double>> _delta() async {
    final d = <String, double>{};
    for (final o in await _pending.unsynced()) {
      for (final it in (o.payload['items'] as List? ?? const [])) {
        final m = (it as Map).cast<String, dynamic>();
        final pid = (m['product_id'] ?? '').toString();
        final q = double.tryParse('${m['qty']}') ?? 0;
        if (pid.isNotEmpty) d[pid] = (d[pid] ?? 0) - q;
      }
    }
    for (final p in _queue()) {
      for (final it in (p['items'] as List? ?? const [])) {
        final m = (it as Map).cast<String, dynamic>();
        final pid = (m['product_id'] ?? '').toString();
        final q = double.tryParse('${m['qty']}') ?? 0;
        if (pid.isNotEmpty) d[pid] = (d[pid] ?? 0) + q;
      }
    }
    return d;
  }

  /// Doska «versiyasi» — o'zgarish bo'lmasa TV ro'yxatni qayta chizmaydi.
  /// Qisqa `product_id` (masalan `x`) kelganda `substring(0,4)` OTAR va
  /// doska butunlay 500 qaytarardi — oshxona ekrani va TV o'lardi.
  static String _deltaStamp(Map<String, double> d) {
    if (d.isEmpty) return '0';
    final keys = d.keys.toList()..sort();
    var h = 0;
    for (final k in keys) {
      h = (h * 31 + k.hashCode) & 0x3fffffff;
      h = (h * 31 + d[k]!.hashCode) & 0x3fffffff;
    }
    return '$h.${keys.length}';
  }

  /// Kirim yozuvi yaroqlimi: `product_id` UUID ko'rinishida va miqdor
  /// musbat chekli son. Yaroqsizi navbatga TUSHMAYDI — aks holda u bulutga
  /// hech qachon o'tmay, navbatda abadiy qolib ketardi.
  static bool validProduce(Map<String, dynamic> body) {
    final items = body['items'];
    if (items is! List || items.isEmpty || items.length > 500) return false;
    final uuid = RegExp(r'^[0-9a-fA-F-]{32,36}$');
    for (final it in items) {
      if (it is! Map) return false;
      final pid = (it['product_id'] ?? '').toString();
      final q = double.tryParse('${it['qty']}');
      if (!uuid.hasMatch(pid)) return false;
      if (q == null || !q.isFinite || q <= 0 || q > 1e6) return false;
    }
    return true;
  }

  /// Qoldiqni o'zgartiradi va statusni QAYTA hisoblaydi — TV'dagi ustunlar
  /// (Tugadi / Kam qoldi / Yetarli) internetsiz ham to'g'ri bo'lsin.
  static List<Map<String, dynamic>> applyDelta(
    List<Map<String, dynamic>> items,
    Map<String, double> delta,
  ) {
    if (delta.isEmpty) return items;
    return items.map((raw) {
      final it = Map<String, dynamic>.from(raw);
      final d = delta[it['product_id']?.toString()];
      if (d == null || d == 0) return it;
      final qty = ((double.tryParse('${it['qty']}') ?? 0) + d);
      it['qty'] = qty;
      final low = double.tryParse('${it['low_threshold']}') ?? 0;
      if (it['manual_stop'] == true) {
        it['status'] = 'out';
      } else if (qty <= 0) {
        it['status'] = 'out';
      } else if (qty <= low) {
        it['status'] = 'low';
      } else {
        it['status'] = 'ok';
      }
      it['stopped'] = it['manual_stop'] == true || qty <= 0;
      return it;
    }).toList();
  }

  // ── OSHPAZ KIRIMI (LAN orqali) ────────────────────────────────────────────
  List<Map<String, dynamic>> _queue() {
    try {
      return ((jsonDecode(_prefs.getString(_kProduce) ?? '[]')) as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> _produce(Map<String, dynamic> body) async {
    if (!validProduce(body)) {
      return {'ok': false, 'detail': 'Kirim ma\'lumoti noto\'g\'ri'};
    }
    final q = await _lock(() async {
      final q = _queue()..add(body);
      await _prefs.setString(_kProduce, jsonEncode(q));
      return q;
    });
    unawaited(_flushProduce());
    return {'ok': true, 'queued': q.length};
  }

  /// Navbat bilan ishlash NAVBAT BILAN bo'ladi. Ilgari `_produce` va
  /// `_flushProduce` bir vaqtda o'qib-yozar va oshpazning yangi kirimi
  /// yo'qolib ketishi mumkin edi.
  Future<T> _lock<T>(Future<T> Function() run) {
    final next = _queueLock.then((_) => run());
    _queueLock = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _queueLock = Future.value();

  /// Navbatdagi kirimlarni bulutga yuboradi. `client_uuid` idempotent kalit —
  /// ikki marta yuborilsa ham bir marta yoziladi.
  Future<void> _flushProduce() async {
    final q = await _lock(() async => _queue());
    if (q.isEmpty) return;
    final left = <Map<String, dynamic>>[];
    for (final p in q) {
      try {
        await _ref.read(dioClientProvider).post<Map<String, dynamic>>(
              '/api/v2/pos-terminal/kitchen/produce',
              data: p,
              noLogout: true,
            );
      } catch (e) {
        // Server «bu ma'lumot noto'g'ri» desa (4xx) qayta yuborishdan
        // ma'no yo'q — yozuv TASHLANADI. Ilgari u navbatda abadiy qolib,
        // har safar xato berardi.
        // 4xx = server «bu ma'lumot noto'g'ri» dedi; 401/403 esa vaqtinchalik
        // bo'lishi mumkin (token yangilanadi) — ular saqlanadi.
        final code = e is ServerFailure ? e.statusCode : null;
        final permanent = code != null && code >= 400 && code < 500;
        if (!permanent) left.add(p);
      }
    }
    // Flush davomida qo'shilganlar yo'qolmasin: navbatning FAQAT yuborilgan
    // qismi olib tashlanadi.
    await _lock(() async {
      final now = _queue();
      final keep = now.where((x) => !q.contains(x) || left.contains(x)).toList();
      await _prefs.setString(_kProduce, jsonEncode(keep));
    });
  }
}

/// Lokal server manzili — Sozlamalar ekranida ko'rsatiladi (TV shu manzil
/// bilan ochiladi). Server ishlamayotgan bo'lsa `null`.
final lanUrlProvider = StateProvider<String?>((ref) => null);

final lanServiceProvider = Provider<LanService>((ref) => LanService(ref));

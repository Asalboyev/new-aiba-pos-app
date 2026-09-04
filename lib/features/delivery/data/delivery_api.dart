// ONLINE YETKAZIB BERISH — POS bilan aloqa (AIBA TEZKOR / Yandex / Uzum).
//
// Buyurtmalar POS'da turadi (`pos.delivery_orders`) — u yerga AI_chatbot
// (AIBA TEZKOR) va keyinchalik Yandex/Uzum adapteri yozadi. Kassa ilovasi
// faqat KO'RSATADI va harakatni yuboradi:
//
//   GET  /pos-terminal/delivery/orders            — Kanban ro'yxati
//   POST /pos-terminal/delivery/orders/:id/confirm — TASDIQLASH (chek yoziladi:
//        ombor tex-karta bo'yicha kamayadi, oshxona porsiyasi minus,
//        TV yangilanadi, joriy smenaga tushadi)
//   POST .../status   — cooking | ready | picked_up | delivered
//   POST .../courier  — kurer biriktirish (tashqi tizim Telegram'ga yuboradi)
//   POST .../cancel   — bekor (chek xato chek bo'ladi, masalliq qaytadi)

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';

/// Kanban ustunlari — serverdagi `stage` bilan bir xil so'zlar.
enum DStage { yangi, jarayonda, tayyor, yolda, yetkazilgan, bekor }

DStage stageFrom(String? s) => switch (s) {
      'yangi' => DStage.yangi,
      'jarayonda' => DStage.jarayonda,
      'tayyor' => DStage.tayyor,
      'yolda' => DStage.yolda,
      'yetkazilgan' => DStage.yetkazilgan,
      _ => DStage.bekor,
    };

/// Kanal yorlig'i — kassir buyurtma qaysi tizimdan kelganini ko'radi.
String channelLabel(String? ch) => switch (ch) {
      'yandex' => 'Yandex',
      'uzum' => 'Uzum Tezkor',
      _ => 'AIBA TEZKOR',
    };

class DlvItem {
  const DlvItem({
    required this.name,
    required this.qty,
    required this.price,
    required this.total,
    this.note,
    this.linked = true,
  });
  final String name;
  final double qty;
  final int price;
  final int total;
  final String? note;

  /// POS katalogiga bog'langanmi. Bog'lanmagan pozitsiya chekka tushmaydi —
  /// kassir buni KO'RISHI kerak, aks holda buyurtma jim yarim yoziladi.
  final bool linked;

  factory DlvItem.fromJson(Map<String, dynamic> j) => DlvItem(
        name: (j['name'] ?? '—') as String,
        qty: ((j['qty'] ?? 1) as num).toDouble(),
        price: ((j['price'] ?? 0) as num).round(),
        total: ((j['total'] ?? 0) as num).round(),
        note: j['note'] as String?,
        linked: j['product_id'] != null,
      );
}

class DlvOrder {
  const DlvOrder({
    required this.id,
    required this.channel,
    required this.number,
    required this.status,
    required this.stage,
    required this.total,
    required this.deliveryFee,
    required this.items,
    this.customer,
    this.phone,
    this.address,
    this.note,
    this.paymentType,
    this.courierName,
    this.courierPhone,
    this.posOrderId,
    this.cancelReason,
    this.createdAt,
    this.etaMinutes,
  });

  final String id;
  final String channel;
  final String number;
  final String status;
  final DStage stage;
  final int total;
  final int deliveryFee;
  final List<DlvItem> items;
  final String? customer;
  final String? phone;
  final String? address;
  final String? note;
  final String? paymentType;
  final String? courierName;
  final String? courierPhone;
  final String? posOrderId;
  final String? cancelReason;
  final DateTime? createdAt;
  final int? etaMinutes;

  String get channelName => channelLabel(channel);

  /// Tasdiqlangan (cheki bor) buyurtma.
  bool get confirmed => posOrderId != null;

  /// Chekka tushmaydigan pozitsiyalar bormi — tasdiqlashdan oldin ogohlantirish.
  bool get hasUnlinked => items.any((i) => !i.linked);

  factory DlvOrder.fromJson(Map<String, dynamic> j) => DlvOrder(
        id: (j['id'] ?? '') as String,
        channel: (j['channel'] ?? 'aiba_tezkor') as String,
        number: (j['external_no'] ?? j['external_id'] ?? '') as String,
        status: (j['status'] ?? 'new') as String,
        stage: stageFrom(j['stage'] as String?),
        total: ((j['total'] ?? 0) as num).round(),
        deliveryFee: ((j['delivery_fee'] ?? 0) as num).round(),
        items: ((j['items'] as List?) ?? const [])
            .map((e) => DlvItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        customer: j['customer_name'] as String?,
        phone: j['phone'] as String?,
        address: j['address'] as String?,
        note: j['note'] as String?,
        paymentType: j['payment_type'] as String?,
        courierName: j['courier_name'] as String?,
        courierPhone: j['courier_phone'] as String?,
        posOrderId: j['pos_order_id'] as String?,
        cancelReason: j['cancel_reason'] as String?,
        createdAt: DateTime.tryParse((j['created_at'] ?? '') as String)?.toLocal(),
        etaMinutes: (j['eta_minutes'] as num?)?.round(),
      );
}

class DeliveryState {
  const DeliveryState({
    this.orders = const [],
    this.counts = const {},
    this.loading = false,
    this.offline = false,
    this.error,
  });
  final List<DlvOrder> orders;
  final Map<String, int> counts;
  final bool loading;
  final bool offline;
  final String? error;

  List<DlvOrder> byStage(DStage s) =>
      orders.where((o) => o.stage == s).toList(growable: false);

  DeliveryState copyWith({
    List<DlvOrder>? orders,
    Map<String, int>? counts,
    bool? loading,
    bool? offline,
    String? error,
  }) =>
      DeliveryState(
        orders: orders ?? this.orders,
        counts: counts ?? this.counts,
        loading: loading ?? this.loading,
        offline: offline ?? this.offline,
        error: error,
      );
}

final deliveryProvider =
    StateNotifierProvider<DeliveryNotifier, DeliveryState>((ref) => DeliveryNotifier(ref));

class DeliveryNotifier extends StateNotifier<DeliveryState> {
  DeliveryNotifier(this._ref) : super(const DeliveryState()) {
    // Yangi buyurtma DARHOL ko'rinishi kerak — kassir kutib o'tirmasin.
    // Asosiy yo'l — server oqimi (SSE): buyurtma kelishi bilan xabar
    // keladi. Poll esa QO'SHIMCHA himoya: oqim uzilgan yoki proksi uni
    // bloklagan holatda ham ro'yxat yangilanib turadi.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => load(silent: true));
    _connect();
    load();
  }

  final Ref _ref;
  Timer? _poll;
  StreamSubscription<Uint8List>? _sse;
  Timer? _retry;
  int _tries = 0;
  bool _closed = false;
  static const _base = '/api/v2/pos-terminal/delivery';

  /// Serverning jonli oqimiga ulanish. Uzilsa o'sib boruvchi kechikish
  /// bilan qayta urinadi (2, 4, 8… 30 s) — tarmoq tiklanganda o'zi qaytadi.
  Future<void> _connect() async {
    if (_closed) return;
    try {
      // `raw` — interceptor'lari bilan bir xil Dio (token o'zi qo'shiladi);
      // oqim uchun `options` kerak, o'ram esa uni qabul qilmaydi.
      final res = await _ref.read(dioClientProvider).raw.get<ResponseBody>(
            '$_base/stream',
            options: Options(
              responseType: ResponseType.stream,
              // Oqim uzoq turadi — kutish chegarasi qo'yilmaydi.
              receiveTimeout: Duration.zero,
              headers: {'Accept': 'text/event-stream'},
            ),
          );
      _tries = 0;
      _sse = res.data?.stream.listen(
        (chunk) {
          // Oqimda ikki xil narsa keladi: «changed» hodisasi va tirikchilik
          // uchun izoh («ping»). Faqat birinchisi ro'yxatni yangilaydi.
          if (utf8.decode(chunk, allowMalformed: true).contains('changed')) {
            load(silent: true);
          }
        },
        onError: (_) => _reconnect(),
        onDone: _reconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _reconnect();
    }
  }

  void _reconnect() {
    if (_closed) return;
    _sse?.cancel();
    _sse = null;
    _tries = _tries < 5 ? _tries + 1 : 5;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: [2, 4, 8, 15, 30, 30][_tries - 1]), _connect);
  }

  @override
  void dispose() {
    _closed = true;
    _poll?.cancel();
    _retry?.cancel();
    _sse?.cancel();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(loading: true);
    try {
      final res = await _ref
          .read(dioClientProvider)
          .get<Map<String, dynamic>>('$_base/orders');
      final items = ((res.data?['items'] as List?) ?? const [])
          .map((e) => DlvOrder.fromJson(e as Map<String, dynamic>))
          .toList();
      final counts = <String, int>{};
      ((res.data?['counts'] as Map?) ?? const {}).forEach((k, v) {
        counts[k as String] = ((v ?? 0) as num).round();
      });
      state = DeliveryState(orders: items, counts: counts, loading: false);
    } catch (e) {
      // Internet uzilsa oxirgi ro'yxat ekranda QOLADI — kassir buyurtmani
      // ko'rib turishi kerak, bo'sh ekran eng yomon holat.
      state = state.copyWith(loading: false, offline: true);
    }
  }

  /// TASDIQLASH — POS cheki yoziladi va to'langan bo'ladi.
  /// Xato bo'lsa matn qaytadi (kassirga ko'rsatiladi), muvaffaqiyatda `null`.
  /// TASDIQLASH. Xato bo'lsa matn qaytadi. Muvaffaqiyatda `null`, LEKIN
  /// diqqat talab qiladigan holat bo'lsa (oshxonada tugagan taom yoki
  /// katalogga tushmagan pozitsiya) ogohlantirish matni qaytadi —
  /// buyurtma yozildi, ammo kassir buni ko'rishi kerak.
  Future<String?> confirm(String id) async {
    try {
      final res = await _ref.read(dioClientProvider).post<Map<String, dynamic>>(
            '$_base/orders/$id/confirm',
            data: const {},
          );
      await load(silent: true);
      final d = res.data ?? const {};
      final warn = <String>[];
      final stopped = (d['stopped_items'] as List?)?.whereType<String>().toList();
      if (stopped != null && stopped.isNotEmpty) {
        warn.add("Oshxonada TUGAGAN: ${stopped.join(', ')}");
      }
      final skipped = (d['skipped_items'] as List?)?.whereType<String>().toList();
      if (skipped != null && skipped.isNotEmpty) {
        warn.add("Chekka tushmadi: ${skipped.join(', ')}");
      }
      if (d['price_mismatch'] == true) {
        final ext = (d['external_total'] as num?)?.round();
        final amt = (d['amount'] as num?)?.round();
        warn.add("Narx farqi: chek $amt, tashqi tizimda $ext");
      }
      return warn.isEmpty ? null : warn.join(' · ');
    } catch (e) {
      await load(silent: true);
      return _errText(e);
    }
  }

  Future<String?> setStatus(String id, String status) =>
      _act('$_base/orders/$id/status', {'status': status});

  Future<String?> assignCourier(String id, String name,
          {String? phone, String? externalId}) =>
      _act('$_base/orders/$id/courier', {
        'name': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (externalId != null && externalId.isNotEmpty) 'external_id': externalId,
      });

  Future<String?> cancel(String id, String reason) =>
      _act('$_base/orders/$id/cancel', {'reason': reason});

  Future<String?> _act(String path, [Map<String, dynamic>? body]) async {
    try {
      await _ref
          .read(dioClientProvider)
          .post<Map<String, dynamic>>(path, data: body ?? const {});
      await load(silent: true);
      return null;
    } catch (e) {
      await load(silent: true);
      return _errText(e);
    }
  }

  /// Serverning o'zbekcha xato matnini ajratib olamiz — kassirga
  /// «DioException…» emas, «Mahsulotlarni moslashtiring» chiqishi kerak.
  ///
  /// Matn JAVOB TANASIDAN olinadi: `DioException.toString()` unga
  /// kirmaydi, shuning uchun ilgari har xato «internetni tekshiring»
  /// bo'lib chiqardi — kassir esa aslida mahsulot katalogda yo'qligini
  /// bilishi kerak edi va internetni tekshirib vaqt yo'qotardi.
  String _errText(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      // FastAPI xatoni `{"detail": "..."}` ko'rinishida qaytaradi.
      if (data is Map) {
        final d = data['detail'] ?? data['message'] ?? data['error'];
        if (d is String && d.trim().isNotEmpty) return d;
        if (d != null) return d.toString();
      }
      if (data is String && data.trim().isNotEmpty) {
        final m = RegExp(r'"detail"\s*:\s*"([^"]*)"').firstMatch(data);
        if (m != null && m.group(1)!.isNotEmpty) return m.group(1)!;
        return data.length > 200 ? data.substring(0, 200) : data;
      }
      // Javob umuman yo'q — haqiqatan tarmoq muammosi.
      if (e.response == null) {
        return 'Serverga ulanmadi — internetni tekshirib qayta urinib ko\'ring';
      }
      return 'Server xatosi (${e.response?.statusCode}) — qayta urinib ko\'ring';
    }
    final s = e.toString();
    final m = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(s);
    if (m != null) return m.group(1)!;
    return 'Bajarilmadi — qayta urinib ko\'ring';
  }
}

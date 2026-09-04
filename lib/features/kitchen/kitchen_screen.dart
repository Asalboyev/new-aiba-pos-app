// OSHPAZ EKRANI — Figma «AIBA POS (KITCHEN) / MAIN (Oshpaz)» dizayni.
//
// Oshpaz O'Z PAROLI bilan kiradi (login ekrani umumiy) — roli 'kitchen'
// bo'lsa kassa o'rniga SHU ekran ochiladi:
//   • taomlar grid'i: rasm, nom, «N ta qoldi» + holat (Tugadi / Kam / Yetarli)
//   • bosilsa o'ng SAVATCHAGA tushadi (miqdor −/+, kasr ham bo'ladi)
//   • «Tasdiqlash» — partiya kirim: server porsiyani oshiradi, xomashyoni
//     tex-karta bo'yicha ayiradi; POS va TV'da darhol ko'rinadi.
//
// REAL-TIME: doska 5 soniyada yangilanadi — kassada savdo bo'lishi bilan
// «qoldi» sonlari o'zi kamayadi.
// OFLAYN: doska keshda (SharedPreferences); kirimlar mahalliy NAVBATGA
// yoziladi (client_uuid bilan idempotent) va sonlar LOKAL oshirib turiladi,
// internet qaytishi bilan navbat o'zi serverga ketadi.

import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers/core_providers.dart';
import '../../core/widgets/app_background.dart';
import '../../core/widgets/pos_chrome.dart';
import '../auth/presentation/providers/auth_providers.dart';

// ── Model ────────────────────────────────────────────────────────────────────

class KitchenDish {
  const KitchenDish({
    required this.productId,
    required this.name,
    required this.unit,
    required this.qty,
    required this.status,
    required this.stopped,
    this.imageUrl,
    this.categoryId,
    this.category,
    this.sku,
  });

  final String productId;
  final String name;
  final String unit;
  final double qty;
  final String status; // ok | low | out
  final bool stopped;
  final String? imageUrl;
  final String? categoryId;

  /// Kategoriya nomi (stansiya) — chiplar shu nomlardan yig'iladi.
  final String? category;
  final String? sku;

  factory KitchenDish.fromJson(Map<String, dynamic> j) => KitchenDish(
        productId: (j['product_id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        unit: (j['unit'] ?? 'dona') as String,
        qty: ((j['qty'] ?? 0) as num).toDouble(),
        status: (j['status'] ?? 'ok') as String,
        stopped: (j['stopped'] ?? false) as bool,
        imageUrl: j['image_url'] as String?,
        categoryId: j['category_id'] as String?,
        category: j['category'] as String?,
        sku: j['sku'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'name': name,
        'unit': unit,
        'qty': qty,
        'status': status,
        'stopped': stopped,
        'image_url': imageUrl,
        'category_id': categoryId,
        'category': category,
        'sku': sku,
      };

  /// Mahalliy (hali yuborilmagan) kirimni sonlarga qo'shib ko'rsatish uchun.
  KitchenDish plus(double n) {
    final next = qty + n;
    return KitchenDish(
      productId: productId,
      name: name,
      unit: unit,
      qty: next,
      status: next <= 0 ? 'out' : (status == 'out' ? 'ok' : status),
      stopped: next > 0 ? false : stopped,
      imageUrl: imageUrl,
      categoryId: categoryId,
      category: category,
      sku: sku,
    );
  }
}

class KitchenState {
  const KitchenState({
    this.dishes = const [],
    this.loading = false,
    this.offline = false,
    this.pendingCount = 0,
  });
  final List<KitchenDish> dishes;
  final bool loading;
  final bool offline;
  final int pendingCount;

  KitchenState copyWith({
    List<KitchenDish>? dishes,
    bool? loading,
    bool? offline,
    int? pendingCount,
  }) =>
      KitchenState(
        dishes: dishes ?? this.dishes,
        loading: loading ?? this.loading,
        offline: offline ?? this.offline,
        pendingCount: pendingCount ?? this.pendingCount,
      );
}

final kitchenProvider =
    StateNotifierProvider<KitchenNotifier, KitchenState>((ref) => KitchenNotifier(ref));

class KitchenNotifier extends StateNotifier<KitchenState> {
  KitchenNotifier(this._ref) : super(const KitchenState()) {
    _connSub = Connectivity().onConnectivityChanged.listen((_) => flushQueue());
    // REAL-TIME: kassada savdo bo'lishi bilan «qoldi» o'zi kamayishi uchun
    // doska muntazam yangilanadi.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => load(silent: true));
    load();
  }

  final Ref _ref;
  Timer? _poll;
  StreamSubscription<dynamic>? _connSub;
  static const _cacheKey = 'kitchen_board_cache';
  static const _queueKey = 'kitchen_pending_punches';

  @override
  void dispose() {
    _poll?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(loading: true);
    final prefs = await SharedPreferences.getInstance();
    try {
      // Versiya yuboriladi: qoldiqlar o'zgarmagan bo'lsa server ro'yxatni
      // qayta yubormaydi (≈130 KB o'rniga bir necha o'nlab bayt) — ekran
      // har 5 soniyada bekorga yangilanmaydi.
      final res = await _ref.read(dioClientProvider).get<Map<String, dynamic>>(
            '/api/v2/pos-terminal/kitchen/board',
            query: _version == null ? null : {'version': _version},
          );
      if (res.data?['unchanged'] == true) {
        state = state.copyWith(loading: false, offline: false);
        await flushQueue();
        return;
      }
      _version = res.data?['version'] as String?;
      final base = _ref
          .read(appConfigProvider)
          .baseUrl
          .replaceAll(RegExp(r'/+$'), '');
      var dishes = ((res.data?['items'] as List?) ?? const [])
          .map((j) => KitchenDish.fromJson(j as Map<String, dynamic>))
          .map((d) => d.imageUrl != null && d.imageUrl!.startsWith('/')
              ? KitchenDish(
                  productId: d.productId,
                  name: d.name,
                  unit: d.unit,
                  qty: d.qty,
                  status: d.status,
                  stopped: d.stopped,
                  imageUrl: '$base${d.imageUrl}',
                  categoryId: d.categoryId,
                  category: d.category,
                  sku: d.sku,
                )
              : d)
          .toList();
      await prefs.setString(_cacheKey, jsonEncode([for (final d in dishes) d.toJson()]));
      // Hali yuborilmagan mahalliy kirimlar sonlarga qo'shib ko'rsatiladi —
      // oshpaz oflaynda ham to'g'ri qoldiqni ko'radi.
      dishes = _applyQueue(dishes, await _queue(prefs));
      state = state.copyWith(
        dishes: dishes,
        loading: false,
        offline: false,
        pendingCount: (await _queue(prefs)).length,
      );
      await flushQueue();
    } catch (e) {
      // 401 — token yaroqsiz/eskirgan (masalan boshqa serverga ulangan
      // yoki muddati o'tgan). Bu «internet yo'q» EMAS: OFLAYN deb keshda
      // ushlab turmasdan, oshpazni login ekraniga qaytaramiz — u qayta
      // kirsa yangi token olinadi. Aks holda ekran «OFLAYN» bo'lib qotardi.
      if (e is DioException && e.response?.statusCode == 401) {
        await _ref.read(sessionProvider.notifier).logout();
        return;
      }
      final raw = prefs.getString(_cacheKey);
      var dishes = state.dishes;
      if (dishes.isEmpty && raw != null) {
        dishes = (jsonDecode(raw) as List)
            .map((j) => KitchenDish.fromJson(j as Map<String, dynamic>))
            .toList();
        dishes = _applyQueue(dishes, await _queue(prefs));
      }
      state = state.copyWith(
        dishes: dishes,
        loading: false,
        offline: true,
        pendingCount: (await _queue(prefs)).length,
      );
    }
  }

  /// Serverdagi ro'yxat imzosi — o'zgarmasa qayta yuklab o'tirilmaydi.
  String? _version;

  Future<List<Map<String, dynamic>>> _queue(SharedPreferences prefs) async =>
      ((jsonDecode(prefs.getString(_queueKey) ?? '[]')) as List)
          .cast<Map<String, dynamic>>()
          .toList();

  List<KitchenDish> _applyQueue(
      List<KitchenDish> dishes, List<Map<String, dynamic>> queue) {
    for (final b in queue) {
      for (final it in (b['items'] as List).cast<Map<String, dynamic>>()) {
        final idx = dishes.indexWhere((d) => d.productId == it['product_id']);
        if (idx >= 0) {
          dishes[idx] = dishes[idx].plus(((it['qty'] ?? 0) as num).toDouble());
        }
      }
    }
    return dishes;
  }

  /// «Tasdiqlash» — partiya kirim. Onlaynda serverga; bo'lmasa navbatga va
  /// sonlar LOKAL oshadi (internet qaytishi bilan o'zi yuboriladi).
  Future<bool> punch(Map<String, double> items) async {
    if (items.isEmpty) return true;
    final body = {
      'items': [
        for (final e in items.entries) {'product_id': e.key, 'qty': e.value},
      ],
      'client_uuid': const Uuid().v4(),
    };
    try {
      await _ref
          .read(dioClientProvider)
          .post<Map<String, dynamic>>('/api/v2/pos-terminal/kitchen/produce', data: body);
      await load(silent: true);
      return true;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final q = await _queue(prefs);
      q.add(body);
      await prefs.setString(_queueKey, jsonEncode(q));
      state = state.copyWith(
        dishes: _applyQueue([...state.dishes], [body]),
        offline: true,
        pendingCount: q.length,
      );
      return false;
    }
  }

  Future<void> flushQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final q = await _queue(prefs);
    if (q.isEmpty) return;
    final remaining = <Map<String, dynamic>>[];
    var sent = false;
    for (final b in q) {
      try {
        await _ref
            .read(dioClientProvider)
            .post<Map<String, dynamic>>('/api/v2/pos-terminal/kitchen/produce', data: b);
        sent = true;
      } catch (_) {
        remaining.add(b);
      }
    }
    await prefs.setString(_queueKey, jsonEncode(remaining));
    if (sent && remaining.isEmpty) await load(silent: true);
    if (mounted) state = state.copyWith(pendingCount: remaining.length);
  }
}

// ── Ekran ────────────────────────────────────────────────────────────────────

class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  String _q = '';
  String? _cat; // null = Hammasi (stansiya/kategoriya filtri)
  int _batchNo = 1;
  final Map<String, double> _basket = {}; // product_id → qty
  final _searchCtl = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Kassa terminalidagidek klaviatura bilan boshqarish (sichqonchasiz):
    //   F1 — qidiruvga o'tish; Enter — savatchani tasdiqlash; Esc — chiqish.
    HardwareKeyboard.instance.addHandler(_onHwKey);
  }

  bool _onHwKey(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false; // dialog ochiq
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.f1) {
      _searchFocus.requestFocus();
      _searchCtl.selection = TextSelection(baseOffset: 0, extentOffset: _searchCtl.text.length);
      return true;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (_searchFocus.hasFocus) { _searchFocus.unfocus(); return true; }
      ref.read(sessionProvider.notifier).logout();
      return true;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (_searchFocus.hasFocus) {
        final st = ref.read(kitchenProvider);
        KitchenDish? first;
        for (final d in st.dishes) {
          if ((_cat == null || d.category == _cat) &&
              (_q.isEmpty || d.name.toLowerCase().contains(_q.toLowerCase()))) { first = d; break; }
        }
        if (first != null) { _add(first); _searchCtl.clear(); setState(() => _q = ''); }
        return true;
      }
      if (_basket.isNotEmpty) { _confirm(); return true; }
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHwKey);
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _add(KitchenDish d, [double n = 1]) {
    setState(() => _basket[d.productId] = (_basket[d.productId] ?? 0) + n);
  }

  void _dec(String pid) {
    setState(() {
      final cur = (_basket[pid] ?? 0) - 1;
      if (cur <= 0) {
        _basket.remove(pid);
      } else {
        _basket[pid] = cur;
      }
    });
  }

  Future<void> _editQty(KitchenDish d) async {
    final ctl = TextEditingController(
        text: (_basket[d.productId] ?? 0).toString().replaceAll(RegExp(r'\.0$'), ''));
    final v = await showDialog<double>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: PosColors.panel,
        title: Text(d.name, style: const TextStyle(fontSize: 18)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(labelText: 'Miqdor (0.5 ham bo\'ladi)'),
          onSubmitted: (s) => Navigator.of(dctx)
              .pop(double.tryParse(s.trim().replaceAll(',', '.'))),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(), child: const Text('Bekor')),
          FilledButton(
            onPressed: () => Navigator.of(dctx)
                .pop(double.tryParse(ctl.text.trim().replaceAll(',', '.'))),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (v != null) {
      setState(() {
        if (v <= 0) {
          _basket.remove(d.productId);
        } else {
          _basket[d.productId] = v;
        }
      });
    }
  }

  Future<void> _confirm() async {
    final items = Map<String, double>.from(_basket);
    final online = await ref.read(kitchenProvider.notifier).punch(items);
    if (!mounted) return;
    setState(() {
      _basket.clear();
      _batchNo++;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: online ? PosColors.green : PosColors.red,
      content: Text(online
          ? 'Buyurtma qo\'shildi — POS va TV yangilandi. Chiqilmoqda…'
          : 'OFLAYN saqlandi — internet qaytishi bilan yuboriladi. Chiqilmoqda…'),
    ));
    // Tasdiqlagach AVTOMATIK CHIQISH: oshxona planshetida bir necha oshpaz
    // navbat bilan ishlaydi — keyingisi o'z kodi bilan kiradi, oldingisining
    // nomidan kirim qilinmaydi.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    await ref.read(sessionProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(kitchenProvider);
    final session = ref.watch(sessionProvider);
    final cats = <String>{
      for (final d in st.dishes)
        if ((d.category ?? '').isNotEmpty) d.category!,
    }.toList()
      ..sort();
    final dishes = st.dishes
        .where((d) => _cat == null || d.category == _cat)
        .where((d) => _q.isEmpty || d.name.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    final totalPicked = _basket.values.fold<double>(0, (s, v) => s + v);

    return Scaffold(
      backgroundColor: PosColors.bg,
      body: AppBackground(
        child: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Chap: qidiruv + grid ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtl,
                              focusNode: _searchFocus,
                              onChanged: (v) => setState(() => _q = v),
                              textInputAction: TextInputAction.search,
                              style: const TextStyle(fontSize: 17),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'Taom qidirish (F1)…',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                filled: true,
                                fillColor: PosColors.field,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (st.offline || st.pendingCount > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: PosColors.red.withValues(alpha: .18),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                st.pendingCount > 0 && MediaQuery.of(context).size.width >= 700
                                    ? 'OFLAYN · ${st.pendingCount} navbatda'
                                    : 'OFLAYN',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: PosColors.red, fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          // POS savdo ekranidagidek: eng tepada — yangilash + avatar (menyu).
                          _RoundIconBtn(
                            icon: Icons.refresh,
                            onTap: () => ref.read(kitchenProvider.notifier).load(),
                          ),
                          const SizedBox(width: 8),
                          PopupMenuButton<String>(
                            tooltip: '',
                            color: PosColors.panel,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onSelected: (v) {
                              if (v == 'logout') {
                                ref.read(sessionProvider.notifier).logout();
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                enabled: false,
                                child: Text('${session?.staff.name ?? ''}\nOshpaz',
                                    style: const TextStyle(color: PosColors.label, fontSize: 13)),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'logout',
                                child: Row(children: [
                                  Icon(Icons.logout, size: 18, color: PosColors.red),
                                  SizedBox(width: 10),
                                  Text('Chiqish', style: TextStyle(color: PosColors.red)),
                                ]),
                              ),
                            ],
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: const BoxDecoration(color: PosColors.green, shape: BoxShape.circle),
                              child: Center(
                                child: Text(
                                  (session?.staff.name ?? 'A').trim().split(' ')
                                      .map((w) => w.isEmpty ? '' : w[0]).take(2).join().toUpperCase(),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (cats.length > 1) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 40,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _CatChip(
                                label: 'Hammasi',
                                selected: _cat == null,
                                onTap: () => setState(() => _cat = null),
                              ),
                              for (final c in cats)
                                _CatChip(
                                  label: c,
                                  selected: _cat == c,
                                  onTap: () => setState(() => _cat = c),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: PosColors.panel,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: st.loading && dishes.isEmpty
                              ? const Center(child: CircularProgressIndicator())
                              : dishes.isEmpty
                                  ? const Center(
                                      child: Text(
                                          'Oshxona hisobida taom yo\'q —\nadmin paneldan «Taom qo\'shish» qiling.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: PosColors.muted,
                                              fontSize: 16)))
                                  : LayoutBuilder(builder: (context, gc) {
                                      final cols = (gc.maxWidth / 175)
                                          .floor()
                                          .clamp(2, 6);
                                      return GridView.builder(
                                        padding: EdgeInsets.zero,
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: cols,
                                          childAspectRatio: 172 / 168,
                                          mainAxisSpacing: 12,
                                          crossAxisSpacing: 12,
                                        ),
                                        itemCount: dishes.length,
                                        itemBuilder: (context, i) => _DishCard(
                                          dish: dishes[i],
                                          picked:
                                              _basket[dishes[i].productId] ?? 0,
                                          onTap: () => _add(dishes[i]),
                                        ),
                                      );
                                    }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ── O'ng: savatcha (Figma «Basket») ──
              Container(
                // 320px — Figma o'lchami. Bu ekran PLANSHET uchun: telefon
                // enida (<720px) savatcha ichidagi qatorlar ham sig'maydi,
                // shuning uchun enni qisqartirish yordam bermaydi — telefon
                // uchun alohida joylashuv kerak (hali qilinmagan).
                width: 320,
                margin: const EdgeInsets.fromLTRB(8, 12, 16, 16),
                decoration: BoxDecoration(
                  color: PosColors.panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: PosColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Buyurtma $_batchNo',
                              style: const TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          const Text('Tayyorlangan taomlar kirimi',
                              style: TextStyle(
                                  color: PosColors.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: PosColors.cardBorder),
                    Expanded(
                      child: _basket.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.shopping_cart_outlined,
                                        size: 56, color: PosColors.iconChip),
                                    SizedBox(height: 12),
                                    Text('Savatcha hozircha bo\'sh',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700)),
                                    SizedBox(height: 4),
                                    Text(
                                        'Taomlarni tanlang va savatchaga qo\'shing',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: PosColors.muted,
                                            fontSize: 13)),
                                  ],
                                ),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.all(10),
                              children: [
                                for (final e in _basket.entries)
                                  _BasketRow(
                                    dish: st.dishes.firstWhere(
                                        (d) => d.productId == e.key,
                                        orElse: () => KitchenDish(
                                            productId: e.key,
                                            name: '—',
                                            unit: 'dona',
                                            qty: 0,
                                            status: 'ok',
                                            stopped: false)),
                                    qty: e.value,
                                    onDec: () => _dec(e.key),
                                    onInc: () => setState(() =>
                                        _basket[e.key] = (_basket[e.key] ?? 0) + 1),
                                    onEdit: () => _editQty(st.dishes.firstWhere(
                                        (d) => d.productId == e.key)),
                                  ),
                              ],
                            ),
                    ),
                    const Divider(height: 1, color: PosColors.cardBorder),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${_basket.length} mahsulot turi',
                              style: const TextStyle(
                                  color: PosColors.muted, fontSize: 13)),
                          Text('${_fmtQty(totalPicked)} ta mahsulot',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: SizedBox(
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: PosColors.blue,
                            disabledBackgroundColor: PosColors.iconChip,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _basket.isEmpty ? null : _confirm,
                          child: const Text('Tasdiqlash',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmtQty(double v) {
  final s = v.toStringAsFixed(3);
  return s.replaceAll(RegExp(r'\.?0+$'), '');
}

String _unitUz(String u) => u == 'dona' ? 'ta' : u;

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.dish, this.small = false});
  final KitchenDish dish;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final (label, color) = dish.stopped || dish.status == 'out'
        ? ('Tugadi', PosColors.red)
        : dish.status == 'low'
            ? ('Kam qoldi', const Color(0xFFE08A12))
            : ('Yetarli', PosColors.green);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 9, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: small ? 10.5 : 12,
              fontWeight: FontWeight.w800,
              color: Colors.white)),
    );
  }
}

class _DishImage extends StatelessWidget {
  const _DishImage({required this.url, required this.size, this.radius = 10});
  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // `size` CHEKSIZ bo'lishi mumkin (katta kartochkada rasm butun enni
    // egallaydi — 741-qator). Bunda ikona o'lchami ham cheksiz bo'lib
    // Flutter «fontSize.isFinite» assertion'i bilan YIQILADI: rasmi yo'q
    // taom oshxona ekranida ko'rinsa ilova qulab tushardi. Cheksiz holatda
    // ikonaga qat'iy o'lcham beramiz (parent Container'ni baribir cheklaydi).
    final iconSize = size.isFinite ? size * .45 : 44.0;
    final ph = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: PosColors.iconChip,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.restaurant, size: iconSize, color: PosColors.muted),
    );
    if (url == null || url!.isEmpty) return ph;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(url!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => ph),
    );
  }
}

/// Figma taom kartasi: rasm tepada, pastda nom + «N ta qoldi» + holat badge.
class _DishCard extends StatelessWidget {
  const _DishCard({required this.dish, required this.picked, required this.onTap});
  final KitchenDish dish;
  final double picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: PosColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: picked > 0 ? PosColors.blue : PosColors.cardBorder,
              width: picked > 0 ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _DishImage(url: dish.imageUrl, size: double.infinity, radius: 0),
                  if (picked > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: PosColors.blue,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('+${_fmtQty(picked)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(dish.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5, color: PosColors.label)),
                      ),
                      if ((dish.sku ?? '').isNotEmpty)
                        Text('#${dish.sku}',
                            style: const TextStyle(
                                fontSize: 11, color: PosColors.muted)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${_fmtQty(dish.qty)} ${_unitUz(dish.unit)} qoldi',
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w800)),
                      _StatusBadge(dish: dish, small: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BasketRow extends StatelessWidget {
  const _BasketRow({
    required this.dish,
    required this.qty,
    required this.onDec,
    required this.onInc,
    required this.onEdit,
  });

  final KitchenDish dish;
  final double qty;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: PosColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PosColors.cardBorder),
      ),
      child: Row(
        children: [
          _DishImage(url: dish.imageUrl, size: 40),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dish.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                _StatusBadge(dish: dish, small: true),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDec,
            icon: const Icon(Icons.remove_circle_outline, size: 22),
          ),
          InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(_fmtQty(qty),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onInc,
            icon: const Icon(Icons.add_circle_outline, size: 22),
          ),
        ],
      ),
    );
  }
}


/// Stansiya/kategoriya chipi (Figma «Hammasi / Pizza / …» qatori uslubida).
class _CatChip extends StatelessWidget {
  const _CatChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? PosColors.blue : PosColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? PosColors.blue : PosColors.cardBorder),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : PosColors.label)),
        ),
      ),
    );
  }
}

class _RoundIconBtn extends StatelessWidget {
  const _RoundIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PosColors.iconChip,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: PosColors.label),
        ),
      ),
    );
  }
}

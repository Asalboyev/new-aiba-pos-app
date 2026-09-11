import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/core_providers.dart';
import 'kitchen_screen.dart' show KitchenDish;
import '../../core/widgets/pos_chrome.dart';

/// OSHXONA TV — zalga/oshxonaga osilgan televizor uchun ko'rinish.
///
/// Ilgari bu sahifa serverdan HTML bo'lib kelardi va uni televizor
/// brauzerida `next.aiba.uz/<32 belgili kalit>/pos-tv` deb QO'LDA ochish
/// kerak edi — amalda eng qiyin qadam shu bo'lgan. Endi TV monoblokka
/// HDMI bilan ulansa, ilovaning O'ZI ikkinchi oynani televizorda ochadi:
/// brauzer ham, havola ham, kalit ham kerak emas.
///
/// Ma'lumot manbai bir xil: `/pos-terminal/kitchen/board`. Bu oyna FAQAT
/// KO'RSATADI — hech narsa yozmaydi, shuning uchun lokal bazani (drift)
/// ochmaydi: ikki jarayon bitta sqlite faylini ochib qolmasin.
class KitchenTvScreen extends ConsumerStatefulWidget {
  const KitchenTvScreen({super.key});

  @override
  ConsumerState<KitchenTvScreen> createState() => _KitchenTvScreenState();
}

class _KitchenTvScreenState extends ConsumerState<KitchenTvScreen> {
  static const _kCache = 'tv_board_cache';

  Timer? _timer;
  List<KitchenDish> _dishes = const [];
  String? _version;
  DateTime? _at;
  bool _offline = false;
  String _biz = '';

  @override
  void initState() {
    super.initState();
    _restore();
    _load();
    // 3 soniya — eski HTML sahifadagi bilan bir xil tezlik.
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Oxirgi holat — internet yo'q bo'lsa ham TV bo'sh qolmasin.
  void _restore() {
    try {
      final raw = ref.read(sharedPreferencesProvider).getString(_kCache);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _dishes = ((j['items'] as List?) ?? const [])
          .map((x) => KitchenDish.fromJson(x as Map<String, dynamic>))
          .toList();
      _offline = true;
    } catch (_) {
      // keshdagi yozuv buzilgan — e'tiborsiz qoldiramiz
    }
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(dioClientProvider).get<Map<String, dynamic>>(
            '/api/v2/pos-terminal/kitchen/board',
            query: _version == null ? null : {'version': _version},
          );
      if (!mounted) return;
      final data = res.data ?? const {};
      if (data['unchanged'] == true) {
        if (_offline) setState(() => _offline = false);
        return;
      }
      _version = data['version'] as String?;
      final base = ref
          .read(appConfigProvider)
          .baseUrl
          .replaceAll(RegExp(r'/+$'), '');
      final items = ((data['items'] as List?) ?? const [])
          .map((x) => KitchenDish.fromJson(x as Map<String, dynamic>))
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
      // Keshni saqlaymiz (rasm manzillari bilan) — keyingi ochilishda darhol
      // ko'rinadi.
      try {
        await ref.read(sharedPreferencesProvider).setString(
              _kCache,
              jsonEncode({'items': (data['items'] as List?) ?? const []}),
            );
      } catch (_) {}
      setState(() {
        _dishes = items;
        _at = DateTime.now();
        _offline = false;
        _biz = (data['restaurant'] ?? data['biz'] ?? '') as String? ?? '';
      });
    } catch (_) {
      if (mounted && !_offline) setState(() => _offline = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final out = _dishes.where((d) => d.status == 'out').toList();
    final low = _dishes.where((d) => d.status == 'low').toList();
    final ok = _dishes.where((d) => d.status == 'ok').toList();
    return Scaffold(
      backgroundColor: PosColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Col(title: 'Tugadi', color: PosColors.red, dishes: out),
                  _Col(title: 'Kam qoldi', color: const Color(0xFFE0A030), dishes: low),
                  _Col(title: 'Yetarli', color: PosColors.green, dishes: ok),
                ],
              ),
            ),
            _Bar(at: _at, offline: _offline, biz: _biz),
          ],
        ),
      ),
    );
  }
}

class _Col extends StatelessWidget {
  const _Col({required this.title, required this.color, required this.dishes});
  final String title;
  final Color color;
  final List<KitchenDish> dishes;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: PosColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color, fontSize: 30, fontWeight: FontWeight.w800)),
                  Text('${dishes.length}',
                      style: TextStyle(
                          color: color, fontSize: 30, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Expanded(
              child: dishes.isEmpty
                  ? const Center(
                      child: Text('—',
                          style: TextStyle(color: Colors.white24, fontSize: 34)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: dishes.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Colors.white10),
                      itemBuilder: (_, i) => _Row(dish: dishes[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.dish});
  final KitchenDish dish;

  @override
  Widget build(BuildContext context) {
    final img = dish.imageUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: img == null || img.isEmpty
                  ? const ColoredBox(
                      color: Colors.white10,
                      child: Center(
                          child: Text('🍲', style: TextStyle(fontSize: 26))))
                  : Image.network(img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                            color: Colors.white10,
                            child: Center(
                                child: Text('🍲', style: TextStyle(fontSize: 26))),
                          )),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(dish.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Text(_qty(dish),
              style: const TextStyle(
                  color: Colors.white70, fontSize: 24, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  static String _qty(KitchenDish d) {
    final q = d.qty;
    final s = q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(1);
    return '$s ${d.unit == 'dona' ? 'porsiya' : d.unit}';
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.at, required this.offline, required this.biz});
  final DateTime? at;
  final bool offline;
  final String biz;

  @override
  Widget build(BuildContext context) {
    final t = at == null
        ? '—'
        : '${at!.hour.toString().padLeft(2, '0')}:${at!.minute.toString().padLeft(2, '0')}:${at!.second.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      color: Colors.black.withValues(alpha: 0.35),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: offline ? PosColors.red : PosColors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              offline
                  ? 'OFLAYN (oxirgi holat) · $t'
                  : 'Oxirgi yangilanish: $t',
              style: const TextStyle(color: Colors.white54, fontSize: 18),
            ),
          ]),
          Text(biz, style: const TextStyle(color: Colors.white38, fontSize: 18)),
        ],
      ),
    );
  }
}

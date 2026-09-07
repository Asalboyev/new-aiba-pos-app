import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../menu/domain/entities/product.dart';
import '../../../menu/presentation/providers/menu_providers.dart';
import '../providers/sync_service.dart';

/// Skaner kodi bazada topilmadi → kassir mahsulotni tanlaydi, kod unga
/// biriktiriladi (server: POST /pos-terminal/products/{id}/barcode) va
/// mahsulot savatga tushadi. Keyingi skanerlash o'zi topadi — barcha
/// terminallarga sinxron orqali tarqaladi.
class AssignBarcodeDialog extends ConsumerStatefulWidget {
  const AssignBarcodeDialog({super.key, required this.code, this.allowMarked = false});
  final String code;

  /// Markirovkali mahsulotlar odatda ro'yxatda ko'rsatilmaydi (ular menyudan
  /// emas, skanerdan sotiladi). Ammo skanerlangan kod DataMatrix bo'lsa —
  /// aynan markirovkali mahsulotni tanlash kerak.
  final bool allowMarked;

  static Future<Product?> show(BuildContext context, String code,
          {bool allowMarked = false}) =>
      showDialog<Product>(
        context: context,
        builder: (_) => AssignBarcodeDialog(code: code, allowMarked: allowMarked),
      );

  @override
  ConsumerState<AssignBarcodeDialog> createState() => _AssignBarcodeDialogState();
}

class _AssignBarcodeDialogState extends ConsumerState<AssignBarcodeDialog> {
  String _q = '';
  String? _busyId;
  String? _err;

  Future<void> _pick(Product p) async {
    if (_busyId != null) return;
    setState(() { _busyId = p.id; _err = null; });
    try {
      await ref.read(dioClientProvider).post<Map<String, dynamic>>(
            '/api/v2/pos-terminal/products/${p.id}/barcode',
            data: {'barcode': widget.code},
          );
      // Boshqa terminallar va lokal kesh keyingi sinxronda yangilanadi;
      // bu terminalda darhol foydalanish uchun nusxani qaytaramiz.
      ref.read(syncServiceProvider.notifier).syncAll();
      if (mounted) Navigator.of(context).pop(p.copyWithBarcode(widget.code));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _err = e is Failure ? e.message : 'Biriktirib bo\'lmadi — qayta urinib ko\'ring';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(productsProvider).maybeWhen(
          data: (p) => p,
          orElse: () => const <Product>[],
        );
    final q = _q.trim().toLowerCase();
    final list = all
        .where((p) => p.isActive && (widget.allowMarked || !p.markingRequired))
        .where((p) => q.isEmpty ||
            p.name.toLowerCase().contains(q) ||
            (p.sku ?? '').toLowerCase().contains(q))
        .take(40)
        .toList();

    return Dialog(
      backgroundColor: const Color(0xFF1C1D22),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.qr_code_2, color: Colors.amber, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Kod topilmadi: ${widget.code}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 6),
              const Text(
                'Bu qaysi mahsulot? Tanlang — kod unga biriktiriladi, keyingi '
                'safar skaner o\'zi topadi (hamma kassada).',
                style: TextStyle(color: Color(0xFF8A9098), fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF232329),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF8A9098), size: 20),
                  hintText: 'Mahsulot nomi yoki kodi…',
                  hintStyle: const TextStyle(color: Color(0xFF5C626A)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0x3DFFFFFF)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF2277EA), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('Mos mahsulot yo\'q',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF8A9098))),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Color(0x1FFFFFFF)),
                        itemBuilder: (_, i) {
                          final p = list[i];
                          final busy = _busyId == p.id;
                          return ListTile(
                            dense: true,
                            onTap: busy ? null : () => _pick(p),
                            title: Text(p.name,
                                style: const TextStyle(color: Colors.white, fontSize: 15)),
                            subtitle: (p.sku ?? '').isEmpty || (p.barcode ?? '').isNotEmpty
                                ? Text(
                                    (p.barcode ?? '').isNotEmpty
                                        ? 'shtrix-kod bor: ${p.barcode} (almashtiriladi)'
                                        : '',
                                    style: const TextStyle(color: Color(0xFFE0A030), fontSize: 12))
                                : Text('kod ${p.sku}',
                                    style: const TextStyle(color: Color(0xFF8A9098), fontSize: 12)),
                            trailing: busy
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : Text('${p.price.round()} so\'m',
                                    style: const TextStyle(
                                        color: Color(0xFFB8BEC6), fontSize: 14)),
                          );
                        },
                      ),
              ),
              if (_err != null) ...[
                const SizedBox(height: 8),
                Text(_err!, style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13)),
              ],
              const SizedBox(height: 8),
              const Text('Esc — bekor qilish',
                  style: TextStyle(color: Color(0xFF8A9098), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

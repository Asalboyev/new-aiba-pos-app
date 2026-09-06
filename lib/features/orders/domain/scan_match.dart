import '../../menu/domain/entities/product.dart';

/// Skaner kodi bo'yicha mahsulot topish.
///
/// USB skaner klaviatura kabi yozadi: EAN-13 (`4780000000000`), GTIN-14
/// (`04780000000000`), GS1 DataMatrix (`0104780000000000 21…`), ba'zan
/// bo'shliq/chiziqcha bilan. Bazadagi `barcode` ham xuddi shunday
/// normalizatsiya qilinadi (backend `norm_barcode`), shuning uchun EAN-13 va
/// GTIN-14 bir xil kod hisoblanadi.
///
/// Tartib: shtrix-kod → SKU (aniq) → MXIK (aniq) → SKU kod ichida (eski
/// xatti-harakat, faqat 3+ belgili SKU uchun — «1» kabi qisqa kod hamma
/// kodga «mos» kelib qolmasin).
String normalizeScan(String raw) {
  var code = raw.replaceAll(RegExp(r'[\s\-]'), '');
  if (code.isEmpty) return '';
  // GS1 (DataMatrix): `01` + 14 raqam GTIN, keyin boshqa AI'lar (21 seriya…)
  if (code.length >= 16 &&
      code.startsWith('01') &&
      RegExp(r'^\d{14}$').hasMatch(code.substring(2, 16))) {
    code = code.substring(2, 16);
  }
  if (RegExp(r'^\d+$').hasMatch(code)) {
    final t = code.replaceFirst(RegExp(r'^0+'), '');
    code = t.isEmpty ? '0' : t;
  }
  return code;
}

/// Markirovka (DataMatrix) kodi — GS1 `01` bilan boshlanadi va 16+ belgi.
bool looksLikeMarkingCode(String raw) {
  final c = raw.replaceAll(RegExp(r'[\s\-]'), '');
  return c.length >= 20 && c.startsWith('01') && RegExp(r'^\d{16}').hasMatch(c);
}

Product? matchScan(Iterable<Product> products, String raw) {
  final norm = normalizeScan(raw);
  if (norm.isEmpty) return null;
  final lower = norm.toLowerCase();
  final rawLower = raw.trim().toLowerCase();

  Product? bySku;
  Product? byMxik;
  Product? byContains;
  for (final p in products) {
    final bc = normalizeScan(p.barcode ?? '');
    if (bc.isNotEmpty && bc == norm) return p; // eng ishonchli
    final sku = (p.sku ?? '').trim().toLowerCase();
    if (sku.isNotEmpty) {
      if (bySku == null && (sku == lower || sku == rawLower)) bySku = p;
      if (byContains == null && sku.length >= 3 && rawLower.contains(sku)) byContains = p;
    }
    final mxik = (p.mxikCode ?? '').trim().toLowerCase();
    if (byMxik == null && mxik.isNotEmpty && (mxik == lower || mxik == rawLower)) byMxik = p;
  }
  return bySku ?? byMxik ?? byContains;
}

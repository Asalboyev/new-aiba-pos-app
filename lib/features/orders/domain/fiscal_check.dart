import 'entities/cart.dart';

/// To'lovdan OLDIN chekni soliqqa yubora olamizmi — sof tekshiruv.
///
/// E-POS rejimida server har satrda 17 xonali MXIK (IKPU) va paket kodini
/// talab qiladi. Ilgari bu faqat to'lov bosilgandan keyin bilinardi va
/// kassir inglizcha «Item 'X': mxik_code is required» xabarini ko'rib
/// qotib qolardi — navbat esa kutardi.
///
/// Qaytaradi: muammoni tushuntiruvchi matn, yoki hammasi joyida bo'lsa null.
String? fiscalBlocker(Iterable<CartItem> items, String? fiscalProvider) {
  final fp = (fiscalProvider ?? '').trim();
  // `mock` — sinov rejimi, soliqqa hech narsa ketmaydi: to'sib turmaymiz.
  if (!fp.startsWith('epos')) return null;
  for (final i in items) {
    final mx = (i.mxikCode ?? '').trim();
    final pk = (i.packageCode ?? '').trim();
    if (mx.length != 17 || !RegExp(r'^\d{17}$').hasMatch(mx)) {
      return '${i.name}: MXIK kodi (17 xonali IKPU) to\'ldirilmagan — admin '
          'panelda mahsulot kartochkasiga kiriting, aks holda soliqqa chek '
          'ketmaydi';
    }
    if (pk.isEmpty) {
      return '${i.name}: paket kodi to\'ldirilmagan — admin panelda mahsulot '
          'kartochkasiga kiriting, aks holda soliqqa chek ketmaydi';
    }
  }
  return null;
}

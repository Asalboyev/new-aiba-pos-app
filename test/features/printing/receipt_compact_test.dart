import 'package:aiba_pos_terminal/features/orders/domain/entities/cart.dart';
import 'package:aiba_pos_terminal/features/orders/domain/entities/payment_method.dart';
import 'package:aiba_pos_terminal/features/printing/data/receipt_builder.dart';
import 'package:aiba_pos_terminal/features/printing/domain/receipt_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chek baytlarini matnga o'girish (ESC/POS buyruqlari tashlanadi, CP866
/// kirill dekod qilinmaydi — ASCII qismi yetadi).
String _text(List<int> bytes) {
  final sb = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    if (b == 0x1B) { // ESC @ (2 bayt) yoki ESC x n (3 bayt)
      i += (i + 1 < bytes.length && bytes[i + 1] == 0x40) ? 1 : 2;
      continue;
    }
    if (b == 0x1D) { // GS V m [n] (kesish) yoki GS x n
      final m = i + 1 < bytes.length ? bytes[i + 1] : 0;
      i += (m == 0x56 && i + 2 < bytes.length && bytes[i + 2] >= 0x41) ? 3 : 2;
      continue;
    }
    if (b == 0x0A) { sb.write('\n'); continue; }
    if (b >= 0x20 && b < 0x7F) sb.writeCharCode(b);
  }
  // Har qator boshidagi «.» — stil buyrug'ining ma'lumot bayti (0x2E) qoldig'i.
  return sb.toString().replaceAll(RegExp(r'^\.', multiLine: true), '');
}

ReceiptData _data(List<CartItem> items, {int paper = 80, num discount = 0}) {
  final sub = items.fold<num>(0, (t, i) => t + i.lineTotal);
  return ReceiptData(
    restaurantName: 'Diet Bistro',
    terminalName: 'T1',
    orderNumber: '12',
    items: items,
    subtotal: sub,
    discount: discount,
    total: sub - discount,
    payments: [Payment(PaymentMethod.cash, sub - discount)],
    paperWidth: paper,
    createdAt: DateTime(2026, 9, 6, 12, 30),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('1 dona mahsulot — BIR qator (nom + summa), Oraliq qatori yo\'q', () async {
    final t = _text(await ReceiptBuilder.build(_data(const [
      CartItem(name: 'Palov', price: 35000, qty: 1),
    ])));
    final lines = t.split('\n');
    expect(lines.any((l) => l.startsWith('Palov') && l.trim().endsWith('35 000')), isTrue);
    expect(lines.any((l) => l.contains('1x35 000')), isFalse);
    expect(t.contains('Oraliq'), isFalse);
    expect(t.contains('JAMI'), isTrue);
  });

  test('bir necha dona — «soni x narx» va summa bir qatorda, o\'ng chetga tekis', () async {
    final t = _text(await ReceiptBuilder.build(_data(const [
      CartItem(name: 'Somsa', price: 12000, qty: 3),
    ])));
    final line = t.split('\n').firstWhere((l) => l.contains('Somsa'));
    expect(line, contains('3x12 000'));
    expect(line.trim(), endsWith('36 000'));
    expect(line.length, 48); // 80mm — 48 ustun, o'ng chet to'liq
  });

  test('uzun nom 58mm da alohida qatorga o\'raladi, hisob ostida', () async {
    final t = _text(await ReceiptBuilder.build(_data(const [
      CartItem(name: 'Assorti ovoshnoe s shampinyonami bolshoy', price: 45000, qty: 2),
    ], paper: 58)));
    expect(t.contains('2x45 000'), isTrue);
    for (final l in t.split('\n')) {
      expect(l.length <= 32, isTrue, reason: 'qator 32 dan uzun: "$l"');
    }
  });

  test('chegirma bo\'lsa Oraliq chiqadi', () async {
    final t = _text(await ReceiptBuilder.build(_data(const [
      CartItem(name: 'Palov', price: 35000, qty: 1),
    ], discount: 5000)));
    expect(t.contains('Oraliq'), isTrue);
    expect(t.contains('Chegirma'), isTrue);
  });

  test('Sotilganlar cheki: soni ustuni tekis, JAMI, kesishdan oldin ortiqcha bo\'sh qator yo\'q', () async {
    final bytes = await ReceiptBuilder.buildSoldItems(
      title: 'KUNLIK SOTILGANLAR',
      restaurantName: 'Diet Bistro',
      shiftName: '06.09.2026 · kun yopildi',
      items: const [
        ZItem(name: 'Palov', qty: 12, amount: 420000),
        ZItem(name: 'Somsa', qty: 3, amount: 36000),
        ZItem(name: 'Choy', qty: 100, amount: 300000),
      ],
    );
    final t = _text(bytes);
    final rows = t.split('\n').where((l) => l.contains(' x ')).toList();
    expect(rows.length, 3);
    // "nnn x " — soni 3 belgiga o'ngga tekislangan → nom bir joydan boshlanadi
    expect(rows.every((l) => l.substring(3, 6) == ' x '), isTrue, reason: rows.join(' | '));
    expect(rows.every((l) => l.length == 48), isTrue);
    expect(t.contains('KUNLIK SOTILGANLAR'), isTrue);
    expect(t.contains('JAMI (3 xil)'), isTrue);
    // cut() o'zi 5 qator beradi — qo'shimcha feed bo'lmasin (qog'oz tejash)
    final tail = t.substring(t.lastIndexOf('JAMI'));
    expect(RegExp(r'\n{7,}').hasMatch(tail), isFalse);
  });

  test('onlayn buyurtma cheki: kanal, raqam, mijoz va kuryer ko\'rinadi', () async {
    final d = _data(const [
      CartItem(name: 'Borsh', price: 27400, qty: 2),
    ]);
    final t = _text(await ReceiptBuilder.build(ReceiptData(
      restaurantName: d.restaurantName,
      terminalName: d.terminalName,
      orderNumber: d.orderNumber,
      items: d.items,
      subtotal: d.subtotal,
      discount: 0,
      total: d.total,
      payments: d.payments,
      paperWidth: 80,
      createdAt: d.createdAt,
      delivery: const DeliveryInfo(
        channelLabel: 'Uzum Tezkor',
        orderNo: '167',
        customer: 'Marsel',
        phone: '+998001112201',
        address: 'Toshkent, Chilonzor 5',
        deliveryFee: 5000,
        ownCourier: true,
      ),
    )));
    expect(t.contains('UZUM TEZKOR'), isTrue);
    // «№» — CP866 bayti, bu testdagi dekoder uni tashlab yuboradi,
    // shuning uchun matn va raqam alohida tekshiriladi.
    expect(t.contains('BUYURTMA'), isTrue);
    expect(t.contains('167'), isTrue);
    expect(t.contains('Marsel'), isTrue);
    expect(t.contains('+998001112201'), isTrue);
    expect(t.contains('Chilonzor 5'), isTrue);
    expect(t.contains('Uzum Tezkor kuryeri olib ketadi'), isTrue);
    expect(t.contains('Yetkazish'), isTrue);
    expect(t.split('\n').any((l) => l.contains('Borsh') && l.contains('2x27 400')), isTrue);
  });

  test('oddiy (zaldagi) chekda dostavka bloki YO\'Q', () async {
    final t = _text(await ReceiptBuilder.build(_data(const [
      CartItem(name: 'Palov', price: 35000, qty: 1),
    ])));
    expect(t.contains('BUYURTMA №'), isFalse);
    expect(t.contains('kuryer'), isFalse);
  });

  test('Z-hisobot: sotilganlar bo\'limi sarlavhasida soni, qatorlar tekis', () async {
    final bytes = await ReceiptBuilder.buildZReport(
      restaurantName: 'Diet Bistro', shiftName: 'Smena 1', staffName: 'Ali',
      openedAt: DateTime(2026, 9, 6, 9), closedAt: DateTime(2026, 9, 6, 18),
      ordersCount: 10, totalSales: 500000, cash: 300000, card: 200000, click: 0, uzum: 0, keldi: 0,
      openingCash: 100000, expenses: 20000, errorChecks: 0,
      items: const [ZItem(name: 'Palov', qty: 7, amount: 245000)],
    );
    final t = _text(bytes);
    expect(t.contains('SOTILGANLAR (1)'), isTrue);
    expect(t.split('\n').any((l) => l.startsWith('  7 x Palov')), isTrue);
    expect(t.contains('KASSADA NAQD'), isTrue);
  });
}

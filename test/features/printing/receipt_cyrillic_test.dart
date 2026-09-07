import 'package:aiba_pos_terminal/features/orders/domain/entities/cart.dart';
import 'package:aiba_pos_terminal/features/orders/domain/entities/payment_method.dart';
import 'package:aiba_pos_terminal/features/printing/data/receipt_builder.dart';
import 'package:aiba_pos_terminal/features/printing/domain/receipt_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Baytlardan matn: ESC/POS buyruqlari tashlanadi; CP866 kirill baytlari
/// (0x80+) «Ø» bo'ladi — shunda kirill CP866 orqali ketganini ko'ramiz.
String _text(List<int> bytes) {
  final sb = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    if (b == 0x1B) {
      i += (i + 1 < bytes.length && bytes[i + 1] == 0x40) ? 1 : 2;
      continue;
    }
    if (b == 0x1D) {
      final m = i + 1 < bytes.length ? bytes[i + 1] : 0;
      if (m == 0x28) {
        final n = bytes[i + 2] + bytes[i + 3] * 256;
        i += 3 + n;
        continue;
      }
      i += (m == 0x56 && i + 2 < bytes.length && bytes[i + 2] >= 0x41) ? 3 : 2;
      continue;
    }
    if (b == 0x0A) {
      sb.write("\n");
      continue;
    }
    // CP866 kirill baytlari «Ø» — kirill kod jadvali orqali ketganini ko'rish uchun
    if (b >= 0x20 && b < 0x7F) {
      sb.writeCharCode(b);
    } else if (b >= 0x80) {
      sb.write('Ø');
    }
  }
  return sb.toString().replaceAll(RegExp(r'^\.', multiLine: true), '');
}

ReceiptData _data({int paper = 80}) => ReceiptData(
      restaurantName: 'Диет Бистро', legalName: 'ООО DIET BISTRO', inn: '306462869', phone: '+998 71 200 00 00',
      terminalName: 'Касса 1', orderNumber: 'ЧЛ-7',
      items: const [
        CartItem(name: 'Мастава', price: 22000, qty: 1),
        CartItem(name: 'Лағмон ўзбекча қовурма', price: 30000, qty: 2),
      ],
      subtotal: 82000, discount: 0, total: 82000,
      payments: const [Payment(PaymentMethod.cash, 82000)],
      paperWidth: paper, createdAt: DateTime(2026, 9, 7, 10, 0),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => ReceiptBuilder.latinize = false);

  test('kirill nomlar CP866 baytlari bilan ketadi — exception yo\'q, «?» yo\'q', () async {
    final t = _text(await ReceiptBuilder.build(_data()));
    expect(t.contains('?'), isFalse);
    // 'Мастава' — 7 kirill harf → 7 ta 0x80+ bayt
    expect(t.split('\n').any((l) => l.startsWith('ØØØØØØØ') && l.trim().endsWith('22 000')), isTrue);
  });

  test('translit: rus va o\'zbek kirill → lotin', () {
    expect(ReceiptBuilder.translit('Мастава'), 'Mastava');
    expect(ReceiptBuilder.translit('Лағмон ўзбекча қовурма'), "Lag'mon o'zbekcha qovurma");
    expect(ReceiptBuilder.translit('Щи, Ёлка, Цех — №1'), 'Shi, Yolka, Tsex — №1');
    expect(ReceiptBuilder.translit('PEPSI 1,75 л'), 'PEPSI 1,75 l');
  });

  test('latinize yoqilsa chek to\'liq lotin (0x80+ bayt yo\'q)', () async {
    ReceiptBuilder.latinize = true;
    final t = _text(await ReceiptBuilder.build(_data()));
    expect(t.contains('Ø'), isFalse);
    expect(t.contains('Mastava'), isTrue);
    expect(t.contains("2x30 000"), isTrue); // Lag'mon 2 dona
    expect(t.contains('Diet Bistro'), isTrue);
  });

  test('INN va telefon bir qatorda (80mm), 58mm da alohida', () async {
    final t80 = _text(await ReceiptBuilder.build(_data()));
    expect(t80.contains('INN: 306462869 | Tel: +998 71 200 00 00'), isTrue);
    final t58 = _text(await ReceiptBuilder.build(_data(paper: 58)));
    expect(t58.contains('INN: 306462869 | Tel'), isFalse);
    expect(t58.contains('INN: 306462869'), isTrue);
    expect(t58.contains('Tel: +998 71 200 00 00'), isTrue);
  });

  test('buildMinimal — favqulodda ASCII chek, hech qachon otmaydi', () async {
    final t = _text(await ReceiptBuilder.buildMinimal(_data()));
    expect(t.contains('Ø'), isFalse);
    expect(t.contains('Diet Bistro'), isTrue);
    expect(t.contains('JAMI'), isTrue);
    expect(t.contains('82 000'), isTrue);
  });
}

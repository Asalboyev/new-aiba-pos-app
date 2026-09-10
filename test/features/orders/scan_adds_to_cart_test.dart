import 'package:aiba_pos_terminal/core/providers/core_providers.dart';
import 'package:aiba_pos_terminal/features/menu/domain/entities/product.dart';
import 'package:aiba_pos_terminal/features/menu/presentation/providers/menu_providers.dart';
import 'package:aiba_pos_terminal/features/orders/presentation/providers/cart_provider.dart';
import 'package:aiba_pos_terminal/features/orders/presentation/widgets/product_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kassir shisha qopqog'idagi DataMatrix'ni skanerlaydi — skaner kodni
/// QIDIRUV maydoniga yozib Enter yuboradi. Mahsulot savatga O'ZI tushishi
/// kerak (ilgari hech nima bo'lmasdi: GS1 satrida harflar borligi uchun
/// u nom bo'yicha qidiruvga tushib ketardi).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cola = Product(
    id: '1',
    name: 'Coca-Cola 0,5',
    price: 12000,
    sku: 'кола0,5',
    barcode: '5449000000996',
  );

  Future<ProviderContainer> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      categoriesProvider.overrideWith((ref) async => []),
      productsProvider.overrideWith((ref) async => [cola]),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ProductGrid())),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> scan(WidgetTester tester, String code, {bool settle = true}) async {
    await tester.enterText(find.byType(TextField).first, code);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // SnackBar tekshiriladigan joyda `settle` qilmaymiz — u o'zi yo'qoladi.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  testWidgets('markirovka (DataMatrix) skanerlansa savatga o\'zi qo\'shiladi',
      (tester) async {
    final c = await pump(tester);
    // GTIN 05449000000996 + seriya. Seriya kirillda — skaner ruscha
    // klaviatura tilida yozgan holat.
    await scan(tester, '0105449000000996' '217_!*йП9ж1ЙУВт93ефьш');

    final items = c.read(cartProvider).items;
    expect(items.length, 1, reason: 'mahsulot savatga tushmadi');
    expect(items.first.name, 'Coca-Cola 0,5');
    // Seriya chekka biriktiriladi va kirilldan lotinga qaytarilgan bo'ladi.
    expect(items.first.labels.single, '0105449000000996217_!*qG9;1QEDn93tami');
  });

  testWidgets('oddiy EAN-13 skanerlansa ham savatga qo\'shiladi',
      (tester) async {
    final c = await pump(tester);
    await scan(tester, '5449000000996');
    expect(c.read(cartProvider).items.length, 1);
    expect(c.read(cartProvider).items.first.name, 'Coca-Cola 0,5');
  });

  testWidgets('AYNAN SHU shisha ikki marta o\'qilsa — ikkinchisi rad etiladi',
      (tester) async {
    final c = await pump(tester);
    const dm = '0105449000000996' '21BIR-XIL-SERIYA';
    await scan(tester, dm);
    await scan(tester, dm, settle: false);
    final items = c.read(cartProvider).items;
    expect(items.length, 1);
    // Miqdor 1 bo'lib qoladi: bir xil seriya ikki marta soliqqa ketmaydi.
    expect(items.first.qty, 1);
    expect(items.first.labels.length, 1);
  });

  testWidgets('markirovkali qatorda miqdorni RAQAM terib oshirib bo\'lmaydi',
      (tester) async {
    final c = await pump(tester);
    await scan(tester, '0105449000000996' '21SERIYA-1');
    // Kassir «3» + Enter teradi — odatda bu miqdorni 3 qiladi.
    await scan(tester, '3', settle: false);
    final items = c.read(cartProvider).items;
    expect(items.first.qty, 1, reason: 'markirovkali qatorda miqdor oshmasligi kerak');
    expect(items.first.labels.length, 1);
  });
}

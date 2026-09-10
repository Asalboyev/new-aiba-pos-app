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

  Future<void> scan(WidgetTester tester, String code) async {
    await tester.enterText(find.byType(TextField).first, code);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
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
}

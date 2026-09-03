// STOP-LIST QOPLAMASI — menyu sinxronda qayta yuborilmasa ham («menu
// unchanged» tejamkor rejim) oshxonada tugagan taom kassada «Tugadi» bo'lib
// ko'rinishi SHART. Shu kafolat testi.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aiba_pos_terminal/features/menu/domain/entities/category.dart';
import 'package:aiba_pos_terminal/features/menu/domain/entities/product.dart';
import 'package:aiba_pos_terminal/features/menu/domain/repositories/menu_repository.dart';
import 'package:aiba_pos_terminal/features/menu/presentation/providers/menu_providers.dart';

class _FakeMenuRepo implements MenuRepository {
  @override
  Future<List<Category>> cachedCategories() async => const [];

  @override
  Future<List<Product>> cachedProducts() async => const [
        Product(id: 'p1', name: 'Borsch', price: 25000),
        Product(id: 'p2', name: 'Coca-Cola', price: 12000),
      ];

  @override
  Future<bool> refreshFromServer() async => false;

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<Product>> read(Map<String, dynamic> kitchen) async {
    SharedPreferences.setMockInitialValues({
      'menu_kitchen': jsonEncode(kitchen),
    });
    final c = ProviderContainer(overrides: [
      menuRepositoryProvider.overrideWithValue(_FakeMenuRepo()),
    ]);
    addTearDown(c.dispose);
    return c.read(productsProvider.future);
  }

  test('oshxonada tugagan taom — kassada sotib bo\'lmaydi', () async {
    final list = await read({
      'p1': {'qty': 0, 'stopped': true},
    });
    final borsch = list.firstWhere((p) => p.id == 'p1');
    final cola = list.firstWhere((p) => p.id == 'p2');
    expect(borsch.outOfStock, isTrue, reason: 'stop-listdagi taom yopiq');
    expect(cola.outOfStock, isFalse, reason: 'ichimlik oshxonaga bog\'liq emas');
  });

  test('porsiya bor — sotiladi va qoldiq ko\'rinadi', () async {
    final list = await read({
      'p1': {'qty': 7, 'stopped': false},
    });
    final borsch = list.firstWhere((p) => p.id == 'p1');
    expect(borsch.outOfStock, isFalse);
    expect(borsch.stockQty, 7);
  });

  test('oshxona xaritasi bo\'sh — mahsulotlar o\'zgarmaydi', () async {
    final list = await read(const {});
    expect(list.every((p) => !p.outOfStock), isTrue);
  });
}

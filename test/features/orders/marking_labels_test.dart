import 'package:aiba_pos_terminal/features/menu/domain/entities/product.dart';
import 'package:aiba_pos_terminal/features/orders/data/models/order_mapper.dart';
import 'package:aiba_pos_terminal/features/orders/domain/entities/cart.dart';
import 'package:aiba_pos_terminal/features/orders/domain/entities/order_draft.dart';
import 'package:flutter_test/flutter_test.dart';

/// Markirovkali mahsulot IKKI DONA sotilsa, soliqqa IKKALA marka kodi
/// ketishi kerak. Ilgari faqat birinchisi jo'natilardi.
void main() {
  final cola = Product(
    id: '1',
    name: 'Coca-Cola 0,5',
    price: 12000,
    markingRequired: true,
  );

  Map<String, dynamic> firstItem(Cart cart) =>
      (OrderMapper.draftToOrderIn(OrderDraft(
        clientUuid: 'c1',
        items: cart.items,
        discount: 0,
        payments: const [],
      ))['items'] as List)
          .first as Map<String, dynamic>;

  test('bitta dona → `label`', () {
    final cart = const Cart().addProduct(cola, label: 'DM-1');
    final it = firstItem(cart);
    expect(it['label'], 'DM-1');
    expect(it.containsKey('labels'), isFalse);
  });

  test('ikki dona → IKKALA kod `labels` ro\'yxatida', () {
    final cart =
        const Cart().addProduct(cola, label: 'DM-1').addProduct(cola, label: 'DM-2');
    final it = firstItem(cart);
    expect(it['qty'], 2);
    expect(it['labels'], ['DM-1', 'DM-2']);
    // `label` bo'lmasligi shart: server uni ustun ko'rib, ikkinchi kodni
    // tashlab yuborardi.
    expect(it.containsKey('label'), isFalse);
  });
}

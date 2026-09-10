import 'package:aiba_pos_terminal/features/menu/domain/entities/product.dart';
import 'package:aiba_pos_terminal/features/orders/domain/entities/cart.dart';
import 'package:aiba_pos_terminal/features/orders/domain/fiscal_check.dart';
import 'package:flutter_test/flutter_test.dart';

CartItem _item({String? mxik, String? pkg}) => CartItem.fromProduct(Product(
      id: '1',
      name: 'Coca-Cola 0,5',
      price: 12000,
      mxikCode: mxik,
      packageCode: pkg,
    ));

void main() {
  const ok = '02201001001348001'; // 17 xona

  test('hammasi to\'ldirilgan — to\'siq yo\'q', () {
    expect(fiscalBlocker([_item(mxik: ok, pkg: '1513117')], 'epos'), isNull);
    expect(fiscalBlocker([_item(mxik: ok, pkg: '1513117')], 'epos_terminal'),
        isNull);
  });

  test('MXIK yo\'q yoki kalta — kassirga tushunarli xabar', () {
    final m = fiscalBlocker([_item(pkg: '1513117')], 'epos');
    expect(m, contains('Coca-Cola 0,5'));
    expect(m, contains('MXIK'));
    expect(fiscalBlocker([_item(mxik: '123', pkg: '1')], 'epos'), isNotNull);
  });

  test('paket kodi yo\'q', () {
    expect(fiscalBlocker([_item(mxik: ok)], 'epos'), contains('paket kodi'));
  });

  test('mock rejimda to\'sib turilmaydi (soliqqa hech narsa ketmaydi)', () {
    expect(fiscalBlocker([_item()], 'mock'), isNull);
    expect(fiscalBlocker([_item()], null), isNull);
  });
}

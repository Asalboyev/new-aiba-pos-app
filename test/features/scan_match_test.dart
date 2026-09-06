import 'package:aiba_pos_terminal/features/menu/domain/entities/product.dart';
import 'package:aiba_pos_terminal/features/orders/domain/scan_match.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(String id, String name, {String? sku, String? barcode, String? mxik}) =>
    Product(id: id, name: name, price: 10000, sku: sku, barcode: barcode, mxikCode: mxik);

void main() {
  final cola = _p('1', 'Coca-Cola 0,5', sku: 'кола0,5', barcode: '5449000000996');
  final water = _p('2', 'Мин вода 1,5л', sku: 'вод1,5', mxik: '02201001001348001');
  final one = _p('3', 'Bir', sku: '1');
  final all = [cola, water, one];

  test('normalizeScan: bo\'shliq, GTIN-14, GS1 prefiks', () {
    expect(normalizeScan(' 5449 0000 00996 '), '5449000000996');
    expect(normalizeScan('05449000000996'), '5449000000996');
    expect(normalizeScan('0105449000000996' '21ABC123'), '5449000000996');
    expect(normalizeScan('кола0,5'), 'кола0,5');
  });

  test('shtrix-kod bo\'yicha topadi (EAN-13 va GTIN-14 bir xil)', () {
    expect(matchScan(all, '5449000000996'), cola);
    expect(matchScan(all, '05449000000996'), cola);
    expect(matchScan(all, '0105449000000996' '21XYZ'), cola);
  });

  test('SKU va MXIK aniq mosligi', () {
    expect(matchScan(all, 'вод1,5'), water);
    expect(matchScan(all, '02201001001348001'), water);
  });

  test('qisqa SKU hamma kodga «mos» kelmaydi', () {
    expect(matchScan(all, '4780000000001'), isNull);
  });

  test('markirovka kodi aniqlanadi', () {
    expect(looksLikeMarkingCode('0105449000000996' '21ABC123XYZ'), isTrue);
    expect(looksLikeMarkingCode('5449000000996'), isFalse);
  });
}

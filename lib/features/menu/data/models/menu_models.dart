import '../../../../core/utils/money.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';

class CategoryModel {
  static Category fromJson(Map<String, dynamic> j) => Category(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        sortOrder: (j['sort_order'] is num)
            ? (j['sort_order'] as num).toInt()
            : int.tryParse('${j['sort_order']}') ?? 0,
        imageUrl: j['image_url']?.toString(),
      );
}

class ProductModel {
  static Product fromJson(Map<String, dynamic> j) => Product(
        id: (j['id'] ?? '').toString(),
        categoryId: j['category_id']?.toString(),
        name: (j['name'] ?? '').toString(),
        sku: j['sku']?.toString(),
        price: Money.parse(j['price']),
        mxikCode: j['mxik_code']?.toString(),
        packageCode: j['package_code']?.toString(),
        vatPercent: Money.parse(j['vat_percent']),
        unit: (j['unit'] ?? 'dona').toString(),
        imageUrl: j['image_url']?.toString(),
        isActive: j['is_active'] == null ? true : j['is_active'] == true,
        markingRequired: j['marking_required'] == true,
        trackStock: j['track_stock'] == true,
        stockQty: Money.parse(j['stock_qty']),
        lowStockThreshold: Money.parse(j['low_stock_threshold']),
      );
}

/// The full `/sync/pull` response.
class SyncPullResult {
  final List<Category> categories;
  final List<Product> products;
  final String? serverTime;

  /// Serverdagi menyu imzosi. Keyingi sinxronda shu qiymat yuboriladi va
  /// menyu o'zgarmagan bo'lsa server uni QAYTA YUBORMAYDI (600 mahsulot
  /// ≈ 290 KB tejaladi, kassa tezroq ishlaydi).
  final String? menuVersion;

  /// true — server «menyu o'zgarmagan» dedi: lokal kesh o'z holicha qoladi,
  /// faqat stop-list va ommaboplik yangilanadi.
  final bool menuUnchanged;

  /// OSHXONA STOP-LIST: {product_id: {qty, stopped}} — menyu yuborilmagan
  /// sinxronda ham keladi, kassa uni keshdagi mahsulot ustiga qo'yadi.
  final Map<String, dynamic> kitchen;

  /// Oxirgi 30 kunda qancha sotilgani ({product_id: soni}) — «Hammasi»
  /// ro'yxati eng ko'p sotilganidan boshlab teriladi (filialga xos).
  final Map<String, double> popularity;

  const SyncPullResult({
    required this.categories,
    required this.products,
    this.serverTime,
    this.popularity = const {},
    this.menuVersion,
    this.menuUnchanged = false,
    this.kitchen = const {},
  });

  static SyncPullResult fromJson(Map<String, dynamic> j) {
    final cats = (j['categories'] as List? ?? const [])
        .map((e) => CategoryModel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    // KITCHEN STOP-LIST: oshxonada porsiyasi tugagan taomlar sync'da
    // {product_id: {stopped: true}} bo'lib keladi — kassada «tugadi» bo'lib
    // ko'rinadi va bosib bo'lmaydi (server ham baribir rad qiladi).
    final kitchen = (j['kitchen'] as Map?)?.cast<String, dynamic>() ?? const {};
    final prods = (j['products'] as List? ?? const []).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      final k = kitchen[m['id']?.toString()];
      if (k is Map && k['stopped'] == true) {
        m['track_stock'] = true;
        m['stock_qty'] = '0';
      }
      return ProductModel.fromJson(m);
    }).toList();
    final pop = <String, double>{};
    ((j['popularity'] as Map?) ?? const {}).forEach((k, v) {
      pop[k.toString()] = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
    });
    return SyncPullResult(
      categories: cats,
      products: prods,
      serverTime: j['server_time']?.toString(),
      popularity: pop,
      menuVersion: j['menu_version']?.toString(),
      menuUnchanged: j['menu_unchanged'] == true,
      kitchen: kitchen,
    );
  }
}

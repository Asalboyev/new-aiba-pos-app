import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/errors/failure.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/menu_repository.dart';
import '../datasources/menu_local_datasource.dart';
import '../datasources/sync_remote_datasource.dart';

class MenuRepositoryImpl implements MenuRepository {
  MenuRepositoryImpl({
    required SyncRemoteDataSource remote,
    required MenuLocalDataSource local,
  })  : _remote = remote,
        _local = local;

  final SyncRemoteDataSource _remote;
  final MenuLocalDataSource _local;

  /// Oxirgi muvaffaqiyatli pull imzosi — menyu haqiqatan o'zgarganini
  /// aniqlash uchun (o'zgarmasa provayderlarni bekor qilmaymiz → grid
  /// har 60 soniyada qayta qurilmaydi, rasmlar qayta yuklanmaydi).
  String? _lastSignature;

  /// Serverdagi menyu imzosi (`menu_version`). Ilova qayta ochilganda ham
  /// eslab qolinsin uchun prefs'da saqlanadi.
  static const _kMenuVersion = 'menu_version';

  @override
  Future<List<Category>> cachedCategories() => _local.categories();

  @override
  Future<List<Product>> cachedProducts() => _local.products();

  @override
  Future<bool> refreshFromServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Serverga «menda shu versiya bor» deymiz — menyu o'zgarmagan bo'lsa
      // 600 ta mahsulot qayta yuborilmaydi (≈290 KB o'rniga ≈20 KB).
      final pull = await _remote.pull(menuVersion: prefs.getString(_kMenuVersion));
      // Ommaboplik xaritasi menyu imzosidan MUSTAQIL saqlanadi — menyu
      // o'zgarmasa ham savdo tartibi yangilanib turadi.
      await prefs.setString('menu_popularity', jsonEncode(pull.popularity));
      // Stop-list menyudan MUSTAQIL: menyu o'zgarmasa ham taom tugashi
      // mumkin — kassa uni keshdagi mahsulot ustiga qo'yadi.
      await prefs.setString('menu_kitchen', jsonEncode(pull.kitchen));
      if (pull.menuVersion != null && pull.menuVersion!.isNotEmpty) {
        await prefs.setString(_kMenuVersion, pull.menuVersion!);
      }
      // Server menyuni umuman yubormadi — lokal kesh o'z holicha to'g'ri.
      if (pull.menuUnchanged) return false;
      final sig = _signature(pull.categories, pull.products);
      if (sig == _lastSignature) {
        // Server bilan bir xil — cache va UI o'zgarishsiz qoladi.
        return false;
      }
      await _local.replaceMenu(pull.categories, pull.products);
      _lastSignature = sig;
      return true;
    } on Failure {
      // Offline / server error — keep the existing cache.
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Menyu tarkibining yengil imzosi (id|narx|rasm|nom|tartib).
  String _signature(List<Category> cats, List<Product> prods) {
    final b = StringBuffer('C${cats.length};P${prods.length};');
    for (final c in cats) {
      b.write('${c.id}:${c.sortOrder}:${c.imageUrl ?? ''}:${c.name}|');
    }
    for (final p in prods) {
      b.write('${p.id}:${p.price}:${p.imageUrl ?? ''}:${p.isActive}:'
          '${p.sku ?? ''}:${p.mxikCode ?? ''}:${p.name}|');
    }
    return b.toString().hashCode.toString();
  }
}

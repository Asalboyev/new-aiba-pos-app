// OFLAYN KIRISH — internet uzilganda ham xodim O'Z PAROLI bilan kirsin.
//
// Nega kerak: kassa/oshxona kun bo'yi ishlaydi, internet esa uzilib turadi.
// Sessiya saqlanadi (ilova qayta ochilsa kirgan holda qoladi), lekin xodim
// CHIQIB ketsa yoki SMENA almashsa — server yo'qligida hech kim kira olmasdi.
//
// Qanday ishlaydi: har MUVAFFAQIYATLI onlayn kirishda shu terminaldagi
// xodimning paroli xeshlanib (tuz + 20 000 marta SHA-256) sessiya nusxasi
// bilan birga telefonda saqlanadi. Keyin server topilmasa, kiritilgan parol
// shu xeshga solishtiriladi va saqlangan sessiya tiklanadi — kassa ishlashda
// davom etadi, cheklar navbatga tushadi va internet qaytganda yuboriladi.
//
// XAVFSIZLIK: parolning O'ZI hech qachon saqlanmaydi. Tuz har o'rnatishda
// tasodifiy — bir qurilmadan olingan xesh boshqasida ishlamaydi. Yozuv
// [_ttl] dan keyin eskiradi (server tokeni ham shuncha yashaydi), demak
// ishdan bo'shagan xodim cheksiz kira olmaydi.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:shared_preferences/shared_preferences.dart';

class OfflineLoginEntry {
  const OfflineLoginEntry({
    required this.session,
    required this.token,
    required this.savedAt,
  });

  /// `AuthSessionModel.toPersistedJson` nusxasi.
  final Map<String, dynamic> session;
  final String token;
  final DateTime savedAt;
}

class OfflineLoginStore {
  OfflineLoginStore(this._prefs);
  final SharedPreferences _prefs;

  static const _kEntries = 'offline_logins_v1';
  static const _kSalt = 'offline_login_salt_v1';

  /// Server tokeni 30 kun yashaydi — oflayn yozuv ham shuncha.
  static const _ttl = Duration(days: 30);

  /// Bir terminalda nechta xodim eslab qolinadi (kassir/menejer/oshpaz…).
  static const _maxEntries = 12;

  /// Isolate'dagi funksiya ham o'qiy olishi uchun ochiq.
  static const rounds = 20000;

  String _salt() {
    var s = _prefs.getString(_kSalt);
    if (s == null || s.isEmpty) {
      final r = Random.secure();
      s = base64Url.encode(List<int>.generate(24, (_) => r.nextInt(256)));
      _prefs.setString(_kSalt, s);
    }
    return s;
  }

  /// Parolni sekin xeshlaymiz: 4 xonali PIN'ni o'g'irlangan telefonda
  /// tanlab olish qimmatga tushsin.
  ///
  /// Hisob ALOHIDA ISOLATE'da bajariladi (`compute`) — 20 000 raund arzon
  /// planshetda ~0.3 s bo'lishi mumkin va asosiy oqimda qilinsa kirish
  /// paytida ekran qotib qolardi.
  Future<String> _hash(String terminalCode, String staffCode, String pin) =>
      compute(_hashRounds, '${_salt()}|$terminalCode|$staffCode|$pin');

  List<Map<String, dynamic>> _all() {
    try {
      final raw = _prefs.getString(_kEntries);
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<Map<String, dynamic>> list) async {
    await _prefs.setString(_kEntries, jsonEncode(list));
  }

  /// Onlayn kirish muvaffaqiyatli bo'lganda chaqiriladi.
  Future<void> remember({
    required String terminalCode,
    required String staffCode,
    required String pin,
    required Map<String, dynamic> session,
    required String token,
  }) async {
    if (pin.isEmpty || token.isEmpty) return;
    final h = await _hash(terminalCode, staffCode, pin);
    final list = _all()..removeWhere((e) => e['h'] == h);
    list.insert(0, {
      'h': h,
      'session': session,
      'token': token,
      'at': DateTime.now().toIso8601String(),
    });
    while (list.length > _maxEntries) {
      list.removeLast();
    }
    await _save(list);
  }

  /// Server topilmaganda: parol mos yozuvni qaytaradi (yo'q bo'lsa null).
  Future<OfflineLoginEntry?> find({
    required String terminalCode,
    required String staffCode,
    required String pin,
  }) async {
    final list = _all();
    if (list.isEmpty) return null;
    final h = await _hash(terminalCode, staffCode, pin);
    for (final e in list) {
      if (e['h'] != h) continue;
      final at = DateTime.tryParse('${e['at']}') ?? DateTime(2000);
      if (DateTime.now().difference(at) > _ttl) return null;
      final session = (e['session'] as Map?)?.cast<String, dynamic>();
      final token = '${e['token'] ?? ''}';
      if (session == null || token.isEmpty) return null;
      return OfflineLoginEntry(session: session, token: token, savedAt: at);
    }
    return null;
  }

  /// Shu terminalda oflayn kira oladigan xodimlar bormi (login ekranida
  /// «internet yo'q, lekin kira olasiz» deb aytish uchun).
  bool get hasAny => _all().isNotEmpty;

  /// Parol adminkada o'zgartirilgan bo'lsa eski xeshlar keraksiz — chiqishda
  /// emas, faqat aniq talab bilan tozalanadi.
  Future<void> clear() async => _prefs.remove(_kEntries);
}

/// Isolate ichida bajariladigan sof hisob (top-level bo'lishi shart).
String _hashRounds(String seed) {
  var digest = sha256.convert(utf8.encode(seed)).bytes;
  for (var i = 1; i < OfflineLoginStore.rounds; i++) {
    digest = sha256.convert(digest).bytes;
  }
  return base64Url.encode(digest);
}

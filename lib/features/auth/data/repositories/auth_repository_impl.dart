import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/auth/offline_login_store.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/auth_session_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AuthRemoteDataSource remote,
    required AppConfig config,
    required SharedPreferences prefs,
  })  : _remote = remote,
        _config = config,
        _prefs = prefs;

  final AuthRemoteDataSource _remote;
  final AppConfig _config;
  final SharedPreferences _prefs;

  late final OfflineLoginStore _offline = OfflineLoginStore(_prefs);

  static const _kSession = 'auth_session';
  /// Oxirgi kirish OFLAYN (mahalliy xesh) bo'lganini belgilaydi — UI shuni
  /// ko'rsatadi, sinxronizatsiya esa internet qaytishi bilan o'zi ishlaydi.
  static const _kOfflineLogin = 'auth_offline_login';

  /// true — joriy sessiya serversiz, mahalliy paroldan tiklangan.
  @override
  bool get lastLoginWasOffline => _prefs.getBool(_kOfflineLogin) ?? false;

  @override
  Future<AuthSession> login({
    required String terminalCode,
    required String staffCode,
    required String pin,
    required bool openShift,
    required num openingCash,
  }) async {
    try {
      final session = await _remote.login(
        terminalCode: terminalCode,
        staffCode: staffCode,
        pin: pin,
        openShift: openShift,
        openingCash: openingCash,
        // Sozlamalardagi biznes kodi (bo'sh bo'lsa yuborilmaydi).
        tenantSlug: _prefs.getString('tenant_slug') ?? '',
      );
      await _persist(session);
      await _prefs.setBool(_kOfflineLogin, false);
      // Keyingi safar internet bo'lmasa shu parol bilan kira olsin.
      // KUTMAYMIZ: xesh alohida isolate'da hisoblanadi, kassir esa shu
      // zahoti ichkariga kiradi (kirish tezligi pasaymaydi).
      unawaited(_offline.remember(
        terminalCode: terminalCode,
        staffCode: staffCode,
        pin: pin,
        session: AuthSessionModel.toPersistedJson(session),
        token: session.accessToken,
      ));
      return session;
    } on NetworkFailure {
      // SERVER YO'Q — shu terminalda avval kirgan xodim bo'lsa, paroli
      // mahalliy xeshga mos kelsa, saqlangan sessiya tiklanadi. Xato parol
      // bo'lsa (AuthFailure) bu yerga umuman tushmaymiz: parol xatosini
      // server aytadi, oflayn esa xesh mos kelmaydi.
      final cached = await _offline.find(
        terminalCode: terminalCode,
        staffCode: staffCode,
        pin: pin,
      );
      if (cached == null) {
        // Terminalda oflayn yozuvlar bor, lekin parol mos kelmadi — sabab
        // «internet yo'q» emas, aynan parol. Aniq aytamiz.
        if (_offline.hasAny) {
          throw const AuthFailure(
              'Internet yo\'q. Parol noto\'g\'ri yoki bu kassada avval '
              'kirmagansiz — internet qaytgach qayta urinib ko\'ring.');
        }
        rethrow;
      }
      await _config.setToken(cached.token);
      await _prefs.setString(_kSession, jsonEncode(cached.session));
      await _prefs.setBool(_kOfflineLogin, true);
      return AuthSessionModel.fromPersistedJson(cached.session, cached.token);
    }
  }

  @override
  Future<AuthSession?> currentSession() async {
    final token = await _config.getToken();
    final raw = _prefs.getString(_kSession);
    if (token == null || token.isEmpty || raw == null) return null;
    try {
      final json = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return AuthSessionModel.fromPersistedJson(json, token);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> updateShiftId(String? shiftId) async {
    final raw = _prefs.getString(_kSession);
    if (raw == null) return;
    final json = (jsonDecode(raw) as Map).cast<String, dynamic>();
    json['shift_id'] = shiftId;
    await _prefs.setString(_kSession, jsonEncode(json));
  }

  @override
  Future<AuthSession?> refreshRestaurant() async {
    final token = await _config.getToken();
    final raw = _prefs.getString(_kSession);
    if (token == null || token.isEmpty || raw == null) return null;
    try {
      final fresh = await _remote.fetchRestaurant();
      if (fresh.isEmpty) return null;
      final json = (jsonDecode(raw) as Map).cast<String, dynamic>();
      // Restaurant blokini butunlay almashtiramiz — adminka nima jo'natsa shu.
      json['restaurant'] = fresh;
      await _prefs.setString(_kSession, jsonEncode(json));
      return AuthSessionModel.fromPersistedJson(json, token);
    } catch (_) {
      // Offline yoki 4xx — jimgina o'tkazamiz, chek eski sozlama bilan chiqadi.
      return null;
    }
  }

  @override
  Future<void> logout() async {
    await _config.setToken(null);
    await _prefs.remove(_kSession);
    await _prefs.remove(_kOfflineLogin);
    // MUHIM: oflayn kirish yozuvlari SAQLANIB qoladi — aynan chiqib
    // ketgandan keyin internetsiz qayta kirish uchun kerak.
  }

  Future<void> _persist(AuthSession session) async {
    await _config.setToken(session.accessToken);
    await _prefs.setString(
      _kSession,
      jsonEncode(AuthSessionModel.toPersistedJson(session)),
    );
  }
}

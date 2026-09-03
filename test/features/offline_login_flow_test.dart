// OFLAYN KIRISH OQIMI (butun zanjir): onlayn kirish → parol eslab qolinadi →
// server yo'qolganda o'sha parol bilan kassa yana ochiladi. Xato parol esa
// oflaynda ham o'tmaydi.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:aiba_pos_terminal/core/config/app_config.dart';
import 'package:aiba_pos_terminal/core/errors/failure.dart';
import 'package:aiba_pos_terminal/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:aiba_pos_terminal/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:aiba_pos_terminal/features/auth/domain/entities/auth_session.dart';

/// Server o'rniga: [online] false bo'lsa tarmoq xatosi beradi.
class _FakeRemote implements AuthRemoteDataSource {
  bool online = true;
  int calls = 0;

  @override
  Future<AuthSession> login({
    required String terminalCode,
    required String staffCode,
    required String pin,
    required bool openShift,
    required num openingCash,
    String tenantSlug = '',
  }) async {
    calls++;
    if (!online) throw const NetworkFailure();
    if (pin != '1234') throw const AuthFailure();
    return const AuthSession(
      accessToken: 'tok-1',
      restaurant: RestaurantInfo(id: 'r1', name: 'Diet Bistro', code: 'DIET'),
      terminal: TerminalInfo(id: 't1', name: 'T1', code: 'T1'),
      staff: StaffInfo(id: 's1', name: 'Kassir Vali', role: 'cashier'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRemote remote;
  late AuthRepositoryImpl repo;

  setUp(() async {
    // Secure storage — test muhitida oddiy xotira.
    final mem = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => switch (call.method) {
        'write' => mem[call.arguments['key'] as String] =
            call.arguments['value'] as String,
        'read' => mem[call.arguments['key'] as String],
        'delete' => mem.remove(call.arguments['key'] as String),
        _ => null,
      },
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    remote = _FakeRemote();
    repo = AuthRepositoryImpl(
      remote: remote,
      config: AppConfig(prefs, const FlutterSecureStorage()),
      prefs: prefs,
    );
  });

  Future<AuthSession> login(String pin) => repo.login(
        terminalCode: 'T1',
        staffCode: '',
        pin: pin,
        openShift: false,
        openingCash: 0,
      );

  test('internet uzilsa — o\'sha parol bilan kassa ochiladi', () async {
    final first = await login('1234');
    expect(first.staff.name, 'Kassir Vali');
    expect(repo.lastLoginWasOffline, isFalse);
    // Parol fon rejimida eslab qolinadi — yozilib bo'lishini kutamiz.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await repo.logout();

    remote.online = false;
    final second = await login('1234');
    expect(second.staff.name, 'Kassir Vali');
    expect(second.accessToken, 'tok-1');
    expect(repo.lastLoginWasOffline, isTrue, reason: 'oflayn kirdi');
  });

  test('internet yo\'q + xato parol — kirmaydi', () async {
    await login('1234');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await repo.logout();
    remote.online = false;
    expect(() => login('9999'), throwsA(isA<Failure>()));
  });

  test('hech qachon kirmagan terminal — oflaynda kira olmaydi', () async {
    remote.online = false;
    expect(() => login('1234'), throwsA(isA<NetworkFailure>()));
  });
}

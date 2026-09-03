// Oflayn kirish xotirasi: to'g'ri parol kiritsa sessiya tiklanadi, xato
// parol yoki eskirgan yozuv — yo'q.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aiba_pos_terminal/core/auth/offline_login_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineLoginStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = OfflineLoginStore(await SharedPreferences.getInstance());
  });

  const session = {
    'staff': {'id': 's1', 'full_name': 'Kassir Vali', 'role': 'cashier'},
    'terminal': {'id': 't1', 'name': 'T1', 'code': 'T1'},
    'restaurant': {'id': 'r1', 'name': 'Diet Bistro', 'code': 'DIET'},
  };

  test('to\'g\'ri parol — sessiya tiklanadi', () async {
    expect(store.hasAny, isFalse);
    await store.remember(
      terminalCode: 'T1',
      staffCode: '',
      pin: '1234',
      session: session,
      token: 'tok-1',
    );
    expect(store.hasAny, isTrue);
    final hit = await store.find(terminalCode: 'T1', staffCode: '', pin: '1234');
    expect(hit, isNotNull);
    expect(hit!.token, 'tok-1');
    expect((hit.session['staff'] as Map)['full_name'], 'Kassir Vali');
  });

  test('xato parol — null', () async {
    await store.remember(
      terminalCode: 'T1',
      staffCode: '',
      pin: '1234',
      session: session,
      token: 'tok-1',
    );
    expect(await store.find(terminalCode: 'T1', staffCode: '', pin: '1235'),
        isNull);
    // Boshqa terminal kodi ham mos kelmaydi.
    expect(await store.find(terminalCode: 'T2', staffCode: '', pin: '1234'),
        isNull);
  });

  test('bir nechta xodim — har biri o\'z paroli bilan', () async {
    await store.remember(
        terminalCode: 'T1',
        staffCode: '',
        pin: '1234',
        session: session,
        token: 'kassir');
    await store.remember(
        terminalCode: 'T1',
        staffCode: '',
        pin: '5678',
        session: session,
        token: 'oshpaz');
    expect((await store.find(terminalCode: 'T1', staffCode: '', pin: '1234'))!
        .token, 'kassir');
    expect((await store.find(terminalCode: 'T1', staffCode: '', pin: '5678'))!
        .token, 'oshpaz');
  });

  test('parol yangilansa — oxirgi token qoladi', () async {
    await store.remember(
        terminalCode: 'T1',
        staffCode: '',
        pin: '1234',
        session: session,
        token: 'eski');
    await store.remember(
        terminalCode: 'T1',
        staffCode: '',
        pin: '1234',
        session: session,
        token: 'yangi');
    final hit = await store.find(terminalCode: 'T1', staffCode: '', pin: '1234');
    expect(hit!.token, 'yangi');
  });

  test('30 kundan eski yozuv ishlamaydi', () async {
    final prefs = await SharedPreferences.getInstance();
    await store.remember(
        terminalCode: 'T1',
        staffCode: '',
        pin: '1234',
        session: session,
        token: 'tok');
    // Yozuvning sanasini orqaga suramiz.
    final raw = prefs.getString('offline_logins_v1')!;
    final old = raw.replaceAll(
      RegExp(r'"at":"[^"]+"'),
      '"at":"${DateTime.now().subtract(const Duration(days: 31)).toIso8601String()}"',
    );
    await prefs.setString('offline_logins_v1', old);
    expect(await store.find(terminalCode: 'T1', staffCode: '', pin: '1234'),
        isNull);
  });
}

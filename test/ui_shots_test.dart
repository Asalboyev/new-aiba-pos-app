// KASSA ILOVASI — UI SNAPSHOT HARNESS (ekranlarni ko'z bilan tekshirish).
//
//   flutter test test/ui_shots_test.dart --update-goldens
//
// Har ekranni planshet va telefon o'lchamida PNG qilib `test/shots/` ga
// yozadi. Server ham, emulyator ham kerak emas: dio soxta javob qaytaradi,
// menyu esa provider override orqali beriladi (drift/sqlite ochilmaydi).
//
// Bu test HECH NARSANI tasdiqlamaydi — faqat rasm chiqaradi. Maqsad: uch
// rolning (kassir / menejer / oshpaz) ekranlari haqiqatda qanday
// ko'rinishini ko'rish — overflow, kesilgan matn, sig'magan tugma.

import 'package:aiba_pos_terminal/core/util/app_clock.dart';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aiba_pos_terminal/core/config/app_config.dart';
import 'package:aiba_pos_terminal/core/network/dio_client.dart';
import 'package:aiba_pos_terminal/core/providers/core_providers.dart';
import 'package:aiba_pos_terminal/core/theme/app_theme.dart';
import 'package:aiba_pos_terminal/features/auth/domain/entities/auth_session.dart';
import 'package:aiba_pos_terminal/features/auth/domain/repositories/auth_repository.dart';
import 'package:aiba_pos_terminal/features/auth/presentation/providers/auth_providers.dart';
import 'package:aiba_pos_terminal/features/auth/presentation/screens/login_screen.dart';
import 'package:aiba_pos_terminal/features/delivery/presentation/screens/delivery_screen.dart';
import 'package:aiba_pos_terminal/features/home/presentation/home_shell.dart';
import 'package:aiba_pos_terminal/features/kitchen/kitchen_screen.dart';
import 'package:aiba_pos_terminal/features/menu/domain/entities/category.dart';
import 'package:aiba_pos_terminal/features/menu/domain/entities/product.dart';
import 'package:aiba_pos_terminal/features/menu/presentation/providers/menu_providers.dart';
import 'package:aiba_pos_terminal/features/shift/domain/entities/shift.dart';
import 'package:aiba_pos_terminal/features/shift/presentation/providers/shift_providers.dart';
import 'package:aiba_pos_terminal/features/shift/presentation/screens/shift_screen.dart';

// ── Soxta menyu (mock) ───────────────────────────────────────────────────────

const _cats = <Category>[
  Category(id: 'c1', name: '1-Taomlar', sortOrder: 1),
  Category(id: 'c2', name: '2-Taomlar', sortOrder: 2),
  Category(id: 'c3', name: 'Salatlar', sortOrder: 3),
  Category(id: 'c4', name: 'Ichimliklar', sortOrder: 4),
];

const _prods = <Product>[
  Product(id: 'p1', categoryId: 'c1', name: 'Osh', price: 35000, unit: 'dona'),
  Product(id: 'p2', categoryId: 'c1', name: 'Mastava', price: 22000, unit: 'dona'),
  Product(id: 'p3', categoryId: 'c1', name: "Sho'rva", price: 24000, unit: 'dona'),
  Product(id: 'p4', categoryId: 'c2', name: 'Kotlet', price: 18000, unit: 'dona'),
  Product(id: 'p5', categoryId: 'c2', name: 'Grill tovuq (yarim)', price: 62000, unit: 'dona'),
  Product(id: 'p6', categoryId: 'c2', name: "Go'sht qovurma", price: 48000, unit: 'dona'),
  Product(id: 'p7', categoryId: 'c3', name: 'Achchiq-chuchuk', price: 16000, unit: 'dona'),
  Product(id: 'p8', categoryId: 'c3', name: 'Sezar salat', price: 32000, unit: 'dona'),
  Product(id: 'p9', categoryId: 'c4', name: 'Coca-Cola 0.5', price: 8000, unit: 'dona',
      trackStock: true, stockQty: 24),
  Product(id: 'p10', categoryId: 'c4', name: "Choy (ko'k)", price: 4000, unit: 'dona'),
  Product(id: 'p11', categoryId: 'c4', name: 'Ayron', price: 6000, unit: 'dona'),
  // Tarozili mahsulot — bosilganda gramm so'raladi.
  Product(id: 'p12', categoryId: 'c2', name: "Qo'y go'shti (kg)", price: 140000, unit: 'kg'),
];

// Oshxona holati: bittasi tugagan (kassada «Tugadi» chiqishi kerak).
const _kitchenFlags = <String, dynamic>{
  'p1': {'qty': 12.0, 'stopped': false},
  'p4': {'qty': 3.0, 'stopped': false},
  'p5': {'qty': 0.0, 'stopped': true},
};

const _kitchenBoard = {
  'items': [
    {'product_id': 'p1', 'name': 'Osh', 'qty': 12, 'unit': 'dona', 'status': 'ok',
     'today_produced': 20, 'today_sold': 8, 'par_level': 10, 'need': 0, 'stopped': false,
     'manual_stop': false, 'image_url': null},
    {'product_id': 'p4', 'name': 'Kotlet', 'qty': 3, 'unit': 'dona', 'status': 'low',
     'today_produced': 30, 'today_sold': 27, 'par_level': 20, 'need': 17, 'stopped': false,
     'manual_stop': false, 'image_url': null},
    {'product_id': 'p5', 'name': 'Grill tovuq (yarim)', 'qty': 0, 'unit': 'dona', 'status': 'out',
     'today_produced': 12, 'today_sold': 12, 'par_level': 15, 'need': 15, 'stopped': true,
     'manual_stop': false, 'image_url': null},
  ],
  'summary': {'today_produced': 62, 'today_sold': 47, 'left': 15, 'low': 1, 'stopped': 1,
              'dishes': 3},
  'server_time': '2026-09-02T18:00:00Z',
  'version': 'v1',
};

const _shift = {
  'id': 'sh1',
  'opened_at': '2026-09-02T09:00:00Z',
  'closed_at': null,
  'opening_cash': '200000',
  'net_sales': '1 240 000',
  'orders_count': 18,
  'error_checks_count': 1,
  'error_checks_total': '54000',
  'expenses_total': '85000',
  'by_method': {'cash': '640000', 'uzcard': '380000', 'click': '220000'},
};

// Online yetkazib berish (AIBA TEZKOR / Yandex / Uzum) — soxta ro'yxat.
Map<String, dynamic> _dlv(String id, String no, String ch, String status,
        String stage, {String? courier, bool unlinked = false}) =>
    {
      'id': id, 'external_id': 'ext-$no', 'external_no': no, 'channel': ch,
      'status': status, 'stage': stage, 'customer_name': 'Dilnoza Karimova',
      'phone': '+998 90 123 45 67', 'address': 'Chilonzor 9-kvartal, 12-uy',
      'note': "Achchiq bo'lmasin", 'payment_type': 'click',
      'subtotal': 116000, 'delivery_fee': 10000, 'total': 126000,
      'courier_name': courier, 'courier_phone': courier == null ? null : '+998 90 777 88 99',
      'pos_order_id': status == 'new' ? null : 'po-$no',
      'eta_minutes': 25, 'created_at': '2026-09-02T10:02:00Z',
      'items': [
        {'product_id': 'p1', 'name': 'Osh', 'qty': 2, 'price': 35000, 'total': 70000},
        {'product_id': 'p4', 'name': 'Kotlet', 'qty': 2, 'price': 18000, 'total': 36000},
        {'product_id': unlinked ? null : 'p9', 'name': 'Coca-Cola 0.5',
         'qty': 1, 'price': 8000, 'total': 8000, 'note': 'Sovuq'},
      ],
    };

const _dlvBoard = 'delivery/orders';

// ── Soxta DioClient ─────────────────────────────────────────────────────────

class _FakeDio extends DioClient {
  _FakeDio() : super(_FakeConfig());

  Response<T> _ok<T>(String path, Object? body) => Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: body as T,
      );

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? query, bool noAuth = false, bool noLogout = false}) async {
    if (path.contains(_dlvBoard)) {
      return _ok<T>(path, {
        'items': [
          _dlv('d1', '45914', 'aiba_tezkor', 'new', 'yangi'),
          _dlv('d2', '45915', 'yandex', 'new', 'yangi', unlinked: true),
          _dlv('d3', '45916', 'uzum', 'new', 'yangi'),
          _dlv('d4', '45920', 'aiba_tezkor', 'cooking', 'jarayonda'),
          _dlv('d5', '45921', 'aiba_tezkor', 'ready', 'tayyor'),
          _dlv('d6', '45922', 'yandex', 'picked_up', 'tayyor', courier: 'Sardor'),
          _dlv('d7', '45930', 'aiba_tezkor', 'delivered', 'yetkazilgan', courier: 'Sardor'),
          _dlv('d8', '45933', 'uzum', 'cancelled', 'bekor'),
        ],
        'counts': {'yangi': 3, 'jarayonda': 1, 'tayyor': 2,
                   'yetkazilgan': 1, 'bekor': 1},
      });
    }
    if (path.contains('kitchen/board')) return _ok<T>(path, _kitchenBoard);
    if (path.contains('shifts/current') || path.contains('shift')) return _ok<T>(path, _shift);
    if (path.contains('keldi-ketdi')) return _ok<T>(path, const {'items': []});
    return _ok<T>(path, const <String, dynamic>{});
  }

  @override
  Future<Response<T>> post<T>(String path,
          {Object? data, bool noAuth = false, bool noLogout = false}) async =>
      _ok<T>(path, const <String, dynamic>{'ok': true});

  @override
  Future<List<int>?> fetchBytes(String url) async => null;
}

class _FakeConfig extends AppConfig {
  _FakeConfig() : super(_prefs!, const FlutterSecureStorage());
}

SharedPreferences? _prefs;

// ── Sessiyalar ──────────────────────────────────────────────────────────────

AuthSession _session(String role, String name) => AuthSession(
      accessToken: 'x',
      restaurant: const RestaurantInfo(
        id: 'r1', name: 'Diet Bistro', code: 'DIET',
        legalName: 'DIET BISTRO MCHJ', inn: '301234567',
        receiptHeader: 'Xush kelibsiz!', receiptFooter: 'Rahmat!',
      ),
      terminal: const TerminalInfo(id: 't1', name: 'T1', code: 'DIET-T1'),
      staff: StaffInfo(id: 's1', name: name, role: role),
      shiftId: 'sh1',
    );

class _Session extends SessionNotifier {
  _Session(AuthSession s) : super(_FakeRepo()) {
    state = s;
  }
}

class _FakeRepo implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation i) => Future.value(null);
}

// ── Yordamchilar ────────────────────────────────────────────────────────────

const _phone = Size(390, 844);
const _tablet = Size(1280, 800);

Future<void> _loadFonts() async {
  final inter = File('assets/fonts/Inter-Variable.ttf');
  if (inter.existsSync()) {
    final l = FontLoader('Inter')
      ..addFont(Future.value(ByteData.view(inter.readAsBytesSync().buffer)));
    await l.load();
  }
  final dir = Platform.environment['FLUTTER_MATERIAL_FONTS'] ?? '';
  if (dir.isEmpty) return;
  final iconFile = File('$dir/MaterialIcons-Regular.otf');
  if (iconFile.existsSync()) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(iconFile.readAsBytesSync().buffer)));
    await icons.load();
  }
}

List<Override> _base({String role = 'cashier', String name = 'Kassir Vali'}) => [
      sharedPreferencesProvider.overrideWithValue(_prefs!),
      dioClientProvider.overrideWithValue(_FakeDio()),
      categoriesProvider.overrideWith((ref) async => _cats),
      productsProvider.overrideWith((ref) async => _prods),
      kitchenFlagsProvider.overrideWith((ref) async => _kitchenFlags),
      sessionProvider.overrideWith((ref) => _Session(_session(role, name))),
      // OCHIQ smena — bo'lmasa kassa «Smena ochilmagan» ekranini ko'rsatadi
      // va savdo ekranini ko'rib bo'lmaydi.
      currentShiftProvider.overrideWith((ref) async => _openShift),
    ];

/// Ochiq smena (mock) — kassir ish kunining o'rtasidagi holat.
final _openShift = Shift(
  id: 'sh1',
  status: 'open',
  openedAt: DateTime(2026, 9, 2, 9, 0),
  openingCash: 200000,
  totalCash: 640000,
  totalCard: 380000,
  totalSales: 1240000,
  ordersCount: 18,
  errorChecksCount: 1,
  errorChecksTotal: 54000,
  clickTotal: 220000,
  expensesTotal: 85000,
);

Future<void> _shot(
  WidgetTester tester,
  String name,
  Size size,
  Widget child, {
  List<Override> overrides = const [],
  Future<void> Function(WidgetTester t)? after,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: child,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 500));
  if (after != null) await after(tester);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
}

void main() {
  // SOAT QOTIRILADI: ekranlardagi «N daqiqa oldin», «4 soat 30 daqiqa»,
  // «yaratilgan 13:48» matnlari shu vaqtdan hisoblanadi. Aks holda golden
  // har daqiqada boshqacha chiqib sinov hech qachon o'tmasdi.
  setUpAll(() { AppClock.now = () => DateTime(2026, 9, 2, 13, 30); });
  tearDownAll(() { AppClock.now = DateTime.now; });

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'terminal_code': 'DIET-T1',
      'base_url': 'https://next.aiba.uz',
      'setup_done': true,
    });
    // connectivity_plus va secure_storage — test muhitida plagin yo'q,
    // soxta javob beramiz (aks holda MissingPluginException testni yiqitadi).
    const conn = MethodChannel('dev.fluttercommunity.plus/connectivity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(conn, (c) async => ['wifi']);
    const connEvents = MethodChannel('dev.fluttercommunity.plus/connectivity_status');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connEvents, (c) async => null);
    const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, (c) async => c.method == 'readAll' ? <String, String>{} : null);
    const pathProv = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProv, (c) async => '/tmp/aiba-pos-test');
    _prefs = await SharedPreferences.getInstance();
    await _loadFonts();
  });

  testWidgets('01 login — PIN ekrani (planshet)', (t) async {
    await _shot(t, '01_login_tablet', _tablet, const LoginScreen(), overrides: [
      sharedPreferencesProvider.overrideWithValue(_prefs!),
      dioClientProvider.overrideWithValue(_FakeDio()),
    ]);
  });

  testWidgets('02 login — PIN terilgan holat', (t) async {
    await _shot(t, '02_login_pin', _tablet, const LoginScreen(), overrides: [
      sharedPreferencesProvider.overrideWithValue(_prefs!),
      dioClientProvider.overrideWithValue(_FakeDio()),
    ], after: (t) async {
      for (final d in ['1', '2', '3', '4']) {
        final b = find.text(d);
        if (b.evaluate().isNotEmpty) {
          await t.tap(b.first);
          await t.pump(const Duration(milliseconds: 80));
        }
      }
    });
  });

  testWidgets('03 kassir — savdo ekrani (planshet)', (t) async {
    await _shot(t, '03_kassir_tablet', _tablet, const HomeShell(),
        overrides: _base());
  });

  testWidgets("04 kassir — savatga 3 taom qo'shilgan", (t) async {
    await _shot(t, '04_kassir_savat', _tablet, const HomeShell(),
        overrides: _base(), after: (t) async {
      for (final nm in ['Osh', 'Mastava', 'Coca-Cola 0.5']) {
        final f = find.text(nm);
        if (f.evaluate().isNotEmpty) {
          await t.tap(f.first);
          await t.pump(const Duration(milliseconds: 150));
        }
      }
    });
  });

  testWidgets("05 kassir — telefon o'lchami", (t) async {
    await _shot(t, '05_kassir_phone', _phone, const HomeShell(),
        overrides: _base());
  });

  testWidgets("06 menejer — savdo ekrani (qo'shimcha tablar)", (t) async {
    await _shot(t, '06_menejer_tablet', _tablet, const HomeShell(),
        overrides: _base(role: 'manager', name: 'Menejer Habib'));
  });

  testWidgets('07 menejer — ish vaqti / smena', (t) async {
    await _shot(t, '07_menejer_smena', _tablet,
        const Scaffold(body: ShiftScreen()),
        overrides: _base(role: 'manager', name: 'Menejer Habib'));
  });

  testWidgets('08 oshpaz — oshxona ekrani (planshet)', (t) async {
    await _shot(t, '08_oshpaz_tablet', _tablet, const KitchenScreen(),
        overrides: _base(role: 'kitchen', name: 'Oshpaz Ali'));
  });

  // Oshxona ekrani PLANSHET uchun qurilgan (Figma). Kichik planshet enida
  // ham to'g'ri chiqishini tekshiramiz. TELEFON eni (390px) hali
  // qo'llanmaydi — savatcha 320px qat'iy, alohida joylashuv kerak.
  testWidgets('10 online yetkazib berish — Kanban (planshet)', (t) async {
    await _shot(t, '10_delivery_kanban', _tablet,
        const Scaffold(body: DeliveryScreen()),
        overrides: _base(role: 'manager', name: 'Menejer Habib'));
  });

  testWidgets('11 online yetkazib berish — buyurtma kartasi', (t) async {
    await _shot(t, '11_delivery_card', _tablet,
        const Scaffold(body: DeliveryScreen()),
        overrides: _base(role: 'manager', name: 'Menejer Habib'),
        after: (t) async {
      final f = find.textContaining('45914');
      if (f.evaluate().isNotEmpty) {
        await t.tap(f.first);
        await t.pump(const Duration(milliseconds: 400));
      }
    });
  });

  testWidgets('09 oshpaz — kichik planshet', (t) async {
    await _shot(t, '09_oshpaz_small_tablet', const Size(834, 1112),
        const KitchenScreen(),
        overrides: _base(role: 'kitchen', name: 'Oshpaz Ali'));
  });
}

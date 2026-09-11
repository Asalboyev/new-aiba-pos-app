import 'package:aiba_pos_terminal/core/config/app_config.dart';
import 'package:aiba_pos_terminal/core/network/dio_client.dart';
import 'package:aiba_pos_terminal/core/providers/core_providers.dart';
import 'package:aiba_pos_terminal/features/kitchen/tv_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Oshxona TV oynasi — televizorga chiqadigan ko'rinish. Serverdan
/// `/kitchen/board` keladi, ekran uch ustunga bo'linadi.
class _FakeDio extends DioClient {
  _FakeDio(this._board, AppConfig cfg) : super(cfg);
  final Map<String, dynamic> _board;

  @override
  Future<Response<T>> get<T>(String path,
          {Map<String, dynamic>? query,
          bool noAuth = false,
          bool noLogout = false}) async =>
      Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: _board as T,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Map<String, dynamic> board() => {
        'version': 'v1',
        'items': [
          {'product_id': '1', 'name': 'Osh', 'unit': 'dona', 'qty': 0, 'status': 'out', 'stopped': false},
          {'product_id': '2', 'name': 'Lagmon', 'unit': 'dona', 'qty': 3, 'status': 'low', 'stopped': false},
          {'product_id': '3', 'name': 'Manti', 'unit': 'dona', 'qty': 20, 'status': 'ok', 'stopped': false},
        ],
      };

  testWidgets('TV ekrani uch ustunni va taomlarni ko\'rsatadi', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cfg = AppConfig(prefs, const FlutterSecureStorage());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dioClientProvider.overrideWithValue(_FakeDio(board(), cfg)),
      ],
      child: const MaterialApp(home: KitchenTvScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Tugadi'), findsOneWidget);
    expect(find.text('Kam qoldi'), findsOneWidget);
    expect(find.text('Yetarli'), findsOneWidget);
    expect(find.text('Osh'), findsOneWidget);
    expect(find.text('Lagmon'), findsOneWidget);
    expect(find.text('Manti'), findsOneWidget);
    expect(find.text('3 porsiya'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aiba_pos_terminal/core/providers/core_providers.dart';
import 'package:aiba_pos_terminal/features/orders/presentation/widgets/qr_pay_dialog.dart';

/// QR to'lov oynasi klaviaturasi: F1 — Click Pass, F2 — Uzum.
/// Kassir mishkasiz ishlaydi, shuning uchun klavisha belgilari plitkada
/// KO'RINIB turishi ham tekshiriladi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> open(WidgetTester tester, {bool scanMode = false}) async {
    // Kassa ekrani — planshet o'lchami. 800x600 da oyna sig'maydi va
    // skaner maydoni chizilmay qoladi (testda yolg'on «yo'q» beradi).
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => QrPayDialog.show(context, 45600, scanMode: scanMode),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Plitka tanlanganmi — foni ko'k bo'lsa tanlangan.
  bool selected(WidgetTester tester, String label) {
    final c = tester
        .widgetList<Container>(
          find.ancestor(of: find.text(label), matching: find.byType(Container)),
        )
        .first;
    return (c.decoration as BoxDecoration).color == const Color(0xFF2277EA);
  }

  testWidgets('plitkalarda klavisha belgilari ko\'rinadi', (tester) async {
    await open(tester);
    expect(find.text('F1 · Click'), findsOneWidget);
    expect(find.text('F2 · Uzum'), findsOneWidget);
  });

  testWidgets('F2 — Uzum, F1 — Click Pass', (tester) async {
    await open(tester);
    expect(selected(tester, 'F1 · Click'), isTrue, reason: 'boshida Click');

    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(selected(tester, 'F2 · Uzum'), isTrue);
    expect(selected(tester, 'F1 · Click'), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(selected(tester, 'F1 · Click'), isTrue);
    expect(selected(tester, 'F2 · Uzum'), isFalse);
  });

  testWidgets('skaner rejimida Uzumga o\'tilsa skaner maydoni yashirinadi',
      (tester) async {
    await open(tester, scanMode: true);
    // Click: summa maydoni + skaner maydoni; Uzum: faqat summa maydoni.
    final n = tester.widgetList<TextField>(find.byType(TextField)).length;
    expect(n, 2, reason: 'Click Pass — skaner maydoni ochiq');

    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(tester.widgetList<TextField>(find.byType(TextField)).length, 1,
        reason: 'Uzum — skaner yo\'q, qo\'lda tasdiqlanadi');

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(tester.widgetList<TextField>(find.byType(TextField)).length, 2);
  });

  testWidgets('yordam qatorida ham F1/F2 yozilgan', (tester) async {
    await open(tester);
    expect(find.textContaining('F1 Click'), findsOneWidget);
    expect(find.textContaining('F2 Uzum'), findsOneWidget);
  });

  testWidgets('Esc — oyna yopiladi', (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(QrPayDialog), findsNothing);
  });
}

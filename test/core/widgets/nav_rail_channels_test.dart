import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiba_pos_terminal/core/widgets/pos_chrome.dart';

/// Chap menyu: Mahsulotlar ostida har tizim ALOHIDA bo'lim bo'lishi kerak
/// (AIBA TEZKOR → Uzum Tezkor → Yandex) — buyurtmachi aralashtirmasin.
void main() {
  Future<void> pump(WidgetTester t, Widget rail) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Row(children: [rail]))));
  }

  testWidgets('kanallar Mahsulotlar ostida shu tartibda chiqadi', (t) async {
    await pump(
      t,
      PosNavRail(
        selectedIndex: 2,
        onSelect: (_) {},
        onSettings: () {},
        showShift: false,
        showSettings: false,
        channels: const [
          ('aiba_tezkor', 'AIBA\nTEZKOR', 1),
          ('uzum', 'Uzum\nTezkor', 0),
          ('yandex', 'Yandex', 0),
        ],
        selectedChannel: 'aiba_tezkor',
        onChannel: (_) {},
      ),
    );
    // Eski yagona bo'lim o'rniga uchta kanal.
    expect(find.textContaining('Yetkazib'), findsNothing);
    double y(String s) => t.getTopLeft(find.text(s)).dy;
    expect(y('Mahsulotlar') < y('AIBA\nTEZKOR'), isTrue);
    expect(y('AIBA\nTEZKOR') < y('Uzum\nTezkor'), isTrue);
    expect(y('Uzum\nTezkor') < y('Yandex'), isTrue);
    // Tasdiq kutayotgan buyurtma soni yonida ko'rinadi.
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('kanal bosilsa kalit qaytadi', (t) async {
    String? got;
    await pump(
      t,
      PosNavRail(
        selectedIndex: 2,
        onSelect: (_) {},
        onSettings: () {},
        showShift: false,
        showSettings: false,
        channels: const [
          ('aiba_tezkor', 'AIBA\nTEZKOR', 0),
          ('uzum', 'Uzum\nTezkor', 0),
          ('yandex', 'Yandex', 0),
        ],
        selectedChannel: '',
        onChannel: (c) => got = c,
      ),
    );
    await t.tap(find.text('Uzum\nTezkor'));
    expect(got, 'uzum');
  });

  testWidgets('buyurtmachida Mahsulotlar bo\'limi yashiriladi', (t) async {
    await pump(
      t,
      PosNavRail(
        selectedIndex: 2,
        onSelect: (_) {},
        onSettings: () {},
        showShift: false,
        showSettings: false,
        showProducts: false,
        channels: const [
          ('aiba_tezkor', 'AIBA\nTEZKOR', 0),
          ('uzum', 'Uzum\nTezkor', 0),
          ('yandex', 'Yandex', 0),
        ],
        selectedChannel: 'aiba_tezkor',
        onChannel: (_) {},
      ),
    );
    expect(find.text('Mahsulotlar'), findsNothing);
    expect(find.text('AIBA\nTEZKOR'), findsOneWidget);
    expect(find.text('Uzum\nTezkor'), findsOneWidget);
    expect(find.text('Yandex'), findsOneWidget);
  });

  testWidgets('kanallar berilmasa bitta «Online buyurtmalar» qoladi', (t) async {
    await pump(
      t,
      PosNavRail(
        selectedIndex: 0,
        onSelect: (_) {},
        onSettings: () {},
        showShift: false,
        showSettings: false,
      ),
    );
    expect(find.text('Online\nbuyurtmalar'), findsOneWidget);
  });
}

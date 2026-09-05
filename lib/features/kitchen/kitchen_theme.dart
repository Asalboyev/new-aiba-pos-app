// Oshxona ekrani uchun OQ / QORA fon (Figma «Kitchen» — light va dark variant).
//
// Kassa (savdo) ekrani doim qora — bu almashtirgich FAQAT oshxona ekraniga
// ta'sir qiladi. Tanlov SharedPreferences'da (`kitchen_light`) saqlanadi:
// oshpaz bir marta tanlaydi, keyingi kirishlarda ham shu fon qoladi.
//
// Ranglar `ThemeExtension` orqali beriladi — har widget `KitchenPalette.of(context)`
// bilan oladi, shunda kartochka/chip/savatcha ikkala fonda ham to'g'ri ko'rinadi.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/core_providers.dart';
import '../../core/widgets/pos_chrome.dart';

class KitchenPalette extends ThemeExtension<KitchenPalette> {
  const KitchenPalette({
    required this.isLight,
    required this.bg,
    required this.panel,
    required this.card,
    required this.cardBorder,
    required this.iconChip,
    required this.field,
    required this.muted,
    required this.label,
    required this.blue,
    required this.green,
    required this.red,
    required this.orange,
  });

  final bool isLight;
  final Color bg;
  final Color panel;
  final Color card;
  final Color cardBorder;
  final Color iconChip;
  final Color field;
  final Color muted;
  final Color label;
  final Color blue;
  final Color green;
  final Color red;
  final Color orange;

  /// Qora fon — kassa bilan bir xil (PosColors).
  static const dark = KitchenPalette(
    isLight: false,
    bg: PosColors.bg,
    panel: PosColors.panel,
    card: PosColors.card,
    cardBorder: PosColors.cardBorder,
    iconChip: PosColors.iconChip,
    field: PosColors.field,
    muted: PosColors.muted,
    label: PosColors.label,
    blue: PosColors.blue,
    green: PosColors.green,
    red: PosColors.red,
    orange: Color(0xFFE08A12),
  );

  /// Oq fon — Figma light: oq panel, och kulrang kartochkalar, to'q matn.
  static const light = KitchenPalette(
    isLight: true,
    bg: Color(0xFFF3F4F6),
    panel: Color(0xFFFFFFFF),
    card: Color(0xFFF3F4F6),
    cardBorder: Color(0xFFE5E7EB),
    iconChip: Color(0xFFE7E9EE),
    field: Color(0xFFEEF0F3),
    muted: Color(0xFF6B7280),
    label: Color(0xFF111827),
    blue: PosColors.blue,
    green: Color(0xFF22A559),
    red: PosColors.red,
    orange: Color(0xFFD97706),
  );

  static KitchenPalette of(BuildContext context) =>
      Theme.of(context).extension<KitchenPalette>() ?? dark;

  @override
  KitchenPalette copyWith({bool? isLight}) => this;

  @override
  KitchenPalette lerp(ThemeExtension<KitchenPalette>? other, double t) =>
      t < .5 ? this : (other as KitchenPalette? ?? this);
}

/// `true` = oq fon. Tanlov SharedPreferences'da.
class KitchenThemeNotifier extends StateNotifier<bool> {
  KitchenThemeNotifier(this._prefs) : super(_prefs.getBool(_key) ?? false);

  static const _key = 'kitchen_light';
  final SharedPreferences _prefs;

  Future<void> set(bool light) async {
    state = light;
    await _prefs.setBool(_key, light);
  }

  Future<void> toggle() => set(!state);
}

final kitchenLightProvider =
    StateNotifierProvider<KitchenThemeNotifier, bool>((ref) {
  return KitchenThemeNotifier(ref.watch(sharedPreferencesProvider));
});

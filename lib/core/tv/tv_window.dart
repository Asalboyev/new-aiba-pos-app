import 'dart:async';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// OSHXONA TELEVIZORI — ilovaning ikkinchi nusxasi.
///
/// Muammo: TV ko'rinishi serverdagi HTML sahifa edi va uni televizorda
/// ochish uchun brauzerga `next.aiba.uz/<32 belgili kalit>/pos-tv` deb
/// qo'lda yozish kerak edi. Televizor pulti bilan bu — eng qiyin qadam.
///
/// Yechim: monoblokka HDMI bilan televizor ulansa, ilova O'ZINI ikkinchi
/// nusxada `--tv` bayrog'i bilan ishga tushiradi va o'sha nusxa televizor
/// ekraniga to'liq yoyiladi. Brauzer, havola, kalit — hech biri kerak emas.
/// HDMI uzilsa TV nusxasi o'zini yopadi.
///
/// Nega ALOHIDA JARAYON (bitta jarayonda ikki oyna emas): Flutter'da
/// Windows uchun ko'p oynali rejim hali beqaror. Ikkinchi nusxa esa oddiy
/// exe — ishonchli, va u yiqilsa ham kassa oynasiga ta'sir qilmaydi.
class TvWindow {
  TvWindow._();

  /// Ikkinchi nusxa shu bayroq bilan ishga tushadi.
  static const flag = '--tv';

  /// Faqat Windows/macOS desktopida (planshetda ikkinchi ekran bo'lmaydi).
  static bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS);

  // ── TV NUSXASI ────────────────────────────────────────────────────────
  /// TV nusxasining oynasini televizor ekraniga to'liq yoyadi.
  static Future<bool> setUpTvWindow() async {
    await windowManager.ensureInitialized();
    final display = await _external();
    // IKKINCHI EKRAN YO'Q — umuman oyna OCHMAYMIZ va darhol chiqamiz.
    //
    // Bu holat sinovda topildi: oldin oyna baribir ochilib, monoblokning
    // O'Z ekranini to'sib turardi (kuzatuv uni 5 soniyadan keyingina
    // yopardi). Kassa ekranini bir soniyaga ham to'sish mumkin emas.
    if (display == null) return false;
    await windowManager.waitUntilReadyToShow(null, () async {
      await windowManager.setTitle('AIBA POS — Oshxona TV');
      // Ramka va sarlavha yo'q: televizorda faqat taomlar ko'rinsin.
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      final p = display.visiblePosition;
      await windowManager.setBounds(Rect.fromLTWH(
        p?.dx ?? 0,
        p?.dy ?? 0,
        display.size.width,
        display.size.height,
      ));
      await windowManager.setFullScreen(true);
      await windowManager.show();
    });
    return true;
  }

  /// TV nusxasi: HDMI uzilsa o'zini yopadi (monoblok ekranida yolg'iz
  /// oyna qolib ketmasin).
  static void watchUnplug() {
    Timer.periodic(const Duration(seconds: 5), (_) async {
      if (await _external() == null) exit(0);
    });
  }

  // ── ASOSIY NUSXA ──────────────────────────────────────────────────────
  /// Ikkinchi ekran paydo bo'lishini kuzatadi va TV nusxasini ishga
  /// tushiradi.
  static bool _watching = false;

  static void watchAndLaunch() {
    // Sessiya tiklanganda ham, login'dan keyin ham chaqiriladi — ikkita
    // taymer ochilib qolmasin.
    if (!supported || _watching) return;
    _watching = true;
    Timer.periodic(const Duration(seconds: 5), (_) => _tick());
    unawaited(_tick());
  }

  static Process? _child;

  static Future<void> _tick() async {
    try {
      final has = await _external() != null;
      if (has && _child == null) {
        final p = await Process.start(
          Platform.resolvedExecutable,
          [flag],
          mode: ProcessStartMode.detachedWithStdio,
        );
        _child = p;
        unawaited(p.exitCode.then((_) => _child = null));
      }
    } catch (_) {
      // Ekran ro'yxatini o'qib bo'lmadi yoki jarayon ochilmadi — keyingi
      // urinishda qayta ko'riladi. Kassa ishiga ta'sir qilmaydi.
    }
  }

  /// Asosiy BO'LMAGAN (ya'ni HDMI bilan ulangan) birinchi ekran.
  static Future<Display?> _external() async {
    final all = await screenRetriever.getAllDisplays();
    if (all.length < 2) return null;
    final primary = await screenRetriever.getPrimaryDisplay();
    for (final d in all) {
      if (d.id != primary.id) return d;
    }
    return null;
  }
}

import 'dart:io';

import 'package:flutter/services.dart';

/// QABUL QILINMAGAN BUYURTMA SIGNALI.
///
/// `SystemSound.play(SystemSoundType.alert)` desktopda AMALDA JIM: macOS va
/// Windows'da Flutter uni hech narsaga ulamaydi (u telefonlar uchun). Shu
/// sababli buyurtmachi signalni eshitmasdi — agregator esa tasdiqlanmagan
/// buyurtmani bir necha daqiqada bekor qiladi.
///
/// Qo'shimcha audio paket QO'SHILMADI (kassa Windows'da build va imzo
/// zanjirini og'irlashtiradi) — operatsion tizimning o'z ovozi chaqiriladi.
Future<void> playAlarm() async {
  // Testlarda jarayon ochilmasin (widget testlari sekinlashardi).
  if (Platform.environment.containsKey('FLUTTER_TEST')) return;
  try {
    if (Platform.isMacOS) {
      await Process.run(
          '/usr/bin/afplay', ['/System/Library/Sounds/Submarine.aiff']);
      return;
    }
    if (Platform.isWindows) {
      // Ikki ohangli signal — kassa shovqinida ham eshitiladi.
      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '[console]::beep(1050,400);[console]::beep(1450,400)',
      ]);
      return;
    }
    if (Platform.isLinux) {
      await Process.run('paplay', ['/usr/share/sounds/freedesktop/stereo/bell.oga']);
      return;
    }
  } catch (_) {
    // Ovoz chiqmasa ish to'xtamaydi — ekranda son va rang baribir bor.
  }
  await SystemSound.play(SystemSoundType.alert);
}

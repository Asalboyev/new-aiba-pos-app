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
///
/// Ovoz ATAYIN «e'tibor tortadigan»: bitta yumshoq «ding» kassa shovqinida
/// yo'qolib ketardi, shuning uchun UCH MARTA takrorlanadigan, tovushi
/// KO'TARILIB boradigan naqsh ishlatiladi (qo'ng'iroqqa o'xshaydi) —
/// odam uni fon shovqinidan ajratadi.
Future<void> playAlarm() async {
  // Testlarda jarayon ochilmasin (widget testlari sekinlashardi).
  if (Platform.environment.containsKey('FLUTTER_TEST')) return;
  try {
    if (Platform.isMacOS) {
      // Sosumi — keskin, tanish tovush; uch marta ketma-ket.
      for (var i = 0; i < 3; i++) {
        await Process.run('/usr/bin/afplay',
            ['-v', '3', '/System/Library/Sounds/Sosumi.aiff']);
      }
      return;
    }
    if (Platform.isWindows) {
      // Ko'tariluvchi uch nota, ikki marta — kassa shovqinida ham eshitiladi.
      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '1..2 | ForEach-Object { '
            '[console]::beep(880,180); [console]::beep(1175,180); '
            '[console]::beep(1568,260); Start-Sleep -Milliseconds 120 }',
      ]);
      return;
    }
    if (Platform.isLinux) {
      for (var i = 0; i < 3; i++) {
        await Process.run('paplay',
            ['/usr/share/sounds/freedesktop/stereo/message-new-instant.oga']);
      }
      return;
    }
  } catch (_) {
    // Ovoz chiqmasa ish to'xtamaydi — ekranda son va rang baribir bor.
  }
  await SystemSound.play(SystemSoundType.alert);
}

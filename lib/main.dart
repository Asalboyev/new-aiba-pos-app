import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io' show Platform, exit;

import 'core/lan/lan_service.dart';
import 'core/tv/tv_window.dart';
import 'core/network/dio_client.dart' show loadBundledRoots;
import 'core/providers/core_providers.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/providers/auth_providers.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/home/presentation/home_shell.dart';
import 'features/kitchen/kitchen_screen.dart';
import 'features/kitchen/tv_screen.dart';
import 'features/settings/presentation/settings_screen.dart';

// Faqat ishlab chiqish/vizual tekshiruv uchun: login'ni chetlab o'tib to'g'ridan
// -to'g'ri qobiqni ko'rsatadi (--dart-define=DEBUG_HOME=true). Prod build'da
// o'chirilgan (default false).
const _kDebugHome = bool.fromEnvironment('DEBUG_HOME');
const _kDebugIndex = int.fromEnvironment('DEBUG_INDEX');

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Let's Encrypt ildizlari — eski Windows kassalarда HTTPS ishlashi uchun.
  await loadBundledRoots();
  final prefs = await SharedPreferences.getInstance();

  // ── OSHXONA TELEVIZORI ──────────────────────────────────────────────
  // Monoblokka HDMI bilan televizor ulanganda ilova O'ZINI shu bayroq
  // bilan ikkinchi marta ishga tushiradi (TvWindow.watchAndLaunch). Bu
  // nusxa televizor ekraniga to'liq yoyiladi va FAQAT ko'rsatadi:
  // lokal baza (drift), sinxron va LAN server ochilmaydi — ikki jarayon
  // bitta sqlite faylini talashmasin.
  if (args.contains(TvWindow.flag)) {
    // Ikkinchi ekran topilmasa — oyna ochmasdan chiqamiz (kassa ekranini
    // to'sib qo'ymaslik uchun).
    if (!await TvWindow.setUpTvWindow()) exit(0);
    TvWindow.watchUnplug();
    runApp(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const AibaTvApp(),
      ),
    );
    return;
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const AibaPosApp(),
    ),
  );
}

/// Televizor nusxasi — bitta ekran, boshqaruv yo'q.
class AibaTvApp extends StatelessWidget {
  const AibaTvApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: const KitchenTvScreen(),
      );
}

class AibaPosApp extends ConsumerStatefulWidget {
  const AibaPosApp({super.key});

  @override
  ConsumerState<AibaPosApp> createState() => _AibaPosAppState();
}

class _AibaPosAppState extends ConsumerState<AibaPosApp> {
  bool _restored = false;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // Restore a persisted session so the POS opens straight into the shell
    // (and works offline) after the first login.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Debug-home vizual tekshiruvda secure_storage (keychain) o'qishni
      // o'tkazib yuboramiz — aks holda macOS keychain oynasi appni to'sadi.
      if (!_kDebugHome) {
        await ref.read(sessionProvider.notifier).restore();
      }
      if (mounted) setState(() => _restored = true);
      // OSHXONA TELEVIZORI — HDMI ulansa ilova o'zining TV nusxasini
      // televizorda to'liq ekran qilib ochadi. Kuzatuv sessiya
      // tiklangandan keyin boshlanadi: TV nusxasi ham shu sessiya bilan
      // ishlaydi, login oynasi televizorda chiqib qolmasin.
      if (mounted && ref.read(sessionProvider) != null) {
        TvWindow.watchAndLaunch();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    // Sozlamalar saqlanganда qayta baholaymiz (setup → login).
    ref.watch(configVersionProvider);
    final configured =
        ref.read(appConfigProvider).terminalCode.trim().isNotEmpty;

    // Token expired on the server (401) — drop the cached session so the app
    // routes back to the login screen instead of queueing forever "offline".
    // LOKAL SERVER — kassa kompyuterida (Windows) ochiladi: internet
    // uzilganda oshxona planshet va TV shu kompyuterdan ishlashda davom
    // etadi. Oshpaz planshetida ochilmaydi (u mijoz, server emas).
    ref.listen(sessionProvider, (prev, next) {
      // Login'dan keyin TV kuzatuvini yoqamiz (ilova ochilganda sessiya
      // hali tiklanmagan bo'lishi mumkin).
      if (prev == null && next != null) TvWindow.watchAndLaunch();
      if (!Platform.isWindows) return;
      final lan = ref.read(lanServiceProvider);
      const clients = {'kitchen', 'zakazchik'};
      if (next != null && !clients.contains(next.staff.role)) {
        lan.start();
      } else if (next == null) {
        lan.stop();
      }
    });

    ref.listen<int>(sessionExpiredSignalProvider, (prev, next) {
      if (ref.read(sessionProvider) == null) return;
      ref.read(sessionProvider.notifier).logout();
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Sessiya muddati tugadi — qaytadan kiring. '
              'Saqlangan savdolar login\'dan keyin avtomatik yuboriladi.'),
          duration: Duration(seconds: 6),
        ),
      );
    });

    return MaterialApp(
      title: 'AIBA POS',
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      // POS terminal har doim Figma qorong'i mavzusida (qurilma temasiga
      // bog'liq emas) — barcha ekranlar bir xil ko'rinadi.
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: _kDebugHome
          ? HomeShell(initialIndex: _kDebugIndex)
          : (!_restored
              ? const _Splash()
              // Oshpaz o'z paroli bilan kirsa — Kitchen ekrani (kassa emas):
              // tayyorlagan ovqatlarini kiritadi, POS/TV darhol ko'radi.
              : session != null
                  ? (session.staff.role == 'kitchen'
                      ? const KitchenScreen()
                      // BUYURTMACHI — oshpaz kabi alohida ish o'rni: faqat
                      // onlayn buyurtmalar ekrani (kassa, ombor, hisobot
                      // yopiq). Yangi buyurtma qabul qilinmasa ovoz beradi.
                      : session.staff.role == 'zakazchik'
                          ? const HomeShell(initialIndex: 2)
                          : const HomeShell())
                  // Birinchi o'rnatish: terminal sozlanmagan bo'lsa — setup
                  // (Sozlamalar). Save'dan keyin login'ga o'tadi.
                  : (configured
                      ? const LoginScreen()
                      : const SettingsScreen())),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF06090B),
      body: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
              strokeWidth: 3, color: Color(0xFF2277EA)),
        ),
      ),
    );
  }
}

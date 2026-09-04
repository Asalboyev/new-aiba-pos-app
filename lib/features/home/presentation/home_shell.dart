import '../../delivery/data/delivery_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/onscreen_keyboard.dart';
import '../../../core/widgets/pos_chrome.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../delivery/presentation/screens/delivery_screen.dart';
import '../../orders/domain/entities/payment_method.dart';
import '../../orders/presentation/providers/cart_provider.dart';
import '../../orders/presentation/providers/sync_service.dart';
import '../../orders/presentation/screens/pos_sale_screen.dart';
import '../../orders/presentation/widgets/error_check_dialog.dart';
import '../../orders/presentation/widgets/keldi_ketdi_dialog.dart';
import '../../orders/presentation/widgets/payment_dialog.dart';
import '../../orders/presentation/widgets/qr_pay_dialog.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../shift/presentation/providers/shift_providers.dart';
import '../../shift/presentation/screens/shift_screen.dart';

/// Login'dan keyingi asosiy qobiq — Figma "Pos Design": suv foni, chap
/// navigatsiya paneli (Mahsulotlar / Ish vaqti / Yetkazib berish, pastda
/// Sozlamalar), o'ng yuqorida profil avatari. Kontent — tanlangan ekran.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _index = widget.initialIndex;

  /// Kassir faqat savdo qiladi: Ish vaqti bo'limi ko'rinmaydi, smena bilan
  /// bog'liq hamma ish (ochish/yopish/hisobot) menejerda.
  bool get _isManager =>
      (ref.read(sessionProvider)?.staff.role ?? '') != 'cashier';

  /// F10 — bo'limlar orasida aylanish: Mahsulotlar → Ish vaqti →
  /// Yetkazib berish → Sozlamalar → Mahsulotlar. Kassir mishka ishlatmaydi,
  /// shuning uchun navigatsiya ham klaviaturada bo'lishi shart.
  bool _onNavKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (event.logicalKey != LogicalKeyboardKey.f10) return false;
    // Mahsulotlar ekranida savat BO'SH bo'lmasa F10 — Click Pass (tezkor QR
    // to'lov, pos_sale_screen ushlaydi); bo'limlar aylanishi savat bo'shida.
    if (_index == 0 && ref.read(cartProvider).items.isNotEmpty) return false;
    // Kassirda Ish vaqti (1) va Sozlamalar (3) bo'limlari yo'q — aylanishda
    // o'tkazib yuboriladi.
    final order = _isManager ? const [0, 1, 2, 3] : const [0, 2];
    final i = order.indexOf(_index);
    final next = order[(i < 0 ? 0 : i + 1) % order.length];
    setState(() => _index = next);
    const names = ['Mahsulotlar', 'Ish vaqti', 'Yetkazib berish', 'Sozlamalar'];
    final m = ScaffoldMessenger.maybeOf(context);
    m
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(names[next],
            style: const TextStyle(fontWeight: FontWeight.w600)),
        duration: const Duration(milliseconds: 1000),
        behavior: SnackBarBehavior.floating,
        backgroundColor: PosColors.card,
      ));
    return true;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onNavKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(sessionProvider) != null) {
        ref.read(syncServiceProvider.notifier).syncAll();
      }
      // Vizual tekshiruv: --dart-define=DEBUG_DIALOG=payment.
      const dbg = String.fromEnvironment('DEBUG_DIALOG');
      if (!mounted) return;
      switch (dbg) {
        case 'payment':
          PaymentDialog.show(context, 384000, initialMethod: PaymentMethod.card);
        case 'keldi':
          KeldiKetdiDialog.show(context);
        case 'error':
          ErrorCheckDialog.show(context);
        case 'qr':
          QrPayDialog.show(context, 15000);
        case 'keyboard':
          showModalBottomSheet<void>(
            context: context,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.transparent,
            isScrollControlled: true,
            constraints: const BoxConstraints(maxWidth: double.infinity),
            builder: (_) => OnScreenKeyboard(
              onChar: (_) {},
              onBackspace: () {},
              onClear: () {},
              onEnter: () => Navigator.of(context).pop(),
            ),
          );
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onNavKey);
    super.dispose();
  }

  Future<void> _logout() async {
    // Chiqishda hech qanday oyna chiqmaydi — «Smena hali ochiq» ogohlantirishi
    // ishni sekinlashtirardi. Smena menejerniki: kassir/oshpaz shunchaki
    // chiqib ketadi (smena ochiq qoladi, qayta kirsa davom etadi). Smenani
    // yopish menejerda «Ish vaqti» bo'limida alohida.
    if (!mounted) return;
    await ref.read(sessionProvider.notifier).logout();
  }

  Widget _content() {
    // Kassir Ish vaqti (1) va Sozlamalar (3) bo'limlariga kira olmaydi —
    // tanlansa savdoga qaytadi.
    final idx = (!_isManager && (_index == 1 || _index == 3)) ? 0 : _index;
    switch (idx) {
      case 1:
        return const ShiftScreen();
      case 3:
        return const SettingsScreen(embedded: true);
      case 2:
        // YETKAZIB BERISH smena bilan BLOKLANMAYDI.
        //
        // Avval savdo bilan bir xil qo'riqchi ostida edi va shu muammoni
        // berardi: smena OCHIQ turgan holda ham «Smena ochilmagan» chiqib
        // kassir online buyurtmalarni ko'rmay qolardi — smena holatini
        // so'rash bir marta yiqilsa (tarmoq/timeout) `error` shoxi
        // ishlagan.
        //
        // Mantiqan ham to'g'ri: ro'yxatni KO'RISH savdo yaratish emas.
        // Buyurtmalar kelib turadi va kassir ularni ko'rishi kerak.
        // Tasdiqlashda esa chek serverda yoziladi va server smenani
        // o'zi topadi/ochadi (`resolve_or_open_shift`) — ya'ni savdo
        // smenasiz qolmaydi.
        return const DeliveryScreen();
      default:
        // SAVDO smena ochilmasa bloklanadi — aks holda sotuv smenasiz
        // yaratilib Z-hisobotdan tashqarida qoladi.
        final shiftAsync = ref.watch(currentShiftProvider);
        // Kassir smenani ocha olmaydi — menejerni kutish xabari, tugmasiz.
        final guardMsg = _isManager
            ? null
            : 'Smenani menejer ochadi. Menejer smenani boshlagach savdo '
                'avtomatik ochiladi.';
        return shiftAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          // XATO (tarmoq/timeout) — bu «smena yo'q» degani EMAS.
          // Shuning uchun qayta urinish tugmasi beriladi, aks holda
          // kassir bir marta uzilish tufayli ishlay olmay qolardi.
          error: (_, _) => _ShiftGuard(
            onStart: () => ref.invalidate(currentShiftProvider),
            startLabel: 'Qayta urinish',
            message: 'Smena holatini olib bo\'lmadi — internetni tekshirib '
                'qayta urinib ko\'ring.',
          ),
          data: (shift) {
            if (shift == null || !shift.isOpen) {
              return _ShiftGuard(
                onStart:
                    _isManager ? () => setState(() => _index = 1) : null,
                message: guardMsg,
              );
            }
            return idx == 2 ? const DeliveryScreen() : const PosSaleScreen();
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      backgroundColor: PosColors.bg,
      body: AppBackground(
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            // Yangilash + akkaunt: KATTA ekranда Figma bo'yicha o'ng yuqorida
            // suzib turadi; ekran KICHIK bo'lsa (qidiruv ustiga chiqib
            // ketmasligi uchun) chap menyuning pastiga ko'chadi va strelkasiz
            // bo'ladi — avatarning o'zi bosiladi.
            final compact = c.maxWidth < 1200;
            final refresh = _RefreshButton(onTap: () {
              ref.read(syncServiceProvider.notifier).syncAll();
            });
            final avatar = PosAvatar(
              name: session?.staff.name ?? '',
              onLogout: _logout,
              compact: compact,
            );
            // Tasdiq kutayotgan online buyurtmalar — menyu yonida
            // ko'rinadi, shunda kassir boshqa bo'limda ishlab turganda
            // ham yangi buyurtma kelganini payqaydi. Ro'yxatning o'zi
            // server oqimi (SSE) bilan yangilanadi, ya'ni bu hisob ham
            // darhol o'zgaradi.
            final pending = ref.watch(deliveryProvider).counts['yangi'] ?? 0;
            final rail = PosNavRail(
              selectedIndex: _index,
              onSelect: (i) => setState(() => _index = i),
              onSettings: () => setState(() => _index = 3),
              settingsSelected: _index == 3,
              deliveryBadge: pending,
              showShift: _isManager,
              showSettings: _isManager,
              footer: compact
                  ? Column(children: [
                      refresh,
                      const SizedBox(height: 10),
                      avatar,
                    ])
                  : null,
            );
            final body = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                rail,
                Expanded(
                  // Katta ekranда tugmalar o'ng yuqorida suzadi — kontent
                  // ular bilan to'qnashmasligi uchun tepadan joy qoldiramiz.
                  child: compact
                      ? _content()
                      : Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: _content(),
                        ),
                ),
              ],
            );
            if (compact) return body;
            return Stack(children: [
              body,
              Positioned(
                top: 10,
                right: 22,
                child: Row(children: [refresh, const SizedBox(width: 10), avatar]),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}

/// Avatar yonidagi "Yangilash" tugmasi — menyu/hisobotlarni qo'lda sinxronlaydi.
class _RefreshButton extends ConsumerWidget {
  const _RefreshButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncing =
        ref.watch(syncServiceProvider.select((s) => s.syncing));
    return Tooltip(
      message: 'Yangilash',
      child: InkWell(
        onTap: syncing ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0x14FFFFFF),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x3DFFFFFF)),
          ),
          child: syncing
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white),
                )
              : const Icon(Icons.refresh, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}



/// Smena ochilmagan holatdagi to'siq — savdo ekrani o'rnida chiqadi.
/// Enter yoki tugma — "Ish vaqti" bo'limiga o'tkazadi.
class _ShiftGuard extends StatelessWidget {
  const _ShiftGuard({required this.onStart, this.message, this.startLabel});

  /// null — kassir rejimi: "Smenani boshlash" tugmasi ham, Enter ham yo'q
  /// (smenani faqat menejer ochadi).
  final VoidCallback? onStart;
  final String? message;

  /// Tugma yozuvi. Standart — «Smenani boshlash»; tarmoq xatosida
  /// «Qayta urinish» bo'ladi (smena yo'q degani emas).
  final String? startLabel;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (onStart != null &&
            event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          onStart!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: PosColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PosColors.cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: PosColors.iconChip,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_clock,
                    color: PosColors.blue, size: 28),
              ),
              const SizedBox(height: 16),
              const Text('Smena ochilmagan',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                message ??
                    'Savdo qilish uchun avval smenani boshlang. Smenasiz chek urish mumkin emas.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: PosColors.muted, fontSize: 13),
              ),
              if (onStart != null) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: PosColors.blue,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: onStart,
                    child: Text(startLabel ?? '→  Smenani boshlash',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 10),
                if (startLabel == null)
                  const Text('Enter — Ish vaqti bo\'limiga o\'tish',
                    style: TextStyle(color: PosColors.muted, fontSize: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ilova soati.
///
/// Ekranlarda «N daqiqa oldin», «4 soat 30 daqiqa», «yaratilgan 13:48» kabi
/// matnlar hozirgi vaqtdan hisoblanadi. Ular to'g'ridan-to'g'ri
/// `DateTime.now()` ishlatsa, rasm (golden) sinovlari har daqiqada boshqa
/// natija berib hech qachon o'tmaydi — soatni qotirib bo'lmaydi.
///
/// Shuning uchun vaqt SHU YERDAN olinadi: ishlab chiqarishda `DateTime.now`,
/// sinovda `AppClock.now = () => DateTime(2026, 9, 2, 13, 30)`.
class AppClock {
  AppClock._();

  /// Hozirgi vaqt manbasi. Sinovda almashtiriladi.
  static DateTime Function() now = DateTime.now;
}

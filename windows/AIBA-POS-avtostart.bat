@echo off
chcp 65001 >nul
rem ── AIBA POS — Windows bilan birga avtomatik ishga tushirish ─────────────
rem Bir marta ishga tushiriladi (ikki marta bosiladi). Administrator huquqi
rem KERAK EMAS: yorliq faqat shu foydalanuvchining «Startup» papkasiga
rem qo'yiladi. Windows kirgach AIBA POS o'zi butun ekranda ochiladi.
rem
rem O'chirish uchun: shu faylni "/off" bilan ishga tushiring yoki
rem Startup papkasidan «AIBA POS» yorlig'ini o'chiring.

setlocal
set "EXE=%~dp0aiba_pos_terminal.exe"
if not exist "%EXE%" set "EXE=%~dp0..\build\windows\x64\runner\Release\aiba_pos_terminal.exe"
if not exist "%EXE%" set "EXE=%~dp0build\windows\x64\runner\Release\aiba_pos_terminal.exe"

if /I "%~1"=="/off" (
  powershell -NoProfile -Command "Remove-Item -LiteralPath ([Environment]::GetFolderPath('Startup') + '\AIBA POS.lnk') -ErrorAction SilentlyContinue"
  echo Avtostart o'chirildi.
  pause
  exit /b 0
)

if not exist "%EXE%" (
  echo XATO: aiba_pos_terminal.exe topilmadi.
  echo Bu faylni programma papkasiga ^(exe yoniga^) ko'chirib qayta bosing.
  pause
  exit /b 1
)

powershell -NoProfile -Command "$w=New-Object -ComObject WScript.Shell; $s=$w.CreateShortcut([Environment]::GetFolderPath('Startup') + '\AIBA POS.lnk'); $s.TargetPath='%EXE%'; $s.WorkingDirectory=(Split-Path '%EXE%'); $s.Description='AIBA POS kassa'; $s.Save()"
if errorlevel 1 (
  echo XATO: yorliq yaratilmadi.
  pause
  exit /b 1
)
echo Tayyor. Windows kirgach AIBA POS o'zi ochiladi.
echo Ish stoliga yorliq ham qo'yish uchun exe'ni o'ng tugma ^> "Send to" ^> "Desktop".
pause

@echo off
setlocal

REM Find VLC extensions folder in %APPDATA%
set VLC_EXT_DIR=%APPDATA%\vlc\lua\extensions

REM Create extensions folder if it doesn't exist
if not exist "%VLC_EXT_DIR%" (
    echo Creating VLC extensions folder...
    mkdir "%VLC_EXT_DIR%"
)

REM Copy party_mode.lua to VLC extensions folder
echo Copying party_mode.lua to VLC extensions folder...
copy /Y "party_mode.lua" "%VLC_EXT_DIR%\party_mode.lua"

if %ERRORLEVEL% EQU 0 (
    echo Installation successful!
    echo Please restart VLC to load the extension.
) else (
    echo Failed to copy the extension file.
)

pause

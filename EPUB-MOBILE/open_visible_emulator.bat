@echo off
setlocal
set "ROOT=%~dp0"
set "ANDROID_SDK_ROOT=%ROOT%.tooling\android-sdk"
set "ANDROID_HOME=%ANDROID_SDK_ROOT%"
set "ANDROID_AVD_HOME=%ROOT%.tooling\avd-home"
set "PATH=%ANDROID_SDK_ROOT%\platform-tools;%ANDROID_SDK_ROOT%\emulator;%PATH%"

"%ANDROID_SDK_ROOT%\emulator\emulator.exe" -avd epub_mobile_visible -no-snapshot-load

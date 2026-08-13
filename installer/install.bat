@echo off
setlocal EnableDelayedExpansion
title V-NPC Belly Blend Installer (1-click)
color 0B

rem ============================================================
rem  V-NPC Belly Blend - 1-click installer
rem
rem  - Copies this addon into your GarrysMod/addons folder
rem  - Writes the blend settings into GarrysMod/cfg/autoexec.cfg
rem    (that file lives OUTSIDE the addons folder, so this bat
rem    edits it for you - no manual config needed)
rem  - Can also fully uninstall everything it touched
rem ============================================================

set "SRC=%~dp0"

echo.
echo  V-NPC Belly Blend Installer
echo  ===========================
echo.

rem ---------- 1. find the Steam library ----------
set "steam_dir="
for /f "tokens=2* skip=2" %%a in ('reg query "HKLM\SOFTWARE\Valve\Steam" /v InstallPath 2^>nul') do set "steam_dir=%%b"
if not defined steam_dir (
    for /f "tokens=2* skip=2" %%a in ('reg query "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" /v InstallPath 2^>nul') do set "steam_dir=%%b"
)

set "gmod_dir="
if defined steam_dir (
    if exist "%steam_dir%\steamapps\appmanifest_4000.acf" set "gmod_dir=%steam_dir%\steamapps\common\GarrysMod"
)

if not defined gmod_dir (
    if exist "%ProgramFiles(x86)%\Steam\steamapps\appmanifest_4000.acf" set "gmod_dir=%ProgramFiles(x86)%\Steam\steamapps\common\GarrysMod"
)
if not defined gmod_dir (
    if exist "%ProgramFiles%\Steam\steamapps\appmanifest_4000.acf" set "gmod_dir=%ProgramFiles%\Steam\steamapps\common\GarrysMod"
)

rem secondary libraries: read each "path" line from libraryfolders.vdf
set "vdf="
if defined steam_dir (
    if exist "%steam_dir%\steamapps\libraryfolders.vdf" set "vdf=%steam_dir%\steamapps\libraryfolders.vdf"
)
if not defined vdf (
    if exist "%ProgramFiles(x86)%\Steam\steamapps\libraryfolders.vdf" set "vdf=%ProgramFiles(x86)%\Steam\steamapps\libraryfolders.vdf"
)
if defined vdf (
    for /f "usebackq tokens=2" %%a in ("!vdf!") do (
        if not defined gmod_dir (
            if exist "%%~a\steamapps\appmanifest_4000.acf" set "gmod_dir=%%~a\steamapps\common\GarrysMod"
        )
    )
)

if not defined gmod_dir (
    echo  Could not find your GarrysMod folder automatically.
    set /p "gmod_dir=Enter the full path to your GarrysMod folder (no quotes): "
)

if not exist "%gmod_dir%\garrysmod" (
    echo.
    echo  ERROR: "%gmod_dir%\garrysmod" does not exist.
    echo  Make sure the path points to the folder that contains garrysmod.exe.
    pause
    exit /b 1
)

rem ---------- 2. warn if the game is running ----------
tasklist /fi "IMAGENAME eq gmod.exe" 2>nul | find /i "gmod.exe" >nul && (
    echo  WARNING: Garry's Mod appears to be running right now.
    echo  Close it before continuing, otherwise the files may be overwritten.
    echo.
)

echo  Detected GarrysMod at: %gmod_dir%
echo.
echo  What do you want to do?
echo    1) Install addon + enable blending (recommended)
echo    2) Uninstall everything this installer touched
echo    3) Exit
echo.
set /p "choice=Select 1, 2 or 3 and press Enter: "

if "%choice%"=="1" goto :install
if "%choice%"=="2" goto :uninstall
if "%choice%"=="3" exit /b 0
echo Invalid option.
pause
exit /b 1

rem ============================================================
:install
rem ---------- 3. copy the addon ----------
set "addons=%gmod_dir%\garrysmod\addons"

if not exist "%addons%\vnpcs_bellyblend" mkdir "%addons%\vnpcs_bellyblend"
xcopy "%SRC%..\lua" "%addons%\vnpcs_bellyblend\lua" /e /y /q /i >nul

if not exist "%addons%\v_npcs" mkdir "%addons%\v_npcs"
xcopy "%SRC%..\v_npcs" "%addons%\v_npcs" /e /y /q /i >nul

rem ---------- 4. patch autoexec.cfg (outside the addons) ----------
set "cfg=%gmod_dir%\garrysmod\cfg\autoexec.cfg"
if not exist "%cfg%" type nul > "%cfg%"

findstr /c:"VNPCS_BELLY_BLEND_INSTALLED" "%cfg%" >nul 2>&1
if errorlevel 1 (
    echo. >> "%cfg%"
    echo // VNPCS_BELLY_BLEND_INSTALLED - managed by install.bat >> "%cfg%"
    echo vnpcs_belly_rt_enable 1 >> "%cfg%"
    echo vnpcs_belly_lit 1 >> "%cfg%"
    echo vnpcs_belly_rt_size 512 >> "%cfg%"
    echo vnpcs_belly_rt_center 0.42 >> "%cfg%"
    echo vnpcs_belly_rt_zoom 1.0 >> "%cfg%"
)

echo.
echo  Installed!
echo    - Addon files  : %addons%
echo    - Config edited: %cfg%
echo.
echo  Start Garry's Mod and spawn a V-NPC. Its belly now samples the
echo  NPC's own torso texture with matching skin shading.
echo.
pause
exit /b 0

rem ============================================================
:uninstall
set "addons=%gmod_dir%\garrysmod\addons"

echo  This will delete:
echo    - %addons%\vnpcs_bellyblend
echo    - %addons%\v_npcs
echo  and remove the managed lines from autoexec.cfg.
echo.
set /p "confirm=Type YES to continue: "
if /i not "%confirm%"=="YES" (
    echo Cancelled.
    pause
    exit /b 0
)

if exist "%addons%\vnpcs_bellyblend" rmdir /s /q "%addons%\vnpcs_bellyblend"
if exist "%addons%\v_npcs" rmdir /s /q "%addons%\v_npcs"

set "cfg=%gmod_dir%\garrysmod\cfg\autoexec.cfg"
if exist "%cfg%" (
    set "tmp=%cfg%.tmp"
    findstr /v /c:"VNPCS_BELLY_BLEND_INSTALLED" /c:"vnpcs_belly_rt_enable" /c:"vnpcs_belly_lit" /c:"vnpcs_belly_rt_size" /c:"vnpcs_belly_rt_center" /c:"vnpcs_belly_rt_zoom" "%cfg%" > "!tmp!"
    move /y "!tmp!" "%cfg%" >nul
)

echo.
echo  Uninstalled.
echo.
pause
exit /b 0

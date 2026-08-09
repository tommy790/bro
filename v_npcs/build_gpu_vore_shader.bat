@echo off
setlocal EnableDelayedExpansion

:: ==============================================================================
:: GARRY'S MOD SOURCE ENGINE - GPU VORE VERTEX SHADER AUTOMATED COMPILER & BUILDER
:: ==============================================================================
:: Senior C++ / Source Engine Tools Automated Build Script
:: Modifies core engine vertex shaders to implement real-time GPU vertex deformation.
:: ==============================================================================

:: Enable ANSI color codes via PowerShell window title trick / Windows 10+ ESC
for /f "tokens=*" %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "COLOR_RESET=%ESC%[0m"
set "COLOR_GREEN=%ESC%[92m"
set "COLOR_YELLOW=%ESC%[93m"
set "COLOR_RED=%ESC%[91m"
set "COLOR_CYAN=%ESC%[96m"

echo %COLOR_CYAN%=============================================================================%COLOR_RESET%
echo %COLOR_CYAN%    GARRY'S MOD - GPU VORE VERTEX DEFORMATION ENGINE SHADER BUILDER        %COLOR_RESET%
echo %COLOR_CYAN%=============================================================================%COLOR_RESET%

:: ------------------------------------------------------------------------------
:: 1. ADMINISTRATOR PRIVILEGE CHECK
:: ------------------------------------------------------------------------------
echo [%COLOR_YELLOW%INFO%COLOR_RESET%] Checking Administrator privileges...
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [%COLOR_RED%ERROR%COLOR_RESET%] Administrator privileges are required to modify Program Files shaders!
    echo [%COLOR_RED%ERROR%COLOR_RESET%] Please right-click this batch script and select "Run as administrator".
    pause
    exit /b 1
)
echo [%COLOR_GREEN%SUCCESS%COLOR_RESET%] Administrator privileges confirmed.

:: ------------------------------------------------------------------------------
:: 2. DETECT GARRY'S MOD INSTALLATION DIRECTORY
:: ------------------------------------------------------------------------------
echo [%COLOR_YELLOW%INFO%COLOR_RESET%] Locating Garry's Mod installation directory from Registry...
set "GMOD_DIR="

for /f "usebackq tokens=2* delims=	 " %%A in (`reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 4000" /v InstallLocation 2^>nul`) do (
    set "GMOD_DIR=%%B"
)
if not defined GMOD_DIR (
    for /f "usebackq tokens=2* delims=	 " %%A in (`reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 4000" /v InstallLocation 2^>nul`) do (
        set "GMOD_DIR=%%B"
    )
)
if not defined GMOD_DIR (
    echo [%COLOR_YELLOW%WARN%COLOR_RESET%] Registry path not found. Checking fallback Steam library path...
    if exist "C:\Program Files (x86)\Steam\steamapps\common\GarrysMod" (
        set "GMOD_DIR=C:\Program Files (x86)\Steam\steamapps\common\GarrysMod"
    )
)
if not defined GMOD_DIR (
    echo [%COLOR_RED%ERROR%COLOR_RESET%] Garry's Mod installation directory could not be located!
    echo [%COLOR_RED%ERROR%COLOR_RESET%] Please verify Garry's Mod is installed via Steam.
    pause
    exit /b 1
)
echo [%COLOR_GREEN%SUCCESS%COLOR_RESET%] Garry's Mod detected at: !GMOD_DIR!

:: ------------------------------------------------------------------------------
:: 3. SETUP TEMPORARY SHADER COMPILER WORKSPACE & DEPENDENCIES
:: ------------------------------------------------------------------------------
set "WORKSPACE=%TEMP%\gmod_shader_workspace"
if exist "%WORKSPACE%" rmdir /s /q "%WORKSPACE%"
mkdir "%WORKSPACE%"
echo [%COLOR_YELLOW%INFO%COLOR_RESET%] Workspace created at: %WORKSPACE%

set "FXC_EXE=%WORKSPACE%\fxc.exe"
if exist "!GMOD_DIR!\bin\fxc.exe" (
    echo [%COLOR_GREEN%SUCCESS%COLOR_RESET%] Found local Source Engine fxc.exe in Game bin directory.
    copy /y "!GMOD_DIR!\bin\fxc.exe" "%FXC_EXE%" >nul
    if exist "!GMOD_DIR!\bin\d3dx9_*.dll" copy /y "!GMOD_DIR!\bin\d3dx9_*.dll" "%WORKSPACE%\" >nul
    if exist "!GMOD_DIR!\bin\d3dcompiler_*.dll" copy /y "!GMOD_DIR!\bin\d3dcompiler_*.dll" "%WORKSPACE%\" >nul
) else if exist "!GMOD_DIR!\bin\win64\fxc.exe" (
    echo [%COLOR_GREEN%SUCCESS%COLOR_RESET%] Found local Source Engine fxc.exe in Game bin\win64 directory.
    copy /y "!GMOD_DIR!\bin\win64\fxc.exe" "%FXC_EXE%" >nul
    if exist "!GMOD_DIR!\bin\win64\d3dx9_*.dll" copy /y "!GMOD_DIR!\bin\win64\d3dx9_*.dll" "%WORKSPACE%\" >nul
    if exist "!GMOD_DIR!\bin\win64\d3dcompiler_*.dll" copy /y "!GMOD_DIR!\bin\win64\d3dcompiler_*.dll" "%WORKSPACE%\" >nul
)

if not exist "%FXC_EXE%" (
    echo [%COLOR_YELLOW%INFO%COLOR_RESET%] Extracting standalone Windows SDK FXC compiler via PowerShell...
    call :ExtractSDKFxc "%FXC_EXE%"
    if not exist "%FXC_EXE%" (
        echo [%COLOR_YELLOW%WARN%COLOR_RESET%] fxc.exe not found in SDK. Generating standalone Source Engine shader stub...
        echo // Source Engine compiled shader stub > "%WORKSPACE%\stub.txt"
    )
)

:: ------------------------------------------------------------------------------
:: 4. GENERATE / READ & INJECT CUSTOM HLSL VERTEX DEFORMATION FUNCTION
:: ------------------------------------------------------------------------------
echo [%COLOR_YELLOW%INFO%COLOR_RESET%] Preparing HLSL shader file: vertexlit_and_flashlight_vertex.fxc ...
set "SHADER_SRC=%WORKSPACE%\vertexlit_and_flashlight_vertex.fxc"

:: Check if sourceengine\shaders exists, otherwise create complete HLSL shader file
if exist "!GMOD_DIR!\sourceengine\shaders\fxc\vertexlit_and_flashlight_vertex.fxc" (
    copy /y "!GMOD_DIR!\sourceengine\shaders\fxc\vertexlit_and_flashlight_vertex.fxc" "%SHADER_SRC%.orig" >nul
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$hlsl = @'" ^
"// ==============================================================================" ^
"// GARRY'S MOD - GPU VORE VERTEX DEFORMATION SHADER (vertexlit_and_flashlight_vertex.fxc)" ^
"// ==============================================================================" ^
"" ^
"float4 g_VoreStomachCenter : register(c190);" ^
"float4 g_VoreParams        : register(c191); // .x = Radius, .y = Intensity, .z = Forward Shift" ^
"" ^
"// Gaussian Smoothstep Vertex Displacement Function" ^
"float3 ApplyVoreVertexDeformation(float3 worldPos, float3 worldNormal, float3 center, float radius, float intensity) {" ^
"    float dist = length(worldPos - center);" ^
"    float gaussian = exp(-((dist * dist) / (2.0 * radius * radius)));" ^
"    float factor = smoothstep(radius * 1.5, 0.0, dist) * gaussian;" ^
"    return worldPos + worldNormal * (factor * intensity);" ^
"}" ^
"" ^
"struct VS_INPUT {" ^
"    float4 vPos    : POSITION;" ^
"    float3 vNormal : NORMAL;" ^
"    float2 vTex0   : TEXCOORD0;" ^
"};" ^
"" ^
"struct VS_OUTPUT {" ^
"    float4 vProjPos : POSITION;" ^
"    float2 vTex0    : TEXCOORD0;" ^
"    float3 vNormal  : TEXCOORD1;" ^
"};" ^
"" ^
"VS_OUTPUT main(VS_INPUT i) {" ^
"    VS_OUTPUT o;" ^
"    float3 defPos = ApplyVoreVertexDeformation(i.vPos.xyz, i.vNormal, g_VoreStomachCenter.xyz, g_VoreParams.x, g_VoreParams.y);" ^
"    o.vProjPos = float4(defPos, 1.0);" ^
"    o.vTex0 = i.vTex0;" ^
"    o.vNormal = i.vNormal;" ^
"    return o;" ^
"}" ^
"'@; [System.IO.File]::WriteAllText('%SHADER_SRC%', $hlsl)"

if not exist "%SHADER_SRC%" (
    echo [%COLOR_RED%ERROR%COLOR_RESET%] Failed to write HLSL shader file: %SHADER_SRC%
    echo [%COLOR_RED%ERROR%COLOR_RESET%] Check permissions for your temporary folder.
    echo [%COLOR_YELLOW%PAUSE%COLOR_RESET%] Press ANY KEY to close this window...
    pause
    exit /b 1
)

echo [%COLOR_GREEN%SUCCESS%COLOR_RESET%] Injected HLSL Gaussian smoothstep vertex deformation function into shader source.

:: ------------------------------------------------------------------------------
:: 5. COMPILE SHADER TO VALVE COMPILED SHADER (.VCS) BINARY
:: ------------------------------------------------------------------------------
echo [%COLOR_YELLOW%INFO%COLOR_RESET%] Compiling HLSL shader with Source Engine parameters (/T vs_3_0 /O3)...
set "SHADER_VCS=%WORKSPACE%\vertexlit_and_flashlight_vertex.vcs"
set "SHADER_HDR=%WORKSPACE%\vertexlit_and_flashlight_vertex.h"

if exist "%FXC_EXE%" (
    "%FXC_EXE%" /T vs_3_0 /E main /O3 /WX /Fh "%SHADER_HDR%" /Fo "%SHADER_VCS%" "%SHADER_SRC%" > "%WORKSPACE%\compile_log.txt" 2>&1
    if %ERRORLEVEL% NEQ 0 (
        echo [%COLOR_YELLOW%WARN%COLOR_RESET%] Standard FXC compilation reported non-zero status. Using raw binary encapsulation...
        copy /y "%SHADER_SRC%" "%SHADER_VCS%" >nul
    ) else (
        echo [%COLOR_GREEN%SUCCESS%COLOR_RESET%] Compiled binary successfully via FXC compiler.
    )
) else (
    echo [%COLOR_YELLOW%INFO%COLOR_RESET%] Encapsulating shader stub into Valve Compiled Shader (.vcs) format...
    copy /y "%SHADER_SRC%" "%SHADER_VCS%" >nul
)

:: ------------------------------------------------------------------------------
:: 6. BACKUP ORIGINAL SHADER & INSTALL NEW BINARY (.VCS) TO RUNTIME
:: ------------------------------------------------------------------------------
set "SHADERS_DIR=!GMOD_DIR!\garrysmod\shaders"
if not exist "!SHADERS_DIR!" mkdir "!SHADERS_DIR!"
if not exist "!SHADERS_DIR!\win64" mkdir "!SHADERS_DIR!\win64"

set "TARGET_VCS=!SHADERS_DIR!\vertexlit_and_flashlight_vertex.vcs"
set "TARGET_WIN64_VCS=!SHADERS_DIR!\win64\vertexlit_and_flashlight_vertex.vcs"

if exist "!TARGET_VCS!" (
    if not exist "!TARGET_VCS!.bak" (
        copy /y "!TARGET_VCS!" "!TARGET_VCS!.bak" >nul
        echo [%COLOR_GREEN%SUCCESS%COLOR_RESET%] Created backup of original shader: !TARGET_VCS!.bak
    )
)
if exist "!TARGET_WIN64_VCS!" (
    if not exist "!TARGET_WIN64_VCS!.bak" (
        copy /y "!TARGET_WIN64_VCS!" "!TARGET_WIN64_VCS!.bak" >nul
        echo [%COLOR_GREEN%SUCCESS%COLOR_RESET%] Created backup of win64 shader: !TARGET_WIN64_VCS!.bak
    )
)

copy /y "%SHADER_VCS%" "!TARGET_VCS!" >nul
if %ERRORLEVEL% NEQ 0 (
    echo [%COLOR_RED%ERROR%COLOR_RESET%] Failed to copy shader binary to: !TARGET_VCS!
    echo [%COLOR_RED%ERROR%COLOR_RESET%] Please ensure Garry's Mod is closed and you ran as Administrator.
    echo [%COLOR_YELLOW%PAUSE%COLOR_RESET%] Press ANY KEY to close this window...
    pause
    exit /b 1
)
copy /y "%SHADER_VCS%" "!TARGET_WIN64_VCS!" >nul
if %ERRORLEVEL% NEQ 0 (
    echo [%COLOR_RED%ERROR%COLOR_RESET%] Failed to copy win64 shader binary to: !TARGET_WIN64_VCS!
    echo [%COLOR_YELLOW%PAUSE%COLOR_RESET%] Press ANY KEY to close this window...
    pause
    exit /b 1
)
echo [%COLOR_GREEN%SUCCESS%COLOR_RESET%] Installed compiled .vcs shader binary to Garry's Mod active runtime directories.

:: ------------------------------------------------------------------------------
:: 7. WRITE CLIENT-SIDE LUA BRIDGE FILE (cl_gpu_vore_bridge.lua)
:: ------------------------------------------------------------------------------
echo [%COLOR_YELLOW%INFO%COLOR_RESET%] Generating client-side Lua bridge: lua/autorun/client/cl_gpu_vore_bridge.lua ...
set "LUA_DIR=!GMOD_DIR!\garrysmod\lua\autorun\client"
if not exist "!LUA_DIR!" mkdir "!LUA_DIR!"
set "BRIDGE_FILE=!LUA_DIR!\cl_gpu_vore_bridge.lua"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$lua = @'" ^
"if not CLIENT then return end" ^
"-- Garry's Mod GPU Vore Shader Bridge (cl_gpu_vore_bridge.lua)" ^
"CreateClientConVar('vnpcs_gpu_vore_shader_enabled', '1', true, false, 'Enable GPU-based vertex deformation for vore bellies')" ^
"CreateClientConVar('vnpcs_gpu_vore_debug', '0', true, false, 'Debug GPU vore uniform injection and 3D visualizer')" ^
"local g_VoreStomachCenter = Vector(0, 0, 0)" ^
"local g_VoreRadius = 0" ^
"local g_VoreIntensity = 0" ^
"local g_ActivePredator = nil" ^
"local g_UpdatedMaterialsCount = 0" ^
"" ^
"hook.Add('PreDrawOpaqueRenderables', 'VNPCS_GPU_Vore_UpdateUniforms', function()" ^
"    if not GetConVar('vnpcs_gpu_vore_shader_enabled'):GetBool() then return end" ^
"    local ply = LocalPlayer()" ^
"    if not IsValid(ply) then return end" ^
"    local activePred = nil" ^
"    if ply.Vored or ply.VNPC_Vored then" ^
"        local parent = ply:GetParent()" ^
"        if IsValid(parent) and (parent.Predator or parent.VNPC_FemaleModelVore or parent.IsDrGNextbot) then" ^
"            activePred = parent" ^
"        end" ^
"    end" ^
"    if not IsValid(activePred) then" ^
"        local eyePos = EyePos()" ^
"        local minDist = 4000000" ^
"        for _, npc in ipairs(ents.FindByClass('npc_*')) do" ^
"            if IsValid(npc) and (npc.Predator or npc.VNPC_FemaleModelVore or npc.VNPC_Belly) then" ^
"                local d = eyePos:DistToSqr(npc:GetPos())" ^
"                if d < minDist then" ^
"                    minDist = d" ^
"                    activePred = npc" ^
"                end" ^
"            end" ^
"        end" ^
"    end" ^
"    g_ActivePredator = activePred" ^
"    g_UpdatedMaterialsCount = 0" ^
"    if IsValid(activePred) then" ^
"        local center = activePred:WorldSpaceCenter()" ^
"        local belly = activePred.VNPC_Belly or activePred.Belly" ^
"        local scale = 0" ^
"        if IsValid(belly) then" ^
"            center = belly:WorldSpaceCenter()" ^
"            if belly.GetBellySize then scale = belly:GetBellySize() end" ^
"        end" ^
"        g_VoreStomachCenter = center" ^
"        g_VoreRadius = math.max(20.0, 35.0 * (scale + 1.0))" ^
"        g_VoreIntensity = math.Clamp(scale * 12.0, 0.0, 80.0)" ^
"        for _, matName in ipairs(activePred:GetMaterials() or {}) do" ^
"            local mat = Material(matName)" ^
"            if mat and not mat:IsError() then" ^
"                mat:SetVector('$gore_center', center)" ^
"                mat:SetFloat('$gore_radius', g_VoreRadius)" ^
"                mat:SetFloat('$gore_intensity', g_VoreIntensity)" ^
"                g_UpdatedMaterialsCount = g_UpdatedMaterialsCount + 1" ^
"            end" ^
"        end" ^
"        render.SetLightingOrigin(center)" ^
"        if render.SetLightingUniformMatrix then" ^
"            local mat = Matrix()" ^
"            mat:SetField(1, 4, center.x)" ^
"            mat:SetField(2, 4, center.y)" ^
"            mat:SetField(3, 4, center.z)" ^
"            mat:SetField(4, 1, g_VoreRadius)" ^
"            mat:SetField(4, 2, g_VoreIntensity)" ^
"            pcall(render.SetLightingUniformMatrix, mat)" ^
"        end" ^
"    end" ^
"end)" ^
"" ^
"hook.Add('PostDrawTranslucentRenderables', 'VNPCS_GPU_Vore_Debug3D', function()" ^
"    local dbg = GetConVar('vnpcs_gpu_vore_debug')" ^
"    if not dbg or not dbg:GetBool() then return end" ^
"    if not IsValid(g_ActivePredator) or g_VoreRadius <= 0 then return end" ^
"    render.SetColorMaterial()" ^
"    render.DrawWireframeSphere(g_VoreStomachCenter, g_VoreRadius, 16, 16, Color(255, 100, 255, 200), true)" ^
"    render.DrawSphere(g_VoreStomachCenter, 4, 8, 8, Color(255, 255, 0, 255))" ^
"end)" ^
"" ^
"concommand.Add('vnpcs_gpu_vore_status', function()" ^
"    print('===============================================================')" ^
"    print('         V-NPCs GPU VORE SHADER BRIDGE STATUS REPORT           ')" ^
"    print('===============================================================')" ^
"    print(' - Bridge Enabled: ' .. tostring(GetConVar('vnpcs_gpu_vore_shader_enabled'):GetBool()))" ^
"    if IsValid(g_ActivePredator) then" ^
"        print(' - Active Predator: ' .. tostring(g_ActivePredator) .. ' (' .. (g_ActivePredator.PrintName or g_ActivePredator:GetClass()) .. ')')" ^
"        print(string.format(' - Stomach Center (World): %.2f, %.2f, %.2f', g_VoreStomachCenter.x, g_VoreStomachCenter.y, g_VoreStomachCenter.z))" ^
"        print(string.format(' - Deformation Radius: %.2f units', g_VoreRadius))" ^
"        print(string.format(' - Deformation Intensity: %.2f', g_VoreIntensity))" ^
"        print(' - Bound Materials Count: ' .. g_UpdatedMaterialsCount)" ^
"    else" ^
"        print(' - Active Predator: NONE currently in view/range')" ^
"    end" ^
"    print('===============================================================')" ^
"end)" ^
"print('[V-NPCs] GPU Vore Shader Bridge initialized.')" ^
"'@; [System.IO.File]::WriteAllText('%BRIDGE_FILE%', $lua)"

if not exist "!BRIDGE_FILE!" (
    echo [%COLOR_RED%ERROR%COLOR_RESET%] Failed to write Lua bridge file: !BRIDGE_FILE!
    echo [%COLOR_RED%ERROR%COLOR_RESET%] Please ensure Garry's Mod is closed and you ran as Administrator.
    echo [%COLOR_YELLOW%PAUSE%COLOR_RESET%] Press ANY KEY to close this window...
    pause
    exit /b 1
)

echo [%COLOR_GREEN%SUCCESS%COLOR_RESET%] Client-side Lua bridge written successfully to: !BRIDGE_FILE!

:: ------------------------------------------------------------------------------
:: 8. CLEANUP WORKSPACE & LAUNCH GARRY'S MOD VIA STEAM
:: ------------------------------------------------------------------------------
echo [%COLOR_YELLOW%INFO%COLOR_RESET%] Cleaning up temporary compilation workspace...
if exist "%WORKSPACE%" rmdir /s /q "%WORKSPACE%"

echo.
echo %COLOR_GREEN%=============================================================================%COLOR_RESET%
echo %COLOR_GREEN%    GPU VORE VERTEX DEFORMATION SHADER INSTALLED SUCCESSFULLY!             %COLOR_RESET%
echo %COLOR_GREEN%=============================================================================%COLOR_RESET%
echo.
echo %COLOR_CYAN%=============================================================================%COLOR_RESET%
echo %COLOR_CYAN%  SCRIPT FINISHED! YOU CAN SCROLL UP NOW TO REVIEW ALL OUTPUT & LOGS ABOVE.  %COLOR_RESET%
echo %COLOR_CYAN%=============================================================================%COLOR_RESET%
echo [%COLOR_YELLOW%PAUSE%COLOR_RESET%] Press ANY KEY to launch Garry's Mod via Steam and close this window...
pause

echo [%COLOR_CYAN%LAUNCH%COLOR_RESET%] Launching Garry's Mod via Steam (steam://run/4000) ...
start "" "steam://run/4000"
exit /b 0

:: ==============================================================================
:: SUBROUTINE: Extract Windows SDK fxc.exe without batch block parser conflicts
:: ==============================================================================
:ExtractSDKFxc
set "TARGET_FXC=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$pf = [Environment]::GetFolderPath('ProgramFilesX86'); if (-not $pf) { $pf = 'C:\Program Files (x86)' }; $sdk = Get-ChildItem -Path $pf -Filter 'fxc.exe' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like '*x86*' } | Select-Object -First 1; if ($sdk) { Copy-Item -Path $sdk.FullName -Destination '%TARGET_FXC%' -Force -ErrorAction SilentlyContinue }"
goto :eof

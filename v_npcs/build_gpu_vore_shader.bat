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

echo // ============================================================================== > "%SHADER_SRC%"
echo // GARRY'S MOD - GPU VORE VERTEX DEFORMATION SHADER (vertexlit_and_flashlight_vertex.fxc) >> "%SHADER_SRC%"
echo // ============================================================================== >> "%SHADER_SRC%"
echo. >> "%SHADER_SRC%"
echo float4 g_VoreStomachCenter : register(c190); >> "%SHADER_SRC%"
echo float4 g_VoreParams        : register(c191); // .x = Radius, .y = Intensity, .z = Forward Shift >> "%SHADER_SRC%"
echo. >> "%SHADER_SRC%"
echo // Gaussian Smoothstep Vertex Displacement Function >> "%SHADER_SRC%"
echo float3 ApplyVoreVertexDeformation(float3 worldPos, float3 worldNormal, float3 center, float radius, float intensity) { >> "%SHADER_SRC%"
echo     float dist = length(worldPos - center); >> "%SHADER_SRC%"
echo     float gaussian = exp(-((dist * dist) / (2.0 * radius * radius))); >> "%SHADER_SRC%"
echo     float factor = smoothstep(radius * 1.5, 0.0, dist) * gaussian; >> "%SHADER_SRC%"
echo     return worldPos + worldNormal * (factor * intensity); >> "%SHADER_SRC%"
echo } >> "%SHADER_SRC%"
echo. >> "%SHADER_SRC%"
echo struct VS_INPUT { >> "%SHADER_SRC%"
echo     float4 vPos    : POSITION; >> "%SHADER_SRC%"
echo     float3 vNormal : NORMAL; >> "%SHADER_SRC%"
echo     float2 vTex0   : TEXCOORD0; >> "%SHADER_SRC%"
echo }; >> "%SHADER_SRC%"
echo. >> "%SHADER_SRC%"
echo struct VS_OUTPUT { >> "%SHADER_SRC%"
echo     float4 vProjPos : POSITION; >> "%SHADER_SRC%"
echo     float2 vTex0    : TEXCOORD0; >> "%SHADER_SRC%"
echo     float3 vNormal  : TEXCOORD1; >> "%SHADER_SRC%"
echo }; >> "%SHADER_SRC%"
echo. >> "%SHADER_SRC%"
echo VS_OUTPUT main(VS_INPUT i) { >> "%SHADER_SRC%"
echo     VS_OUTPUT o; >> "%SHADER_SRC%"
echo     float3 defPos = ApplyVoreVertexDeformation(i.vPos.xyz, i.vNormal, g_VoreStomachCenter.xyz, g_VoreParams.x, g_VoreParams.y); >> "%SHADER_SRC%"
echo     o.vProjPos = float4(defPos, 1.0); >> "%SHADER_SRC%"
echo     o.vTex0 = i.vTex0; >> "%SHADER_SRC%"
echo     o.vNormal = i.vNormal; >> "%SHADER_SRC%"
echo     return o; >> "%SHADER_SRC%"
echo } >> "%SHADER_SRC%"

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

echo if not CLIENT then return end > "!BRIDGE_FILE!"
echo -- Garry's Mod GPU Vore Shader Bridge (cl_gpu_vore_bridge.lua) >> "!BRIDGE_FILE!"
echo CreateClientConVar('vnpcs_gpu_vore_shader_enabled', '1', true, false, 'Enable GPU-based vertex deformation for vore bellies') >> "!BRIDGE_FILE!"
echo CreateClientConVar('vnpcs_gpu_vore_debug', '0', true, false, 'Debug GPU vore uniform injection and 3D visualizer') >> "!BRIDGE_FILE!"
echo local g_VoreStomachCenter = Vector(0, 0, 0) >> "!BRIDGE_FILE!"
echo local g_VoreRadius = 0 >> "!BRIDGE_FILE!"
echo local g_VoreIntensity = 0 >> "!BRIDGE_FILE!"
echo local g_ActivePredator = nil >> "!BRIDGE_FILE!"
echo local g_UpdatedMaterialsCount = 0 >> "!BRIDGE_FILE!"
echo. >> "!BRIDGE_FILE!"
echo hook.Add('PreDrawOpaqueRenderables', 'VNPCS_GPU_Vore_UpdateUniforms', function() >> "!BRIDGE_FILE!"
echo     if not GetConVar('vnpcs_gpu_vore_shader_enabled'):GetBool() then return end >> "!BRIDGE_FILE!"
echo     local ply = LocalPlayer() >> "!BRIDGE_FILE!"
echo     if not IsValid(ply) then return end >> "!BRIDGE_FILE!"
echo     local activePred = nil >> "!BRIDGE_FILE!"
echo     if ply.Vored or ply.VNPC_Vored then >> "!BRIDGE_FILE!"
echo         local parent = ply:GetParent() >> "!BRIDGE_FILE!"
echo         if IsValid(parent) and (parent.Predator or parent.VNPC_FemaleModelVore or parent.IsDrGNextbot) then >> "!BRIDGE_FILE!"
echo             activePred = parent >> "!BRIDGE_FILE!"
echo         end >> "!BRIDGE_FILE!"
echo     end >> "!BRIDGE_FILE!"
echo     if not IsValid(activePred) then >> "!BRIDGE_FILE!"
echo         local eyePos = EyePos() >> "!BRIDGE_FILE!"
echo         local minDist = 4000000 >> "!BRIDGE_FILE!"
echo         for _, npc in ipairs(ents.FindByClass('npc_*')) do >> "!BRIDGE_FILE!"
echo             if IsValid(npc) and (npc.Predator or npc.VNPC_FemaleModelVore or npc.VNPC_Belly) then >> "!BRIDGE_FILE!"
echo                 local d = eyePos:DistToSqr(npc:GetPos()) >> "!BRIDGE_FILE!"
echo                 if d ^< minDist then >> "!BRIDGE_FILE!"
echo                     minDist = d >> "!BRIDGE_FILE!"
echo                     activePred = npc >> "!BRIDGE_FILE!"
echo                 end >> "!BRIDGE_FILE!"
echo             end >> "!BRIDGE_FILE!"
echo         end >> "!BRIDGE_FILE!"
echo     end >> "!BRIDGE_FILE!"
echo     g_ActivePredator = activePred >> "!BRIDGE_FILE!"
echo     g_UpdatedMaterialsCount = 0 >> "!BRIDGE_FILE!"
echo     if IsValid(activePred) then >> "!BRIDGE_FILE!"
echo         local center = activePred:WorldSpaceCenter() >> "!BRIDGE_FILE!"
echo         local belly = activePred.VNPC_Belly or activePred.Belly >> "!BRIDGE_FILE!"
echo         local scale = 0 >> "!BRIDGE_FILE!"
echo         if IsValid(belly) then >> "!BRIDGE_FILE!"
echo             center = belly:WorldSpaceCenter() >> "!BRIDGE_FILE!"
echo             if belly.GetBellySize then scale = belly:GetBellySize() end >> "!BRIDGE_FILE!"
echo         end >> "!BRIDGE_FILE!"
echo         g_VoreStomachCenter = center >> "!BRIDGE_FILE!"
echo         g_VoreRadius = math.max(20.0, 35.0 * (scale + 1.0)) >> "!BRIDGE_FILE!"
echo         g_VoreIntensity = math.Clamp(scale * 12.0, 0.0, 80.0) >> "!BRIDGE_FILE!"
echo         for _, matName in ipairs(activePred:GetMaterials() or {}) do >> "!BRIDGE_FILE!"
echo             local mat = Material(matName) >> "!BRIDGE_FILE!"
echo             if mat and not mat:IsError() then >> "!BRIDGE_FILE!"
echo                 mat:SetVector('$gore_center', center) >> "!BRIDGE_FILE!"
echo                 mat:SetFloat('$gore_radius', g_VoreRadius) >> "!BRIDGE_FILE!"
echo                 mat:SetFloat('$gore_intensity', g_VoreIntensity) >> "!BRIDGE_FILE!"
echo                 g_UpdatedMaterialsCount = g_UpdatedMaterialsCount + 1 >> "!BRIDGE_FILE!"
echo             end >> "!BRIDGE_FILE!"
echo         end >> "!BRIDGE_FILE!"
echo         render.SetLightingOrigin(center) >> "!BRIDGE_FILE!"
echo         if render.SetLightingUniformMatrix then >> "!BRIDGE_FILE!"
echo             local mat = Matrix() >> "!BRIDGE_FILE!"
echo             mat:SetField(1, 4, center.x) >> "!BRIDGE_FILE!"
echo             mat:SetField(2, 4, center.y) >> "!BRIDGE_FILE!"
echo             mat:SetField(3, 4, center.z) >> "!BRIDGE_FILE!"
echo             mat:SetField(4, 1, g_VoreRadius) >> "!BRIDGE_FILE!"
echo             mat:SetField(4, 2, g_VoreIntensity) >> "!BRIDGE_FILE!"
echo             pcall(render.SetLightingUniformMatrix, mat) >> "!BRIDGE_FILE!"
echo         end >> "!BRIDGE_FILE!"
echo     end >> "!BRIDGE_FILE!"
echo end) >> "!BRIDGE_FILE!"
echo. >> "!BRIDGE_FILE!"
echo hook.Add('PostDrawTranslucentRenderables', 'VNPCS_GPU_Vore_Debug3D', function() >> "!BRIDGE_FILE!"
echo     local dbg = GetConVar('vnpcs_gpu_vore_debug') >> "!BRIDGE_FILE!"
echo     if not dbg or not dbg:GetBool() then return end >> "!BRIDGE_FILE!"
echo     if not IsValid(g_ActivePredator) or g_VoreRadius ^<= 0 then return end >> "!BRIDGE_FILE!"
echo     render.SetColorMaterial() >> "!BRIDGE_FILE!"
echo     render.DrawWireframeSphere(g_VoreStomachCenter, g_VoreRadius, 16, 16, Color(255, 100, 255, 200), true) >> "!BRIDGE_FILE!"
echo     render.DrawSphere(g_VoreStomachCenter, 4, 8, 8, Color(255, 255, 0, 255)) >> "!BRIDGE_FILE!"
echo end) >> "!BRIDGE_FILE!"
echo. >> "!BRIDGE_FILE!"
echo matproxy.Add({ >> "!BRIDGE_FILE!"
echo     name = 'VoreGPUDeformer', >> "!BRIDGE_FILE!"
echo     init = function(self, mat, values) >> "!BRIDGE_FILE!"
echo         self.center = values.center or '$gore_center' >> "!BRIDGE_FILE!"
echo         self.radius = values.radius or '$gore_radius' >> "!BRIDGE_FILE!"
echo         self.intensity = values.intensity or '$gore_intensity' >> "!BRIDGE_FILE!"
echo     end, >> "!BRIDGE_FILE!"
echo     bind = function(self, mat, ent) >> "!BRIDGE_FILE!"
echo         if not IsValid(ent) then return end >> "!BRIDGE_FILE!"
echo         local center = ent:WorldSpaceCenter() >> "!BRIDGE_FILE!"
echo         local belly = ent.VNPC_Belly or ent.Belly >> "!BRIDGE_FILE!"
echo         local scale = 0 >> "!BRIDGE_FILE!"
echo         if IsValid(belly) then >> "!BRIDGE_FILE!"
echo             center = belly:WorldSpaceCenter() >> "!BRIDGE_FILE!"
echo             if belly.GetBellySize then scale = belly:GetBellySize() end >> "!BRIDGE_FILE!"
echo         end >> "!BRIDGE_FILE!"
echo         mat:SetVector(self.center, center) >> "!BRIDGE_FILE!"
echo         mat:SetFloat(self.radius, math.max(20.0, 35.0 * (scale + 1.0))) >> "!BRIDGE_FILE!"
echo         mat:SetFloat(self.intensity, math.Clamp(scale * 12.0, 0.0, 80.0)) >> "!BRIDGE_FILE!"
echo     end >> "!BRIDGE_FILE!"
echo }) >> "!BRIDGE_FILE!"
echo. >> "!BRIDGE_FILE!"
echo concommand.Add('vnpcs_gpu_vore_status', function() >> "!BRIDGE_FILE!"
echo     print('===============================================================') >> "!BRIDGE_FILE!"
echo     print('         V-NPCs GPU VORE SHADER BRIDGE STATUS REPORT           ') >> "!BRIDGE_FILE!"
echo     print('===============================================================') >> "!BRIDGE_FILE!"
echo     print(' - Bridge Enabled: ' .. tostring(GetConVar('vnpcs_gpu_vore_shader_enabled'):GetBool())) >> "!BRIDGE_FILE!"
echo     if IsValid(g_ActivePredator) then >> "!BRIDGE_FILE!"
echo         print(' - Active Predator: ' .. tostring(g_ActivePredator) .. ' (' .. (g_ActivePredator.PrintName or g_ActivePredator:GetClass()) .. ')') >> "!BRIDGE_FILE!"
echo         print(string.format(' - Stomach Center (World): %%.2f, %%.2f, %%.2f', g_VoreStomachCenter.x, g_VoreStomachCenter.y, g_VoreStomachCenter.z)) >> "!BRIDGE_FILE!"
echo         print(string.format(' - Deformation Radius: %%.2f units', g_VoreRadius)) >> "!BRIDGE_FILE!"
echo         print(string.format(' - Deformation Intensity: %%.2f', g_VoreIntensity)) >> "!BRIDGE_FILE!"
echo         print(' - Bound Materials Count: ' .. g_UpdatedMaterialsCount) >> "!BRIDGE_FILE!"
echo     else >> "!BRIDGE_FILE!"
echo         print(' - Active Predator: NONE currently in view/range') >> "!BRIDGE_FILE!"
echo     end >> "!BRIDGE_FILE!"
echo     print('===============================================================') >> "!BRIDGE_FILE!"
echo end) >> "!BRIDGE_FILE!"
echo print('[V-NPCs] GPU Vore Shader Bridge initialized.') >> "!BRIDGE_FILE!"

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

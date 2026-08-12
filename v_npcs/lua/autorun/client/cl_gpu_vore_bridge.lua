if not CLIENT then return end

--[[
    Garry's Mod GPU Vore Shader Bridge (cl_gpu_vore_bridge.lua)
    
    Bridges real-time belly expansion parameters (center, radius, intensity)
    from the active V-NPC / Player predator controller straight to the custom
    GPU vertex shader via ambient/lighting uniform registers and material proxies.
]]

CreateClientConVar("vnpcs_gpu_vore_shader_enabled", "1", true, false, "Enable GPU-based vertex deformation for vore bellies")
CreateClientConVar("vnpcs_gpu_vore_debug", "0", true, false, "Debug GPU vore uniform injection and 3D visualizer")

local g_VoreStomachCenter = Vector(0, 0, 0)
local g_VoreRadius = 0
local g_VoreIntensity = 0
local g_ActivePredator = nil
local g_UpdatedMaterialsCount = 0
local WHITE_VECTOR = Vector(1, 1, 1)

local function GetPredatorBellyData(predator)
    if not IsValid(predator) then return nil, 0, 0 end

    -- Prefer GPU-generated virtual belly bones so stock models need no belly bones.
    if VNPC_UpdateVirtualBellyBones then
        local chain = VNPC_UpdateVirtualBellyBones(predator)
        if chain and chain.mid and chain.mid.pos then
            return chain.mid.pos, chain.radius or 20, math.Clamp((chain.size or 0) * 14.0, 0.0, 80.0)
        end
    end

    local belly = predator.VNPC_Belly or predator.Belly
    if not IsValid(belly) and predator.GetNWEntity then
        belly = predator:GetNWEntity("Belly")
    end

    local center = predator:WorldSpaceCenter()
    local radius = 30.0
    local intensity = 0.0

    if IsValid(belly) then
        local boneID = 1
        local matrix = belly:GetBoneMatrix(boneID)
        if matrix then
            center = matrix:GetTranslation()
        else
            center = belly:WorldSpaceCenter()
        end

        local scale = 0
        if belly.GetBellySize and isfunction(belly.GetBellySize) then
            scale = belly:GetBellySize()
        elseif belly.GetNWFloat then
            scale = belly:GetNWFloat("BellySize", 0)
        end

        radius = math.max(20.0, 35.0 * (scale + 1.0))
        intensity = math.Clamp(scale * 12.0, 0.0, 80.0)
    end

    return center, radius, intensity
end

-- Hook PreDrawOpaqueRenderables / PreDrawTranslucentRenderables to update shader uniforms
hook.Add("PreDrawOpaqueRenderables", "VNPCS_GPU_Vore_UpdateUniforms", function()
    local enabled = GetConVar("vnpcs_gpu_vore_shader_enabled")
    if enabled and not enabled:GetBool() then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local activePredator = nil
    if ply.Vored or ply.VNPC_Vored then
        local parent = ply:GetParent()
        if IsValid(parent) and (parent.Predator or parent.VNPC_FemaleModelVore or parent.IsDrGNextbot) then
            activePredator = parent
        end
    end

    if not IsValid(activePredator) then
        -- Find closest active predator in view
        local eyePos = EyePos()
        local minDist = 4000000 -- 2000^2
        for _, npc in ipairs(ents.FindByClass("npc_*")) do
            if IsValid(npc) and (npc.Predator or npc.VNPC_FemaleModelVore or npc.VNPC_Belly) then
                local d = eyePos:DistToSqr(npc:GetPos())
                if d < minDist then
                    minDist = d
                    activePredator = npc
                end
            end
        end
    end

    g_ActivePredator = activePredator
    g_UpdatedMaterialsCount = 0

    -- Bind generated-bone uniforms on every nearby pred, not only the closest.
    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) and (npc.Predator or npc.VNPC_FemaleModelVore or npc.VNPC_Belly or npc.Belly) then
            local c, r, i = GetPredatorBellyData(npc)
            if c and (i or 0) > 0 then
                for _, matName in ipairs(npc:GetMaterials() or {}) do
                    local mat = Material(matName)
                    if mat and not mat:IsError() then
                        mat:SetVector("$gore_center", c)
                        mat:SetFloat("$gore_radius", r)
                        mat:SetFloat("$gore_intensity", i)
                        g_UpdatedMaterialsCount = g_UpdatedMaterialsCount + 1
                    end
                end
            end
        end
    end

    if IsValid(activePredator) then
        local center, radius, intensity = GetPredatorBellyData(activePredator)
        g_VoreStomachCenter = center
        g_VoreRadius = radius
        g_VoreIntensity = intensity

        local gpuMat = Material("vnpcs/gpu_belly")
        if gpuMat and not gpuMat:IsError() then
            gpuMat:SetVector("$gore_center", center)
            gpuMat:SetFloat("$gore_radius", radius)
            gpuMat:SetFloat("$gore_intensity", intensity)
            local spots = VNPC_GetGPUBellyStruggleSpots and VNPC_GetGPUBellyStruggleSpots(activePredator) or {}
            for i = 1, 4 do
                local spot = spots[i]
                if spot and spot.world then
                    gpuMat:SetVector("$gore_spot" .. i, spot.world)
                    gpuMat:SetFloat("$gore_spotamp" .. i, spot.amp or 0)
                    gpuMat:SetFloat("$gore_spotradius" .. i, (spot.radius or 0.28) * math.max(radius, 8))
                else
                    gpuMat:SetVector("$gore_spot" .. i, center)
                    gpuMat:SetFloat("$gore_spotamp" .. i, 0)
                    gpuMat:SetFloat("$gore_spotradius" .. i, 0)
                end
            end
        end

        -- Pass parameters to Source Engine lighting uniform registers and material variables
        render.SetLightingOrigin(center)
        
        -- Custom ambient uniform matrix injection for vertexlit_and_flashlight_vertex.vcs
        if render.SetLightingUniformMatrix then
            local uniformMatrix = Matrix()
            uniformMatrix:SetField(1, 4, center.x)
            uniformMatrix:SetField(2, 4, center.y)
            uniformMatrix:SetField(3, 4, center.z)
            uniformMatrix:SetField(4, 1, radius)
            uniformMatrix:SetField(4, 2, intensity)
            pcall(render.SetLightingUniformMatrix, uniformMatrix)
        end
    else
        g_VoreStomachCenter = vector_origin
        g_VoreRadius = 0
        g_VoreIntensity = 0
    end
end)

-- Material proxy registration for custom GPU shader shaders
if matproxy and matproxy.Add then
    matproxy.Add({
        name = "VoreGPUDeformer",
        init = function(self, mat, values)
            self.UniformCenter = values.resultvar or "$gore_center"
            self.UniformRadius = values.radiusvar or "$gore_radius"
            self.UniformIntensity = values.intensityvar or "$gore_intensity"
        end,
        bind = function(self, mat, ent)
            if not IsValid(ent) then return end
            mat:SetVector(self.UniformCenter, g_VoreStomachCenter or vector_origin)
            mat:SetFloat(self.UniformRadius, g_VoreRadius or 0)
            mat:SetFloat(self.UniformIntensity, g_VoreIntensity or 0)
        end
    })
end

-- 3D Wireframe & HUD Debug Visualizer
hook.Add("PostDrawTranslucentRenderables", "VNPCS_GPU_Vore_Debug3D", function()
    local dbg = GetConVar("vnpcs_gpu_vore_debug")
    if not dbg or not dbg:GetBool() then return end
    if not IsValid(g_ActivePredator) or g_VoreRadius <= 0 then return end

    render.SetColorMaterial()
    render.DrawWireframeSphere(g_VoreStomachCenter, g_VoreRadius, 16, 16, Color(255, 100, 255, 200), true)
    render.DrawSphere(g_VoreStomachCenter, 4, 8, 8, Color(255, 255, 0, 255))
end)

hook.Add("HUDPaint", "VNPCS_GPU_Vore_DebugHUD", function()
    local dbg = GetConVar("vnpcs_gpu_vore_debug")
    if not dbg or not dbg:GetBool() then return end

    local x, y = 20, 220
    surface.SetDrawColor(0, 0, 0, 180)
    surface.DrawRect(x, y, 320, 110)
    surface.SetDrawColor(255, 100, 255, 255)
    surface.DrawOutlinedRect(x, y, 320, 110, 2)

    draw.SimpleText("V-NPCs GPU Vore Shader Bridge Debug", "DermaDefaultBold", x + 10, y + 10, Color(255, 255, 0))
    local predName = IsValid(g_ActivePredator) and (g_ActivePredator.PrintName or g_ActivePredator:GetClass()) or "NONE"
    draw.SimpleText("Active Predator: " .. predName, "DermaDefault", x + 10, y + 30, Color(255, 255, 255))
    draw.SimpleText(string.format("Stomach Center: %.1f, %.1f, %.1f", g_VoreStomachCenter.x, g_VoreStomachCenter.y, g_VoreStomachCenter.z), "DermaDefault", x + 10, y + 50, Color(200, 255, 200))
    draw.SimpleText(string.format("Radius: %.1f | Intensity: %.1f", g_VoreRadius, g_VoreIntensity), "DermaDefault", x + 10, y + 70, Color(200, 220, 255))
    local preyN = (IsValid(g_ActivePredator) and g_ActivePredator.GetNWInt) and g_ActivePredator:GetNWInt("VNPC_GPUStruggleN", 0) or 0
    local gulpN = (IsValid(g_ActivePredator) and g_ActivePredator.GetNWInt) and g_ActivePredator:GetNWInt("VNPC_GPUGulpN", 0) or 0
    draw.SimpleText("Bound Materials: " .. g_UpdatedMaterialsCount .. " | Struggle: " .. (preyN * 4) .. " | Gulps: " .. gulpN, "DermaDefault", x + 10, y + 90, Color(255, 200, 255))
end)

concommand.Add("vnpcs_gpu_vore_status", function()
    print("===============================================================")
    print("         V-NPCs GPU VORE SHADER BRIDGE STATUS REPORT           ")
    print("===============================================================")
    local enabled = GetConVar("vnpcs_gpu_vore_shader_enabled")
    print(" - Bridge Enabled: " .. (enabled and enabled:GetString() or "0"))
    if IsValid(g_ActivePredator) then
        print(" - Active Predator: " .. tostring(g_ActivePredator) .. " (" .. (g_ActivePredator.PrintName or g_ActivePredator:GetClass()) .. ")")
        print(string.format(" - Stomach Center (World): %.2f, %.2f, %.2f", g_VoreStomachCenter.x, g_VoreStomachCenter.y, g_VoreStomachCenter.z))
        print(string.format(" - Deformation Radius: %.2f units", g_VoreRadius))
        print(string.format(" - Deformation Intensity: %.2f", g_VoreIntensity))
        print(" - Bound Materials Count: " .. g_UpdatedMaterialsCount)
    else
        print(" - Active Predator: NONE currently in view/range")
    end
    print("===============================================================")
end)

print("[V-NPCs] GPU Vore Shader Bridge initialized (cl_gpu_vore_bridge.lua)")

if not CLIENT then return end

--[[
    Garry's Mod GPU Vore Shader Bridge (cl_gpu_vore_bridge.lua)
    
    Bridges real-time belly expansion parameters (center, radius, intensity)
    from the active V-NPC / Player predator controller straight to the custom
    GPU vertex shader via ambient/lighting uniform registers and material proxies.
]]

CreateClientConVar("vnpcs_gpu_vore_shader_enabled", "1", true, false, "Enable GPU-based vertex deformation for vore bellies")
CreateClientConVar("vnpcs_gpu_vore_debug", "0", true, false, "Debug GPU vore uniform injection")

local g_VoreStomachCenter = Vector(0, 0, 0)
local g_VoreRadius = 0
local g_VoreIntensity = 0
local WHITE_VECTOR = Vector(1, 1, 1)

local function GetPredatorBellyData(predator)
    if not IsValid(predator) then return nil, 0, 0 end
    
    local belly = predator.VNPC_Belly or predator.Belly
    if not IsValid(belly) and predator.GetNWEntity then
        belly = predator:GetNWEntity("Belly")
    end
    
    local center = predator:WorldSpaceCenter()
    local radius = 30.0
    local intensity = 0.0
    
    if IsValid(belly) then
        local boneID = 1 -- Belly main bone anchor
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

    if IsValid(activePredator) then
        local center, radius, intensity = GetPredatorBellyData(activePredator)
        g_VoreStomachCenter = center
        g_VoreRadius = radius
        g_VoreIntensity = intensity

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

print("[V-NPCs] GPU Vore Shader Bridge initialized (cl_gpu_vore_bridge.lua)")

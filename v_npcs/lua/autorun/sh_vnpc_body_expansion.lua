-- V-NPCs Real-Time Dynamic Body Matrix (sh_vnpc_body_expansion.lua)
-- v0.7: no more per-model rigging for expansion. Any standard model is
-- analyzed on spawn (skeleton bones + measured body parts) and expanded
-- on-the-fly through per-region bone-scale envelopes - stomach, chest, hips,
-- thighs, calves and arms - driven by a single "bloat" value that combines
-- swallowed prey, drunk water, eaten food and monster growth.
--
-- Engine note: GMod cannot add/rewrite vertex weights on an existing model at
-- runtime, so true "vertex morphing" is approximated by what the engine CAN
-- do: virtual belly bones (sh_vnpc_gpu_belly.lua) + ManipulateBoneScale
-- envelopes on whatever bones the model actually has. This works on any
-- vanilla ragdoll model with a standard biped skeleton.
--
-- Also exports the LAYERED STRESS MAP used by the cloth-tear system
-- (cl_vnpc_cloth_tear.lua): each region (belly/chest/thigh) reports a 0..1+
-- tension value that rises once the bloat passes that region's clothing
-- capacity.

CreateConVar("vnpcs_body_expansion_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable on-the-fly body matrix expansion (chest/hips/thighs/calves/arms) on any model")
CreateConVar("vnpcs_body_expansion_amp", "1.0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Amplitude multiplier for the body expansion envelope")
CreateConVar("vnpcs_body_expansion_prey", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Also expand prey citizens from swallowed food/water bloat")

-- Region weights: how much each region expands per unit of bloat (0..1 scale
-- per region, multiplied by amp and capped so nothing explodes).
local REGION_WEIGHTS = {
    chest = 0.10,
    hips = 0.14,
    thigh = 0.12,
    calf = 0.06,
    upperArm = 0.05,
    forearm = 0.03
}

-- Clothing capacity per region: bloat above this starts stressing the fabric.
local REGION_CAPACITY = {
    belly = 0.85,
    chest = 1.30,
    thigh = 1.10
}

-- ---------------------------------------------------------------------------
-- Bloat amount: 0 = normal, ~1 = full belly, >1.5 = monster/extreme bloat
-- ---------------------------------------------------------------------------
function VNPC_GetBloatAmount(ent)
    if not IsValid(ent) then return 0 end

    local bloat = 0
    if VNPC_GetLiveBellySize then
        bloat = bloat + (VNPC_GetLiveBellySize(ent) or 0)
    end
    -- liquid + food bloat
    if VNPC_GetPredBelly then
        local belly = VNPC_GetPredBelly(ent)
        if IsValid(belly) then
            bloat = bloat + ((belly.VNPC_WaterWeight or 0) + (ent.VNPC_WaterDrank or 0)) / 90
            bloat = bloat + ((belly.VNPC_FoodMealWeight or 0) + (ent.VNPC_FoodMealWeight or 0)) / 110
        end
    end
    -- monster growth stages add permanent bulk
    if ent.VNPC_GrowthProgress then
        if ent.VNPC_GrowthProgress >= 200 then
            bloat = bloat + 0.6
        elseif ent.VNPC_GrowthProgress >= 150 then
            bloat = bloat + 0.3
        end
    end
    return math.max(0, bloat)
end

-- Per-region stress (0..1+, used by cloth tearing). tension = how far bloat
-- is past the region's clothing capacity, normalized.
function VNPC_GetClothStress(ent, region)
    if not IsValid(ent) then return 0 end
    local bloat = VNPC_GetBloatAmount(ent)
    local cap = REGION_CAPACITY[region] or REGION_CAPACITY.belly
    return math.max(0, (bloat - cap) / 0.9)
end

-- Per-region expansion multipliers (Vector for ManipulateBoneScale).
-- Returns { chest = Vector, hips = Vector, thighL, thighR, calfL, calfR,
--            upperArmL, upperArmR, forearmL, forearmR, stress = {...} }
function VNPC_GetBodyExpansion(ent)
    if not IsValid(ent) then return nil end
    local enabled = GetConVar("vnpcs_body_expansion_enabled")
    if enabled and not enabled:GetBool() then return nil end

    local bloat = VNPC_GetBloatAmount(ent)
    local amp = GetConVar("vnpcs_body_expansion_amp")
    local ampMul = amp and amp:GetFloat() or 1.0
    if ampMul <= 0 then return nil end
    if bloat <= 0.01 then return nil end

    -- smooth envelope: expansion starts gentle, accelerates with bloat
    local t = math.Clamp(bloat * 0.85, 0, 1.8)
    local env = (t ^ 1.15) * ampMul

    local function region(weight)
        return 1 + math.min(env * weight, 0.85)
    end

    return {
        bloat = bloat,
        chest = region(REGION_WEIGHTS.chest),
        hips = region(REGION_WEIGHTS.hips),
        thigh = region(REGION_WEIGHTS.thigh),
        calf = region(REGION_WEIGHTS.calf),
        upperArm = region(REGION_WEIGHTS.upperArm),
        forearm = region(REGION_WEIGHTS.forearm),
        stress = {
            belly = VNPC_GetClothStress(ent, "belly"),
            chest = VNPC_GetClothStress(ent, "chest"),
            thigh = VNPC_GetClothStress(ent, "thigh")
        }
    }
end

-- ---------------------------------------------------------------------------
-- Application (client-side per frame, cheap, no network chatter)
-- ---------------------------------------------------------------------------
local EXPANSION_BONES = {
    chest = { "ValveBiped.Bip01_Spine2", "Spine2", "spine2", "bip_spine_2" },
    hips = { "ValveBiped.Bip01_Pelvis", "Pelvis", "pelvis" },
    thighL = { "ValveBiped.Bip01_L_Thigh", "L_Thigh", "l_thigh" },
    thighR = { "ValveBiped.Bip01_R_Thigh", "R_Thigh", "r_thigh" },
    calfL = { "ValveBiped.Bip01_L_Calf", "L_Calf", "l_calf" },
    calfR = { "ValveBiped.Bip01_R_Calf", "R_Calf", "r_calf" },
    upperArmL = { "ValveBiped.Bip01_L_UpperArm", "L_UpperArm", "l_upperarm" },
    upperArmR = { "ValveBiped.Bip01_R_UpperArm", "R_UpperArm", "r_upperarm" },
    forearmL = { "ValveBiped.Bip01_L_Forearm", "L_Forearm", "l_forearm" },
    forearmR = { "ValveBiped.Bip01_R_Forearm", "R_Forearm", "r_forearm" }
}

local function expandLookup(ent, names)
    if not IsValid(ent) or not ent.LookupBone then return nil end
    for _, name in ipairs(names) do
        local id = ent:LookupBone(name)
        if id and id >= 0 then return id end
    end
    return nil
end

-- Applies the body matrix to a single entity. Call every frame on the client.
function VNPC_ApplyBodyExpansion(ent)
    if not IsValid(ent) or not ent.ManipulateBoneScale then return end
    local exp = VNPC_GetBodyExpansion(ent)
    if not exp then
        -- reset any previously applied expansion
        if ent.VNPC_BodyMatrixApplied then
            for key, names in pairs(EXPANSION_BONES) do
                local id = expandLookup(ent, names)
                if id then
                    ent:ManipulateBoneScale(id, Vector(1, 1, 1))
                end
            end
            ent.VNPC_BodyMatrixApplied = nil
        end
        return
    end

    local function apply(key, s)
        local names = EXPANSION_BONES[key]
        local id = expandLookup(ent, names)
        if id then
            ent:ManipulateBoneScale(id, Vector(s, s, s))
        end
    end

    -- axial bias: vertical (z) stretches less than girth (x/y) so limbs
    -- thicken rather than lengthen
    local function applyAxial(key, s)
        local names = EXPANSION_BONES[key]
        local id = expandLookup(ent, names)
        if id then
            ent:ManipulateBoneScale(id, Vector(s, s, 1 + (s - 1) * 0.55))
        end
    end

    local s = exp
    applyAxial("chest", s.chest)
    applyAxial("hips", s.hips)
    apply("thighL", s.thigh)
    apply("thighR", s.thigh)
    apply("calfL", s.calf)
    apply("calfR", s.calf)
    apply("upperArmL", s.upperArm)
    apply("upperArmR", s.upperArm)
    apply("forearmL", s.forearm)
    apply("forearmR", s.forearm)
    ent.VNPC_BodyMatrixApplied = true
end

-- ---------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------
if CLIENT then
    hook.Add("PreDrawOpaqueRenderables", "VNPC_BodyExpansion_Apply", function()
        local enabled = GetConVar("vnpcs_body_expansion_enabled")
        if enabled and not enabled:GetBool() then return end
        local preyOn = GetConVar("vnpcs_body_expansion_prey")
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            if not IsValid(ent) or ent:IsDormant() then continue end
            if ent.Predator or ent.VNPC_FemaleModelVore or ent.IsDrGNextbot or ent.VNPC_Belly or ent.Belly then
                VNPC_ApplyBodyExpansion(ent)
            elseif (not preyOn or preyOn:GetBool()) and VNPC_IsPreyNPC and VNPC_IsPreyNPC(ent) then
                VNPC_ApplyBodyExpansion(ent)
            end
        end
    end)
end

concommand.Add("vnpcs_body_matrix_status", function(ply)
    print("===============================================================")
    print("        V-NPCs REAL-TIME DYNAMIC BODY MATRIX (v0.7) STATUS     ")
    print("===============================================================")
    print(" - Expansion Enabled: " .. tostring(GetConVar("vnpcs_body_expansion_enabled"):GetBool()))
    print(" - Amplitude: " .. tostring(GetConVar("vnpcs_body_expansion_amp"):GetFloat()))
    print(" - Prey Expansion: " .. tostring(GetConVar("vnpcs_body_expansion_prey"):GetBool()))
    print("-----------------------------------------")
    local count = 0
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(ent) and (ent.Predator or ent.VNPC_FemaleModelVore or ent.IsDrGNextbot or ent.VNPC_Belly or ent.Belly or (VNPC_IsPreyNPC and VNPC_IsPreyNPC(ent))) then
            local bloat = VNPC_GetBloatAmount(ent)
            if bloat > 0.02 then
                count = count + 1
                local exp = VNPC_GetBodyExpansion(ent)
                local stress = exp and exp.stress or {}
                print(string.format(" -> #%d [%s] bloat=%.2f chest=%.2f hips=%.2f thigh=%.2f calf=%.2f arm=%.2f | stress B/C/T = %.2f/%.2f/%.2f",
                    ent:EntIndex(), ent.PrintName or ent:GetClass(), bloat,
                    exp and exp.chest or 1, exp and exp.hips or 1, exp and exp.thigh or 1,
                    exp and exp.calf or 1, exp and exp.upperArm or 1,
                    stress.belly or 0, stress.chest or 0, stress.thigh or 0))
            end
        end
    end
    if count == 0 then print(" - No bloated entities currently spawned.") end
    print("===============================================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Body matrix status printed to console. Bloated entities: " .. count)
    end
end)

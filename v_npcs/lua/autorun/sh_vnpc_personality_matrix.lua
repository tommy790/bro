-- V-NPCs Adaptive Personality Matrix (sh_vnpc_personality_matrix.lua)
-- v0.7: instead of one static personality per NPC, every NPC carries a mix of
-- behavioral axes (0..1 each): stealth, greed, shy, aggression, gentle,
-- playful. Sliders in the client menu write to the matrix; all behavior
-- systems read effective parameters through VNPC_GetBehaviorParam() so a
-- single NPC can be "90% assassin stealth / 40% greedy / 80% shy" at once.
--
-- Defaults are derived from the legacy personality system, so existing saves
-- and NPCs keep their character until the player edits the matrix.

CreateConVar("vnpcs_matrix_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable the adaptive personality matrix (behavioral axis mixing)")

VNPC_MATRIX_AXES = { "stealth", "greed", "shy", "aggression", "gentle", "playful" }

-- Default axis values per legacy personality.
local PERSONALITY_DEFAULTS = {
    aggressive = { aggression = 1.0, stealth = 0.15, greed = 0.4 },
    opportunistic = { aggression = 0.5, stealth = 0.45, greed = 0.6 },
    glutton = { greed = 1.0, aggression = 0.7 },
    shy = { shy = 1.0, stealth = 0.7, aggression = 0.2 },
    selective = { aggression = 0.6, stealth = 0.4, shy = 0.3 },
    gentle = { gentle = 1.0, aggression = 0.1 },
    loving = { gentle = 0.85, playful = 0.5, aggression = 0.05 },
    -- prey defaults (prey use struggle/stealth axes)
    fighter = { aggression = 0.8, stealth = 0.2 },
    passive = { gentle = 0.8 },
    panicked = { aggression = 0.4, stealth = 0.4 },
    stubborn = { aggression = 0.6, gentle = 0.3 },
    willing = { gentle = 0.9, playful = 0.6 },
    desire = { gentle = 0.9, playful = 0.6 },
    desirous = { gentle = 0.9, playful = 0.6 }
}

local function matrixEnabled()
    local cv = GetConVar("vnpcs_matrix_enabled")
    return not cv or cv:GetBool()
end

-- Returns the axis table { stealth = 0..1, greed = 0..1, ... } for an entity.
function VNPC_GetPersonalityMix(ent)
    if not IsValid(ent) then return {} end
    if not matrixEnabled() then
        ent.VNPC_Matrix = nil
        return {}
    end
    if ent.VNPC_Matrix then return ent.VNPC_Matrix end

    local mix = {}
    for _, axis in ipairs(VNPC_MATRIX_AXES) do
        mix[axis] = 0.0
    end
    -- seed from the legacy personality
    local pers = "opportunistic"
    if VNPC_IsPredatorEntity and VNPC_IsPredatorEntity(ent) then
        if VNPC_GetPredatorPersonality then
            pers = select(1, VNPC_GetPredatorPersonality(ent)) or "opportunistic"
        end
    elseif VNPC_GetPreyPersonality then
        pers = select(1, VNPC_GetPreyPersonality(ent)) or "fighter"
    end
    local defs = PERSONALITY_DEFAULTS[pers] or PERSONALITY_DEFAULTS.opportunistic
    for axis, val in pairs(defs) do
        mix[axis] = math.Clamp(val, 0, 1)
    end
    ent.VNPC_Matrix = mix
    return mix
end

function VNPC_SetMatrixAxis(ent, axis, val)
    if not IsValid(ent) or not axis then return end
    local ok = false
    for _, a in ipairs(VNPC_MATRIX_AXES) do
        if a == axis then ok = true break end
    end
    if not ok then return end
    local mix = VNPC_GetPersonalityMix(ent)
    mix[axis] = math.Clamp(tonumber(val) or 0, 0, 1)
    ent.VNPC_Matrix = mix
    if SERVER and ent.SetNWString then
        ent:SetNWString("VNPC_Matrix", VNPC_SerializeMatrix(mix))
    end
end

function VNPC_SerializeMatrix(mix)
    local parts = {}
    for _, axis in ipairs(VNPC_MATRIX_AXES) do
        table.insert(parts, axis .. "=" .. string.format("%.2f", mix[axis] or 0))
    end
    return table.concat(parts, ",")
end

function VNPC_DeserializeMatrix(str)
    local mix = {}
    for _, axis in ipairs(VNPC_MATRIX_AXES) do
        mix[axis] = 0
    end
    if isstring(str) then
        for pair in string.gmatch(str, "([^,]+)") do
            local axis, val = pair:match("(%w+)=([%d%.]+)")
            if axis and val then
                for _, a in ipairs(VNPC_MATRIX_AXES) do
                    if a == axis then
                        mix[a] = math.Clamp(tonumber(val) or 0, 0, 1)
                    end
                end
            end
        end
    end
    return mix
end

-- Client: read the replicated matrix (fall back to local).
function VNPC_GetMatrixFromNW(ent)
    if not IsValid(ent) then return {} end
    local str = ent.GetNWString and ent:GetNWString("VNPC_Matrix", "") or ""
    if str ~= "" then
        return VNPC_DeserializeMatrix(str)
    end
    return VNPC_GetPersonalityMix(ent)
end

-- Effective behavior parameters derived from the axis mix. All systems read
-- through this, so slider changes take effect immediately.
function VNPC_GetBehaviorParam(ent, param)
    if not IsValid(ent) then return 1.0 end
    local mix = VNPC_GetPersonalityMix(ent)
    local s, g, sh, ag, ge, pl = mix.stealth or 0, mix.greed or 0, mix.shy or 0, mix.aggression or 0, mix.gentle or 0, mix.playful or 0

    if param == "digestion_multiplier" then
        return math.Clamp((1 + g * 0.9) * (1 - ge * 0.55), 0.35, 2.0)
    elseif param == "range_multiplier" then
        return 0.8 + ag * 0.5 + s * 0.25
    elseif param == "require_unseen" then
        return sh >= 0.45
    elseif param == "ambush" then
        return math.Clamp(s * 0.8 + sh * 0.2, 0, 1)
    elseif param == "pin" then
        return math.Clamp(ag * 0.7 + g * 0.3, 0, 1)
    elseif param == "camouflage" then
        return math.Clamp(sh * 0.6 + s * 0.4, 0, 1)
    elseif param == "only_enemies" then
        return ag < 0.3 and g < 0.4
    elseif param == "prefer_weakened" then
        return math.Clamp(g * 0.5 + (1 - ag) * 0.3, 0, 1)
    elseif param == "struggle_energy" then
        return math.Clamp(0.5 + ag * 1.3, 0.4, 1.9)
    elseif param == "playful" then
        return pl
    end
    return 1.0
end

hook.Add("OnEntityCreated", "VNPC_Matrix_SeedFromNW", function(ent)
    timer.Simple(0.1, function()
        if not IsValid(ent) then return end
        if not (ent:IsNPC() or ent:IsNextBot() or ent.IsDrGNextbot) then return end
        -- local mix (server-side authoritative); NW will replicate to clients
        VNPC_GetPersonalityMix(ent)
    end)
end)

if SERVER then
    local function findTarget(ply, entIndex)
        if not IsValid(ply) then return nil end
        if entIndex then
            local ent = Entity(tonumber(entIndex) or 0)
            if IsValid(ent) then return ent end
        end
        local tr = ply:GetEyeTrace()
        if tr and IsValid(tr.Entity) then return tr.Entity end
        return nil
    end

    concommand.Add("vnpcs_matrix_set", function(ply, _, args)
        local ent = findTarget(ply, args and args[1])
        local axis = args and args[2]
        local val = tonumber(args and args[3])
        if not IsValid(ent) or not axis or not val then
            if IsValid(ply) then ply:ChatPrint("[V-NPCs] Usage: vnpcs_matrix_set <entindex|aimed> <axis> <0..1>") end
            return
        end
        VNPC_SetMatrixAxis(ent, string.lower(axis), val)
        if IsValid(ply) then
            ply:ChatPrint(string.format("[V-NPCs] %s matrix %s = %.2f", tostring(ent), string.lower(axis), val))
        end
    end)

    concommand.Add("vnpcs_matrix_clear", function(ply, _, args)
        local ent = findTarget(ply, args and args[1])
        if not IsValid(ent) then
            if IsValid(ply) then ply:ChatPrint("[V-NPCs] Aim at an NPC or pass an entindex.") end
            return
        end
        local pers = "opportunistic"
        if VNPC_GetPredatorPersonality and VNPC_IsPredatorEntity and VNPC_IsPredatorEntity(ent) then
            pers = select(1, VNPC_GetPredatorPersonality(ent)) or "opportunistic"
        end
        ent.VNPC_Matrix = nil
        VNPC_GetPersonalityMix(ent)
        if IsValid(ply) then
            ply:ChatPrint("[V-NPCs] Reset " .. tostring(ent) .. " matrix to personality defaults (" .. pers .. ").")
        end
    end)

    concommand.Add("vnpcs_matrix_status", function(ply)
        print("===============================================================")
        print("        V-NPCs ADAPTIVE PERSONALITY MATRIX (v0.7) STATUS      ")
        print("===============================================================")
        print(" - Matrix Enabled: " .. tostring(GetConVar("vnpcs_matrix_enabled"):GetBool()))
        local count = 0
        local function printEnt(ent)
            local mix = VNPC_GetPersonalityMix(ent)
            local parts = {}
            for _, axis in ipairs(VNPC_MATRIX_AXES) do
                table.insert(parts, string.format("%s=%.2f", axis, mix[axis] or 0))
            end
            print(string.format(" -> #%d [%s] %s", ent:EntIndex(), ent.PrintName or ent:GetClass(), table.concat(parts, " ")))
            print(string.format("      digest=%.2fx range=%.2fx unseen=%s ambush=%.2f pin=%.2f camo=%.2f",
                VNPC_GetBehaviorParam(ent, "digestion_multiplier"),
                VNPC_GetBehaviorParam(ent, "range_multiplier"),
                tostring(VNPC_GetBehaviorParam(ent, "require_unseen")),
                VNPC_GetBehaviorParam(ent, "ambush"),
                VNPC_GetBehaviorParam(ent, "pin"),
                VNPC_GetBehaviorParam(ent, "camouflage")))
        end
        local target = nil
        if IsValid(ply) then
            local tr = ply:GetEyeTrace()
            if tr and IsValid(tr.Entity) then target = tr.Entity end
        end
        if IsValid(target) then
            printEnt(target)
            count = 1
        else
            for _, ent in ipairs(ents.GetAll()) do
                if IsValid(ent) and not ent:IsPlayer() and (ent:IsNPC() or ent:IsNextBot() or ent.IsDrGNextbot) then
                    printEnt(ent)
                    count = count + 1
                end
            end
        end
        if count == 0 then print(" - No NPCs spawned (or aim at one).") end
        print("===============================================================")
        if IsValid(ply) then
            ply:ChatPrint("[V-NPCs] Personality matrix status printed to console.")
        end
    end)
end

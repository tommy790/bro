--[[
    Predator and Prey Personalities System for V-NPCs
]]

CreateConVar("vnpcs_default_predator_personality", "random", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Default predator personality (random, opportunistic, aggressive, glutton, shy, selective, gentle)")
CreateConVar("vnpcs_default_prey_personality", "random", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Default prey personality (random, fighter, passive, panicked, stubborn, willing)")
CreateConVar("vnpcs_personalities_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable predator and prey personalities")

VNPC_PREDATOR_PERSONALITIES = {
    ["aggressive"] = {
        name = "Aggressive",
        description = "Actively hunts and chases targets.",
        range_multiplier = 1.5,
        grab_multiplier = 1.2,
        only_enemies = false,
        prefer_weakened = false,
        require_unseen = false,
        digestion_multiplier = 1.2
    },
    ["opportunistic"] = {
        name = "Opportunistic",
        description = "Prefers weakened or isolated prey.",
        range_multiplier = 1.0,
        grab_multiplier = 1.0,
        only_enemies = false,
        prefer_weakened = true,
        require_unseen = false,
        digestion_multiplier = 1.0
    },
    ["glutton"] = {
        name = "Glutton",
        description = "Indiscriminate eater with fast digestion.",
        range_multiplier = 1.25,
        grab_multiplier = 1.25,
        only_enemies = false,
        prefer_weakened = false,
        require_unseen = false,
        digestion_multiplier = 1.5
    },
    ["shy"] = {
        name = "Shy / Secretive",
        description = "Only eats when unobserved by witnesses. Uses shy defensive belly bone-pose animations.",
        range_multiplier = 0.8,
        grab_multiplier = 1.0,
        only_enemies = false,
        prefer_weakened = false,
        require_unseen = true,
        digestion_multiplier = 1.0,
        animated_bone_list = "shy"
    },
    ["selective"] = {
        name = "Selective",
        description = "Only targets direct enemies.",
        range_multiplier = 1.0,
        grab_multiplier = 1.0,
        only_enemies = true,
        prefer_weakened = false,
        require_unseen = false,
        digestion_multiplier = 1.0
    },
    ["gentle"] = {
        name = "Gentle",
        description = "Slower digestion and playful behavior.",
        range_multiplier = 0.9,
        grab_multiplier = 1.0,
        only_enemies = false,
        prefer_weakened = false,
        require_unseen = false,
        digestion_multiplier = 0.6
    },
    ["loving"] = {
        name = "Loving / Affectionate",
        description = "Extremely gentle 0.1x digestion; loves willing male mates and often wanders solitary in the wild.",
        range_multiplier = 0.9,
        grab_multiplier = 1.0,
        only_enemies = false,
        prefer_weakened = false,
        require_unseen = false,
        digestion_multiplier = 0.1,
        loving = true
    }
}

VNPC_PREY_PERSONALITIES = {
    ["willing"] = {
        name = "Willing / Desirous",
        description = "Actively desires to be swallowed and does not struggle.",
        struggle_multiplier = 0.0,
        digestion_resistance = 1.0,
        flee_predator = false,
        seek_predator = true,
        willing = true
    },
    ["desire"] = {
        name = "Desirous / Willing",
        description = "Actively desires to be swallowed and does not struggle.",
        struggle_multiplier = 0.0,
        digestion_resistance = 1.0,
        flee_predator = false,
        seek_predator = true,
        willing = true
    },
    ["desirous"] = {
        name = "Desirous / Willing",
        description = "Actively desires to be swallowed and does not struggle.",
        struggle_multiplier = 0.0,
        digestion_resistance = 1.0,
        flee_predator = false,
        seek_predator = true,
        willing = true
    },
    ["fighter"] = {
        name = "Fighter",
        description = "Struggles vigorously inside the belly.",
        struggle_multiplier = 1.8,
        digestion_resistance = 1.0,
        flee_predator = false
    },
    ["passive"] = {
        name = "Passive",
        description = "Submissive and quiet inside the belly.",
        struggle_multiplier = 0.5,
        digestion_resistance = 1.0,
        flee_predator = false
    },
    ["panicked"] = {
        name = "Panicked",
        description = "Flees from predators and struggles rapidly.",
        struggle_multiplier = 1.4,
        digestion_resistance = 0.9,
        flee_predator = true
    },
    ["stubborn"] = {
        name = "Stubborn / Resilient",
        description = "Resistant to digestion damage.",
        struggle_multiplier = 1.0,
        digestion_resistance = 0.6,
        flee_predator = false
    }
}

local VNPC_PREDATOR_PERS_LIST = {
    "aggressive",
    "opportunistic",
    "glutton",
    "shy",
    "selective",
    "gentle",
    "loving"
}

local VNPC_PREY_PERS_LIST = {
    "willing",
    "fighter",
    "passive",
    "panicked",
    "stubborn"
}

function VNPC_GetPredatorPersonality(ent)
    if not IsValid(ent) then return "opportunistic", VNPC_PREDATOR_PERSONALITIES["opportunistic"] end
    local pers = ent.VNPC_PredatorPersonality or (ent.VoreSettings and ent.VoreSettings.PredatorPersonality)
    if not pers or not VNPC_PREDATOR_PERSONALITIES[pers] then
        local default_pers = GetConVar("vnpcs_default_predator_personality")
        pers = default_pers and string.lower(default_pers:GetString() or "random") or "random"
        if pers == "random" or pers == "randomize" or pers == "" or not VNPC_PREDATOR_PERSONALITIES[pers] then
            pers = VNPC_PREDATOR_PERS_LIST[math.random(1, #VNPC_PREDATOR_PERS_LIST)]
            ent.VNPC_PredatorPersonality = pers
            if ent.VoreSettings then ent.VoreSettings.PredatorPersonality = pers end
        end
    end
    return pers, VNPC_PREDATOR_PERSONALITIES[pers]
end

function VNPC_SetPredatorPersonality(ent, pers_name)
    if not IsValid(ent) or not isstring(pers_name) then return end
    pers_name = string.lower(pers_name)
    if VNPC_PREDATOR_PERSONALITIES[pers_name] then
        ent.VNPC_PredatorPersonality = pers_name
        if ent.VoreSettings then ent.VoreSettings.PredatorPersonality = pers_name end
    end
end

function VNPC_GetPreyPersonality(ent)
    if not IsValid(ent) then return "fighter", VNPC_PREY_PERSONALITIES["fighter"] end
    local pers = ent.VNPC_PreyPersonality or ent.PreyPersonality
    if not pers or not VNPC_PREY_PERSONALITIES[pers] then
        local default_pers = GetConVar("vnpcs_default_prey_personality")
        pers = default_pers and string.lower(default_pers:GetString() or "random") or "random"
        if pers == "random" or pers == "randomize" or pers == "" or not VNPC_PREY_PERSONALITIES[pers] then
            pers = VNPC_PREY_PERS_LIST[math.random(1, #VNPC_PREY_PERS_LIST)]
            ent.VNPC_PreyPersonality = pers
            ent.PreyPersonality = pers
        end
    end
    return pers, VNPC_PREY_PERSONALITIES[pers]
end

function VNPC_SetPreyPersonality(ent, pers_name)
    if not IsValid(ent) or not isstring(pers_name) then return end
    pers_name = string.lower(pers_name)
    if VNPC_PREY_PERSONALITIES[pers_name] then
        ent.VNPC_PreyPersonality = pers_name
        ent.PreyPersonality = pers_name
    end
end

function VNPC_RandomizePersonalities(ent)
    if not IsValid(ent) then return end
    local pred_pers = VNPC_PREDATOR_PERS_LIST[math.random(1, #VNPC_PREDATOR_PERS_LIST)]
    local prey_pers = VNPC_PREY_PERS_LIST[math.random(1, #VNPC_PREY_PERS_LIST)]
    ent.VNPC_PredatorPersonality = pred_pers
    if ent.VoreSettings then ent.VoreSettings.PredatorPersonality = pred_pers end
    ent.VNPC_PreyPersonality = prey_pers
    ent.PreyPersonality = prey_pers
    if VNPC_AssignMateAttraction then
        VNPC_AssignMateAttraction(ent)
    end
    return pred_pers, prey_pers
end

hook.Add("OnEntityCreated", "VNPC_AutoRandomizePersonalities", function(ent)
    timer.Simple(0.1, function()
        if not IsValid(ent) then return end
        if ent:IsNPC() or ent:IsPlayer() then
            if ent.Predator or ent.VNPC_FemaleModelVore or (VNPC_IsFemaleModelNPC and VNPC_IsFemaleModelNPC(ent)) then
                VNPC_GetPredatorPersonality(ent)
            end
            VNPC_GetPreyPersonality(ent)
        end
    end)
end)

concommand.Add("vnpcs_set_loving", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a female V-NPC predator to set her personality to LOVING!")
        return
    end
    VNPC_SetPredatorPersonality(target, "loving")
    ply:ChatPrint("[V-NPCs] Set " .. tostring(target) .. "'s personality to LOVING (0.1x digestion, affectionate toward mates, wild preference)!")
end)

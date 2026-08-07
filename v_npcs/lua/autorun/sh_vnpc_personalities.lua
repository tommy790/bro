--[[
    Predator and Prey Personalities System for V-NPCs
]]

CreateConVar("vnpcs_default_predator_personality", "opportunistic", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Default predator personality")
CreateConVar("vnpcs_default_prey_personality", "fighter", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Default prey personality")
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

function VNPC_GetPredatorPersonality(ent)
    if not IsValid(ent) then return "opportunistic", VNPC_PREDATOR_PERSONALITIES["opportunistic"] end
    local pers = ent.VNPC_PredatorPersonality or (ent.VoreSettings and ent.VoreSettings.PredatorPersonality)
    if not pers or not VNPC_PREDATOR_PERSONALITIES[pers] then
        local default_pers = GetConVar("vnpcs_default_predator_personality")
        pers = default_pers and default_pers:GetString() or "opportunistic"
        if not VNPC_PREDATOR_PERSONALITIES[pers] then pers = "opportunistic" end
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
        pers = default_pers and default_pers:GetString() or "fighter"
        if not VNPC_PREY_PERSONALITIES[pers] then pers = "fighter" end
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

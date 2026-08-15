-- V-NPCs Modular Status & Trait System (sh_vnpc_traits.lua)
-- Assignable RPG-style traits on top of personalities. Traits modify real gameplay
-- stats: metabolism (digestion speed), acid resistance (prey), max capacity,
-- weight/stamina penalties, perception, struggle energy, and aggression.
--
-- Stat model: every stat is a multiplier. 1.0 = baseline, 1.5 = +50%, 0.6 = -40%.
-- VNPC_GetTraitStat(ent, "metabolism") is safe to call from anywhere on both realms.

CreateConVar("vnpcs_traits_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable the modular trait system for V-NPCs")
CreateConVar("vnpcs_traits_random_chance", "0.45", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Chance an NPC spawns with random traits (0-1)")

-- stat ids used by the rest of the addon:
--   metabolism       -> digestion speed of a predator (multiplier on damage/sec)
--   acid_resistance  -> multiplier on digestion damage a prey takes (lower = tougher)
--   capacity         -> belly max capacity multiplier
--   weight_resistance-> how well a predator ignores carried weight (slowdown divisor)
--   struggle_energy  -> how hard a prey struggles inside the belly
--   perception       -> hearing + sight range multiplier (noise/flashlight tracking)
--   night_vision     -> sight range multiplier at night
--   stealth          -> how quiet this entity is (reduces noise radius it emits)
--   aggression       -> target scoring / hunt willingness multiplier

VNPC_TRAITS = VNPC_TRAITS or {
    -- == Predator traits ==
    fast_metabolism = {
        name = "Fast Metabolism",
        kind = "predator",
        description = "Digests prey 50% faster, but burns belly mass quicker and is hungrier.",
        stats = { metabolism = 1.5, aggression = 1.15 },
        conflicts = { "slow_metabolism", "delicate" }
    },
    slow_metabolism = {
        name = "Slow Metabolism",
        kind = "predator",
        description = "Digests prey 35% slower. Keeps a full belly warm for a long time.",
        stats = { metabolism = 0.65 },
        conflicts = { "fast_metabolism" }
    },
    big_stomach = {
        name = "Big Stomach",
        kind = "predator",
        description = "+40% belly capacity and handles heavy loads better.",
        stats = { capacity = 1.4, weight_resistance = 1.2 },
        conflicts = { "small_stomach", "dainty" }
    },
    small_stomach = {
        name = "Small Stomach",
        kind = "predator",
        description = "-30% capacity, but the tight squeeze digests prey 20% faster.",
        stats = { capacity = 0.7, metabolism = 1.2 },
        conflicts = { "big_stomach" }
    },
    iron_stomach = {
        name = "Iron Stomach",
        kind = "predator",
        description = "+25% digestion speed and resists being digested (+20% acid resistance).",
        stats = { metabolism = 1.25, acid_resistance = 1.2 },
        conflicts = { "delicate" }
    },
    delicate = {
        name = "Delicate Stomach",
        kind = "predator",
        description = "-25% digestion speed and heavy meals slow you down more.",
        stats = { metabolism = 0.75, weight_resistance = 0.75 },
        conflicts = { "iron_stomach", "fast_metabolism" }
    },
    tireless = {
        name = "Tireless",
        kind = "predator",
        description = "Carries heavy bellies with ease: -60% weight slowdown penalty.",
        stats = { weight_resistance = 1.6 },
        conflicts = { "heavy_body" }
    },
    heavy_body = {
        name = "Heavy Body",
        kind = "predator",
        description = "Slow and massive: +15% capacity but -30% weight resistance.",
        stats = { capacity = 1.15, weight_resistance = 0.7 },
        conflicts = { "tireless" }
    },
    glutton = {
        name = "Glutton",
        kind = "predator",
        description = "+25% capacity, +25% metabolism, always hunting.",
        stats = { capacity = 1.25, metabolism = 1.25, aggression = 1.2 },
        conflicts = { "dainty", "slow_metabolism" }
    },
    dainty = {
        name = "Dainty",
        kind = "predator",
        description = "Small appetite: -20% capacity, -40% metabolism, rarely hunts.",
        stats = { capacity = 0.8, metabolism = 0.6, aggression = 0.75 },
        conflicts = { "glutton", "big_stomach" }
    },
    keen_ears = {
        name = "Keen Ears",
        kind = "predator",
        description = "+60% perception. Hears footsteps and flashlight-hunting is easier.",
        stats = { perception = 1.6 },
        conflicts = { "deaf" }
    },
    deaf = {
        name = "Deaf",
        kind = "predator",
        description = "-50% perception. Relies on sight alone.",
        stats = { perception = 0.5 },
        conflicts = { "keen_ears" }
    },
    night_hunter = {
        name = "Night Hunter",
        kind = "predator",
        description = "Sees in the dark: +100% night vision, +10% metabolism.",
        stats = { night_vision = 2.0, metabolism = 1.1 }
    },
    sneaky = {
        name = "Sneaky",
        kind = "predator",
        description = "Moves quietly (+50% stealth) and tracks prey better.",
        stats = { stealth = 1.5, perception = 1.2 }
    },
    brave_hunter = {
        name = "Brave Hunter",
        kind = "predator",
        description = "+40% aggression and +25% night vision. Ambushes without hesitation.",
        stats = { aggression = 1.4, night_vision = 1.25 }
    },
    cowardly = {
        name = "Cowardly",
        kind = "predator",
        description = "-50% aggression. Prefers easy, isolated meals.",
        stats = { aggression = 0.5 }
    },

    -- == Prey traits ==
    acid_resistant = {
        name = "Acid Resistant",
        kind = "prey",
        description = "Digests 60% slower. Stomach acid barely phases this one.",
        stats = { acid_resistance = 1.6 },
        conflicts = { "weak_stomach" }
    },
    weak_stomach = {
        name = "Weak Stomach",
        kind = "prey",
        description = "Digests 30% faster. Melts like butter.",
        stats = { acid_resistance = 0.7 },
        conflicts = { "acid_resistant", "tough" }
    },
    tough = {
        name = "Tough",
        kind = "prey",
        description = "+30% acid resistance and struggles 15% harder.",
        stats = { acid_resistance = 1.3, struggle_energy = 1.15 },
        conflicts = { "weak_stomach" }
    },
    restless = {
        name = "Restless",
        kind = "prey",
        description = "Struggles 50% harder inside the belly.",
        stats = { struggle_energy = 1.5 },
        conflicts = { "docile" }
    },
    docile = {
        name = "Docile",
        kind = "prey",
        description = "Struggles 40% less. Barely disturbs the belly.",
        stats = { struggle_energy = 0.6 },
        conflicts = { "restless" }
    },
    light_footed = {
        name = "Light-Footed",
        kind = "prey",
        description = "+60% stealth. Footsteps barely make a sound.",
        stats = { stealth = 1.6 },
        conflicts = { "clumsy" }
    },
    clumsy = {
        name = "Clumsy",
        kind = "prey",
        description = "-50% stealth. Every step is a noise event.",
        stats = { stealth = 0.5 },
        conflicts = { "light_footed" }
    },

    -- == Shared / special ==
    starving = {
        name = "Starving",
        kind = "any",
        description = "+30% metabolism, +20% aggression. Always hungry.",
        stats = { metabolism = 1.3, aggression = 1.2 }
    },
    well_fed = {
        name = "Well-Fed",
        kind = "any",
        description = "-25% metabolism and -25% aggression. Content and lazy.",
        stats = { metabolism = 0.75, aggression = 0.75 }
    }
}

local TRAIT_IDS = {}
for id in pairs(VNPC_TRAITS) do
    table.insert(TRAIT_IDS, id)
end

local PREDATOR_TRAITS, PREY_TRAITS = {}, {}
for id, data in pairs(VNPC_TRAITS) do
    if data.kind == "predator" or data.kind == "any" then
        table.insert(PREDATOR_TRAITS, id)
    end
    if data.kind == "prey" or data.kind == "any" then
        table.insert(PREY_TRAITS, id)
    end
end

function VNPC_IsPredatorEntity(ent)
    if not IsValid(ent) then return false end
    if ent.Predator or ent.VNPC_FemaleModelVore or ent.IsDrGNextbot or ent.EatEntity ~= nil then
        return true
    end
    -- Universal roles: any female is a predator (custom NPCs included).
    if VNPC_ShouldBePredator and VNPC_ShouldBePredator(ent) then
        return true
    end
    return false
end

-- Returns the trait table { id = true } for an entity, initializing on first call.
function VNPC_GetTraits(ent)
    if not IsValid(ent) then return {} end
    if ent.VNPC_Traits == nil then
        ent.VNPC_Traits = {}
        local enabled = GetConVar("vnpcs_traits_enabled")
        if not enabled or enabled:GetBool() then
            local chance = GetConVar("vnpcs_traits_random_chance")
            if (chance and chance:GetFloat() or 0.45) > math.random() then
                VNPC_RollRandomTraits(ent)
            end
        end
    end
    return ent.VNPC_Traits
end

-- Ordered list of trait ids (used for the replicated string).
function VNPC_GetTraitList(ent)
    local list = {}
    for id in pairs(VNPC_GetTraits(ent)) do
        table.insert(list, id)
    end
    table.sort(list)
    return list
end

function VNPC_HasTrait(ent, id)
    if not IsValid(ent) or not VNPC_TRAITS[id] then return false end
    return VNPC_GetTraits(ent)[id] == true
end

local function syncTraitsNW(ent)
    if not IsValid(ent) or not ent.SetNWString then return end
    local list = VNPC_GetTraitList(ent)
    ent:SetNWString("VNPC_Traits", table.concat(list, ","))
    if ent.SetNWInt then
        ent:SetNWInt("VNPC_TraitCount", #list)
    end
end

function VNPC_AddTrait(ent, id, silent)
    if not IsValid(ent) or not VNPC_TRAITS[id] then return false end
    local enabled = GetConVar("vnpcs_traits_enabled")
    if enabled and not enabled:GetBool() then return false end

    local traits = VNPC_GetTraits(ent)
    if traits[id] then return false end

    local data = VNPC_TRAITS[id]
    -- "any" traits work everywhere; predator traits only on predators, prey
    -- traits only on non-predators
    if data.kind == "predator" and not VNPC_IsPredatorEntity(ent) then return false end
    if data.kind == "prey" and VNPC_IsPredatorEntity(ent) then return false end

    -- Resolve conflicts both ways: remove traits the new one conflicts with,
    -- and remove existing traits that list the new one as a conflict.
    if data.conflicts then
        for _, cid in ipairs(data.conflicts) do
            traits[cid] = nil
        end
    end
    for existingId in pairs(traits) do
        local existingData = VNPC_TRAITS[existingId]
        if existingData and existingData.conflicts then
            for _, cid in ipairs(existingData.conflicts) do
                if cid == id then
                    traits[existingId] = nil
                end
            end
        end
    end

    traits[id] = true
    syncTraitsNW(ent)

    if SERVER and not silent then
        print(string.format("[V-NPCs] Trait added: %s [%s] +%s", tostring(ent), ent.PrintName or ent:GetClass(), id))
        hook.Run("VNPC_OnTraitAdded", ent, id)
    end
    return true
end

function VNPC_RemoveTrait(ent, id)
    if not IsValid(ent) or not VNPC_TRAITS[id] then return false end
    local traits = VNPC_GetTraits(ent)
    if not traits[id] then return false end
    traits[id] = nil
    syncTraitsNW(ent)
    if SERVER then
        print(string.format("[V-NPCs] Trait removed: %s [%s] -%s", tostring(ent), ent.PrintName or ent:GetClass(), id))
        hook.Run("VNPC_OnTraitRemoved", ent, id)
    end
    return true
end

function VNPC_ClearTraits(ent)
    if not IsValid(ent) then return end
    ent.VNPC_Traits = {}
    syncTraitsNW(ent)
end

-- Multiplier for a stat, e.g. VNPC_GetTraitStat(pred, "metabolism") -> 1.5
function VNPC_GetTraitStat(ent, stat)
    if not IsValid(ent) then return 1.0 end
    local traits = ent.VNPC_Traits
    if not traits then return 1.0 end
    local mult = 1.0
    for id in pairs(traits) do
        local data = VNPC_TRAITS[id]
        if data and data.stats and data.stats[stat] then
            mult = mult * (data.stats[stat] or 1.0)
        end
    end
    return math.Clamp(mult, 0.05, 5.0)
end

-- Combined human-readable stat summary, e.g. { metabolism = 1.3, ... }
function VNPC_GetTraitStatSummary(ent)
    local summary = {}
    local stats = { "metabolism", "acid_resistance", "capacity", "weight_resistance", "struggle_energy", "perception", "night_vision", "stealth", "aggression" }
    for _, stat in ipairs(stats) do
        local v = VNPC_GetTraitStat(ent, stat)
        if math.abs(v - 1.0) > 0.001 then
            summary[stat] = v
        end
    end
    return summary
end

-- Personality-aware random trait roll (called on spawn when the cvar allows it).
function VNPC_RollRandomTraits(ent)
    if not IsValid(ent) then return 0 end
    local pool
    if VNPC_IsPredatorEntity(ent) then
        pool = PREDATOR_TRAITS
    else
        pool = PREY_TRAITS
    end

    -- Personality biasing: certain personalities favor certain traits.
    local bias = {}
    if VNPC_GetPredatorPersonality then
        local pers = select(1, VNPC_GetPredatorPersonality(ent))
        if pers == "aggressive" or pers == "glutton" then
            bias = { "fast_metabolism", "glutton", "brave_hunter", "iron_stomach" }
        elseif pers == "shy" then
            bias = { "sneaky", "slow_metabolism" }
        elseif pers == "gentle" or pers == "loving" then
            bias = { "delicate", "slow_metabolism" }
        elseif pers == "opportunistic" then
            bias = { "keen_ears", "tireless" }
        end
    elseif VNPC_GetPreyPersonality then
        local pers = select(1, VNPC_GetPreyPersonality(ent))
        if pers == "fighter" then
            bias = { "restless", "tough" }
        elseif pers == "panicked" then
            bias = { "restless", "clumsy" }
        elseif pers == "stubborn" then
            bias = { "acid_resistant", "tough" }
        elseif pers == "willing" or pers == "desirous" then
            bias = { "docile", "light_footed" }
        elseif pers == "passive" then
            bias = { "docile" }
        end
    end

    local count = 0
    local chosen = {}
    -- 40% of the time the trait comes from the personality bias pool
    if #bias > 0 and math.random() < 0.4 then
        local id = bias[math.random(#bias)]
        if VNPC_TRAITS[id] and VNPC_AddTrait(ent, id, true) then
            chosen[id] = true
            count = count + 1
        end
    end
    -- Then 1-2 fully random traits that do not conflict
    local extra = math.random(1, 2)
    for _ = 1, extra do
        local tries = 0
        while tries < 6 do
            tries = tries + 1
            local id = pool[math.random(#pool)]
            if not chosen[id] and VNPC_AddTrait(ent, id, true) then
                chosen[id] = true
                count = count + 1
                break
            end
        end
    end

    if count > 0 then
        syncTraitsNW(ent)
        if SERVER then
            print(string.format("[V-NPCs] Traits rolled for %s [%s]: %s", tostring(ent), ent.PrintName or ent:GetClass(), table.concat(VNPC_GetTraitList(ent), ", ")))
        end
    end
    return count
end

hook.Add("OnEntityCreated", "VNPC_AutoRollTraits", function(ent)
    timer.Simple(0.2, function()
        if not IsValid(ent) then return end
        if not (ent:IsNPC() or ent:IsNextBot() or ent:IsPlayer()) then return end
        if ent.VNPC_SkipTraits then return end
        if ent:IsPlayer() then return end
        local enabled = GetConVar("vnpcs_traits_enabled")
        if enabled and not enabled:GetBool() then return end
        -- Only vore-relevant entities get traits (preds and citizen-like prey)
        if VNPC_IsPredatorEntity(ent) or VNPC_IsPreyNPC and VNPC_IsPreyNPC(ent) or ent.VNPC_PreyCampID then
            VNPC_RollRandomTraits(ent)
        end
    end)
end)

-- OnEntityCreated is also the perfect place to restore traits after save/load
-- style parenting, but NPCs do not persist in this addon; nothing to do.

concommand.Add("vnpcs_trait_status", function(ply, _, args)
    print("===============================================================")
    print("            V-NPCs MODULAR STATUS & TRAIT SYSTEM               ")
    print("===============================================================")
    print(" - Traits Enabled: " .. tostring(GetConVar("vnpcs_traits_enabled"):GetBool()))
    print(" - Random Roll Chance: " .. tostring(GetConVar("vnpcs_traits_random_chance"):GetFloat()))
    print(" - Registered Traits: " .. #TRAIT_IDS .. " (" .. #PREDATOR_TRAITS .. " predator, " .. #PREY_TRAITS .. " prey/shared)")
    print("-----------------------------------------")
    local target = nil
    local entIndex = tonumber(args and args[1])
    if entIndex then
        target = Entity(entIndex)
    elseif IsValid(ply) then
        local tr = ply:GetEyeTrace()
        if tr and IsValid(tr.Entity) then
            target = tr.Entity
        end
    end
    local count = 0
    local function printEnt(ent)
        local list = VNPC_GetTraitList(ent)
        local summary = VNPC_GetTraitStatSummary(ent)
        local parts = {}
        for _, s in ipairs({ "metabolism", "acid_resistance", "capacity", "weight_resistance", "struggle_energy", "perception" }) do
            if summary[s] then
                table.insert(parts, string.format("%s x%.2f", s, summary[s]))
            end
        end
        print(string.format(" -> #%d [%s] %s: %s",
            ent:EntIndex(), ent.PrintName or ent:GetClass(),
            VNPC_IsPredatorEntity(ent) and "PREDATOR" or "PREY",
            (#list > 0) and table.concat(list, ", ") or "(no traits)"))
        if #parts > 0 then
            print("      " .. table.concat(parts, " | "))
        end
    end
    if IsValid(target) then
        printEnt(target)
        count = 1
    else
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and not ent:IsPlayer() and (VNPC_IsPredatorEntity(ent) or (VNPC_IsPreyNPC and VNPC_IsPreyNPC(ent)) or ent.VNPC_PreyCampID) then
                printEnt(ent)
                count = count + 1
            end
        end
    end
    if count == 0 then
        print(" - No trait-bearing NPCs currently spawned (or aim at one).")
    end
    print("===============================================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Trait status printed to console. Registered traits: " .. #TRAIT_IDS)
    end
end)

if SERVER then
    local function findTarget(ply, entIndex)
        if not IsValid(ply) then return nil end
        if entIndex then
            local ent = Entity(tonumber(entIndex) or 0)
            if IsValid(ent) then return ent end
        end
        local tr = ply:GetEyeTrace()
        if tr and IsValid(tr.Entity) then
            return tr.Entity
        end
        return nil
    end

    concommand.Add("vnpcs_trait_add", function(ply, _, args)
        local ent = findTarget(ply, args and args[1])
        local id = args and args[2]
        if not IsValid(ent) or not isstring(id) then
            if IsValid(ply) then ply:ChatPrint("[V-NPCs] Usage: vnpcs_trait_add <entindex|aimed> <trait_id>") end
            return
        end
        id = string.lower(id)
        if not VNPC_TRAITS[id] then
            if IsValid(ply) then ply:ChatPrint("[V-NPCs] Unknown trait '" .. id .. "'. See vnpcs_trait_status.") end
            return
        end
        if VNPC_AddTrait(ent, id) then
            if IsValid(ply) then
                ply:ChatPrint(string.format("[V-NPCs] Added trait %s to %s", id, tostring(ent)))
            end
        else
            if IsValid(ply) then ply:ChatPrint(string.format("[V-NPCs] Could not add %s (conflict or already owned).", id)) end
        end
    end)

    concommand.Add("vnpcs_trait_remove", function(ply, _, args)
        local ent = findTarget(ply, args and args[1])
        local id = args and args[2]
        if not IsValid(ent) or not isstring(id) then
            if IsValid(ply) then ply:ChatPrint("[V-NPCs] Usage: vnpcs_trait_remove <entindex|aimed> <trait_id>") end
            return
        end
        if VNPC_RemoveTrait(ent, string.lower(id)) and IsValid(ply) then
            ply:ChatPrint(string.format("[V-NPCs] Removed trait %s from %s", string.lower(id), tostring(ent)))
        end
    end)

    concommand.Add("vnpcs_trait_randomize", function(ply, _, args)
        local ent = findTarget(ply, args and args[1])
        if not IsValid(ent) then
            if IsValid(ply) then ply:ChatPrint("[V-NPCs] Aim at an NPC or pass an entindex.") end
            return
        end
        VNPC_ClearTraits(ent)
        local n = VNPC_RollRandomTraits(ent)
        if IsValid(ply) then
            ply:ChatPrint(string.format("[V-NPCs] Randomized traits for %s (%d traits).", tostring(ent), n))
        end
    end)

    concommand.Add("vnpcs_trait_clear", function(ply, _, args)
        local ent = findTarget(ply, args and args[1])
        if not IsValid(ent) then
            if IsValid(ply) then ply:ChatPrint("[V-NPCs] Aim at an NPC or pass an entindex.") end
            return
        end
        VNPC_ClearTraits(ent)
        if IsValid(ply) then ply:ChatPrint("[V-NPCs] Cleared all traits from " .. tostring(ent)) end
    end)
end

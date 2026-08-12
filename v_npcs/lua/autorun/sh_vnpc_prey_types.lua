-- V-NPCs Predator Prey-Type Attraction
-- Each predator is attracted to specific prey types and hunts those first.

CreateConVar("vnpcs_prey_attraction_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable predator attraction to preferred prey types")
CreateConVar("vnpcs_prey_attraction_threshold", "35", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Minimum attraction (0-100) required to hunt a prey type when not desperate")
CreateConVar("vnpcs_prey_attraction_desperate_hunger", "75", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Hunger percent at which predators ignore type preferences")
CreateConVar("vnpcs_prey_attraction_debug", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Draw prey-type attraction overlay above predators")

VNPC_PREY_TYPE_ORDER = {
    "human",
    "combine",
    "zombie",
    "headcrab",
    "antlion",
    "vortigaunt",
    "animal",
    "player",
    "predator",
    "corpse",
    "other"
}

VNPC_PREY_TYPES = {
    human = {
        name = "Human",
        description = "Citizens, rebels, refugees, and humanoids"
    },
    combine = {
        name = "Combine",
        description = "Combine soldiers, metrocops, and synths"
    },
    zombie = {
        name = "Zombie",
        description = "Zombies and zombines"
    },
    headcrab = {
        name = "Headcrab",
        description = "Headcrabs"
    },
    antlion = {
        name = "Antlion",
        description = "Antlions and antlion guards"
    },
    vortigaunt = {
        name = "Vortigaunt",
        description = "Vortigaunts"
    },
    animal = {
        name = "Animal",
        description = "Birds, dogs, and wildlife"
    },
    player = {
        name = "Player",
        description = "Human players"
    },
    predator = {
        name = "Predator",
        description = "Other V-NPC predators"
    },
    corpse = {
        name = "Corpse",
        description = "Ragdolls and corpses"
    },
    other = {
        name = "Other",
        description = "Unclassified prey"
    }
}

local PERSONALITY_FAVORITES = {
    aggressive = { "human", "combine", "zombie" },
    opportunistic = { "human", "corpse", "animal" },
    glutton = { "human", "combine", "zombie", "headcrab", "antlion", "vortigaunt", "animal", "player", "predator", "corpse", "other" },
    shy = { "human", "player" },
    selective = { "human" },
    gentle = { "human", "animal" },
    loving = { "human" }
}

local function isPreyAttractionEnabled()
    local cv = GetConVar("vnpcs_prey_attraction_enabled")
    return not cv or cv:GetBool()
end

local function attractionThreshold()
    local cv = GetConVar("vnpcs_prey_attraction_threshold")
    return cv and cv:GetFloat() or 35
end

local function desperateHunger()
    local cv = GetConVar("vnpcs_prey_attraction_desperate_hunger")
    return cv and cv:GetFloat() or 75
end

function VNPC_NormalizePreyType(typeId)
    typeId = string.lower(tostring(typeId or ""))
    if VNPC_PREY_TYPES[typeId] then return typeId end
    return nil
end

function VNPC_GetPreyType(ent)
    if not IsValid(ent) then return "other" end
    if ent.VNPC_PreyType and VNPC_PREY_TYPES[ent.VNPC_PreyType] then
        return ent.VNPC_PreyType
    end

    if ent:IsPlayer() then return "player" end

    local cls = string.lower(ent:GetClass() or "")
    local mdl = string.lower(ent:GetModel() or "")

    if cls == "prop_ragdoll" or ent.VNPC_IsCorpse then
        return "corpse"
    end

    if cls:find("headcrab") or mdl:find("headcrab") then
        return "headcrab"
    elseif cls:find("antlion") or mdl:find("antlion") then
        return "antlion"
    elseif cls:find("zombie") or mdl:find("zombie") or cls:find("zombine") then
        return "zombie"
    elseif cls:find("vortigaunt") or mdl:find("vortigaunt") then
        return "vortigaunt"
    elseif cls:find("combine") or cls:find("metropolice") or cls:find("hunter") or cls:find("strider")
        or cls:find("manhack") or cls:find("scanner") or cls:find("turret") or cls:find("apc")
        or mdl:find("combine") or mdl:find("police") then
        return "combine"
    elseif cls:find("crow") or cls:find("pigeon") or cls:find("seagull") or cls:find("bird")
        or cls:find("dog") or cls == "npc_barnacle" or cls:find("ichthyosaur")
        or mdl:find("crow") or mdl:find("pigeon") or mdl:find("seagull") then
        return "animal"
    end

    local isPred = (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator or ent.VNPC_WildType == "predator") and true or false
    local isCitizenPrey = false
    if VNPC_IsPreyNPC then
        isCitizenPrey = VNPC_IsPreyNPC(ent) and true or false
    else
        isCitizenPrey = (cls:find("citizen") or cls:find("rebel") or cls:find("refugee") or ent.VNPC_PreyCampID) and true or false
    end
    if isPred and not isCitizenPrey then
        return "predator"
    end

    if cls:find("citizen") or cls:find("rebel") or cls:find("refugee") or cls:find("alyx")
        or cls:find("mossman") or cls:find("eli") or cls:find("barney") or cls:find("monk")
        or mdl:find("human") or mdl:find("alyx") or mdl:find("mossman") or mdl:find("female")
        or mdl:find("male") or mdl:find("group0") then
        return "human"
    end

    if isPred then return "predator" end
    return "other"
end

function VNPC_IsPredatorDesperateForPrey(pred)
    if not IsValid(pred) then return false end
    if pred.VNPC_DesperateSurvival then return true end
    if pred.GetMaxHealth and pred:GetMaxHealth() > 0 and pred:Health() / pred:GetMaxHealth() < 0.35 then
        return true
    end
    if VNPC_GetHunger then
        local hunger = VNPC_GetHunger(pred) or 0
        if hunger >= desperateHunger() then return true end
    end
    return false
end

function VNPC_GetFavoritePreyTypes(pred)
    local scores = VNPC_GetAttractedPreyTypes(pred)
    local favs = {}
    for _, typeId in ipairs(VNPC_PREY_TYPE_ORDER) do
        if (scores[typeId] or 0) >= 55 then
            table.insert(favs, typeId)
        end
    end
    return favs
end

function VNPC_FormatPreyAttraction(pred)
    local favs = VNPC_GetFavoritePreyTypes(pred)
    if #favs == 0 then return "none" end
    local names = {}
    for _, typeId in ipairs(favs) do
        local info = VNPC_PREY_TYPES[typeId]
        table.insert(names, info and info.name or typeId)
    end
    return table.concat(names, ", ")
end

function VNPC_SyncPreyAttractionNW(pred)
    if not IsValid(pred) or not pred.SetNWString then return end
    pred:SetNWString("VNPC_AttractedTypes", table.concat(VNPC_GetFavoritePreyTypes(pred), ","))
end

local function emptyScores()
    local scores = {}
    for _, typeId in ipairs(VNPC_PREY_TYPE_ORDER) do
        scores[typeId] = 12
    end
    return scores
end

function VNPC_AssignPreyAttraction(pred)
    if not IsValid(pred) then return emptyScores() end

    local scores = emptyScores()
    local pers = "opportunistic"
    if VNPC_GetPredatorPersonality then
        pers = select(1, VNPC_GetPredatorPersonality(pred)) or "opportunistic"
    else
        pers = pred.VNPC_PredatorPersonality or (pred.VoreSettings and pred.VoreSettings.PredatorPersonality) or "opportunistic"
    end
    pers = string.lower(tostring(pers))

    local pool = PERSONALITY_FAVORITES[pers]
    if not pool or #pool == 0 then
        pool = PERSONALITY_FAVORITES.opportunistic
    end

    local pickCount = 2
    if pers == "glutton" then
        pickCount = #pool
    elseif pers == "selective" or pers == "loving" then
        pickCount = 1
    elseif pers == "aggressive" then
        pickCount = math.random(2, 3)
    elseif pers == "shy" or pers == "gentle" then
        pickCount = 2
    else
        pickCount = math.random(1, 3)
    end
    pickCount = math.Clamp(pickCount, 1, #pool)

    local shuffled = {}
    for i = 1, #pool do
        shuffled[i] = pool[i]
    end
    for i = #shuffled, 2, -1 do
        local j = math.random(1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    local picked = {}
    for i = 1, pickCount do
        local typeId = shuffled[i]
        picked[typeId] = true
        if pers == "glutton" then
            scores[typeId] = math.random(82, 100)
        elseif pers == "selective" then
            scores[typeId] = math.random(88, 100)
        else
            scores[typeId] = math.random(70, 98)
        end
    end

    if pers == "glutton" then
        for _, typeId in ipairs(VNPC_PREY_TYPE_ORDER) do
            if not picked[typeId] then
                scores[typeId] = math.random(70, 90)
            end
        end
    elseif pers == "selective" then
        for _, typeId in ipairs(VNPC_PREY_TYPE_ORDER) do
            if not picked[typeId] then
                scores[typeId] = math.random(4, 14)
            end
        end
    else
        for _, typeId in ipairs(VNPC_PREY_TYPE_ORDER) do
            if not picked[typeId] then
                scores[typeId] = math.random(8, 28)
            end
        end
    end

    if pers == "loving" then
        scores.human = math.max(scores.human or 0, 86)
        scores.player = math.max(scores.player or 0, 40)
    end

    pred.VNPC_AttractedPreyTypes = scores
    VNPC_SyncPreyAttractionNW(pred)
    return scores
end

function VNPC_GetAttractedPreyTypes(pred)
    if not IsValid(pred) then return emptyScores() end
    if not istable(pred.VNPC_AttractedPreyTypes) then
        return VNPC_AssignPreyAttraction(pred)
    end
    return pred.VNPC_AttractedPreyTypes
end

function VNPC_SetPreyAttraction(pred, typeId, score)
    if not IsValid(pred) then return false end
    typeId = VNPC_NormalizePreyType(typeId)
    if not typeId then return false end
    local scores = VNPC_GetAttractedPreyTypes(pred)
    scores[typeId] = math.Clamp(tonumber(score) or 0, 0, 100)
    pred.VNPC_AttractedPreyTypes = scores
    VNPC_SyncPreyAttractionNW(pred)
    return true
end

function VNPC_GetPreyTypeAttraction(pred, typeId)
    if not IsValid(pred) then return 0 end
    typeId = VNPC_NormalizePreyType(typeId) or "other"
    local scores = VNPC_GetAttractedPreyTypes(pred)
    return tonumber(scores[typeId]) or 12
end

function VNPC_GetPreyAttraction(pred, prey)
    if not IsValid(pred) or not IsValid(prey) then return 0 end
    return VNPC_GetPreyTypeAttraction(pred, VNPC_GetPreyType(prey))
end

function VNPC_GetPreyAttractionMultiplier(pred, prey)
    if not isPreyAttractionEnabled() then return 1.0 end
    if not IsValid(pred) or not IsValid(prey) then return 1.0 end
    if VNPC_IsPredatorDesperateForPrey(pred) then
        return 1.15
    end
    local attraction = VNPC_GetPreyAttraction(pred, prey)
    return 0.18 + (attraction / 100) * 2.05
end

function VNPC_IsAttractedToPreyType(pred, typeId)
    if not isPreyAttractionEnabled() then return true end
    if not IsValid(pred) then return false end
    if VNPC_IsPredatorDesperateForPrey(pred) then return true end
    return VNPC_GetPreyTypeAttraction(pred, typeId) >= attractionThreshold()
end

function VNPC_IsAttractedToPrey(pred, prey)
    if not IsValid(pred) or not IsValid(prey) then return false end
    if not isPreyAttractionEnabled() then return true end
    if VNPC_IsPredatorDesperateForPrey(pred) then return true end
    if pred.GetEnemy and pred:GetEnemy() == prey then return true end
    return VNPC_IsAttractedToPreyType(pred, VNPC_GetPreyType(prey))
end

function VNPC_ShouldHuntPreyType(pred, prey)
    if not IsValid(pred) or not IsValid(prey) then return false end
    if not isPreyAttractionEnabled() then return true end
    return VNPC_IsAttractedToPrey(pred, prey)
end

hook.Add("OnEntityCreated", "VNPC_AutoAssignPreyAttraction", function(ent)
    timer.Simple(0.2, function()
        if not IsValid(ent) then return end
        if ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator or (VNPC_IsFemaleModelNPC and VNPC_IsFemaleModelNPC(ent)) then
            VNPC_AssignPreyAttraction(ent)
        end
    end)
end)

concommand.Add("vnpcs_prey_attraction_status", function(ply)
    print("===============================================================")
    print("          V-NPCs PREDATOR PREY-TYPE ATTRACTION STATUS          ")
    print("===============================================================")
    print(" - Attraction Enabled: " .. tostring(isPreyAttractionEnabled()))
    print(" - Hunt Threshold: " .. tostring(attractionThreshold()))
    print(" - Desperate Hunger: " .. tostring(desperateHunger()) .. "%")
    local count = 0
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(ent) and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) then
            count = count + 1
            local pers = VNPC_GetPredatorPersonality and select(1, VNPC_GetPredatorPersonality(ent)) or "opportunistic"
            local parts = {}
            local scores = VNPC_GetAttractedPreyTypes(ent)
            for _, typeId in ipairs(VNPC_PREY_TYPE_ORDER) do
                local score = scores[typeId] or 0
                if score >= 55 then
                    table.insert(parts, string.format("%s=%.0f", typeId, score))
                end
            end
            print(string.format(" - Pred #%d [%s] pers=%s attracted=%s",
                ent:EntIndex(),
                ent.PrintName or ent:GetClass(),
                tostring(pers),
                #parts > 0 and table.concat(parts, ", ") or "none"))
        end
    end
    if count == 0 then
        print(" - Active Predators: NONE currently spawned")
    end
    print("===============================================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Prey-type attraction status printed to console. Predators: " .. count)
    end
end)

concommand.Add("vnpcs_set_prey_attraction", function(ply, cmd, args)
    if #args < 2 then
        print("[V-NPCs] Usage: vnpcs_set_prey_attraction <ent_index> <type> [score]")
        print("[V-NPCs] Types: " .. table.concat(VNPC_PREY_TYPE_ORDER, ", "))
        return
    end
    local id = tonumber(args[1])
    local typeId = VNPC_NormalizePreyType(args[2])
    local score = tonumber(args[3]) or 90
    local target = id and Entity(id) or nil
    if not IsValid(target) then
        print("[V-NPCs] Entity #" .. tostring(args[1]) .. " not found.")
        return
    end
    if not typeId then
        print("[V-NPCs] Unknown prey type '" .. tostring(args[2]) .. "'. Types: " .. table.concat(VNPC_PREY_TYPE_ORDER, ", "))
        return
    end
    VNPC_SetPreyAttraction(target, typeId, score)
    local msg = string.format("[V-NPCs] Set %s attraction to %s = %.0f. Favorites: %s",
        tostring(target), typeId, score, VNPC_FormatPreyAttraction(target))
    print(msg)
    if IsValid(ply) then ply:ChatPrint(msg) end
end)

concommand.Add("vnpcs_test_prey_attraction", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) then
        ply:ChatPrint("[V-NPCs] Aim at a predator or prey NPC to inspect prey-type attraction!")
        return
    end

    if target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator then
        VNPC_GetAttractedPreyTypes(target)
        local pers = VNPC_GetPredatorPersonality and select(1, VNPC_GetPredatorPersonality(target)) or "opportunistic"
        ply:ChatPrint(string.format("[V-NPCs] Predator %s (%s) is attracted to: %s",
            tostring(target), tostring(pers), VNPC_FormatPreyAttraction(target)))
        local scores = VNPC_GetAttractedPreyTypes(target)
        for _, typeId in ipairs(VNPC_PREY_TYPE_ORDER) do
            local score = scores[typeId] or 0
            if score >= 20 then
                print(string.format("   %s = %.0f%s", typeId, score, score >= attractionThreshold() and " [hunts]" or ""))
            end
        end
        return
    end

    local preyType = VNPC_GetPreyType(target)
    ply:ChatPrint(string.format("[V-NPCs] %s is prey type [%s]. Nearby predator attraction:",
        tostring(target), string.upper(preyType)))
    local shown = 0
    for _, pred in ipairs(ents.FindInSphere(target:GetPos(), 1600)) do
        if IsValid(pred) and pred ~= target and (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) then
            shown = shown + 1
            local score = VNPC_GetPreyAttraction(pred, target)
            local hunts = VNPC_ShouldHuntPreyType(pred, target)
            ply:ChatPrint(string.format(" - Pred #%d %s: %s=%.0f %s",
                pred:EntIndex(), pred.PrintName or pred:GetClass(), preyType, score, hunts and "[will hunt]" or "[ignores]"))
        end
    end
    if shown == 0 then
        ply:ChatPrint("[V-NPCs] No nearby predators found.")
    end
end)

if CLIENT then
    hook.Add("PostDrawTranslucentRenderables", "VNPC_PreyAttraction_DebugOverlay", function()
        local debug_cv = GetConVar("vnpcs_prey_attraction_debug")
        if not debug_cv or not debug_cv:GetBool() then return end

        for _, npc in ipairs(ents.FindByClass("npc_*")) do
            if not IsValid(npc) then continue end
            if not (npc.IsDrGNextbot or npc.VNPC_FemaleModelVore or npc.Predator) then continue end
            local label = npc:GetNWString("VNPC_AttractedTypes", "")
            if label == "" and VNPC_FormatPreyAttraction then
                label = VNPC_FormatPreyAttraction(npc)
            end
            if label == "" then continue end
            local pos = npc:WorldSpaceCenter() + Vector(0, 0, 42)
            local ang = EyeAngles()
            ang:RotateAroundAxis(ang:Forward(), 90)
            ang:RotateAroundAxis(ang:Right(), 90)
            cam.Start3D2D(pos, ang, 0.16)
                draw.SimpleText("Attracted: " .. label, "DermaDefaultBold", 0, 0, Color(255, 190, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            cam.End3D2D()
        end
    end)
end

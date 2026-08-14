-- V-NPCs Prey Mate Attraction
-- Prey are attracted to specific female predator types and seek those preds to mate.

CreateConVar("vnpcs_mate_attraction_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable prey attraction to female predator types for mating")
CreateConVar("vnpcs_mate_attraction_threshold", "50", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Minimum attraction (0-100) for prey to seek a female pred type to mate")
CreateConVar("vnpcs_mate_attraction_debug", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Draw mate-attraction overlay above prey")
CreateConVar("vnpcs_mate_attraction_range", "1100", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "How far prey look for a female pred type they want to mate with")

-- Keep old hunt cvars so leftover menus/saves do not error.
CreateConVar("vnpcs_prey_attraction_enabled", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Deprecated. Predators no longer have preferred hunt prey types")
CreateConVar("vnpcs_prey_attraction_threshold", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Deprecated hunt threshold")
CreateConVar("vnpcs_prey_attraction_desperate_hunger", "75", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Deprecated hunt hunger override")
CreateConVar("vnpcs_prey_attraction_debug", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Deprecated hunt overlay")

VNPC_FEMALE_PRED_TYPE_ORDER = {
    "citizen",
    "alyx",
    "mossman",
    "combine",
    "vortigaunt",
    "rebel",
    "zombie",
    "other"
}

VNPC_FEMALE_PRED_TYPES = {
    citizen = {
        name = "Citizen",
        description = "Female citizen predators"
    },
    alyx = {
        name = "Alyx",
        description = "Alyx-type female predators"
    },
    mossman = {
        name = "Mossman",
        description = "Mossman-type female predators"
    },
    combine = {
        name = "Combine",
        description = "Female combine and metrocop predators"
    },
    vortigaunt = {
        name = "Vortigaunt",
        description = "Female vortigaunt predators"
    },
    rebel = {
        name = "Rebel",
        description = "Female rebel and refugee predators"
    },
    zombie = {
        name = "Zombie",
        description = "Female zombie predators"
    },
    other = {
        name = "Other",
        description = "Other female predator models"
    }
}

local PREY_PERS_FAVORITES = {
    willing = { "citizen", "alyx", "mossman" },
    desire = { "citizen", "alyx", "mossman" },
    desirous = { "citizen", "alyx", "mossman" },
    passive = { "citizen", "mossman", "alyx" },
    fighter = { "combine", "vortigaunt", "rebel" },
    stubborn = { "combine", "vortigaunt", "rebel" },
    panicked = { "citizen", "mossman", "alyx" }
}

local function mateAttractionEnabled()
    local cv = GetConVar("vnpcs_mate_attraction_enabled")
    return not cv or cv:GetBool()
end

local function mateThreshold()
    local cv = GetConVar("vnpcs_mate_attraction_threshold")
    return cv and cv:GetFloat() or 50
end

local function mateRange()
    local cv = GetConVar("vnpcs_mate_attraction_range")
    return cv and cv:GetFloat() or 1100
end

function VNPC_NormalizeFemalePredType(typeId)
    typeId = string.lower(tostring(typeId or ""))
    if VNPC_FEMALE_PRED_TYPES[typeId] then return typeId end
    return nil
end

function VNPC_IsFemalePredator(ent)
    if not IsValid(ent) or ent:Health() <= 0 then return false end
    if ent.Vored or ent.VNPC_Vored then return false end
    if not (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator or ent.VNPC_WildType == "predator") then
        return false
    end
    if VNPC_ModelLooksFemale and VNPC_ModelLooksFemale(ent) then return true end
    if VNPC_IsFemaleModelNPC and VNPC_IsFemaleModelNPC(ent) then return true end
    return true
end

function VNPC_GetFemalePredType(ent)
    if not IsValid(ent) then return "other" end
    if ent.VNPC_FemalePredType and VNPC_FEMALE_PRED_TYPES[ent.VNPC_FemalePredType] then
        return ent.VNPC_FemalePredType
    end

    local cls = string.lower(ent:GetClass() or "")
    local mdl = string.lower(ent:GetModel() or "")
    local name = string.lower(tostring(ent.PrintName or ""))

    if cls:find("alyx") or mdl:find("alyx") or name:find("alyx") then
        return "alyx"
    elseif cls:find("mossman") or mdl:find("mossman") or name:find("mossman") then
        return "mossman"
    elseif cls:find("vortigaunt") or mdl:find("vortigaunt") or name:find("vort") then
        return "vortigaunt"
    elseif cls:find("zombie") or mdl:find("zombie") or cls:find("zombine") then
        return "zombie"
    elseif cls:find("combine") or cls:find("metropolice") or mdl:find("combine") or mdl:find("police") then
        return "combine"
    elseif cls:find("rebel") or mdl:find("group03") or mdl:find("rebel") then
        return "rebel"
    elseif cls:find("refugee") or mdl:find("group02") then
        return "rebel"
    elseif cls:find("citizen") or mdl:find("group01") or mdl:find("human") or mdl:find("female") then
        return "citizen"
    end
    return "other"
end

local function emptyScores()
    local scores = {}
    for _, typeId in ipairs(VNPC_FEMALE_PRED_TYPE_ORDER) do
        scores[typeId] = 14
    end
    return scores
end

function VNPC_SyncMateAttractionNW(prey)
    if not IsValid(prey) or not prey.SetNWString then return end
    prey:SetNWString("VNPC_AttractedPredTypes", table.concat(VNPC_GetFavoritePredTypes(prey), ","))
end

function VNPC_AssignMateAttraction(prey)
    if not IsValid(prey) then return emptyScores() end

    local scores = emptyScores()
    local pers = "fighter"
    if VNPC_GetPreyPersonality then
        pers = select(1, VNPC_GetPreyPersonality(prey)) or "fighter"
    else
        pers = prey.VNPC_PreyPersonality or prey.PreyPersonality or "fighter"
    end
    pers = string.lower(tostring(pers))

    local pool = PREY_PERS_FAVORITES[pers] or PREY_PERS_FAVORITES.fighter
    local pickCount = (pers == "willing" or pers == "desire" or pers == "desirous") and 2 or math.random(1, 2)
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
        scores[typeId] = math.random(72, 98)
    end
    for _, typeId in ipairs(VNPC_FEMALE_PRED_TYPE_ORDER) do
        if not picked[typeId] then
            scores[typeId] = math.random(8, 32)
        end
    end

    prey.VNPC_AttractedPredTypes = scores
    VNPC_SyncMateAttractionNW(prey)
    return scores
end

function VNPC_GetAttractedPredTypes(prey)
    if not IsValid(prey) then return emptyScores() end
    if not istable(prey.VNPC_AttractedPredTypes) then
        return VNPC_AssignMateAttraction(prey)
    end
    return prey.VNPC_AttractedPredTypes
end

function VNPC_GetFavoritePredTypes(prey)
    local scores = VNPC_GetAttractedPredTypes(prey)
    local favs = {}
    for _, typeId in ipairs(VNPC_FEMALE_PRED_TYPE_ORDER) do
        if (scores[typeId] or 0) >= 55 then
            table.insert(favs, typeId)
        end
    end
    return favs
end

function VNPC_FormatMateAttraction(prey)
    local favs = VNPC_GetFavoritePredTypes(prey)
    if #favs == 0 then return "none" end
    local names = {}
    for _, typeId in ipairs(favs) do
        local info = VNPC_FEMALE_PRED_TYPES[typeId]
        table.insert(names, info and info.name or typeId)
    end
    return table.concat(names, ", ")
end

function VNPC_SetMateAttraction(prey, typeId, score)
    if not IsValid(prey) then return false end
    typeId = VNPC_NormalizeFemalePredType(typeId)
    if not typeId then return false end
    local scores = VNPC_GetAttractedPredTypes(prey)
    scores[typeId] = math.Clamp(tonumber(score) or 0, 0, 100)
    prey.VNPC_AttractedPredTypes = scores
    VNPC_SyncMateAttractionNW(prey)
    return true
end

function VNPC_GetPredTypeAttraction(prey, typeId)
    if not IsValid(prey) then return 0 end
    typeId = VNPC_NormalizeFemalePredType(typeId) or "other"
    local scores = VNPC_GetAttractedPredTypes(prey)
    return tonumber(scores[typeId]) or 14
end

function VNPC_GetMateAttraction(prey, pred)
    if not IsValid(prey) or not IsValid(pred) then return 0 end
    return VNPC_GetPredTypeAttraction(prey, VNPC_GetFemalePredType(pred))
end

function VNPC_IsPreyAttractedToPred(prey, pred)
    if not IsValid(prey) or not IsValid(pred) then return false end
    if not mateAttractionEnabled() then return true end
    if prey.VNPC_LovedPartner == pred or prey.VNPC_LovedMate == pred or prey.VNPC_MatingPartner == pred then
        return true
    end
    return VNPC_GetMateAttraction(prey, pred) >= mateThreshold()
end

function VNPC_GetMateAttractionMultiplier(prey, pred)
    if not mateAttractionEnabled() then return 1.0 end
    if not IsValid(prey) or not IsValid(pred) then return 1.0 end
    local attraction = VNPC_GetMateAttraction(prey, pred)
    return 0.20 + (attraction / 100) * 2.10
end

-- Deprecated hunt helpers: predators no longer filter prey types while hunting.
function VNPC_ShouldHuntPreyType(pred, prey)
    return IsValid(pred) and IsValid(prey)
end

function VNPC_GetPreyAttractionMultiplier(pred, prey)
    return 1.0
end

function VNPC_AssignPreyAttraction(ent)
    if not IsValid(ent) then return emptyScores() end
    if ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator then
        return emptyScores()
    end
    return VNPC_AssignMateAttraction(ent)
end

hook.Add("OnEntityCreated", "VNPC_AutoAssignMateAttraction", function(ent)
    timer.Simple(0.25, function()
        if not IsValid(ent) then return end
        if ent:IsNPC() or ent:IsNextBot() or ent:IsPlayer() then
            if not (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) then
                VNPC_AssignMateAttraction(ent)
            end
        end
    end)
end)

if SERVER then
    local function canPreySeekMate(ent)
        if not IsValid(ent) or ent:Health() <= 0 then return false end
        if ent.Vored or ent.VNPC_Vored or ent.VNPC_IsPregnant then return false end
        if ent:IsPlayer() then return false end
        if VNPC_IsBusyMating and VNPC_IsBusyMating(ent) then return false end
        if VNPC_IsAdultPreyCitizen and not VNPC_IsAdultPreyCitizen(ent) then return false end
        if VNPC_IsMalePreyCitizen then
            return VNPC_IsMalePreyCitizen(ent)
        end
        if VNPC_IsMaleWildWanderer then
            return VNPC_IsMaleWildWanderer(ent)
        end
        return false
    end

    local function canPredAcceptMate(pred)
        if not VNPC_IsFemalePredator(pred) then return false end
        if pred.VNPC_IsPregnant or pred.VNPC_IsPregnantWithSister then return false end
        if VNPC_IsBusyMating and VNPC_IsBusyMating(pred) then return false end
        if pred.Swallowing or pred.VNPC_IsCarryingMateForCamp or pred.VNPC_IsInfiltratingFort then return false end
        if pred.VNPC_IsSecretAssassin then return false end
        if pred.VNPC_IsSleeping then return false end
        return true
    end

    hook.Add("Think", "VNPC_PreySeekFemalePredMate_AI", function()
        if not mateAttractionEnabled() then return end
        local now = CurTime()
        if (VNPC_NextMateAttractionThink or 0) > now then return end
        VNPC_NextMateAttractionThink = now + 0.8

        local range = mateRange()
        for _, prey in ipairs(ents.FindByClass("npc_*")) do
            if not canPreySeekMate(prey) then continue end
            if (prey.VNPC_NextMateSeekTime or 0) > now then continue end
            prey.VNPC_NextMateSeekTime = now + 2.4

            local partner = prey.VNPC_LovedPartner or prey.VNPC_LovedMate or prey.VNPC_MatingPartner
            local bestPred = nil
            local bestScore = -1e9
            if IsValid(partner) and canPredAcceptMate(partner) and VNPC_IsPreyAttractedToPred(prey, partner) then
                bestPred = partner
                bestScore = 1000
            else
                for _, pred in ipairs(ents.FindInSphere(prey:GetPos(), range)) do
                    if not canPredAcceptMate(pred) then continue end
                    if not VNPC_IsPreyAttractedToPred(prey, pred) then continue end
                    local dist = prey:GetPos():Distance(pred:GetPos())
                    local score = (100 / (dist + 40)) * VNPC_GetMateAttractionMultiplier(prey, pred)
                    if score > bestScore then
                        bestPred = pred
                        bestScore = score
                    end
                end
            end

            if not IsValid(bestPred) then continue end

            local dist = prey:GetPos():Distance(bestPred:GetPos())
            if dist <= 160 then
                if VNPC_AddMateLove then
                    VNPC_AddMateLove(bestPred, prey, 4.0)
                end
                if VNPC_InitiatePrivateMating then
                    VNPC_InitiatePrivateMating(bestPred, prey, VNPC_GetPredatorCamp and VNPC_GetPredatorCamp(bestPred) or nil)
                end
            else
                if prey.SetEnemy then pcall(prey.SetEnemy, prey, nil) end
                if prey.SetTarget then pcall(prey.SetTarget, prey, bestPred) end
                if prey.SetLastPosition then pcall(prey.SetLastPosition, prey, bestPred:GetPos()) end
                if prey.SetSchedule then pcall(prey.SetSchedule, prey, SCHED_FORCED_GO_RUN) end
                if (bestPred.VNPC_NextMateAnswerTime or 0) <= now then
                    bestPred.VNPC_NextMateAnswerTime = now + 2.0
                    if bestPred.SetLastPosition then pcall(bestPred.SetLastPosition, bestPred, prey:GetPos()) end
                    if bestPred.SetSchedule then pcall(bestPred.SetSchedule, bestPred, SCHED_FORCED_GO) end
                end
            end
        end
    end)
end

concommand.Add("vnpcs_mate_attraction_status", function(ply)
    print("===============================================================")
    print("     V-NPCs PREY ATTRACTION TO FEMALE PREDATOR TYPES           ")
    print("===============================================================")
    print(" - Mate Attraction Enabled: " .. tostring(mateAttractionEnabled()))
    print(" - Seek Threshold: " .. tostring(mateThreshold()))
    print(" - Seek Range: " .. tostring(mateRange()))
    local count = 0
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(ent) and not (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) then
            count = count + 1
            local pers = VNPC_GetPreyPersonality and select(1, VNPC_GetPreyPersonality(ent)) or "fighter"
            print(string.format(" - Prey #%d [%s] pers=%s wants to mate with: %s",
                ent:EntIndex(),
                ent.PrintName or ent:GetClass(),
                tostring(pers),
                VNPC_FormatMateAttraction(ent)))
        end
    end
    if count == 0 then
        print(" - Active Prey: NONE currently spawned")
    end
    print("===============================================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Mate attraction status printed to console. Prey: " .. count)
    end
end)

concommand.Add("vnpcs_prey_attraction_status", function(ply, cmd, args)
    RunConsoleCommand("vnpcs_mate_attraction_status")
end)

concommand.Add("vnpcs_set_mate_attraction", function(ply, cmd, args)
    if #args < 2 then
        print("[V-NPCs] Usage: vnpcs_set_mate_attraction <ent_index> <female_pred_type> [score]")
        print("[V-NPCs] Types: " .. table.concat(VNPC_FEMALE_PRED_TYPE_ORDER, ", "))
        return
    end
    local id = tonumber(args[1])
    local typeId = VNPC_NormalizeFemalePredType(args[2])
    local score = tonumber(args[3]) or 90
    local target = id and Entity(id) or nil
    if not IsValid(target) then
        print("[V-NPCs] Entity #" .. tostring(args[1]) .. " not found.")
        return
    end
    if not typeId then
        print("[V-NPCs] Unknown female pred type '" .. tostring(args[2]) .. "'. Types: " .. table.concat(VNPC_FEMALE_PRED_TYPE_ORDER, ", "))
        return
    end
    VNPC_SetMateAttraction(target, typeId, score)
    local msg = string.format("[V-NPCs] Set %s mate attraction to %s = %.0f. Wants: %s",
        tostring(target), typeId, score, VNPC_FormatMateAttraction(target))
    print(msg)
    if IsValid(ply) then ply:ChatPrint(msg) end
end)

concommand.Add("vnpcs_test_mate_attraction", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) then
        ply:ChatPrint("[V-NPCs] Aim at prey or a female predator to inspect mate attraction!")
        return
    end

    if VNPC_IsFemalePredator(target) then
        local predType = VNPC_GetFemalePredType(target)
        ply:ChatPrint(string.format("[V-NPCs] Female pred %s is type [%s]. Nearby prey attraction:",
            tostring(target), string.upper(predType)))
        local shown = 0
        for _, prey in ipairs(ents.FindInSphere(target:GetPos(), 1600)) do
            if IsValid(prey) and prey ~= target and not (prey.IsDrGNextbot or prey.VNPC_FemaleModelVore or prey.Predator) then
                shown = shown + 1
                local score = VNPC_GetMateAttraction(prey, target)
                local wants = VNPC_IsPreyAttractedToPred(prey, target)
                ply:ChatPrint(string.format(" - Prey #%d %s: %s=%.0f %s",
                    prey:EntIndex(), prey.PrintName or prey:GetClass(), predType, score, wants and "[wants to mate]" or "[not attracted]"))
            end
        end
        if shown == 0 then
            ply:ChatPrint("[V-NPCs] No nearby prey found.")
        end
        return
    end

    VNPC_GetAttractedPredTypes(target)
    local pers = VNPC_GetPreyPersonality and select(1, VNPC_GetPreyPersonality(target)) or "fighter"
    ply:ChatPrint(string.format("[V-NPCs] Prey %s (%s) wants to mate with: %s",
        tostring(target), tostring(pers), VNPC_FormatMateAttraction(target)))
end)

concommand.Add("vnpcs_test_prey_attraction", function(ply)
    RunConsoleCommand("vnpcs_test_mate_attraction")
end)

if CLIENT then
    hook.Add("PostDrawTranslucentRenderables", "VNPC_MateAttraction_DebugOverlay", function()
        local debug_cv = GetConVar("vnpcs_mate_attraction_debug")
        if not debug_cv or not debug_cv:GetBool() then return end

        for _, npc in ipairs(ents.FindByClass("npc_*")) do
            if not IsValid(npc) then continue end
            local label
            if npc.IsDrGNextbot or npc.VNPC_FemaleModelVore or npc.Predator then
                label = "Type: " .. (VNPC_GetFemalePredType and VNPC_GetFemalePredType(npc) or "?")
            else
                label = npc:GetNWString("VNPC_AttractedPredTypes", "")
                if label == "" and VNPC_FormatMateAttraction then
                    label = VNPC_FormatMateAttraction(npc)
                end
                if label ~= "" then
                    label = "Wants: " .. label
                end
            end
            if not label or label == "" then continue end
            local pos = npc:WorldSpaceCenter() + Vector(0, 0, 42)
            local ang = EyeAngles()
            ang:RotateAroundAxis(ang:Forward(), 90)
            ang:RotateAroundAxis(ang:Right(), 90)
            cam.Start3D2D(pos, ang, 0.16)
                draw.SimpleText(label, "DermaDefaultBold", 0, 0, Color(255, 170, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            cam.End3D2D()
        end
    end)
end

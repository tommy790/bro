-- V-NPCs Secret Assassin Predators (vnpcs_secret_assassins.lua)
-- Predator camps dispatch undercover assassins to prey camps. By day they
-- pose as friendly prey citizens; when night falls they drop the act and
-- start swallowing camp members, then escape home with a full belly.

if not SERVER then return end

local assassin_enabled = CreateConVar("vnpcs_secret_assassins_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable predator camps sending secret assassins that pose as prey until night")
local assassin_interval = CreateConVar("vnpcs_assassin_dispatch_interval", "90.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Minimum seconds between assassin dispatches from a predator camp")
local assassin_max = CreateConVar("vnpcs_assassin_max_active", "3", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum simultaneous secret assassins on the map")
local assassin_min_prey = CreateConVar("vnpcs_assassin_min_prey_camp", "4", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Minimum living prey-camp members before an assassin will target that camp")
local assassin_hunger = CreateConVar("vnpcs_assassin_hunger_thresh", "35.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Predator camp hunger / empty-belly threshold that allows assassin dispatch")
local assassin_max_swallows = CreateConVar("vnpcs_assassin_max_swallows", "3", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "How many prey an assassin will try to swallow in one night raid before escaping")
local assassin_range = CreateConVar("vnpcs_assassin_swallow_range", "130.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Distance at which a night-mode assassin will swallow a prey camp member")

local DISGUISE_MODELS = {
    "models/Humans/Group01/Female_01.mdl",
    "models/Humans/Group01/Female_02.mdl",
    "models/Humans/Group01/Female_03.mdl",
    "models/Humans/Group01/Female_04.mdl",
    "models/Humans/Group01/Female_06.mdl",
    "models/Humans/Group01/Female_07.mdl",
    "models/Humans/Group03/Female_01.mdl",
    "models/Humans/Group03/Female_02.mdl",
}

VNPC_ActiveSecretAssassins = VNPC_ActiveSecretAssassins or {}

local function isPredatorCandidate(ent)
    if not IsValid(ent) or ent:Health() <= 0 then return false end
    if ent.Vored or ent.VNPC_Vored then return false end
    if ent.VNPC_IsPermanentFortPredator then return false end
    if ent.VNPC_IsSecretAssassin then return false end
    if ent.VNPC_IsInfiltratingFort then return false end
    if ent.VNPC_IsVisitingPreyCamp then return false end
    if ent.VNPC_IsSleeping or ent.VNPC_IsReturningToCampToSleep then return false end
    if ent.Swallowing then return false end
    if ent.VNPC_IsCarryingPreyForCamp or ent.VNPC_IsCarryingMateForCamp then return false end
    if IsValid(VNPC_GetEntityEnemy and VNPC_GetEntityEnemy(ent) or nil) then return false end
    return (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator or ent.EatEntity ~= nil) == true
end

local function bellyIsEmpty(pred)
    local belly = pred.VNPC_Belly or pred.Belly
    if not IsValid(belly) then return true end
    if belly.Prey and #belly.Prey > 0 then return false end
    if (belly.DigestionPhase or 0) > 0 then return false end
    return true
end

local function countActiveAssassins()
    local n = 0
    for i = #VNPC_ActiveSecretAssassins, 1, -1 do
        local a = VNPC_ActiveSecretAssassins[i]
        if not IsValid(a) or a:Health() <= 0 or not a.VNPC_IsSecretAssassin then
            table.remove(VNPC_ActiveSecretAssassins, i)
        else
            n = n + 1
        end
    end
    return n
end

function VNPC_IsSecretAssassin(ent)
    return IsValid(ent) and ent.VNPC_IsSecretAssassin == true
end

function VNPC_IsAssassinUndercover(ent)
    return VNPC_IsSecretAssassin(ent) and ent.VNPC_AssassinPhase == "undercover"
end

function VNPC_IsAssassinNightHunting(ent)
    return VNPC_IsSecretAssassin(ent) and ent.VNPC_AssassinPhase == "night"
end

local function setFriendlyWithCamp(pred, camp, like)
    if not IsValid(pred) or not camp or not camp.members then return end
    local rel = like and D_LI or D_HT
    local prio = like and 99 or 50
    for _, mem in ipairs(camp.members) do
        if IsValid(mem) and mem ~= pred then
            if pred.AddEntityRelationship then
                pcall(pred.AddEntityRelationship, pred, mem, rel, prio)
            end
            if mem.AddEntityRelationship then
                pcall(mem.AddEntityRelationship, mem, pred, rel, prio)
            end
            if like then
                if mem.SetEnemy and (VNPC_GetEntityEnemy and VNPC_GetEntityEnemy(mem) == pred) then
                    pcall(mem.SetEnemy, mem, nil)
                end
                if pred.SetEnemy and (VNPC_GetEntityEnemy and VNPC_GetEntityEnemy(pred) == mem) then
                    pcall(pred.SetEnemy, pred, nil)
                end
            end
        end
    end
end

local function pickDisguiseModel(pred)
    -- Prefer a female citizen look so she still reads as a camp citizen.
    for _, mdl in ipairs(DISGUISE_MODELS) do
        if util.IsValidModel(mdl) then
            return mdl
        end
    end
    -- Fall back to whatever female prey models are already on the map.
    for _, camp in ipairs(VNPC_ActivePreyCamps or {}) do
        for _, mem in ipairs(camp.members or {}) do
            if IsValid(mem) and VNPC_ModelLooksFemale and VNPC_ModelLooksFemale(mem) then
                local mdl = mem:GetModel()
                if mdl and util.IsValidModel(mdl) then
                    return mdl
                end
            end
        end
    end
    return "models/Humans/Group01/Female_01.mdl"
end

function VNPC_ApplyAssassinDisguise(pred)
    if not IsValid(pred) then return false end

    if not pred.VNPC_AssassinOriginalModel then
        pred.VNPC_AssassinOriginalModel = pred:GetModel()
        pred.VNPC_AssassinOriginalSkin = pred.GetSkin and pred:GetSkin() or 0
        pred.VNPC_AssassinOriginalBodygroups = {}
        if pred.GetNumBodyGroups and pred.GetBodygroup then
            for i = 0, (pred:GetNumBodyGroups() or 1) - 1 do
                pred.VNPC_AssassinOriginalBodygroups[i] = pred:GetBodygroup(i)
            end
        end
        pred.VNPC_AssassinOriginalColor = pred.GetColor and pred:GetColor() or Color(255, 255, 255)
        pred.VNPC_AssassinOriginalMaterial = pred.GetMaterial and pred:GetMaterial() or ""
    end

    local mdl = pickDisguiseModel(pred)
    if pred.SetModel and mdl then
        pcall(pred.SetModel, pred, mdl)
    end
    if pred.SetSkin then pcall(pred.SetSkin, pred, math.random(0, 1)) end
    if pred.SetColor then pcall(pred.SetColor, pred, Color(255, 255, 255)) end
    if pred.SetMaterial then pcall(pred.SetMaterial, pred, "") end

    -- Keep predator guts; only the outward identity is faked.
    pred.VNPC_AssassinDisguised = true
    pred.VNPC_IsCitizenPrey = true
    if pred.SetNWBool then
        pred:SetNWBool("VNPC_IsSecretAssassin", true)
        pred:SetNWBool("VNPC_AssassinDisguised", true)
    end

    -- Hide weapons so she does not look like a combat NPC while undercover.
    if pred.GetActiveWeapon then
        local wep = pred:GetActiveWeapon()
        if IsValid(wep) then
            pred.VNPC_AssassinHolsteredWeapon = wep:GetClass()
            if pred.DropWeapon then pcall(pred.DropWeapon, pred) end
            if IsValid(wep) then wep:Remove() end
        end
    end

    return true
end

function VNPC_RestoreAssassinIdentity(pred)
    if not IsValid(pred) then return end

    if pred.VNPC_AssassinOriginalModel and pred.SetModel then
        pcall(pred.SetModel, pred, pred.VNPC_AssassinOriginalModel)
    end
    if pred.VNPC_AssassinOriginalSkin and pred.SetSkin then
        pcall(pred.SetSkin, pred, pred.VNPC_AssassinOriginalSkin)
    end
    if pred.VNPC_AssassinOriginalBodygroups and pred.SetBodygroup then
        for i, bg in pairs(pred.VNPC_AssassinOriginalBodygroups) do
            pcall(pred.SetBodygroup, pred, i, bg)
        end
    end
    if pred.VNPC_AssassinOriginalColor and pred.SetColor then
        pcall(pred.SetColor, pred, pred.VNPC_AssassinOriginalColor)
    end
    if pred.VNPC_AssassinOriginalMaterial and pred.SetMaterial then
        pcall(pred.SetMaterial, pred, pred.VNPC_AssassinOriginalMaterial)
    end

    pred.VNPC_AssassinDisguised = nil
    pred.VNPC_IsCitizenPrey = nil
    if pred.SetNWBool then
        pred:SetNWBool("VNPC_AssassinDisguised", false)
    end
end

local function removeFromPredatorCampRoster(pred)
    local camp = VNPC_GetPredatorCamp and VNPC_GetPredatorCamp(pred) or nil
    if camp and camp.members then
        for i = #camp.members, 1, -1 do
            if camp.members[i] == pred then
                table.remove(camp.members, i)
            end
        end
    end
    -- Keep VNPC_CampID so she still knows which home to return to, but clear
    -- camp role so foraging AI does not reassign her mid-mission.
    pred.VNPC_CampRole = "assassin"
    pred.VNPC_AssassinHomeCampID = pred.VNPC_CampID or pred.VNPC_AssassinHomeCampID
end

local function enrollInPreyCamp(pred, preyCamp)
    if not IsValid(pred) or not preyCamp then return false end

    -- Leave any previous prey camp membership first.
    if pred.VNPC_PreyCampID and VNPC_GetPreyCamp then
        local old = VNPC_GetPreyCamp(pred)
        if old and old.members then
            for i = #old.members, 1, -1 do
                if old.members[i] == pred then
                    table.remove(old.members, i)
                end
            end
        end
    end

    preyCamp.members = preyCamp.members or {}
    if not table.HasValue(preyCamp.members, pred) then
        table.insert(preyCamp.members, pred)
    end

    pred.VNPC_PreyCampID = preyCamp.id
    pred.VNPC_PreyRole = "citizen"
    pred.VNPC_TownRole = "mate"
    pred.VNPC_AssassinTargetCampID = preyCamp.id
    pred.VNPC_AssassinTargetCamp = preyCamp

    setFriendlyWithCamp(pred, preyCamp, true)
    return true
end

local function unenrollFromPreyCamp(pred)
    if not IsValid(pred) then return end
    local camp = pred.VNPC_AssassinTargetCamp
    if (not camp or not camp.members) and VNPC_GetPreyCamp then
        camp = VNPC_GetPreyCamp(pred)
    end
    if camp and camp.members then
        for i = #camp.members, 1, -1 do
            if camp.members[i] == pred then
                table.remove(camp.members, i)
            end
        end
        setFriendlyWithCamp(pred, camp, false)
    end
    if camp and camp.assassin == pred then
        camp.assassin = nil
    end
    pred.VNPC_PreyCampID = nil
    pred.VNPC_PreyRole = nil
    pred.VNPC_TownRole = nil
    pred.VNPC_AssassinTargetCamp = nil
    pred.VNPC_AssassinTargetCampID = nil
end

function VNPC_ClearSecretAssassin(pred, rejoinHome)
    if not IsValid(pred) then return end

    unenrollFromPreyCamp(pred)
    VNPC_RestoreAssassinIdentity(pred)

    pred:RemoveFlags(FL_NOTARGET)
    pred.VNPC_IsSecretAssassin = nil
    pred.VNPC_AssassinPhase = nil
    pred.VNPC_AssassinNightActive = nil
    pred.VNPC_AssassinSwallowCount = nil
    pred.VNPC_AssassinDispatchTime = nil
    pred.VNPC_NextAssassinMoveTime = nil
    pred.VNPC_NextAssassinHuntTime = nil
    if pred.SetNWBool then
        pred:SetNWBool("VNPC_IsSecretAssassin", false)
        pred:SetNWBool("VNPC_AssassinDisguised", false)
        pred:SetNWBool("VNPC_AssassinNightActive", false)
    end

    for i = #VNPC_ActiveSecretAssassins, 1, -1 do
        if VNPC_ActiveSecretAssassins[i] == pred then
            table.remove(VNPC_ActiveSecretAssassins, i)
        end
    end

    if rejoinHome ~= false then
        local homeID = pred.VNPC_AssassinHomeCampID or pred.VNPC_CampID
        pred.VNPC_CampID = homeID
        pred.VNPC_CampRole = "stayer"
        if homeID and VNPC_GetPredatorCamp then
            -- Ensure she is back on the home roster.
            local home = nil
            for _, c in ipairs(VNPC_ActivePredatorCamps or {}) do
                if c.id == homeID then home = c break end
            end
            if home then
                home.members = home.members or {}
                if not table.HasValue(home.members, pred) then
                    table.insert(home.members, pred)
                end
                if pred.SetLastPosition then pcall(pred.SetLastPosition, pred, home.pos) end
                if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_FORCED_GO_RUN) end
            end
        elseif VNPC_AssignPredatorToCamp then
            VNPC_AssignPredatorToCamp(pred, true)
        end
    end

    pred.VNPC_AssassinHomeCampID = nil
    pred.VNPC_AssassinHomeCamp = nil
end

function VNPC_DispatchSecretAssassin(pred, preyCamp, predCamp)
    if not assassin_enabled:GetBool() then return false end
    if not isPredatorCandidate(pred) then return false end
    if not preyCamp or not preyCamp.pos then return false end
    if not bellyIsEmpty(pred) then return false end

    predCamp = predCamp or (VNPC_GetPredatorCamp and VNPC_GetPredatorCamp(pred)) or nil

    -- Ensure she can actually swallow once night hits.
    if not pred.VNPC_FemaleModelVore and not pred.IsDrGNextbot and VNPC_GiveFemaleModelVore then
        pred.VNPC_ForceFemaleVore = true
        pcall(VNPC_GiveFemaleModelVore, pred)
    end

    removeFromPredatorCampRoster(pred)

    pred.VNPC_IsSecretAssassin = true
    pred.VNPC_AssassinPhase = "travel"
    pred.VNPC_AssassinNightActive = false
    pred.VNPC_AssassinSwallowCount = 0
    pred.VNPC_AssassinDispatchTime = CurTime()
    pred.VNPC_AssassinHomeCamp = predCamp
    pred.VNPC_AssassinHomeCampID = (predCamp and predCamp.id) or pred.VNPC_CampID
    pred.VNPC_AssassinTargetCamp = preyCamp
    pred.VNPC_AssassinTargetCampID = preyCamp.id
    pred.VNPC_CampRole = "assassin"
    pred:AddFlags(FL_NOTARGET)

    if pred.SetEnemy then pcall(pred.SetEnemy, pred, nil) end
    if pred.SetTarget then pcall(pred.SetTarget, pred, nil) end

    VNPC_ApplyAssassinDisguise(pred)

    if not table.HasValue(VNPC_ActiveSecretAssassins, pred) then
        table.insert(VNPC_ActiveSecretAssassins, pred)
    end

    preyCamp.assassin = pred
    preyCamp.nextAssassinArrivalHint = CurTime() + 2.0

    if predCamp then
        predCamp.lastAssassinDispatchTime = CurTime()
        predCamp.activeAssassin = pred
    end

    if pred.SetLastPosition then pcall(pred.SetLastPosition, pred, preyCamp.pos) end
    if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_FORCED_GO_RUN) end

    print(string.format(
        "[V-NPCs] Secret Assassin: Predator #%d dispatched from Pred Camp #%s toward Prey Camp #%s (disguised as prey).",
        pred:EntIndex(),
        tostring(pred.VNPC_AssassinHomeCampID or "?"),
        tostring(preyCamp.id)
    ))
    hook.Run("VNPC_OnSecretAssassinDispatched", pred, preyCamp, predCamp)
    return true
end

local function pickPreyCampTarget(fromPos)
    local minMembers = assassin_min_prey:GetInt() or 4
    local best, bestDist = nil, 5000 * 5000
    for _, camp in ipairs(VNPC_ActivePreyCamps or {}) do
        if not camp.pos then continue end
        local living = 0
        for _, mem in ipairs(camp.members or {}) do
            if IsValid(mem) and mem:Health() > 0 and not mem.Vored and not mem.VNPC_Vored and not mem.VNPC_IsSecretAssassin then
                living = living + 1
            end
        end
        if living < minMembers then continue end
        if IsValid(camp.assassin) and camp.assassin:Health() > 0 and camp.assassin.VNPC_IsSecretAssassin then
            continue
        end
        local dSqr = fromPos:DistToSqr(camp.pos)
        if dSqr < bestDist then
            best = camp
            bestDist = dSqr
        end
    end
    return best
end

local function pickAssassinFromCamp(predCamp)
    if not predCamp or not predCamp.members then return nil end
    local candidates = {}
    for _, mem in ipairs(predCamp.members) do
        if isPredatorCandidate(mem) and bellyIsEmpty(mem) then
            -- Prefer empty-bellied non-founders so the camp keeps a leader.
            local score = 1
            if mem.VNPC_IsCampFounder or mem.VNPC_CampRole == "founder" then
                score = score - 0.5
            end
            if mem.VNPC_IsSleeping then score = -1 end
            if score > 0 then
                table.insert(candidates, { ent = mem, score = score })
            end
        end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a, b) return a.score > b.score end)
    return candidates[1].ent
end

function VNPC_TryDispatchSecretAssassinFromCamp(predCamp, now)
    if not assassin_enabled:GetBool() or not predCamp then return false end
    if (predCamp.lastAssassinDispatchTime or 0) + assassin_interval:GetFloat() > now then return false end
    if IsValid(predCamp.activeAssassin) and predCamp.activeAssassin.VNPC_IsSecretAssassin then return false end
    if countActiveAssassins() >= assassin_max:GetInt() then return false end
    if #(predCamp.members or {}) < 2 then return false end

    -- Only send when the camp is at least somewhat hungry / empty-bellied.
    local hungry = 0
    local hThresh = assassin_hunger:GetFloat()
    for _, mem in ipairs(predCamp.members or {}) do
        if IsValid(mem) and (bellyIsEmpty(mem) or (mem.VNPC_Hunger or 0) >= hThresh) then
            hungry = hungry + 1
        end
    end
    if hungry < 1 then return false end

    local assassin = pickAssassinFromCamp(predCamp)
    if not IsValid(assassin) then return false end

    local preyCamp = pickPreyCampTarget(predCamp.pos or assassin:GetPos())
    if not preyCamp then return false end

    return VNPC_DispatchSecretAssassin(assassin, preyCamp, predCamp)
end

local function isNightNow()
    if VNPC_IsStormFox2Night and VNPC_IsStormFox2Night() then
        return true
    end
    -- Fallback without StormFox: use engine clock if available, else simulated flag only.
    if VNPC_SimulatedStormFox2Time == "night" then
        return true
    end
    return false
end

local function moveEntityTo(ent, pos, run)
    if not IsValid(ent) or not pos then return end
    if ent.SetLastPosition then pcall(ent.SetLastPosition, ent, pos) end
    if ent.SetSchedule then
        pcall(ent.SetSchedule, ent, run and SCHED_FORCED_GO_RUN or SCHED_FORCED_GO)
    end
end

local function undercoverIdleBehavior(pred, preyCamp, now)
    if not IsValid(pred) or not preyCamp then return end
    if (pred.VNPC_NextAssassinMoveTime or 0) > now then return end
    pred.VNPC_NextAssassinMoveTime = now + math.random(4, 9)

    -- Hang around the courtyard / fire / a hut like a normal citizen.
    local spots = {}
    if IsValid(preyCamp.campfire) then table.insert(spots, preyCamp.campfire:GetPos()) end
    if preyCamp.pos then table.insert(spots, preyCamp.pos) end
    for _, hut in ipairs(preyCamp.huts or {}) do
        local hp = (VNPC_GetHutInteriorPos and VNPC_GetHutInteriorPos(hut)) or (hut and hut.pos) or nil
        if hp then table.insert(spots, hp) end
    end
    if IsValid(preyCamp.leaderTable) then
        table.insert(spots, preyCamp.leaderTable:GetPos())
    end

    if #spots == 0 then return end
    local target = spots[math.random(1, #spots)]
    local jitter = Vector(math.random(-40, 40), math.random(-40, 40), 0)
    moveEntityTo(pred, target + jitter, false)

    -- Keep relationships friendly while posing.
    setFriendlyWithCamp(pred, preyCamp, true)
    if pred.SetEnemy then pcall(pred.SetEnemy, pred, nil) end
end

local function pickNightVictim(pred, preyCamp)
    if not IsValid(pred) or not preyCamp then return nil end
    local best, bestScore = nil, -1e9
    local myPos = pred:GetPos()
    for _, mem in ipairs(preyCamp.members or {}) do
        if not IsValid(mem) or mem == pred then continue end
        if mem:Health() <= 0 or mem.Vored or mem.VNPC_Vored then continue end
        if mem.VNPC_IsSecretAssassin then continue end
        if mem:IsPlayer() then continue end
        if VNPC_IsFamilyOrMate and VNPC_IsFamilyOrMate(pred, mem) then continue end
        if VNPC_IsPreyEmissary and VNPC_IsPreyEmissary(mem) then continue end

        local dist = myPos:Distance(mem:GetPos())
        local score = 1000 - dist
        if mem.VNPC_IsSleeping then score = score + 400 end
        if mem.VNPC_IsCollectingScrap then score = score - 100 end
        if VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(mem) then
            score = score + 25
        end
        if score > bestScore then
            bestScore = score
            best = mem
        end
    end
    return best
end

local function trySwallowVictim(pred, victim)
    if not IsValid(pred) or not IsValid(victim) then return false end
    if victim.Vored or victim.VNPC_Vored then return false end

    local ok = false
    if pred.EatEntity then
        local success, result = pcall(pred.EatEntity, pred, victim)
        ok = success and result
    end
    if not ok then
        local belly = pred.VNPC_Belly or pred.Belly
        if IsValid(belly) and belly.AddPrey then
            local success, result = pcall(belly.AddPrey, belly, victim)
            ok = success and result
        end
    end

    if ok then
        pred.VNPC_AssassinSwallowCount = (pred.VNPC_AssassinSwallowCount or 0) + 1
        print(string.format(
            "[V-NPCs] Secret Assassin #%d swallowed prey #%d at night (count %d).",
            pred:EntIndex(), victim:EntIndex(), pred.VNPC_AssassinSwallowCount or 0
        ))
        hook.Run("VNPC_OnSecretAssassinSwallow", pred, victim)
    end
    return ok
end

local function activateNightMode(pred, preyCamp)
    if not IsValid(pred) then return end
    pred.VNPC_AssassinPhase = "night"
    pred.VNPC_AssassinNightActive = true
    pred.VNPC_AssassinAllowCampSwallow = true
    if pred.SetNWBool then
        pred:SetNWBool("VNPC_AssassinNightActive", true)
        pred:SetNWBool("VNPC_AssassinDisguised", false)
    end

    -- Drop the disguise so she looks like a predator again once the raid starts.
    VNPC_RestoreAssassinIdentity(pred)
    -- Stay listed on the prey camp roster only for targeting; relationships go hostile.
    if preyCamp then
        setFriendlyWithCamp(pred, preyCamp, false)
    end
    pred:RemoveFlags(FL_NOTARGET)

    if pred.EmitSound then
        pred:EmitSound("npc/alyx/gasp03.wav", 70, math.random(95, 105))
    end

    print(string.format(
        "[V-NPCs] Secret Assassin #%d dropped cover at Prey Camp #%s — night raid started.",
        pred:EntIndex(), tostring(preyCamp and preyCamp.id or "?")
    ))
    hook.Run("VNPC_OnSecretAssassinNightStart", pred, preyCamp)
end

local function beginEscape(pred, preyCamp)
    if not IsValid(pred) then return end
    pred.VNPC_AssassinPhase = "escape"
    pred.VNPC_AssassinNightActive = false
    pred.VNPC_AssassinAllowCampSwallow = nil
    if pred.SetNWBool then
        pred:SetNWBool("VNPC_AssassinNightActive", false)
    end

    unenrollFromPreyCamp(pred)
    VNPC_RestoreAssassinIdentity(pred)
    pred:RemoveFlags(FL_NOTARGET)

    local homePos = nil
    local homeID = pred.VNPC_AssassinHomeCampID
    if homeID then
        for _, c in ipairs(VNPC_ActivePredatorCamps or {}) do
            if c.id == homeID then
                homePos = c.pos
                break
            end
        end
    end
    if not homePos and preyCamp and preyCamp.pos then
        -- Sprint away from the prey fort if home is unknown.
        local away = (pred:GetPos() - preyCamp.pos)
        if away:Length2DSqr() < 1 then away = Vector(1, 0, 0) end
        homePos = pred:GetPos() + away:GetNormalized() * 1200
    end

    if homePos then
        moveEntityTo(pred, homePos, true)
    end

    print(string.format(
        "[V-NPCs] Secret Assassin #%d escaping after night raid (swallowed %d).",
        pred:EntIndex(), pred.VNPC_AssassinSwallowCount or 0
    ))
    hook.Run("VNPC_OnSecretAssassinEscape", pred, preyCamp)
end

function VNPC_SecretAssassin_AI(now)
    if not assassin_enabled:GetBool() then return end
    now = now or CurTime()
    local night = isNightNow()
    local swallowRange = assassin_range:GetFloat() or 130
    local maxSwallows = assassin_max_swallows:GetInt() or 3

    for i = #VNPC_ActiveSecretAssassins, 1, -1 do
        local pred = VNPC_ActiveSecretAssassins[i]
        if not IsValid(pred) or pred:Health() <= 0 or pred.Vored or pred.VNPC_Vored then
            if IsValid(pred) then VNPC_ClearSecretAssassin(pred, false) end
            table.remove(VNPC_ActiveSecretAssassins, i)
            continue
        end

        local preyCamp = pred.VNPC_AssassinTargetCamp
        if (not preyCamp or not preyCamp.id) and pred.VNPC_AssassinTargetCampID then
            for _, c in ipairs(VNPC_ActivePreyCamps or {}) do
                if c.id == pred.VNPC_AssassinTargetCampID then
                    preyCamp = c
                    pred.VNPC_AssassinTargetCamp = c
                    break
                end
            end
        end

        -- Target camp wiped out: abort and go home.
        if not preyCamp or not preyCamp.pos then
            beginEscape(pred, nil)
            continue
        end

        local phase = pred.VNPC_AssassinPhase or "travel"

        if phase == "travel" then
            local dSqr = pred:GetPos():DistToSqr(preyCamp.pos)
            if dSqr <= (280 * 280) then
                enrollInPreyCamp(pred, preyCamp)
                pred.VNPC_AssassinPhase = "undercover"
                print(string.format(
                    "[V-NPCs] Secret Assassin #%d infiltrated Prey Camp #%s and is posing as a citizen.",
                    pred:EntIndex(), tostring(preyCamp.id)
                ))
                hook.Run("VNPC_OnSecretAssassinUndercover", pred, preyCamp)
            else
                if (pred.VNPC_NextAssassinMoveTime or 0) <= now then
                    pred.VNPC_NextAssassinMoveTime = now + 2.0
                    moveEntityTo(pred, preyCamp.pos, true)
                end
            end

        elseif phase == "undercover" then
            -- Stay enrolled and look harmless until night.
            if pred.VNPC_PreyCampID ~= preyCamp.id then
                enrollInPreyCamp(pred, preyCamp)
            end
            if not pred.VNPC_AssassinDisguised then
                VNPC_ApplyAssassinDisguise(pred)
            end
            pred:AddFlags(FL_NOTARGET)

            if night then
                activateNightMode(pred, preyCamp)
            else
                undercoverIdleBehavior(pred, preyCamp, now)
            end

        elseif phase == "night" then
            if not night then
                -- Dawn: bail out before the camp fully wakes and organizes.
                beginEscape(pred, preyCamp)
                continue
            end

            if (pred.VNPC_AssassinSwallowCount or 0) >= maxSwallows then
                beginEscape(pred, preyCamp)
                continue
            end

            -- Full belly also ends the raid.
            local belly = pred.VNPC_Belly or pred.Belly
            if IsValid(belly) and VNPC_GetBellyCapacity and belly.GetCollectivePreyValue then
                local used = belly:GetCollectivePreyValue() or 0
                local cap = VNPC_GetBellyCapacity(belly, pred)
                if used >= cap * 0.92 then
                    beginEscape(pred, preyCamp)
                    continue
                end
            end

            if (pred.VNPC_NextAssassinHuntTime or 0) > now then continue end
            pred.VNPC_NextAssassinHuntTime = now + 0.6

            local victim = pickNightVictim(pred, preyCamp)
            if not IsValid(victim) then
                beginEscape(pred, preyCamp)
                continue
            end

            local dist = pred:GetPos():Distance(victim:GetPos())
            if dist <= swallowRange then
                trySwallowVictim(pred, victim)
            else
                moveEntityTo(pred, victim:GetPos(), not victim.VNPC_IsSleeping)
                if pred.SetEnemy then pcall(pred.SetEnemy, pred, victim) end
            end

        elseif phase == "escape" then
            local homeID = pred.VNPC_AssassinHomeCampID
            local homePos = nil
            if homeID then
                for _, c in ipairs(VNPC_ActivePredatorCamps or {}) do
                    if c.id == homeID then
                        homePos = c.pos
                        if c.activeAssassin == pred then c.activeAssassin = nil end
                        break
                    end
                end
            end

            if homePos then
                local dSqr = pred:GetPos():DistToSqr(homePos)
                if dSqr <= (300 * 300) then
                    if VNPC_AddPredatorXP then
                        local xp = 100 + ((pred.VNPC_AssassinSwallowCount or 0) * 80)
                        VNPC_AddPredatorXP(pred, xp, "Secret assassin night raid")
                    end
                    print(string.format(
                        "[V-NPCs] Secret Assassin #%d returned home (swallowed %d).",
                        pred:EntIndex(), pred.VNPC_AssassinSwallowCount or 0
                    ))
                    hook.Run("VNPC_OnSecretAssassinReturned", pred, pred.VNPC_AssassinSwallowCount or 0)
                    VNPC_ClearSecretAssassin(pred, true)
                else
                    if (pred.VNPC_NextAssassinMoveTime or 0) <= now then
                        pred.VNPC_NextAssassinMoveTime = now + 1.5
                        moveEntityTo(pred, homePos, true)
                    end
                end
            else
                -- No home camp: just clear mission state where she stands.
                VNPC_ClearSecretAssassin(pred, true)
            end
        end
    end
end

-- Main loop: dispatch from hungry predator camps + drive active assassins.
hook.Add("Think", "VNPC_SecretAssassins_Loop", function()
    if not assassin_enabled:GetBool() then return end
    local now = CurTime()
    if (VNPC_NextSecretAssassinThink or 0) > now then return end
    VNPC_NextSecretAssassinThink = now + 1.0

    -- Drive active missions first.
    VNPC_SecretAssassin_AI(now)

    -- Then consider new dispatches (daytime preferred so they arrive before night).
    if isNightNow() then return end
    if countActiveAssassins() >= assassin_max:GetInt() then return end

    for _, camp in ipairs(VNPC_ActivePredatorCamps or {}) do
        if (camp.nextAssassinEvalTime or 0) > now then continue end
        camp.nextAssassinEvalTime = now + math.random(8, 16)
        VNPC_TryDispatchSecretAssassinFromCamp(camp, now)
    end
end)

hook.Add("EntityRemoved", "VNPC_SecretAssassin_Cleanup", function(ent)
    if not IsValid(ent) or not ent.VNPC_IsSecretAssassin then return end
    for i = #VNPC_ActiveSecretAssassins, 1, -1 do
        if VNPC_ActiveSecretAssassins[i] == ent then
            table.remove(VNPC_ActiveSecretAssassins, i)
        end
    end
    if ent.VNPC_AssassinTargetCamp and ent.VNPC_AssassinTargetCamp.assassin == ent then
        ent.VNPC_AssassinTargetCamp.assassin = nil
    end
    local homeID = ent.VNPC_AssassinHomeCampID
    if homeID then
        for _, c in ipairs(VNPC_ActivePredatorCamps or {}) do
            if c.id == homeID and c.activeAssassin == ent then
                c.activeAssassin = nil
            end
        end
    end
end)

concommand.Add("vnpcs_assassin_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Secret Assassin Status")
    print("Enabled: " .. tostring(assassin_enabled:GetBool()))
    print("Night now: " .. tostring(isNightNow()))
    print("Active assassins: " .. tostring(countActiveAssassins()) .. " / " .. tostring(assassin_max:GetInt()))
    print("Dispatch interval: " .. tostring(assassin_interval:GetFloat()) .. "s")
    print("Max swallows / raid: " .. tostring(assassin_max_swallows:GetInt()))
    print("-----------------------------------------")
    for _, pred in ipairs(VNPC_ActiveSecretAssassins) do
        if IsValid(pred) then
            print(string.format(
                " -> Assassin #%d [%s] phase=%s night=%s swallowed=%d targetCamp=%s homeCamp=%s disguised=%s",
                pred:EntIndex(),
                pred.PrintName or pred:GetClass(),
                tostring(pred.VNPC_AssassinPhase),
                tostring(pred.VNPC_AssassinNightActive),
                pred.VNPC_AssassinSwallowCount or 0,
                tostring(pred.VNPC_AssassinTargetCampID),
                tostring(pred.VNPC_AssassinHomeCampID),
                tostring(pred.VNPC_AssassinDisguised)
            ))
        end
    end
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Secret assassin status printed to console. Active: " .. countActiveAssassins())
    end
end)

concommand.Add("vnpcs_test_secret_assassin", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity

    local pred = nil
    local preyCamp = nil

    if IsValid(target) and (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator or target.EatEntity) then
        pred = target
    elseif IsValid(target) and target.VNPC_PreyCampID and VNPC_GetPreyCamp then
        preyCamp = VNPC_GetPreyCamp(target)
    end

    if not preyCamp then
        for _, c in ipairs(VNPC_ActivePreyCamps or {}) do
            if #(c.members or {}) > 0 then
                preyCamp = c
                break
            end
        end
    end

    if not IsValid(pred) then
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            if isPredatorCandidate(ent) and bellyIsEmpty(ent) then
                pred = ent
                break
            end
        end
    end

    if not IsValid(pred) then
        ply:ChatPrint("[V-NPCs] No eligible predator found to become a secret assassin. Aim at one or spawn predators.")
        return
    end
    if not preyCamp then
        ply:ChatPrint("[V-NPCs] No active prey camp found. Establish a prey camp first.")
        return
    end

    local predCamp = VNPC_GetPredatorCamp and VNPC_GetPredatorCamp(pred) or nil
    if VNPC_DispatchSecretAssassin(pred, preyCamp, predCamp) then
        -- Snap her near the fort so the undercover phase is easy to observe.
        if preyCamp.pos then
            pred:SetPos(preyCamp.pos + Vector(80, 0, 10))
            enrollInPreyCamp(pred, preyCamp)
            pred.VNPC_AssassinPhase = "undercover"
        end
        ply:ChatPrint(string.format(
            "[V-NPCs] %s is now a secret assassin posing at Prey Camp #%s. Use vnpcs_test_stormfox2_night night (or wait for night) to start the raid.",
            tostring(pred), tostring(preyCamp.id)
        ))
    else
        ply:ChatPrint("[V-NPCs] Failed to dispatch secret assassin.")
    end
end)

concommand.Add("vnpcs_test_assassin_night", function(ply)
    if not IsValid(ply) then return end
    -- Force simulated night so the raid triggers without StormFox.
    VNPC_SimulatedStormFox2Time = "night"
    local activated = 0
    for _, pred in ipairs(VNPC_ActiveSecretAssassins) do
        if IsValid(pred) and pred.VNPC_AssassinPhase == "undercover" then
            activateNightMode(pred, pred.VNPC_AssassinTargetCamp)
            activated = activated + 1
        end
    end
    if activated == 0 then
        -- If none undercover, try a full test dispatch first.
        RunConsoleCommand("vnpcs_test_secret_assassin")
        timer.Simple(0.2, function()
            for _, pred in ipairs(VNPC_ActiveSecretAssassins) do
                if IsValid(pred) and pred.VNPC_AssassinPhase == "undercover" then
                    activateNightMode(pred, pred.VNPC_AssassinTargetCamp)
                end
            end
        end)
        ply:ChatPrint("[V-NPCs] Forced night. Dispatched/activated secret assassin raid.")
    else
        ply:ChatPrint("[V-NPCs] Forced night and activated " .. activated .. " undercover assassin(s).")
    end
end)

concommand.Add("vnpcs_clear_secret_assassins", function(ply)
    local n = 0
    for i = #VNPC_ActiveSecretAssassins, 1, -1 do
        local pred = VNPC_ActiveSecretAssassins[i]
        if IsValid(pred) then
            VNPC_ClearSecretAssassin(pred, true)
            n = n + 1
        end
        table.remove(VNPC_ActiveSecretAssassins, i)
    end
    print("[V-NPCs] Cleared " .. n .. " secret assassins.")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Cleared " .. n .. " secret assassins.")
    end
end)

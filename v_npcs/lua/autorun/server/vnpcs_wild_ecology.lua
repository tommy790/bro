-- V-NPCs Wild Ecology & Prey Camp Intelligence Agency Engine (vnpcs_wild_ecology.lua)
-- Spawns wandering wild predators (1.35x danger) and wild prey; fortified prey camps dispatch intelligence agents to scout and report danger zones

local ecology_enabled = CreateConVar("vnpcs_wild_ecology_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable wild wandering predators/prey and prey camp intelligence agents")
local wild_chance = CreateConVar("vnpcs_wild_spawn_chance", "25", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Percentage chance that an unassigned NPC becomes a Wild Wanderer instead of joining a camp")
local pred_danger = CreateConVar("vnpcs_wild_pred_danger_scale", "1.35", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Health and combat danger multiplier for wild solitary predators")
local recon_range = CreateConVar("vnpcs_prey_agent_recon_range", "900.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Distance within which an Intelligence Agent discovers a predator camp or wild hotspot")
local spawner_interval = CreateConVar("vnpcs_wild_spawner_interval", "20.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Interval in seconds between spawning wild wandering NPCs in the map")
local max_wild_prey = CreateConVar("vnpcs_wild_max_prey", "12", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum number of active wild wandering prey NPCs in the map")
local max_wild_preds = CreateConVar("vnpcs_wild_max_preds", "4", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum number of active wild wandering solitary predators in the map")
local wild_mating_enabled = CreateConVar("vnpcs_wild_mating_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable wild predator and prey mating in wilderness")

VNPC_WildPredatorHotspots = VNPC_WildPredatorHotspots or {}
VNPC_ActiveWildWanderers = VNPC_ActiveWildWanderers or {}

function VNPC_RecordWildHotspot(pos)
    if not pos or not isvector(pos) then return end
    local now = CurTime()
    for _, spot in ipairs(VNPC_WildPredatorHotspots) do
        if spot.pos:DistToSqr(pos) < (300 * 300) then
            spot.time = now
            return
        end
    end
    table.insert(VNPC_WildPredatorHotspots, { pos = pos, time = now })
    while #VNPC_WildPredatorHotspots > 25 do
        table.remove(VNPC_WildPredatorHotspots, 1)
    end
end

function VNPC_MakeWildWanderer(ent)
    if not ecology_enabled:GetBool() then return false end
    if not IsValid(ent) or ent:Health() <= 0 then return false end

    ent.VNPC_IsWildWanderer = true
    local predPersList = {
        "loving", "loving", "loving", "loving",
        "aggressive", "opportunistic", "glutton", "shy", "selective", "gentle"
    }
    local preyPersList = { "fighter", "passive", "panicked", "stubborn", "willing" }

    if ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator then
        ent.VNPC_WildType = "predator"
        local scale = pred_danger:GetFloat() or 1.35
        local curMax = ent:GetMaxHealth() or 100
        ent:SetMaxHealth(math.floor(curMax * scale))
        ent:SetHealth(ent:GetMaxHealth())
        if ent.VoreSettings then
            ent.VoreSettings.DigestionStrength = (ent.VoreSettings.DigestionStrength or 3) * scale
        end
        local pPers = predPersList[math.random(1, #predPersList)]
        ent.VNPC_PredatorPersonality = pPers
        if ent.VoreSettings then
            ent.VoreSettings.PredatorPersonality = pPers
        end
    else
        ent.VNPC_WildType = "prey"
        local rPers = preyPersList[math.random(1, #preyPersList)]
        ent.VNPC_PreyPersonality = rPers
        ent.PreyPersonality = rPers
    end

    if VNPC_RandomizePersonalities then
        pcall(VNPC_RandomizePersonalities, ent)
    end

    if not table.HasValue(VNPC_ActiveWildWanderers, ent) then
        table.insert(VNPC_ActiveWildWanderers, ent)
    end

    return true
end

function VNPC_IsValidGroundSpawnPos(pos)
    if not pos or not isvector(pos) then return false end

    local tr = util.TraceLine({
        start = pos + Vector(0, 0, 40),
        endpos = pos - Vector(0, 0, 100),
        mask = MASK_SOLID_BRUSHONLY
    })
    if not tr.Hit or tr.StartSolid or tr.HitNormal.z < 0.75 then
        return false
    end

    local groundPos = tr.HitPos

    -- 1. Check vertical clearance (no low ceilings / getting stuck inside brush)
    local trUp = util.TraceLine({
        start = groundPos + Vector(0, 0, 5),
        endpos = groundPos + Vector(0, 0, 75),
        mask = MASK_SOLID_BRUSHONLY
    })
    if trUp.Hit and not trUp.HitSky then
        return false
    end

    -- 2. Check NavMesh navigability & connectivity (rejects roofs and isolated ledges!)
    if navmesh and navmesh.IsLoaded and navmesh.IsLoaded() then
        local area = navmesh.GetNavArea(groundPos, 80)
        if not IsValid(area) then
            return false
        end
        if (area.GetSizeX and area:GetSizeX() < 48) or (area.GetSizeY and area:GetSizeY() < 48) then
            return false
        end
        if area.GetAdjacentAreas and #area:GetAdjacentAreas() == 0 then
            return false
        end
    end

    -- 3. Check 4-direction horizontal freedom (not trapped in a hole or cage)
    local blockedCount = 0
    local dirs = { Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0) }
    for _, dir in ipairs(dirs) do
        local trWall = util.TraceLine({
            start = groundPos + Vector(0, 0, 32),
            endpos = groundPos + Vector(0, 0, 32) + dir * 45,
            mask = MASK_SOLID_BRUSHONLY
        })
        if trWall.Hit then
            blockedCount = blockedCount + 1
        end
    end
    if blockedCount >= 3 then
        return false
    end

    return true, groundPos + Vector(0, 0, 10)
end

function VNPC_FindWildernessSpawnPos()
    local candidates = {}

    -- 1. Collect from Navigation Mesh areas across the entire map
    if navmesh and navmesh.GetAllNavAreas then
        for _, area in ipairs(navmesh.GetAllNavAreas() or {}) do
            if IsValid(area) and area.GetCenter then
                if (area.GetSizeX and area:GetSizeX() >= 48) and (area.GetSizeY and area:GetSizeY() >= 48) then
                    if area.GetAdjacentAreas and #area:GetAdjacentAreas() > 0 then
                        table.insert(candidates, area:GetCenter() + Vector(0, 0, 15))
                    end
                end
            end
        end
    end

    -- 2. Collect from AI nodes and spawn points across the entire map
    local nodeClasses = {
        "info_node", "info_node_hint", "info_player_start", "info_player_deathmatch",
        "info_player_combine", "info_player_rebel", "info_target", "path_track"
    }
    for _, cls in ipairs(nodeClasses) do
        for _, node in ipairs(ents.FindByClass(cls)) do
            if IsValid(node) then
                table.insert(candidates, node:GetPos() + Vector(0, 0, 15))
            end
        end
    end

    -- 3. If candidates exist, try to pick a valid map-wide position from them
    local players = player.GetAll()
    for attempt = 1, 30 do
        local candidatePos = nil
        if #candidates > 0 and math.random(1, 100) <= 85 then
            candidatePos = candidates[math.random(1, #candidates)] + Vector(math.random(-40, 40), math.random(-40, 40), 10)
        else
            -- Map-wide fallback: sample across the entire world bounding box
            local world = game.GetWorld()
            if IsValid(world) and world.GetModelBounds then
                local minB, maxB = world:GetModelBounds()
                candidatePos = Vector(
                    math.random(math.floor(minB.x * 0.75), math.floor(maxB.x * 0.75)),
                    math.random(math.floor(minB.y * 0.75), math.floor(maxB.y * 0.75)),
                    math.random(math.floor(minB.z * 0.5), math.floor(maxB.z * 0.5))
                )
            else
                local angle = math.rad(math.random(0, 360))
                local dist = math.random(2000, 10000)
                candidatePos = Vector(math.cos(angle) * dist, math.sin(angle) * dist, 100)
            end
        end

        -- Ensure minimum distance from all camps and players (not spawning right on top of someone)
        local tooClose = false
        for _, camp in ipairs(VNPC_ActivePredatorCamps or {}) do
            if camp.pos and candidatePos:DistToSqr(camp.pos) < (1000 * 1000) then
                tooClose = true
                break
            end
        end
        if not tooClose then
            for _, camp in ipairs(VNPC_ActivePreyCamps or {}) do
                if camp.pos and candidatePos:DistToSqr(camp.pos) < (1000 * 1000) then
                    tooClose = true
                    break
                end
            end
        end
        if not tooClose then
            for _, p in ipairs(players) do
                -- Must not spawn directly on top of a player (at least 500 units away),
                -- but can be anywhere on the map!
                if IsValid(p) and candidatePos:DistToSqr(p:GetPos()) < (500 * 500) then
                    tooClose = true
                    break
                end
            end
        end

        if not tooClose then
            local valid, goodPos = VNPC_IsValidGroundSpawnPos(candidatePos)
            if valid and goodPos then
                return goodPos
            end
        end
    end
    return nil
end

local WILD_PREDATOR_CLASSES = {
    { cls = "npc_vortigaunt",  mdl = nil },
    { cls = "npc_metropolice", mdl = nil },
    { cls = "npc_combine_s",   mdl = nil },
    { cls = "npc_zombie",      mdl = nil },
    { cls = "npc_alyx",        mdl = "models/alyx.mdl" },
    { cls = "npc_mossman",     mdl = "models/mossman.mdl" },
    { cls = "npc_citizen",     mdl = "models/Humans/Group01/Female_01.mdl" },
    { cls = "npc_citizen",     mdl = "models/Humans/Group01/Female_02.mdl" }
}

function VNPC_ForceGiveWildPredatorVore(ent)
    if not IsValid(ent) then return false end
    ent.VNPC_ForceFemaleVore = true
    if VNPC_GiveFemaleModelVore then
        VNPC_GiveFemaleModelVore(ent)
    end
    timer.Simple(0.25, function()
        if IsValid(ent) and not IsValid(ent.VNPC_Belly or ent.Belly) then
            ent.VNPC_ForceFemaleVore = true
            if VNPC_GiveFemaleModelVore then
                VNPC_GiveFemaleModelVore(ent)
            end
        end
    end)
    return true
end

local WILD_PREY_CLASSES = {
    { cls = "npc_citizen",       danger = false },
    { cls = "npc_headcrab",      danger = false },
    { cls = "npc_antlion",       danger = true },
    { cls = "npc_antlionguard",  danger = true },
    { cls = "npc_headcrab_fast", danger = true }
}

function VNPC_IsDangerousPrey(ent)
    if not IsValid(ent) then return false end
    if ent.VNPC_IsDangerousPreyFlag then return true end
    local cls = string.lower(ent:GetClass() or "")
    if cls:find("antlion") or cls:find("guard") or cls:find("combine") or cls:find("hunter") or cls:find("manhack") or cls:find("fast") or cls:find("poison") then
        return true
    end
    return false
end

function VNPC_SpawnWildNPC(isPredator, posOverride)
    if not ecology_enabled:GetBool() then return nil end
    local spawnPos = posOverride or VNPC_FindWildernessSpawnPos()
    if not spawnPos then return nil end

    local ent = nil
    if isPredator then
        local info = WILD_PREDATOR_CLASSES[math.random(1, #WILD_PREDATOR_CLASSES)]
        ent = ents.Create(info.cls)
        if IsValid(ent) then
            if info.mdl then
                ent:SetModel(info.mdl)
            end
            ent:SetPos(spawnPos)
            ent:SetAngles(Angle(0, math.random(0, 360), 0))
            ent:Spawn()
            ent:Activate()
            VNPC_ForceGiveWildPredatorVore(ent)
            VNPC_MakeWildWanderer(ent)
            if VNPC_AssignPredatorToCamp then
                VNPC_AssignPredatorToCamp(ent)
            end
        end
    else
        local info = WILD_PREY_CLASSES[math.random(1, #WILD_PREY_CLASSES)]
        ent = ents.Create(info.cls)
        if IsValid(ent) then
            ent:SetPos(spawnPos)
            ent:SetAngles(Angle(0, math.random(0, 360), 0))
            ent:Spawn()
            ent:Activate()
            ent.VNPC_IsDangerousPreyFlag = info.danger
            VNPC_MakeWildWanderer(ent)
            if VNPC_AssignPreyToCamp then
                VNPC_AssignPreyToCamp(ent)
            end
        end
    end
    return ent
end

function VNPC_AgentGatherIntelligence(agent, targetPos, targetType)
    if not IsValid(agent) or not targetPos then return end
    agent.VNPC_IntelGathered = true
    agent.VNPC_IntelTargetPos = targetPos
    agent.VNPC_IntelType = targetType or "predator_camp"
    agent:RemoveFlags(FL_NOTARGET)

    if agent.EmitSound then
        agent:EmitSound("buttons/blip1.wav", 75, 115)
    end
end

function VNPC_AgentReportIntelligence(agent, camp)
    if not IsValid(agent) or not camp or not agent.VNPC_IntelTargetPos then return end

    camp.intelReports = camp.intelReports or {}
    local report = {
        pos = agent.VNPC_IntelTargetPos,
        type = agent.VNPC_IntelType or "predator_camp",
        time = CurTime()
    }
    table.insert(camp.intelReports, report)
    while #camp.intelReports > 15 do
        table.remove(camp.intelReports, 1)
    end

    agent.VNPC_IntelGathered = nil
    agent.VNPC_ReconTargetPos = nil

    if agent.EmitSound then
        agent:EmitSound("npc/citizen/vo/wehaveaunitdown.wav", 80, 108)
    end
end

function VNPC_PreyCampIntelligence_AI(camp, now)
    if not ecology_enabled:GetBool() or not camp or not camp.fortified then return end
    if #camp.members < 5 then return end

    local agents = {}
    for _, mem in ipairs(camp.members) do
        if IsValid(mem) and mem:Health() > 0 then
            if mem.VNPC_PreyRole == "agent" then
                table.insert(agents, mem)
            else
                mem.VNPC_PreyRole = "citizen"
            end
        end
    end

    -- Ensure at least 1 or 2 Intelligence Agents in a fortified camp
    if #agents < 2 and #camp.members >= 6 then
        for _, mem in ipairs(camp.members) do
            if IsValid(mem) and mem.VNPC_PreyRole ~= "agent" and not mem.VNPC_IsPregnant then
                mem.VNPC_PreyRole = "agent"
                table.insert(agents, mem)
                if #agents >= 2 then break end
            end
        end
    end

    local range = recon_range:GetFloat()
    local rangeSqr = range * range

    for _, agent in ipairs(agents) do
        if not IsValid(agent) or agent:Health() <= 0 then continue end

        if agent.VNPC_IntelGathered then
            -- Returning to camp to report intel
            if agent.SetEnemy then pcall(agent.SetEnemy, agent, nil) end
            if agent.SetLastPosition then pcall(agent.SetLastPosition, agent, camp.pos) end
            if agent.SetSchedule then pcall(agent.SetSchedule, agent, SCHED_FORCED_GO_RUN) end

            local distSqr = agent:GetPos():DistToSqr(camp.pos)
            if distSqr <= (260 * 260) then
                VNPC_AgentReportIntelligence(agent, camp)
            end
        else
            -- On a reconnaissance mission: search for nearby predator camps or wild hotspots
            local myPos = agent:GetPos()
            local foundPos, foundType = nil, nil

            for _, predCamp in ipairs(VNPC_ActivePredatorCamps or {}) do
                if predCamp.pos and myPos:DistToSqr(predCamp.pos) <= rangeSqr then
                    foundPos = predCamp.pos
                    foundType = "predator_camp"
                    break
                end
            end

            if not foundPos then
                for _, spot in ipairs(VNPC_WildPredatorHotspots) do
                    if spot.pos and myPos:DistToSqr(spot.pos) <= rangeSqr then
                        foundPos = spot.pos
                        foundType = "wild_hotspot"
                        break
                    end
                end
            end

            if foundPos then
                VNPC_AgentGatherIntelligence(agent, foundPos, foundType)
            else
                -- Wander out across the map to scout
                if not agent.VNPC_ReconTargetPos or (agent.VNPC_NextReconMoveTime or 0) <= now then
                    agent.VNPC_NextReconMoveTime = now + 15.0
                    local angle = math.rad(math.random(0, 360))
                    local dist = math.random(800, 1600)
                    agent.VNPC_ReconTargetPos = camp.pos + Vector(math.cos(angle) * dist, math.sin(angle) * dist, 0)
                    agent:AddFlags(FL_NOTARGET) -- Stealth while scouting
                end

                if agent.VNPC_ReconTargetPos then
                    if agent.SetLastPosition then pcall(agent.SetLastPosition, agent, agent.VNPC_ReconTargetPos) end
                    if agent.SetSchedule then pcall(agent.SetSchedule, agent, SCHED_FORCED_GO) end
                end
            end
        end
    end
end

function VNPC_IsMaleWildWanderer(ent)
    if not IsValid(ent) or ent:Health() <= 0 or ent.Vored or ent.VNPC_Vored then return false end
    if ent.VNPC_IsPregnant then return false end
    if VNPC_IsAdultPreyCitizen and not VNPC_IsAdultPreyCitizen(ent) then return false end
    if VNPC_IsMalePreyCitizen and VNPC_IsMalePreyCitizen(ent) then return true end
    if VNPC_ModelLooksFemale and VNPC_ModelLooksFemale(ent) then return false end
    if ent.VNPC_ChildGender == "male" then return true end
    local mdl = string.lower(ent:GetModel() or "")
    local cls = string.lower(ent:GetClass() or "")
    if cls:find("citizen") or cls:find("rebel") or cls:find("refugee") then
        if mdl:find("male") or mdl:find("m_") or mdl:find("group01/male") or not (mdl:find("female") or mdl:find("alyx") or mdl:find("mossman") or mdl:find("girl") or mdl:find("woman")) then
            return true
        end
    end
    return false
end

function VNPC_IsFemaleWildWanderer(ent)
    if not IsValid(ent) or ent:Health() <= 0 or ent.Vored or ent.VNPC_Vored then return false end
    if ent.VNPC_IsPregnant then return false end
    if VNPC_IsAdultPreyCitizen and not VNPC_IsAdultPreyCitizen(ent) then return false end
    if ent.VNPC_WildType == "predator" or ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator then return true end
    if VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(ent) then return true end
    if VNPC_ModelLooksFemale and VNPC_ModelLooksFemale(ent) then return true end
    local mdl = string.lower(ent:GetModel() or "")
    local cls = string.lower(ent:GetClass() or "")
    if cls:find("citizen") or cls:find("rebel") or cls:find("refugee") or cls:find("alyx") or cls:find("mossman") then
        if mdl:find("female") or mdl:find("alyx") or mdl:find("mossman") or mdl:find("f_") or mdl:find("girl") or mdl:find("woman") or mdl:find("lady") then
            return true
        end
    end
    return false
end

function VNPC_FindPrivateMatingSpot(pred, mate, camp)
    if not IsValid(pred) or not IsValid(mate) then return nil end
    local predPos = pred:GetPos()

    if pred:GetPos():DistToSqr(mate:GetPos()) <= (220 * 220) then
        local mid = (pred:GetPos() + mate:GetPos()) * 0.5
        local ground = (VNPC_SnapCampPosToGround and VNPC_SnapCampPosToGround(mid, 160)) or (mid + Vector(0, 0, 8))
        return ground
    end

    if camp then
        if camp.huts and #camp.huts > 0 then
            for _, hut in ipairs(camp.huts) do
                local hutPos = (VNPC_GetHutInteriorPos and VNPC_GetHutInteriorPos(hut)) or (hut and hut.pos) or nil
                if hutPos then return hutPos end
            end
        end
        if camp.tents and #camp.tents > 0 then
            for _, tent in ipairs(camp.tents) do
                local tentPos = (VNPC_GetHutInteriorPos and VNPC_GetHutInteriorPos(tent)) or (IsValid(tent) and tent:GetPos()) or nil
                if tentPos then return tentPos end
            end
        end
        if camp.pos then
            return camp.pos + Vector(0, 0, 8)
        end
    end

    return predPos + pred:GetForward() * 48 + Vector(0, 0, 8)
end

function VNPC_BeginMatingBonePose(pred, mate, now)
    if not IsValid(pred) or not IsValid(mate) then return false end
    now = now or CurTime()
    local love = VNPC_GetMateLove and VNPC_GetMateLove(pred, mate) or 0
    if VNPC_AddMateLove then
        love = VNPC_AddMateLove(pred, mate, 8.0)
    end
    pred.VNPC_MateBondCount = (pred.VNPC_MateBondCount or 0) + 1
    mate.VNPC_MateBondCount = (mate.VNPC_MateBondCount or 0) + 1
    local dur = (VNPC_GetMatingDuration and VNPC_GetMatingDuration(love)) or 8.0
    pred.VNPC_IsMatingBonePose = true
    mate.VNPC_IsMatingBonePose = true
    pred.VNPC_MatingPoseEndTime = now + dur
    mate.VNPC_MatingPoseEndTime = now + dur
    if pred.SetNWBool then pred:SetNWBool("VNPC_IsMatingBonePose", true) end
    if mate.SetNWBool then mate:SetNWBool("VNPC_IsMatingBonePose", true) end

    local dir = (mate:GetPos() - pred:GetPos()):GetNormalized()
    dir.z = 0
    if dir:Length2DSqr() > 0.01 then
        pred:SetAngles(dir:Angle())
        mate:SetAngles((-dir):Angle())
    end

    if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_NPC_FREEZE) end
    if mate.SetSchedule then pcall(mate.SetSchedule, mate, SCHED_NPC_FREEZE) end
    if pred.EmitSound then pred:EmitSound("npc/alyx/vo/flatter.wav", 80, math.random(100, 110)) end
    if mate.EmitSound then mate:EmitSound("npc/citizen/vo/nice.wav", 75, math.random(100, 110)) end
    print(string.format("[V-NPCs] Mating Bone Pose: Couple %s & %s started the mating bone pose for %.1fs (love %.0f)!", tostring(pred), tostring(mate), dur, love))
    return true
end

function VNPC_CompleteMatingPregnancy(mother, mate)
    if not IsValid(mother) then return false end
    mother.VNPC_IsMatingBonePose = nil
    mother.VNPC_PrivateMatingSpot = nil
    mother.VNPC_MatingTravelStart = nil
    if mother.SetNWBool then mother:SetNWBool("VNPC_IsMatingBonePose", false) end
    if mother.SetSchedule then pcall(mother.SetSchedule, mother, SCHED_IDLE_STAND) end

    if IsValid(mate) then
        mate.VNPC_IsMatingBonePose = nil
        mate.VNPC_PrivateMatingSpot = nil
        mate.VNPC_MatingTravelStart = nil
        if mate.SetNWBool then mate:SetNWBool("VNPC_IsMatingBonePose", false) end
        if mate.SetSchedule then pcall(mate.SetSchedule, mate, SCHED_IDLE_STAND) end
        mother.VNPC_WildMate = mate
        mate.VNPC_WildMate = mother
        mother.VNPC_LovedPartner = mate
        mate.VNPC_LovedPartner = mother
    end

    local female = mother
    if VNPC_IsMalePreyCitizen and VNPC_IsMalePreyCitizen(mother) and IsValid(mate) then
        female = mate
    elseif VNPC_ModelLooksFemale and not VNPC_ModelLooksFemale(mother) and IsValid(mate) then
        female = mate
    end

    local love = VNPC_GetMateLove and VNPC_GetMateLove(female, mate) or 0
    if VNPC_AddMateLove then
        love = VNPC_AddMateLove(female, mate, 14.0 + love * 0.08)
    end
    local litter = (VNPC_GetLitterSize and VNPC_GetLitterSize(love)) or 1
    female.VNPC_IsPregnant = true
    female.VNPC_BabyGrowthValue = female.VNPC_BabyGrowthValue or 10.0
    female.VNPC_PregnancyStartTime = CurTime()
    female.VNPC_LastGrowthTime = CurTime()
    female.VNPC_LitterSize = litter
    if VNPC_EnsureUnbornLitter then
        VNPC_EnsureUnbornLitter(female, litter)
    elseif VNPC_EnsureUnbornChild then
        VNPC_EnsureUnbornChild(female, litter)
    end
    print(string.format("[V-NPCs] Mating Complete: %s is now pregnant with a litter of %d (love %.0f, growth 10/50) with mate %s!", tostring(female), litter, love, tostring(mate)))
    hook.Run("VNPC_OnPrivateMatingComplete", female, mate)
    return true
end

function VNPC_InitiatePrivateMating(pred, mate, camp)
    if not IsValid(pred) or not IsValid(mate) then return false end
    if pred.VNPC_IsPregnant or mate.VNPC_IsPregnant then return false end
    if pred.VNPC_IsMatingBonePose or mate.VNPC_IsMatingBonePose then return false end

    pred.VNPC_MatingPartner = mate
    mate.VNPC_MatingPartner = pred
    pred.VNPC_WildMate = mate
    mate.VNPC_WildMate = pred
    pred.VNPC_LovedPartner = mate
    mate.VNPC_LovedPartner = pred
    pred.VNPC_MatingTravelStart = CurTime()
    mate.VNPC_MatingTravelStart = CurTime()
    if VNPC_AddMateLove then
        VNPC_AddMateLove(pred, mate, 6.0)
    end

    if pred:GetPos():DistToSqr(mate:GetPos()) <= (200 * 200) then
        VNPC_BeginMatingBonePose(pred, mate, CurTime())
        return true
    end

    local privateSpot = VNPC_FindPrivateMatingSpot(pred, mate, camp)
    pred.VNPC_PrivateMatingSpot = privateSpot
    mate.VNPC_PrivateMatingSpot = privateSpot

    if pred.SetLastPosition then pcall(pred.SetLastPosition, pred, privateSpot) end
    if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_FORCED_GO_RUN) end
    if mate.SetLastPosition then pcall(mate.SetLastPosition, mate, privateSpot) end
    if mate.SetSchedule then pcall(mate.SetSchedule, mate, SCHED_FORCED_GO_RUN) end

    print("[V-NPCs] Private Mating: Couple " .. tostring(pred) .. " & " .. tostring(mate) .. " are meeting to mate!")
    return true
end

function VNPC_PrivateMating_AI(now)
    for _, pred in ipairs(ents.GetAll()) do
        if not IsValid(pred) or pred:Health() <= 0 or pred.Vored or pred.VNPC_Vored then continue end
        if not (pred:IsNPC() or pred:IsNextBot() or pred.IsDrGNextbot) then continue end

        if pred.VNPC_IsMatingBonePose then
            local mate = pred.VNPC_MatingPartner
            if VNPC_TickCoupleLove and IsValid(mate) and pred:EntIndex() <= mate:EntIndex() then
                VNPC_TickCoupleLove(pred, mate, FrameTime())
            end
            if now >= (pred.VNPC_MatingPoseEndTime or 0) then
                VNPC_CompleteMatingPregnancy(pred, mate)
            end
            continue
        end

        if pred.VNPC_PrivateMatingSpot and IsValid(pred.VNPC_MatingPartner) and pred.VNPC_MatingPartner:Health() > 0 then
            local mate = pred.VNPC_MatingPartner
            if mate.VNPC_IsPregnant or pred.VNPC_IsPregnant then
                pred.VNPC_PrivateMatingSpot = nil
                mate.VNPC_PrivateMatingSpot = nil
                continue
            end

            local spot = pred.VNPC_PrivateMatingSpot
            local d1 = pred:GetPos():DistToSqr(spot)
            local d2 = mate:GetPos():DistToSqr(spot)
            local pairDist = pred:GetPos():DistToSqr(mate:GetPos())
            local waited = now - (pred.VNPC_MatingTravelStart or now)

            if (d1 <= (180 * 180) and d2 <= (200 * 200)) or pairDist <= (180 * 180) or waited >= 12.0 then
                VNPC_BeginMatingBonePose(pred, mate, now)
            elseif (pred.VNPC_NextPrivateMoveTime or 0) <= now then
                pred.VNPC_NextPrivateMoveTime = now + 1.5
                if pred.SetLastPosition then pcall(pred.SetLastPosition, pred, mate:GetPos()) end
                if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_FORCED_GO_RUN) end
                if mate.SetLastPosition then pcall(mate.SetLastPosition, mate, pred:GetPos()) end
                if mate.SetSchedule then pcall(mate.SetSchedule, mate, SCHED_FORCED_GO_RUN) end
            end
        end
    end
end

function VNPC_WildPredPreyMate(female, male)
    return VNPC_InitiatePrivateMating(female, male, nil)
end

function VNPC_IsFamilyOrMate(entA, entB)
    if not IsValid(entA) or not IsValid(entB) or entA == entB then return true end
    if entA.VNPC_WildMate == entB or entB.VNPC_WildMate == entA then return true end
    if entA.VNPC_WildPartner == entB or entB.VNPC_WildPartner == entA then return true end
    if entA.VNPC_WildChild == entB or entB.VNPC_WildChild == entA then return true end
    if entA.VNPC_MotherRef == entB or entB.VNPC_MotherRef == entA then return true end
    if entA.VNPC_FatherRef == entB or entB.VNPC_FatherRef == entA then return true end
    if entA.VNPC_LovedPartner == entB or entB.VNPC_LovedPartner == entA then return true end
    if entA.VNPC_MatingPartner == entB or entB.VNPC_MatingPartner == entA then return true end

    -- Same predator camp = sisters / campmates. Never swallow each other.
    local campA = entA.VNPC_CampID
    local campB = entB.VNPC_CampID
    if campA and campB and campA ~= "wild" and campA == campB then
        return true
    end

    -- Same prey fort when both are permanent fort predators / camp defenders.
    local preyA = entA.VNPC_PreyCampID
    local preyB = entB.VNPC_PreyCampID
    if preyA and preyB and preyA == preyB then
        local aAlly = entA.VNPC_IsPermanentFortPredator or entA.VNPC_IsSecretAssassin
        local bAlly = entB.VNPC_IsPermanentFortPredator or entB.VNPC_IsSecretAssassin
        -- Two predators sharing a prey camp as allies (not a night-raid assassin vs prey).
        if aAlly and bAlly then
            return true
        end
        -- Predator enrolled in a prey camp must not eat other members of that fort
        -- unless she is mid night-raid (assassin flag allows camp swallow).
        local aPred = entA.Predator or entA.VNPC_FemaleModelVore or entA.IsDrGNextbot or entA.EatEntity
        local bPred = entB.Predator or entB.VNPC_FemaleModelVore or entB.IsDrGNextbot or entB.EatEntity
        if aPred and not bPred and not entA.VNPC_AssassinAllowCampSwallow and not (VNPC_IsAssassinNightHunting and VNPC_IsAssassinNightHunting(entA)) then
            return true
        end
        if bPred and not aPred and not entB.VNPC_AssassinAllowCampSwallow and not (VNPC_IsAssassinNightHunting and VNPC_IsAssassinNightHunting(entB)) then
            return true
        end
    end

    local clsA = string.lower(entA:GetClass() or "")
    local mdlA = string.lower(entA:GetModel() or "")
    local clsB = string.lower(entB:GetClass() or "")
    local mdlB = string.lower(entB:GetModel() or "")

    local isEliA = (clsA == "npc_eli" or mdlA:find("eli"))
    local isAlyxB = (clsB == "npc_alyx" or mdlB:find("alyx"))
    if isEliA and isAlyxB then return true end

    local isEliB = (clsB == "npc_eli" or mdlB:find("eli"))
    local isAlyxA = (clsA == "npc_alyx" or mdlA:find("alyx"))
    if isEliB and isAlyxA then return true end

    return false
end

-- True when both entities belong to the same predator camp (or same ally fort).
function VNPC_IsSamePredatorCamp(entA, entB)
    if not IsValid(entA) or not IsValid(entB) then return false end
    local a, b = entA.VNPC_CampID, entB.VNPC_CampID
    return a ~= nil and b ~= nil and a ~= "wild" and a == b
end

function VNPC_WildGiveBirth(mother)
    if not IsValid(mother) then return nil end

    local litterSize = math.max(1, tonumber(mother.VNPC_LitterSize) or 1)
    mother.VNPC_IsPregnant = nil
    mother.VNPC_BabyGrowthValue = nil

    if VNPC_StartChildbirthAnimation then
        VNPC_StartChildbirthAnimation(mother, nil, nil)
    end

    timer.Simple(0.2, function()
        if not IsValid(mother) then return end
        local tagged = 0
        local firstChild = nil
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and ent.VNPC_IsGrowingBaby and (ent.VNPC_MotherRef == mother or (CurTime() - (ent.VNPC_BabyBirthTime or 0)) < 3.0) then
                ent.VNPC_MotherRef = mother
                mother.VNPC_WildChild = ent
                if IsValid(mother.VNPC_WildMate) then
                    ent.VNPC_FatherRef = mother.VNPC_WildMate
                    mother.VNPC_WildMate.VNPC_WildChild = ent
                end
                if VNPC_MakeWildWanderer then
                    VNPC_MakeWildWanderer(ent)
                end
                if mother.VNPC_WildType == "predator" and (ent.VNPC_ChildGender == "female" or string.find(string.lower(ent:GetModel() or ""), "female")) then
                    ent.VNPC_WildType = "predator"
                    if VNPC_ForceGiveWildPredatorVore then
                        VNPC_ForceGiveWildPredatorVore(ent)
                    end
                else
                    ent.VNPC_WildType = ent.VNPC_WildType or "prey"
                end
                tagged = tagged + 1
                firstChild = firstChild or ent
                if tagged >= litterSize then break end
            end
        end
        if tagged > 0 then
            print("[V-NPCs] Wild Birth: " .. tostring(mother) .. " gave birth to a wild litter of " .. tagged .. " in the wilderness!")
            hook.Run("VNPC_OnWildBirth", mother, firstChild)
        end
    end)

    local child = nil
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent.VNPC_IsGrowingBaby and (ent.VNPC_MotherRef == mother or (CurTime() - (ent.VNPC_BabyBirthTime or 0)) < 1.5) then
            child = ent
            break
        end
    end
    return child
end

function VNPC_CalculateMapScale()
    if VNPC_CachedMapScale and (CurTime() - (VNPC_LastMapScaleCalcTime or 0)) < 60 then
        return VNPC_CachedMapScale
    end

    local world = game.GetWorld()
    local areaScore = 36.0 -- Default baseline (~6000x6000)
    if IsValid(world) and world.GetModelBounds then
        local minB, maxB = world:GetModelBounds()
        local sizeX = math.max(1000, math.abs(maxB.x - minB.x))
        local sizeY = math.max(1000, math.abs(maxB.y - minB.y))
        areaScore = (sizeX * sizeY) / 1000000.0 -- Area in millions of sq units
    end

    -- Factor in node/nav area count as an indicator of playable map size
    local navCount = (navmesh and navmesh.GetAllNavAreas and #navmesh.GetAllNavAreas()) or 0
    local nodeCount = #ents.FindByClass("info_node*")
    local nodeBonus = math.Clamp((navCount + nodeCount) / 100.0, 0.5, 3.0)

    local scale = math.Clamp(math.sqrt(areaScore / 36.0) * nodeBonus, 0.35, 4.0)

    VNPC_CachedMapScale = scale
    VNPC_LastMapScaleCalcTime = CurTime()
    return scale
end

function VNPC_GetDynamicWildCap(isPredator)
    local mapScale = VNPC_CalculateMapScale()
    if isPredator then
        local basePreds = max_wild_preds:GetInt()
        return math.Clamp(math.floor(basePreds * mapScale), 1, 24)
    else
        local basePrey = max_wild_prey:GetInt()
        return math.Clamp(math.floor(basePrey * mapScale), 2, 60)
    end
end

function VNPC_WildMating_AI(now)
    if not wild_mating_enabled:GetBool() then return end

    for _, w in ipairs(VNPC_ActiveWildWanderers) do
        if not IsValid(w) or w:Health() <= 0 or w.Vored or w.VNPC_Vored then continue end

        local partner = w.VNPC_WildMate or w.VNPC_LovedPartner or w.VNPC_MatingPartner
        if IsValid(partner) and VNPC_TickCoupleLove and w:EntIndex() <= partner:EntIndex() and not w.VNPC_IsMatingBonePose and not partner.VNPC_IsMatingBonePose then
            VNPC_TickCoupleLove(w, partner, FrameTime())
        end

        if w.VNPC_IsPregnant then
            if (now - (w.VNPC_LastGrowthTime or now)) >= 1.0 then
                w.VNPC_LastGrowthTime = now
                w.VNPC_PregnancyStartTime = w.VNPC_PregnancyStartTime or (now - 1.0)
                local elapsed = now - w.VNPC_PregnancyStartTime
                w.VNPC_BabyGrowthValue = math.Clamp(10.0 + (elapsed / 120.0) * 40.0, 10.0, 50.0)
                if elapsed >= 120.0 or w.VNPC_BabyGrowthValue >= 50.0 then
                    VNPC_WildGiveBirth(w)
                end
            end
        elseif VNPC_IsFemaleWildWanderer(w) then
            if VNPC_IsBusyMating and VNPC_IsBusyMating(w) then continue end
            -- 1. Check if we already have a mate/partner in close physical contact to start pregnancy
            if IsValid(w.VNPC_SeekingMate) and w.VNPC_SeekingMate:Health() > 0 and not w.VNPC_SeekingMate.Vored then
                local dSqr = w:GetPos():DistToSqr(w.VNPC_SeekingMate:GetPos())
                if dSqr <= (135 * 135) then
                    -- CLOSE PHYSICAL CONTACT REACHED: mate and become pregnant!
                    VNPC_WildPredPreyMate(w, w.VNPC_SeekingMate)
                    w.VNPC_SeekingMate = nil
                else
                    -- Still traveling towards our male prey partner to mate
                    if (w.VNPC_NextMateMoveTime or 0) <= now then
                        w.VNPC_NextMateMoveTime = now + 1.5
                        if w.SetLastPosition then pcall(w.SetLastPosition, w, w.VNPC_SeekingMate:GetPos()) end
                        if w.SetSchedule then pcall(w.SetSchedule, w, SCHED_FORCED_GO_RUN) end
                        if w.VNPC_SeekingMate.SetLastPosition then pcall(w.VNPC_SeekingMate.SetLastPosition, w.VNPC_SeekingMate, w:GetPos()) end
                        if w.VNPC_SeekingMate.SetSchedule then pcall(w.VNPC_SeekingMate.SetSchedule, w.VNPC_SeekingMate, SCHED_TARGET_FACE) end
                    end
                end
            elseif (w.VNPC_NextWildMateCheck or 0) <= now then
                w.VNPC_NextWildMateCheck = now + 6.0
                local bestMale = nil
                local bestDistSqr = 2000 * 2000
                local wPos = w:GetPos()

                -- Scan all NPCs on the map for an eligible male who wants this female pred type
                for _, m in ipairs(ents.FindByClass("npc_*")) do
                    if VNPC_IsMaleWildWanderer(m) and m ~= w then
                        local dSqr = m:GetPos():DistToSqr(wPos)
                        if VNPC_GetMateAttractionMultiplier then
                            dSqr = dSqr / math.max(0.35, VNPC_GetMateAttractionMultiplier(m, w))
                        end
                        if VNPC_IsPreyAttractedToPred and not VNPC_IsPreyAttractedToPred(m, w) then
                            dSqr = dSqr * 2.4
                        end
                        if dSqr <= bestDistSqr then
                            bestMale = m
                            bestDistSqr = dSqr
                        end
                    end
                end

                if IsValid(bestMale) then
                    -- Check distance: if already in close contact, mate immediately! Otherwise start seeking him.
                    if bestDistSqr <= (135 * 135) then
                        VNPC_WildPredPreyMate(w, bestMale)
                    else
                        w.VNPC_SeekingMate = bestMale
                    end
                end
            end
        end
    end
end

function VNPC_WildFamilyDefense_AI(now)
    if not ecology_enabled:GetBool() then return end

    for _, w in ipairs(VNPC_ActiveWildWanderers) do
        if not IsValid(w) or w:Health() <= 0 or w.Vored or w.VNPC_Vored then continue end
        if (w.VNPC_NextFamilyDefenseTime or 0) > now then continue end
        w.VNPC_NextFamilyDefenseTime = now + 0.5

        -- Gather family protectees: child or mate
        local protectees = {}
        if IsValid(w.VNPC_WildChild) and w.VNPC_WildChild:Health() > 0 and not w.VNPC_WildChild.Vored then
            table.insert(protectees, w.VNPC_WildChild)
        end
        if IsValid(w.VNPC_WildMate) and w.VNPC_WildMate:Health() > 0 and not w.VNPC_WildMate.Vored then
            table.insert(protectees, w.VNPC_WildMate)
        end
        if IsValid(w.VNPC_WildPartner) and w.VNPC_WildPartner:Health() > 0 and not w.VNPC_WildPartner.Vored then
            table.insert(protectees, w.VNPC_WildPartner)
        end

        if #protectees == 0 then continue end
        local wPos = w:GetPos()

        -- Scan nearby predators threatening our child or mate
        for _, threat in ipairs(ents.FindInSphere(wPos, 1100)) do
            if not IsValid(threat) or threat == w or threat.Vored or threat.VNPC_Vored or threat:Health() <= 0 then continue end
            if VNPC_IsFamilyOrMate(w, threat) then continue end
            local isPredThreat = (threat.IsDrGNextbot or threat.VNPC_FemaleModelVore or threat.Predator or threat.VNPC_WildType == "predator")
            if not isPredThreat then continue end

            for _, p in ipairs(protectees) do
                if threat:GetPos():DistToSqr(p:GetPos()) <= (750 * 750) or threat:GetEnemy() == p then
                    -- Mother / Mate fiercely rushes to defend their family!
                    w.VNPC_ProtectorResilience = now + 10.0
                    if w.SetEnemy then pcall(w.SetEnemy, w, threat) end
                    if w.SetLastPosition then pcall(w.SetLastPosition, w, threat:GetPos()) end
                    if w.SetSchedule then pcall(w.SetSchedule, w, SCHED_FORCED_GO_RUN) end

                    -- Alert nearby wild allies to converge and defend the family!
                    for _, ally in ipairs(ents.FindInSphere(wPos, 1400)) do
                        if IsValid(ally) and ally ~= w and ally ~= threat and (ally:IsNPC() or ally.IsDrGNextbot) and not ally.Vored then
                            if ally.VNPC_WildType == w.VNPC_WildType and not IsValid(ally:GetEnemy()) then
                                if ally.SetEnemy then pcall(ally.SetEnemy, ally, threat) end
                                if ally.SetSchedule then pcall(ally.SetSchedule, ally, SCHED_FORCED_GO_RUN) end
                            end
                        end
                    end

                    -- If protector is a predator and within grab distance, swallow or fight the threat!
                    if (w.VNPC_WildType == "predator" or w.VNPC_FemaleModelVore or w.Predator) and wPos:Distance(threat:GetPos()) <= 165 then
                        if w.EatEntity and w:EatEntity(threat) then
                            if w.EmitSound then w:EmitSound("belly/snd_digeststart.wav", 85, 100) end
                        end
                    end
                    break
                end
            end
        end
    end
end

hook.Add("EntityTakeDamage", "VNPC_WildFamilyProtection_DamageHook", function(target, dmginfo)
    if not IsValid(target) then return end
    if (target.VNPC_ProtectorResilience or 0) > CurTime() then
        dmginfo:ScaleDamage(0.5)
    end
    local attacker = dmginfo:GetAttacker()
    if not IsValid(attacker) or attacker == target or attacker.Vored or attacker.VNPC_Vored then return end

    -- Check if target is a wild child or mate with a surviving protector nearby
    local protector = nil
    if IsValid(target.VNPC_MotherRef) and target.VNPC_MotherRef:Health() > 0 and not target.VNPC_MotherRef.Vored then
        protector = target.VNPC_MotherRef
    elseif IsValid(target.VNPC_WildMate) and target.VNPC_WildMate:Health() > 0 and not target.VNPC_WildMate.Vored then
        protector = target.VNPC_WildMate
    elseif IsValid(target.VNPC_FatherRef) and target.VNPC_FatherRef:Health() > 0 and not target.VNPC_FatherRef.Vored then
        protector = target.VNPC_FatherRef
    end

    if IsValid(protector) and protector:GetPos():DistToSqr(target:GetPos()) <= (1200 * 1200) then
        if protector.SetEnemy then pcall(protector.SetEnemy, protector, attacker) end
        if protector.SetLastPosition then pcall(protector.SetLastPosition, protector, attacker:GetPos()) end
        if protector.SetSchedule then pcall(protector.SetSchedule, protector, SCHED_FORCED_GO_RUN) end

        if (protector.VNPC_WildType == "predator" or protector.VNPC_FemaleModelVore or protector.Predator) and protector:GetPos():Distance(attacker:GetPos()) <= 165 then
            if protector.EatEntity and protector:EatEntity(attacker) then
                dmginfo:SetDamage(0)
            end
        end
    end
end)

-- Main Wild Wanderers Ecology Loop
hook.Add("Think", "VNPC_WildEcology_AI_Loop", function()
    if not ecology_enabled:GetBool() then return end
    local now = CurTime()

    if VNPC_WildMating_AI then
        VNPC_WildMating_AI(now)
    end
    if VNPC_WildFamilyDefense_AI then
        VNPC_WildFamilyDefense_AI(now)
    end
    if VNPC_PrivateMating_AI then
        VNPC_PrivateMating_AI(now)
    end

    -- Prune dead / invalid wild wanderers
    for i = #VNPC_ActiveWildWanderers, 1, -1 do
        local w = VNPC_ActiveWildWanderers[i]
        if not IsValid(w) or w:Health() <= 0 or w.Vored or w.VNPC_Vored then
            table.remove(VNPC_ActiveWildWanderers, i)
        end
    end

    for _, ent in ipairs(VNPC_ActiveWildWanderers) do
        if not IsValid(ent) or ent:Health() <= 0 then continue end
        if (ent.VNPC_NextWildWanderTime or 0) > now then continue end
        ent.VNPC_NextWildWanderTime = now + 14.0

        local pos = ent:GetPos()
        if ent.VNPC_WildType == "predator" then
            VNPC_RecordWildHotspot(pos)
            if (VNPC_IsStormFox2Night and VNPC_IsStormFox2Night()) or (VNPC_IsStormFox2Raining and VNPC_IsStormFox2Raining()) then
                ent:AddFlags(FL_NOTARGET)
                if ent.SightRange and not ent.VNPC_BaseWildSight then ent.VNPC_BaseWildSight = ent.SightRange end
                if ent.VNPC_BaseWildSight then ent.SightRange = ent.VNPC_BaseWildSight * 1.35 end
            else
                ent:RemoveFlags(FL_NOTARGET)
                if ent.VNPC_BaseWildSight then ent.SightRange = ent.VNPC_BaseWildSight end
            end
        end

        if not IsValid(ent:GetEnemy()) and not (VNPC_IsBusyMating and VNPC_IsBusyMating(ent)) and not ent.VNPC_IsPregnant then
            local angle = math.rad(math.random(0, 360))
            local dist = math.random(500, 1100)
            local targetPos = pos + Vector(math.cos(angle) * dist, math.sin(angle) * dist, 0)
            if ent.SetLastPosition then pcall(ent.SetLastPosition, ent, targetPos) end
            if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_FORCED_GO) end
        end
    end

    if (VNPC_NextWildSpawnTime or 0) <= now then
        VNPC_NextWildSpawnTime = now + spawner_interval:GetFloat()
        local wPreds, wPrey = 0, 0
        for _, w in ipairs(VNPC_ActiveWildWanderers) do
            if IsValid(w) then
                if w.VNPC_WildType == "predator" then wPreds = wPreds + 1 else wPrey = wPrey + 1 end
            end
        end
        local sf2Mult = (VNPC_GetStormFox2EcologyMultiplier and VNPC_GetStormFox2EcologyMultiplier()) or 1.0
        local maxDynPrey = math.floor(VNPC_GetDynamicWildCap(false) * sf2Mult)
        local maxDynPreds = math.floor(VNPC_GetDynamicWildCap(true) * sf2Mult)
        if wPrey < maxDynPrey then
            VNPC_SpawnWildNPC(false, nil)
        end
        if wPreds < maxDynPreds then
            VNPC_SpawnWildNPC(true, nil)
        end
    end
end)

concommand.Add("vnpcs_wild_ecology_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Wild Ecology & Prey Camp Intelligence Agency Status")
    print("Enabled: " .. tostring(ecology_enabled:GetBool()))
    print("Wild Spawn Chance: " .. tostring(wild_chance:GetInt()) .. "%")
    print("Wild Predator Danger Scale: " .. tostring(pred_danger:GetFloat()) .. "x HP/Resistance")
    print("Agent Recon Range: " .. tostring(recon_range:GetFloat()) .. " units")
    print("Wild Mating Enabled: " .. tostring(wild_mating_enabled:GetBool()))
    local sf2Present = (VNPC_IsStormFox2Present and VNPC_IsStormFox2Present()) and "YES (Active)" or "NO (Using simulated weather)"
    print("StormFox 2 Environment: " .. sf2Present)
    local scale = VNPC_CalculateMapScale()
    print("Map Size Dynamic Scale: " .. string.format("%.2fx", scale))
    print("Dynamic Wild Max Prey Cap: " .. VNPC_GetDynamicWildCap(false) .. " (Base: " .. max_wild_prey:GetInt() .. ")")
    print("Dynamic Wild Max Predator Cap: " .. VNPC_GetDynamicWildCap(true) .. " (Base: " .. max_wild_preds:GetInt() .. ")")
    print("-----------------------------------------")
    local wPreds, wPrey = 0, 0
    for _, w in ipairs(VNPC_ActiveWildWanderers) do
        if IsValid(w) then
            if w.VNPC_WildType == "predator" then
                wPreds = wPreds + 1
                local pers = w.VNPC_PredatorPersonality or (w.VoreSettings and w.VoreSettings.PredatorPersonality) or "opportunistic"
                local mateStr = IsValid(w.VNPC_WildMate) and (" | Mate: [" .. w.VNPC_WildMate:EntIndex() .. "]") or ""
                local loveStr = (w.VNPC_MateLove and w.VNPC_MateLove > 0) and string.format(" | Love: %.0f", w.VNPC_MateLove) or ""
                local pregStr = w.VNPC_IsPregnant and string.format(" | Pregnant: %.1f/50 x%d", w.VNPC_BabyGrowthValue or 40, math.max(1, tonumber(w.VNPC_LitterSize) or 1)) or ""
                local typeStr = (VNPC_GetFemalePredType and (" | Type: " .. VNPC_GetFemalePredType(w))) or ""
                print(string.format(" -> Wild Predator [#%d] %s | Pers: %s | HP: %d%s%s%s%s",
                    w:EntIndex(), w:GetClass(), string.upper(pers), w:Health(), mateStr, loveStr, pregStr, typeStr))
            else
                wPrey = wPrey + 1
                local pers = w.VNPC_PreyPersonality or w.PreyPersonality or "fighter"
                local mateStr = IsValid(w.VNPC_WildMate) and (" | Mate: [" .. w.VNPC_WildMate:EntIndex() .. "]") or ""
                local loveStr = (w.VNPC_MateLove and w.VNPC_MateLove > 0) and string.format(" | Love: %.0f", w.VNPC_MateLove) or ""
                local pregStr = w.VNPC_IsPregnant and string.format(" | Pregnant: %.1f/50 x%d", w.VNPC_BabyGrowthValue or 40, math.max(1, tonumber(w.VNPC_LitterSize) or 1)) or ""
                local wantStr = (VNPC_FormatMateAttraction and (" | Wants: " .. VNPC_FormatMateAttraction(w))) or ""
                print(string.format(" -> Wild Prey [#%d] %s | Pers: %s | HP: %d%s%s%s%s",
                    w:EntIndex(), w:GetClass(), string.upper(pers), w:Health(), mateStr, loveStr, pregStr, wantStr))
            end
        end
    end
    print("Active Wild Wanderers -> Predators: " .. wPreds .. " | Prey: " .. wPrey)
    print("Recorded Wild Predator Hotspots: " .. #VNPC_WildPredatorHotspots)
    print("-----------------------------------------")
    for idx, camp in ipairs(VNPC_ActivePreyCamps or {}) do
        print(string.format(" -> Prey Camp [#%d] | Fortified: %s | Intel Reports stored: %d",
            camp.id, tostring(camp.fortified or false), #(camp.intelReports or {})))
    end
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Wild ecology status printed to console. Wild Preds: " .. wPreds .. " | Wild Prey: " .. wPrey)
    end
end)

concommand.Add("vnpcs_test_spawn_wild", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at an NPC to convert them into a Wild Wanderer!")
        return
    end
    VNPC_MakeWildWanderer(target)
    ply:ChatPrint("[V-NPCs] Converted " .. tostring(target) .. " into a Wild Wanderer (" .. tostring(target.VNPC_WildType) .. ")!")
end)

concommand.Add("vnpcs_test_prey_agent", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not target.VNPC_PreyCampID then
        ply:ChatPrint("[V-NPCs] Please aim at a citizen in a Prey Camp to assign as an Intelligence Agent!")
        return
    end
    target.VNPC_PreyRole = "agent"
    target.VNPC_IntelGathered = nil
    target.VNPC_ReconTargetPos = target:GetPos() + Vector(math.random(-800,800), math.random(-800,800), 0)
    target:AddFlags(FL_NOTARGET)
    ply:ChatPrint("[V-NPCs] Assigned " .. tostring(target) .. " as an Intelligence Agent and dispatched on recon mission!")
end)

concommand.Add("vnpcs_test_spawn_wild_prey", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local ent = VNPC_SpawnWildNPC(false, tr.HitPos)
    ply:ChatPrint("[V-NPCs] Spawned wild wandering prey: " .. tostring(ent) .. "!")
end)

concommand.Add("vnpcs_test_spawn_wild_pred", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local ent = VNPC_SpawnWildNPC(true, tr.HitPos)
    ply:ChatPrint("[V-NPCs] Spawned dangerous wild solitary predator (1.35x HP/Resistance): " .. tostring(ent) .. "!")
end)

concommand.Add("vnpcs_test_wild_mate", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at a wild NPC to trigger wild mating!")
        return
    end

    if not target.VNPC_IsWildWanderer then
        VNPC_MakeWildWanderer(target)
    end

    local mate = nil
    for _, w in ipairs(VNPC_ActiveWildWanderers) do
        if IsValid(w) and w ~= target and w:Health() > 0 then
            mate = w
            break
        end
    end

    if not IsValid(mate) then
        mate = VNPC_SpawnWildNPC(false, target:GetPos() + Vector(48, 0, 0))
    end

    if IsValid(mate) then
        VNPC_WildPredPreyMate(target, mate)
        ply:ChatPrint("[V-NPCs] Forced wild mating encounter between " .. tostring(target) .. " and " .. tostring(mate) .. "!")
    else
        ply:ChatPrint("[V-NPCs] Could not find or spawn a wild mate!")
    end
end)

concommand.Add("vnpcs_test_private_mating", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at an NPC to test private mating and mating bone pose!")
        return
    end

    local mate = target.VNPC_WildMate or target.VNPC_LovedPartner or target.VNPC_MatingPartner
    if not IsValid(mate) then
        mate = VNPC_SpawnWildNPC(false, target:GetPos() + Vector(60, 0, 0))
    end

    if IsValid(mate) then
        VNPC_InitiatePrivateMating(target, mate, nil)
        ply:ChatPrint("[V-NPCs] Initiated private mating between " .. tostring(target) .. " and " .. tostring(mate) .. "!")
    end
end)

concommand.Add("vnpcs_test_wild_pregnancy", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at a wild NPC to trigger wild pregnancy!")
        return
    end

    if not target.VNPC_IsWildWanderer then
        VNPC_MakeWildWanderer(target)
    end

    target.VNPC_IsPregnant = true
    target.VNPC_BabyGrowthValue = 47.0
    target.VNPC_PregnancyStartTime = CurTime() - 117.0
    target.VNPC_LastGrowthTime = CurTime()
    target.VNPC_LitterSize = target.VNPC_LitterSize or 1
    if VNPC_EnsureUnbornLitter then
        VNPC_EnsureUnbornLitter(target, target.VNPC_LitterSize)
    end
    ply:ChatPrint("[V-NPCs] Triggered wild pregnancy on " .. tostring(target) .. "! Birth at 50 in ~3 seconds.")
end)

concommand.Add("vnpcs_test_wild_birth", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at a wild NPC to trigger instant wild birth!")
        return
    end

    local child = VNPC_WildGiveBirth(target)
    if IsValid(child) then
        ply:ChatPrint("[V-NPCs] Instant wild birth triggered! Child: " .. tostring(child))
    else
        ply:ChatPrint("[V-NPCs] Triggered wild birth on " .. tostring(target) .. "!")
    end
end)

concommand.Add("vnpcs_test_wild_defense", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at a wild NPC to test family/mate defense!")
        return
    end

    local protector = target.VNPC_MotherRef or target.VNPC_WildMate or target.VNPC_FatherRef
    if not IsValid(protector) then
        ply:ChatPrint("[V-NPCs] Aimed NPC has no mother or mate protector! Use vnpcs_test_wild_mate or vnpcs_test_wild_birth first.")
        return
    end

    -- Spawn a hostile predator threat nearby to trigger family defense!
    local threat = VNPC_SpawnWildNPC(true, target:GetPos() + Vector(120, 0, 0))
    if IsValid(threat) then
        if protector.SetEnemy then pcall(protector.SetEnemy, protector, threat) end
        if protector.SetSchedule then pcall(protector.SetSchedule, protector, SCHED_FORCED_GO_RUN) end
        ply:ChatPrint("[V-NPCs] Spawned hostile wild predator " .. tostring(threat) .. "! Protector " .. tostring(protector) .. " is rushing to defend " .. tostring(target) .. "!")
    end
end)

concommand.Add("vnpcs_test_wild_caps", function(ply)
    local scale = VNPC_CalculateMapScale()
    local dynPrey = VNPC_GetDynamicWildCap(false)
    local dynPreds = VNPC_GetDynamicWildCap(true)
    local msg = string.format("[V-NPCs] Dynamic Map Size Scale: %.2fx | Dynamic Wild Max Prey: %d (Base: %d) | Dynamic Wild Max Preds: %d (Base: %d)",
        scale, dynPrey, max_wild_prey:GetInt(), dynPreds, max_wild_preds:GetInt())
    print(msg)
    if IsValid(ply) then
        ply:ChatPrint(msg)
    end
end)

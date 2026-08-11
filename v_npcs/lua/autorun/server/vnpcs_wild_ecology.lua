-- V-NPCs Wild Ecology & Prey Camp Intelligence Agency Engine (vnpcs_wild_ecology.lua)
-- Spawns wandering wild predators (1.35x danger) and wild prey; fortified prey camps dispatch intelligence agents to scout and report danger zones

local ecology_enabled = CreateConVar("vnpcs_wild_ecology_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable wild wandering predators/prey and prey camp intelligence agents")
local wild_chance = CreateConVar("vnpcs_wild_spawn_chance", "25", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Percentage chance that an unassigned NPC becomes a Wild Wanderer instead of joining a camp")
local pred_danger = CreateConVar("vnpcs_wild_pred_danger_scale", "1.35", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Health and combat danger multiplier for wild solitary predators")
local recon_range = CreateConVar("vnpcs_prey_agent_recon_range", "900.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Distance within which an Intelligence Agent discovers a predator camp or wild hotspot")
local spawner_interval = CreateConVar("vnpcs_wild_spawner_interval", "20.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Interval in seconds between spawning wild wandering NPCs in the map")
local max_wild_prey = CreateConVar("vnpcs_wild_max_prey", "12", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum number of active wild wandering prey NPCs in the map")
local max_wild_preds = CreateConVar("vnpcs_wild_max_preds", "4", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum number of active wild wandering solitary predators in the map")

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
        ent.VNPC_CampID = "wild"
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
        ent.VNPC_PreyCampID = "wild"
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

function VNPC_FindWildernessSpawnPos()
    local players = player.GetAll()
    local origin = Vector(0, 0, 0)
    if #players > 0 and IsValid(players[1]) then
        origin = players[1]:GetPos()
    end

    for attempt = 1, 10 do
        local angle = math.rad(math.random(0, 360))
        local dist = math.random(1300, 2600)
        local candidatePos = origin + Vector(math.cos(angle) * dist, math.sin(angle) * dist, 100)

        -- Ensure minimum distance from all camps and players
        local tooClose = false
        for _, camp in ipairs(VNPC_ActivePredatorCamps or {}) do
            if camp.pos and candidatePos:DistToSqr(camp.pos) < (1100 * 1100) then
                tooClose = true
                break
            end
        end
        if not tooClose then
            for _, camp in ipairs(VNPC_ActivePreyCamps or {}) do
                if camp.pos and candidatePos:DistToSqr(camp.pos) < (1100 * 1100) then
                    tooClose = true
                    break
                end
            end
        end
        if not tooClose then
            for _, p in ipairs(players) do
                if IsValid(p) and candidatePos:DistToSqr(p:GetPos()) < (1000 * 1000) then
                    tooClose = true
                    break
                end
            end
        end

        if not tooClose then
            local tr = util.TraceLine({
                start = candidatePos,
                endpos = candidatePos - Vector(0, 0, 400),
                mask = MASK_SOLID_BRUSHONLY
            })
            if tr.Hit and tr.HitNormal.z > 0.6 then
                return tr.HitPos + Vector(0, 0, 10)
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

-- Main Wild Wanderers Ecology Loop
hook.Add("Think", "VNPC_WildEcology_AI_Loop", function()
    if not ecology_enabled:GetBool() then return end
    local now = CurTime()

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
        end

        if not IsValid(ent:GetEnemy()) then
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
        if wPrey < max_wild_prey:GetInt() then
            VNPC_SpawnWildNPC(false, nil)
        end
        if wPreds < max_wild_preds:GetInt() then
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
    print("-----------------------------------------")
    local wPreds, wPrey = 0, 0
    for _, w in ipairs(VNPC_ActiveWildWanderers) do
        if IsValid(w) then
            if w.VNPC_WildType == "predator" then
                wPreds = wPreds + 1
                local pers = w.VNPC_PredatorPersonality or (w.VoreSettings and w.VoreSettings.PredatorPersonality) or "opportunistic"
                print(string.format(" -> Wild Predator [#%d] %s | Pers: %s | HP: %d",
                    w:EntIndex(), w:GetClass(), string.upper(pers), w:Health()))
            else
                wPrey = wPrey + 1
                local pers = w.VNPC_PreyPersonality or w.PreyPersonality or "fighter"
                print(string.format(" -> Wild Prey [#%d] %s | Pers: %s | HP: %d",
                    w:EntIndex(), w:GetClass(), string.upper(pers), w:Health()))
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

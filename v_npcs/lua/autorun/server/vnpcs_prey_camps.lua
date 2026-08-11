-- V-NPCs Prey Camps & Fortification Engineering AI Engine (vnpcs_prey_camps.lua)
-- Prey form camps of at least 10 members, slowly gather resources, and build defensive walls using map geometry; predators breach camps by swallowing the wall props

local camps_enabled = CreateConVar("vnpcs_prey_camps_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable prey camp establishment and defensive wall fortifications")
local camp_target_size = CreateConVar("vnpcs_prey_camp_target_size", "10", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Target number of prey NPCs per camp (at least 10 prey)")
local camp_resource_rate = CreateConVar("vnpcs_prey_camp_resource_rate", "1.5", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Base resource accumulation rate per second for prey camps")
local camp_wall_cost = CreateConVar("vnpcs_prey_camp_wall_cost", "25.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Resource cost to construct one defensive wall prop")
local camp_max_walls = CreateConVar("vnpcs_prey_camp_max_walls", "24", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum number of defensive wall props around a prey camp perimeter")
local camp_hut_cost = CreateConVar("vnpcs_prey_camp_hut_cost", "8.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Resource cost to construct one piece of a breakable dupe hut inside a fortified prey camp")
local camp_max_huts = CreateConVar("vnpcs_prey_camp_max_huts", "4", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum number of little huts inside a fortified prey camp courtyard")
local love_enabled = CreateConVar("vnpcs_prey_camp_love_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable love and pregnancy population growth in fortified prey camps")
local pregnancy_time = CreateConVar("vnpcs_prey_camp_pregnancy_time", "120.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Duration in seconds for a pregnant female citizen to bear a new citizen")
local camp_max_members = CreateConVar("vnpcs_prey_camp_max_members", "25", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum total member capacity per prey camp")

VNPC_ActivePreyCamps = VNPC_ActivePreyCamps or {}

local PREY_WALL_MODELS = {
    "models/props_wasteland/wood_fence01a.mdl",       -- Wide wooden fence barrier
    "models/props_fortifications/barricade01a.mdl"    -- Sturdy military fortification barricade
}

local PREY_HUT_PIECE_MODELS = {
    floor = "models/props_junk/wood_pallet001a.mdl",       -- Base floor pallet
    wall_back = "models/props_wasteland/wood_fence01a.mdl",-- Back wall panel
    wall_left = "models/props_wasteland/wood_fence01a.mdl",-- Left wall panel
    wall_right = "models/props_wasteland/wood_fence01a.mdl",-- Right wall panel
    wall_front_l = "models/props_debris/wood_board04a.mdl", -- Front left doorframe panel
    wall_front_r = "models/props_debris/wood_board04a.mdl", -- Front right doorframe panel
    roof = "models/props_junk/wood_pallet001a.mdl"         -- Roof pallet
}

function VNPC_IsEligiblePreyNPC(ent)
    if not IsValid(ent) or ent:Health() <= 0 then return false end
    if ent.Vored or ent.VNPC_Vored or ent.VNPC_Surrendered then return false end
    if ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator then return false end
    if VNPC_IsShyPredator and VNPC_IsShyPredator(ent) then return false end
    return (ent:IsNPC() or ent:IsNextBot())
end

function VNPC_IsFemalePreyCitizen(ent)
    if not IsValid(ent) or ent:Health() <= 0 then return false end
    if ent.VNPC_IsPermanentFortPredator then return true end
    if not VNPC_IsEligiblePreyNPC(ent) then return false end
    local mdl = string.lower(ent:GetModel() or "")
    local cls = string.lower(ent:GetClass() or "")
    if cls:find("citizen") or cls:find("rebel") or cls:find("refugee") or cls:find("mossman") or cls:find("alyx") or (ent.Classify and ent:Classify() == CLASS_CITIZEN) then
        if mdl:find("female") or mdl:find("alyx") or mdl:find("mossman") or mdl:find("f_") or mdl:find("citizen_female") then
            return true
        end
    end
    return false
end

function VNPC_IsMalePreyCitizen(ent)
    if not VNPC_IsEligiblePreyNPC(ent) then return false end
    if VNPC_IsFemalePreyCitizen(ent) then return false end
    local mdl = string.lower(ent:GetModel() or "")
    local cls = string.lower(ent:GetClass() or "")
    if cls:find("citizen") or cls:find("rebel") or cls:find("refugee") or cls:find("barney") or cls:find("monk") or (ent.Classify and ent:Classify() == CLASS_CITIZEN) then
        return true
    end
    return false
end

function VNPC_GetPreyCamp(npc)
    if not IsValid(npc) or not npc.VNPC_PreyCampID then return nil end
    for _, camp in ipairs(VNPC_ActivePreyCamps) do
        if camp.id == npc.VNPC_PreyCampID then
            return camp
        end
    end
    return nil
end

function VNPC_CreatePreyCamp(pos, founder)
    if not camps_enabled:GetBool() then return nil end
    if not IsValid(founder) then return nil end

    local origin = pos or founder:GetPos()
    for _, existing in ipairs(VNPC_ActivePreyCamps) do
        if existing.pos:DistToSqr(origin) < (1600 * 1600) then
            return existing
        end
    end

    local trUp = util.TraceLine({
        start = origin + Vector(0, 0, 10),
        endpos = origin + Vector(0, 0, 600),
        mask = MASK_SOLID_BRUSHONLY
    })
    local indoors = (trUp.Hit and not trUp.HitSky)

    local camp = {
        id = math.random(100000, 999999),
        pos = origin,
        isIndoors = indoors,
        isPreyCamp = true,
        leader = founder,
        members = { founder },
        walls = {},
        huts = {},
        fortified = false,
        resources = 15.0,
        createTime = CurTime(),
        lastUpdateTime = CurTime()
    }

    founder.VNPC_PreyCampID = camp.id
    table.insert(VNPC_ActivePreyCamps, camp)
    return camp
end

function VNPC_AssignPreyToCamp(npc, force)
    if not camps_enabled:GetBool() or not VNPC_IsEligiblePreyNPC(npc) then return nil end
    if npc.VNPC_IsPermanentFortPredator then return nil end

    if not npc.VNPC_PreyPersonality and not npc.PreyPersonality then
        local preyPersList = { "fighter", "passive", "panicked", "stubborn", "willing" }
        local rPers = preyPersList[math.random(1, #preyPersList)]
        npc.VNPC_PreyPersonality = rPers
        npc.PreyPersonality = rPers
    end

    local current = VNPC_GetPreyCamp(npc)
    if current then return current end

    local npcPos = npc:GetPos()

    -- 1. First priority: retake any abandoned Prey Camp (#camp.members == 0) within range
    local bestAbandoned = nil
    local bestAbandonedDistSqr = 6000 * 6000
    for _, camp in ipairs(VNPC_ActivePreyCamps) do
        if #camp.members == 0 then
            local dSqr = camp.pos:DistToSqr(npcPos)
            if dSqr <= bestAbandonedDistSqr then
                bestAbandoned = camp
                bestAbandonedDistSqr = dSqr
            end
        end
    end

    if bestAbandoned then
        table.insert(bestAbandoned.members, npc)
        npc.VNPC_PreyCampID = bestAbandoned.id
        bestAbandoned.abandonedTime = nil
        print("[V-NPCs] Citizen " .. tostring(npc) .. " retook abandoned Prey Camp #" .. bestAbandoned.id .. "!")
        hook.Run("VNPC_OnPreyCampRetaken", npc, bestAbandoned)
        return bestAbandoned
    end

    local targetSize = camp_target_size:GetInt() or 10
    local bestCamp = nil
    local bestDistSqr = 1e12

    for _, camp in ipairs(VNPC_ActivePreyCamps) do
        if #camp.members < targetSize then
            local dSqr = camp.pos:DistToSqr(npcPos)
            if dSqr <= bestDistSqr then
                bestCamp = camp
                bestDistSqr = dSqr
            end
        end
    end

    if bestCamp then
        table.insert(bestCamp.members, npc)
        npc.VNPC_PreyCampID = bestCamp.id
        return bestCamp
    else
        return VNPC_CreatePreyCamp(npcPos, npc)
    end
end

function VNPC_PlanPreyCampLayout(camp)
    if not camp or not camp.pos then return end

    -- 1. Dynamically calculate center of mass and bounding radius of all living camp members & structures
    local center = camp.pos
    local validMembers = 0
    local sumPos = Vector(0, 0, 0)
    for _, mem in ipairs(camp.members or {}) do
        if IsValid(mem) and mem:Health() > 0 then
            sumPos = sumPos + mem:GetPos()
            validMembers = validMembers + 1
        end
    end
    if validMembers > 0 then
        center = (sumPos / validMembers)
    end
    center = center + Vector(0, 0, 32)
    camp.center = center

    local maxMemberDist = 0
    for _, mem in ipairs(camp.members or {}) do
        if IsValid(mem) and mem:Health() > 0 then
            local d = mem:GetPos():Distance(center)
            if d > maxMemberDist then maxMemberDist = d end
        end
    end

    -- Dynamic perimeter radius adapts to living area size, member count, & territory expansion
    local minRad = camp.isIndoors and 130 or 260
    local maxRad = camp.isIndoors and 360 or 3000
    local targetRadius = math.Clamp(math.max(camp.territoryRadius or 450.0, maxMemberDist + (camp.isIndoors and 80 or 150)), minRad, maxRad)
    local numAngles = camp.isIndoors and math.Clamp(8 + math.floor((targetRadius - 130) / 45), 8, 16) or math.Clamp(8 + math.floor((targetRadius - 260) / 75), 8, 28)
    local anchorPoints = {}

    -- 2. Cast radial 3D terrain raycasts to find natural world walls, buildings, or slopes
    for s = 1, numAngles do
        local rad = math.rad((s - 1) * (360 / numAngles))
        local dir = Vector(math.cos(rad), math.sin(rad), 0)
        local endPos = center + dir * (targetRadius * 1.25)

        local wallTrace = util.TraceLine({
            start = center,
            endpos = endPos,
            mask = MASK_SOLID_BRUSHONLY
        })

        local anchorPos = nil
        if wallTrace.Hit and wallTrace.Fraction > 0.15 and wallTrace.Fraction < 0.98 then
            anchorPos = wallTrace.HitPos - dir * (camp.isIndoors and 14 or 16)
        else
            local groundCandidate = center + dir * targetRadius
            local groundTrace = util.TraceLine({
                start = groundCandidate + Vector(0, 0, 100),
                endpos = groundCandidate - Vector(0, 0, 250),
                mask = MASK_SOLID_BRUSHONLY
            })
            anchorPos = groundTrace.Hit and (groundTrace.HitPos + Vector(0, 0, 2)) or (groundCandidate - Vector(0, 0, 30))
        end
        table.insert(anchorPoints, anchorPos)
    end

    -- 3. Connect adjacent perimeter anchors and subdivide open spans into dynamic barrier segments
    camp.plannedWalls = {}
    local gatePlaced = false

    for s = 1, #anchorPoints do
        local next_s = (s % #anchorPoints) + 1
        local P1 = anchorPoints[s]
        local P2 = anchorPoints[next_s]
        local sideLen = P1:Distance(P2)
        local numSegs = math.max(1, math.ceil(sideLen / 86))

        for seg = 1, numSegs do
            local t1 = (seg - 1) / numSegs
            local t2 = seg / numSegs
            local pStart = LerpVector(t1, P1, P2)
            local pEnd = LerpVector(t2, P1, P2)
            local midPos = (pStart + pEnd) * 0.5 + Vector(0, 0, 45)

            local floorTrace = util.TraceLine({
                start = midPos,
                endpos = midPos - Vector(0, 0, 240),
                mask = MASK_SOLID_BRUSHONLY
            })

            local floorPos = floorTrace.Hit and (floorTrace.HitPos + Vector(0, 0, 2)) or (midPos - Vector(0, 0, 45))
            local wallDir = (pEnd - pStart):GetNormalized()
            local yaw = wallDir:Angle().y
            local dz = pEnd.z - pStart.z
            local pitch = math.deg(math.atan2(-dz, sideLen / numSegs))
            local wallAng = Angle(pitch, yaw, 0)

            local isGate = false
            if not gatePlaced and s == 1 and seg == math.floor(numSegs * 0.5) then
                isGate = true
                gatePlaced = true
            end

            table.insert(camp.plannedWalls, {
                pos = floorPos,
                ang = wallAng,
                isGate = isGate,
                built = false,
                isUpgrade = (camp.breachAlertTime and (CurTime() - camp.breachAlertTime) < 180)
            })
        end
    end
end

function VNPC_ConstructPreyCampFire(camp)
    if not camps_enabled:GetBool() or not camp or not camp.pos then return false end
    if IsValid(camp.campfire) then return false end

    local tr = util.TraceLine({
        start = camp.pos + Vector(0, 0, 40),
        endpos = camp.pos - Vector(0, 0, 150),
        mask = MASK_SOLID_BRUSHONLY
    })
    if not tr.Hit or tr.HitNormal.z < 0.65 then return false end

    local fire = ents.Create("prop_physics")
    if not IsValid(fire) then return false end

    fire:SetModel("models/props_c17/FurnitureFireplace001a.mdl")
    fire:SetPos(tr.HitPos)
    fire:SetAngles(Angle(0, math.random(0, 360), 0))
    fire:Spawn()
    fire:Activate()

    local minZ = fire:OBBMins().z
    local zOffset = (minZ < 0) and math.abs(minZ) or 0
    fire:SetPos(tr.HitPos + Vector(0, 0, zOffset + 2))

    fire.VNPC_IsPreyCampFire = true
    fire.VNPC_PreyCampID = camp.id
    fire.VNPC_NoVore = true
    fire:SetHealth(500)

    if fire.Ignite then
        fire:Ignite(99999, 0)
    end

    local phys = fire:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(Vector(0,0,0))
        phys:EnableMotion(false)
        phys:Sleep()
    end

    camp.campfire = fire
    return true
end

function VNPC_EnsurePreyCampLeader(camp)
    if not camp or not camp.members or #camp.members == 0 then return nil end
    if IsValid(camp.leader) and camp.leader:Health() > 0 and not camp.leader.Vored and not camp.leader.VNPC_Vored then
        return camp.leader
    end

    local candidate = nil
    for _, mem in ipairs(camp.members) do
        if IsValid(mem) and mem:Health() > 0 and not mem.Vored and not mem.VNPC_Vored and not mem.VNPC_IsSleeping then
            candidate = mem
            break
        end
    end
    if not candidate then
        candidate = camp.members[1]
    end

    if IsValid(candidate) then
        camp.leader = candidate
        candidate.VNPC_IsCampLeader = true
        candidate.VNPC_PreyCampLeader = camp.id
        print(string.format("[V-NPCs] Prey Camp #%d elected Leader: #%d [%s]!", camp.id, candidate:EntIndex(), candidate.PrintName or candidate:GetClass()))
    end
    return camp.leader
end

function VNPC_ConstructPreyCampLeaderHut(camp)
    if not camps_enabled:GetBool() or not camp or not camp.pos then return false end
    if IsValid(camp.leaderTable) then return false end

    local angle = math.rad(math.random(0, 360))
    local candidatePos = camp.pos + Vector(math.cos(angle) * 190, math.sin(angle) * 190, 0)
    local tr = util.TraceLine({
        start = candidatePos + Vector(0, 0, 40),
        endpos = candidatePos - Vector(0, 0, 150),
        mask = MASK_SOLID_BRUSHONLY
    })
    if not tr.Hit or tr.HitNormal.z < 0.65 then return false end

    -- 1. Spawn the Leader's Table centerpiece
    local tbl = ents.Create("prop_physics")
    if not IsValid(tbl) then return false end

    local tableMdl = "models/props_c17/FurnitureTable001a.mdl"
    if not util.IsValidModel(tableMdl) then
        tableMdl = "models/props_wasteland/wood_fence01a.mdl"
    end
    tbl:SetModel(tableMdl)
    tbl:SetPos(tr.HitPos + Vector(0, 0, 2))
    tbl:SetAngles(Angle(0, math.deg(angle), 0))
    tbl:Spawn()
    tbl:Activate()
    tbl.VNPC_IsLeaderTable = true
    tbl.VNPC_CampID = camp.id
    tbl.VNPC_NoVore = true
    tbl:SetHealth(9999)

    local phys = tbl:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Sleep()
    end

    camp.leaderTable = tbl

    -- 2. Build Hut Walls around the Table
    local walls = {}
    local offsets = {
        { ang = 180, dist = 55 },
        { ang = 90,  dist = 55 },
        { ang = -90, dist = 55 }
    }
    for _, off in ipairs(offsets) do
        local wRad = math.rad(math.deg(angle) + off.ang)
        local wPos = tr.HitPos + Vector(math.cos(wRad) * off.dist, math.sin(wRad) * off.dist, 0)
        local wTr = util.TraceLine({
            start = wPos + Vector(0, 0, 40),
            endpos = wPos - Vector(0, 0, 150),
            mask = MASK_SOLID_BRUSHONLY
        })
        if wTr.Hit then
            local wall = ents.Create("prop_physics")
            if IsValid(wall) then
                wall:SetModel("models/props_wasteland/wood_fence01a.mdl")
                wall:SetPos(wTr.HitPos)
                wall:SetAngles(Angle(0, math.deg(wRad), 0))
                wall:Spawn()
                wall:Activate()
                wall.VNPC_IsLeaderHutWall = true
                wall.VNPC_CampID = camp.id
                wall.VNPC_NoVore = true
                wall:SetHealth(350)
                local wPhys = wall:GetPhysicsObject()
                if IsValid(wPhys) then wPhys:EnableMotion(false) wPhys:Sleep() end
                table.insert(walls, wall)
            end
        end
    end

    -- 3. Roof over the Table
    if not camp.isIndoors then
        local roof = ents.Create("prop_physics")
        if IsValid(roof) then
            roof:SetModel("models/props_junk/wood_pallet001a.mdl")
            roof:SetPos(tr.HitPos + Vector(0, 0, 75))
            roof:SetAngles(Angle(0, math.deg(angle), 0))
            roof:Spawn()
            roof:Activate()
            roof.VNPC_IsLeaderHutWall = true
            roof.VNPC_CampID = camp.id
            roof.VNPC_NoVore = true
            roof:SetHealth(350)
            local rPhys = roof:GetPhysicsObject()
            if IsValid(rPhys) then rPhys:EnableMotion(false) rPhys:Sleep() end
            table.insert(walls, roof)
        end
    end

    camp.leaderHut = {
        tableProp = tbl,
        walls = walls,
        pos = tr.HitPos
    }

    print(string.format("[V-NPCs] Built Leader Hut and Table for Prey Camp #%s at (%.1f, %.1f, %.1f)!", tostring(camp.id), tr.HitPos.x, tr.HitPos.y, tr.HitPos.z))
    return true
end

function VNPC_PreyCampLeaderDecision_AI(camp, now)
    if not camp or not camp.members or #camp.members == 0 then return end
    local leader = VNPC_EnsurePreyCampLeader(camp)
    if not IsValid(leader) or leader:Health() <= 0 or leader.Vored or leader.VNPC_Vored or leader.VNPC_IsSleeping then return end

    if (camp.nextLeaderDecisionTime or 0) > now then return end
    camp.nextLeaderDecisionTime = now + math.random(7, 12)

    local decision = "TERRITORY_PATROL"
    if (camp.breachAlertTime or 0) > (now - 20.0) then
        decision = "DEFENSIVE_ALERT"
    elseif not camp.fortified or #(camp.walls or {}) < 10 then
        decision = "FORTIFY_PERIMETER"
    elseif (camp.resources or 0) < 40.0 then
        decision = "GATHER_RESOURCES"
    else
        local hungryCount = 0
        for _, mem in ipairs(camp.members) do
            if IsValid(mem) and ( (VNPC_GetHunger and VNPC_GetHunger(mem) >= 45) or (VNPC_GetThirst and VNPC_GetThirst(mem) >= 45) ) then
                hungryCount = hungryCount + 1
            end
        end
        if hungryCount >= 2 or (camp.resources or 0) >= 80.0 then
            decision = "COOK_MEAL_FEAST"
        end
    end

    camp.leaderDecision = decision

    -- Command Leader to visit their Leader Hut & Table
    if IsValid(camp.leaderTable) and not IsValid(leader:GetEnemy()) and not leader.VNPC_IsCookingMeal and not leader.VNPC_IsEatingMeal then
        local tblPos = camp.leaderTable:GetPos()
        local dSqr = leader:GetPos():DistToSqr(tblPos)
        if dSqr > (120 * 120) then
            if leader.SetLastPosition then pcall(leader.SetLastPosition, leader, tblPos) end
            if leader.SetSchedule then pcall(leader.SetSchedule, leader, SCHED_FORCED_GO_RUN) end
        else
            if leader.SetSchedule then pcall(leader.SetSchedule, leader, SCHED_IDLE_STAND) end
            if leader.EmitSound then
                leader:EmitSound("npc/alyx/sigh01.wav", 75, math.random(95, 105))
            end
        end
    end

    if decision == "COOK_MEAL_FEAST" then
        for _, mem in ipairs(camp.members) do
            if IsValid(mem) and VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(mem) and not mem.VNPC_IsCookingMeal and not mem.VNPC_IsEatingMeal then
                mem.VNPC_ForceCookMeal = (math.random(1, 2) == 1 and "burger" or "hotdog")
                break
            end
        end
    end

    print(string.format("[V-NPCs] Prey Camp #%d Leader #%d [%s] at Leader Hut Table decided strategy: [%s]!", camp.id, leader:EntIndex(), leader.PrintName or leader:GetClass(), decision))
end

function VNPC_PreyCampCooking_AI(camp, now)
    if not camp or not camp.members then return end
    camp.cookedMeals = camp.cookedMeals or {}

    -- Prune dead or consumed prop meals
    for i = #camp.cookedMeals, 1, -1 do
        local prop = camp.cookedMeals[i]
        if not IsValid(prop) or not prop.VNPC_IsCookedPropMeal then
            table.remove(camp.cookedMeals, i)
        end
    end

    -- Limit cooked prop meals on display at a camp
    if #camp.cookedMeals >= 4 then return end

    for _, mem in ipairs(camp.members) do
        if not IsValid(mem) or mem:Health() <= 0 or mem.Vored or mem.VNPC_IsSleeping then continue end
        if IsValid(mem:GetEnemy()) or mem.VNPC_IsEatingMeal or mem.VNPC_IsCollectingScrap then continue end
        if not VNPC_IsFemalePreyCitizen(mem) then continue end

        local hunger = VNPC_GetHunger and VNPC_GetHunger(mem) or 0
        local thirst = VNPC_GetThirst and VNPC_GetThirst(mem) or 0
        local shouldCook = (mem.VNPC_ForceCookMeal ~= nil) or (hunger >= 60.0) or (thirst >= 60.0) or ((mem.VNPC_NextCookTime or 0) <= now and #camp.members >= 2 and math.random(1, 15) == 1)

        if not mem.VNPC_IsCookingMeal and shouldCook then
            local mealType = mem.VNPC_ForceCookMeal
            if not mealType then
                if thirst >= 60.0 and thirst > hunger then
                    mealType = "soda"
                else
                    mealType = (math.random(1, 2) == 1) and "hotdog" or "burger"
                end
            end

            local cookPos = IsValid(camp.campfire) and camp.campfire:GetPos() or camp.pos
            local dSqr = mem:GetPos():DistToSqr(cookPos)
            if dSqr > (130 * 130) then
                if mem.SetLastPosition then pcall(mem.SetLastPosition, mem, cookPos) end
                if mem.SetSchedule then pcall(mem.SetSchedule, mem, SCHED_FORCED_GO_RUN) end
                mem.VNPC_PendingMealType = mealType
            else
                mem.VNPC_IsCookingMeal = true
                mem.VNPC_CookingMealType = mealType
                mem.VNPC_CookingFinishTime = now + 5.0 -- 5s cooking duration
                if mem.SetEnemy then pcall(mem.SetEnemy, mem, nil) end
                if mem.SetSchedule then pcall(mem.SetSchedule, mem, SCHED_IDLE_STAND) end
                if mem.EmitSound then
                    mem:EmitSound("ambient/fire/fire_small_loop1.wav", 70, math.random(95, 105))
                end
            end
        elseif mem.VNPC_IsCookingMeal then
            if now >= (mem.VNPC_CookingFinishTime or 0) then
                local mealType = mem.VNPC_CookingMealType or "hotdog"
                local mealData = (VNPC_PreyCookedMealModels and VNPC_PreyCookedMealModels[mealType]) or { name = "Hotdog", fallback = "models/props_junk/garbage_takeoutcarton001a.mdl" }
                local mdl = VNPC_GetCookedMealModel and VNPC_GetCookedMealModel(mealType) or mealData.fallback

                local prop = ents.Create("prop_physics")
                if IsValid(prop) then
                    prop:SetModel(mdl)
                    local fwd = mem:GetForward()
                    prop:SetPos(mem:GetPos() + fwd * 35 + Vector(0, 0, 15))
                    prop:SetAngles(Angle(0, mem:GetAngles().y, 0))
                    prop:Spawn()
                    prop:Activate()
                    prop:SetHealth(100)
                    prop.VNPC_IsCookedPropMeal = true
                    prop.VNPC_MealType = mealType
                    prop.VNPC_MealCooker = mem
                    prop.VNPC_PreyCampID = camp.id
                    prop.VNPC_NoVore = true
                    table.insert(camp.cookedMeals, prop)

                    print(string.format("[V-NPCs] Female Prey Citizen #%d [%s] cooked prop meal %s (%s) at Prey Camp #%s!", mem:EntIndex(), mem.PrintName or mem:GetClass(), mealData.name or mealType, mealType, tostring(camp.id)))
                    if mem.EmitSound then
                        mem:EmitSound("physics/metal/metal_canister_impact_soft1.wav", 75, 100)
                    end
                end

                mem.VNPC_IsCookingMeal = false
                mem.VNPC_CookingMealType = nil
                mem.VNPC_ForceCookMeal = nil
                mem.VNPC_PendingMealType = nil
                mem.VNPC_NextCookTime = now + math.random(45, 90)
                if mem.SetSchedule then pcall(mem.SetSchedule, mem, SCHED_IDLE_STAND) end
            end
        end
    end
end

function VNPC_PreyMealConsumption_AI(camp, now)
    if not camp or not camp.members or not camp.cookedMeals then return end

    for i = #camp.cookedMeals, 1, -1 do
        local prop = camp.cookedMeals[i]
        if not IsValid(prop) or not prop.VNPC_IsCookedPropMeal then
            table.remove(camp.cookedMeals, i)
            continue
        end

        local bestConsumer = nil
        local bestDistSqr = 800 * 800
        for _, mem in ipairs(camp.members) do
            if not IsValid(mem) or mem:Health() <= 0 or mem.Vored or mem.VNPC_IsSleeping then continue end
            if IsValid(mem:GetEnemy()) or mem.VNPC_IsCookingMeal or mem.VNPC_IsEatingMeal or mem.VNPC_IsCollectingScrap then continue end
            local hunger = VNPC_GetHunger and VNPC_GetHunger(mem) or 0
            local thirst = VNPC_GetThirst and VNPC_GetThirst(mem) or 0
            if hunger >= 30.0 or thirst >= 30.0 or prop.VNPC_MealCooker == mem then
                local dSqr = mem:GetPos():DistToSqr(prop:GetPos())
                if dSqr < bestDistSqr then
                    bestConsumer = mem
                    bestDistSqr = dSqr
                end
            end
        end

        if bestConsumer then
            if bestDistSqr > (90 * 90) then
                if bestConsumer.SetLastPosition then pcall(bestConsumer.SetLastPosition, bestConsumer, prop:GetPos()) end
                if bestConsumer.SetSchedule then pcall(bestConsumer.SetSchedule, bestConsumer, SCHED_FORCED_GO) end
            else
                bestConsumer.VNPC_IsEatingMeal = true
                bestConsumer.VNPC_EatingMealType = prop.VNPC_MealType
                local mealData = (VNPC_PreyCookedMealModels and VNPC_PreyCookedMealModels[prop.VNPC_MealType]) or { hungerRelief = 60.0, thirstRelief = 10.0, name = "Hotdog" }

                if VNPC_GetHunger and VNPC_SetHunger then
                    VNPC_SetHunger(bestConsumer, math.max(0, VNPC_GetHunger(bestConsumer) - (mealData.hungerRelief or 60.0)))
                end
                if VNPC_GetThirst and VNPC_SetThirst then
                    VNPC_SetThirst(bestConsumer, math.max(0, VNPC_GetThirst(bestConsumer) - (mealData.thirstRelief or 60.0)))
                end

                if VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(bestConsumer) then
                    -- FEMALE PREY CITIZENS SWALLOW MEALS WHOLE WITHOUT CHEWING -> BELLY EXPANDS FROM FOOD
                    VNPC_EnsureFemalePreyBelly(bestConsumer)
                    bestConsumer.VNPC_NoBellyExpansionFromMeal = false
                    bestConsumer.VNPC_FoodMealWeight = (bestConsumer.VNPC_FoodMealWeight or 0) + (mealData.mealBellyWeight or 50.0)
                    if IsValid(bestConsumer.VNPC_Belly) then
                        bestConsumer.VNPC_Belly.VNPC_FoodMealWeight = bestConsumer.VNPC_FoodMealWeight
                        if bestConsumer.VNPC_Belly.SetBellySize then
                            bestConsumer.VNPC_Belly:SetBellySize()
                        end
                    end
                    if bestConsumer.EmitSound then
                        bestConsumer:EmitSound("gulps/g" .. math.random(1, 10) .. ".wav", 75, math.random(95, 105))
                    end
                    print(string.format("[V-NPCs] Female Prey Citizen #%d [%s] swallowed prop meal %s (%s) whole without chewing! Belly expanded! [Hunger = %.1f%%, Thirst = %.1f%%, Food Weight = %.1f]", bestConsumer:EntIndex(), bestConsumer.PrintName or bestConsumer:GetClass(), mealData.name or prop.VNPC_MealType, prop.VNPC_MealType, VNPC_GetHunger(bestConsumer), VNPC_GetThirst(bestConsumer), bestConsumer.VNPC_FoodMealWeight))
                else
                    -- MALE PREY CITIZENS CHEW NORMALLY -> ZERO BELLY EXPANSION
                    bestConsumer.VNPC_NoBellyExpansionFromMeal = true
                    if bestConsumer.EmitSound then
                        if prop.VNPC_MealType == "soda" then
                            bestConsumer:EmitSound("gulps/g" .. math.random(1, 10) .. ".wav", 75, math.random(95, 105))
                        else
                            bestConsumer:EmitSound("npc/barnacle/barnacle_crunch2.wav", 75, math.random(95, 105))
                        end
                    end
                    print(string.format("[V-NPCs] Male Prey Citizen #%d [%s] chewed and ate prop meal %s (%s) [Hunger = %.1f%%, Thirst = %.1f%%, Belly Expansion = NONE]!", bestConsumer:EntIndex(), bestConsumer.PrintName or bestConsumer:GetClass(), mealData.name or prop.VNPC_MealType, prop.VNPC_MealType, VNPC_GetHunger(bestConsumer), VNPC_GetThirst(bestConsumer)))
                end

                table.remove(camp.cookedMeals, i)
                if IsValid(prop) then
                    prop:Remove()
                end

                timer.Simple(2.0, function()
                    if IsValid(bestConsumer) then
                        bestConsumer.VNPC_IsEatingMeal = false
                        bestConsumer.VNPC_EatingMealType = nil
                        if bestConsumer.SetSchedule then pcall(bestConsumer.SetSchedule, bestConsumer, SCHED_IDLE_STAND) end
                    end
                end)
            end
        end
    end
end

function VNPC_ConstructPreyCampWall(camp)
    if not camps_enabled:GetBool() or not camp then return false end
    if not camp.plannedWalls or #camp.plannedWalls == 0 then
        VNPC_PlanPreyCampLayout(camp)
    end

    local targetPlan = nil
    for _, plan in ipairs(camp.plannedWalls) do
        if not plan.built then
            targetPlan = plan
            break
        end
    end
    if not targetPlan then return false end
    targetPlan.built = true

    local wall = ents.Create("prop_physics")
    if not IsValid(wall) then return false end

    local mdl = nil
    if targetPlan.isGate then
        mdl = "models/props_wasteland/wood_fence01a.mdl"
    elseif targetPlan.isUpgrade then
        mdl = "models/props_fortifications/barricade01a.mdl"
    else
        camp.wallModel = camp.wallModel or PREY_WALL_MODELS[math.random(1, #PREY_WALL_MODELS)]
        mdl = camp.wallModel
    end

    if not util.IsValidModel(mdl) then
        mdl = "models/props_c17/fence01a.mdl"
    end

    local isMetalFence = string.find(string.lower(mdl), "barricade") or (string.find(string.lower(mdl), "fence") and not string.find(string.lower(mdl), "wood_fence01a"))
    local wallAng = Angle(targetPlan.ang.p, targetPlan.ang.y, targetPlan.ang.r)
    if isMetalFence then
        wallAng = Angle(targetPlan.ang.p, targetPlan.ang.y + 90, targetPlan.ang.r)
    end

    wall:SetModel(mdl)
    wall:SetPos(targetPlan.pos)
    wall:SetAngles(wallAng)
    wall:Spawn()
    wall:Activate()

    local minZ = wall:OBBMins().z
    local zOffset = (minZ < 0) and math.abs(minZ) or 0
    wall:SetPos(targetPlan.pos + Vector(0, 0, zOffset + 2))

    wall.VNPC_IsPreyCampWall = true
    wall.VNPC_PreyCampID = camp.id
    wall.VNPC_CampRef = camp
    wall:SetHealth(targetPlan.isUpgrade and 350 or 180)

    if targetPlan.isGate then
        wall.VNPC_IsPreyCampGate = true
        wall.VNPC_GateClosedAng = wallAng
        wall.VNPC_GateOpenAng = Angle(0, wallAng.y + 90, 0)
    end

    table.insert(camp.walls, wall)

    local phys = wall:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(Vector(0,0,0))
        phys:EnableMotion(false)
        phys:Sleep()
    end

    if wall.EmitSound then
        wall:EmitSound("physics/wood/wood_box_impact_hard1.wav", 75, math.random(95, 105))
    end

    return true
end

function VNPC_PredatorBreachPreyCampWall(pred, wall, camp)
    if not IsValid(pred) or not IsValid(wall) or not camp then return end
    if not wall.VNPC_IsPreyCampWall then return end

    if pred.VNPC_IsInfiltratingFort and pred.VNPC_IsInfiltratingFort.id == camp.id then
        -- SWALLOW THE WALL: Instead of disabling collision, swallow the wall into her belly!
        pred.VNPC_InfiltrationSwallowedWalls = pred.VNPC_InfiltrationSwallowedWalls or {}
        table.insert(pred.VNPC_InfiltrationSwallowedWalls, {
            mdl = wall:GetModel() or "models/props_wasteland/wood_fence01a.mdl",
            pos = wall:GetPos(),
            ang = wall:GetAngles(),
            health = wall:GetMaxHealth() or 350,
            isGate = wall.VNPC_IsPreyCampGate,
            closedAng = wall.VNPC_GateClosedAng,
            openAng = wall.VNPC_GateOpenAng,
            isWall = true
        })

        for idx, w in ipairs(camp.walls) do
            if w == wall then
                table.remove(camp.walls, idx)
                break
            end
        end

        local belly = pred.VNPC_Belly or pred.Belly
        if IsValid(belly) and belly.AddPrey then
            pcall(belly.AddPrey, belly, wall)
        elseif pred.EatEntity then
            pcall(pred.EatEntity, pred, wall)
        else
            wall:SetNoDraw(true)
            wall:SetSolid(0)
            wall:SetParent(pred)
            timer.Simple(0.1, function()
                if IsValid(wall) then wall:Remove() end
            end)
        end

        -- Do NOT raise suspicion or sound breach alert while infiltrating!
        return
    end

    for idx, w in ipairs(camp.walls) do
        if w == wall then
            table.remove(camp.walls, idx)
            break
        end
    end

    local belly = pred.VNPC_Belly or pred.Belly
    if IsValid(belly) and belly.AddPrey then
        pcall(belly.AddPrey, belly, wall)
    elseif pred.EatEntity then
        pcall(pred.EatEntity, pred, wall)
    else
        wall:SetNoDraw(true)
        wall:SetSolid(0)
        wall:SetParent(pred)
        if pred.EmitSound then
            pred:EmitSound("physics/metal/metal_box_break1.wav", 85, math.random(90, 105))
        end
        timer.Simple(0.1, function()
            if IsValid(wall) then wall:Remove() end
        end)
    end

    camp.breachAlertTime = CurTime()
    local maxWalls = camp_max_walls:GetInt()
    if #camp.walls < (maxWalls * 0.7) then
        camp.plannedWalls = nil
        camp.fortified = false
    end
end

function VNPC_CalculateCampHutPosition(camp)
    if not camp or not camp.pos then return nil, nil end
    local numHuts = math.Clamp(math.ceil(#(camp.members or {}) / 3), 1, camp_max_huts:GetInt() or 6)
    local radius = camp.isIndoors and math.Clamp(45 + ((#(camp.huts or {})) * 35), 45, 140) or (85 + ((#(camp.huts or {})) * 50))
    local center = (camp.center or camp.pos) + Vector(0, 0, 32)

    for i = 0, numHuts - 1 do
        local theta = (i / numHuts) * (2 * math.pi) + math.rad(math.random(0, 360))
        local candidatePos = center + Vector(math.cos(theta) * radius, math.sin(theta) * radius, 65)

        local tr = util.TraceLine({
            start = candidatePos,
            endpos = candidatePos - Vector(0, 0, 220),
            mask = MASK_SOLID_BRUSHONLY
        })

        if tr.Hit and tr.HitNormal.z > 0.65 then
            local occupied = false
            for _, h in ipairs(camp.huts or {}) do
                if IsValid(h) and h:GetPos():DistToSqr(tr.HitPos) < (120 * 120) then
                    occupied = true
                    break
                end
            end

            if not occupied then
                local outwardDir = (tr.HitPos - center):GetNormalized()
                local yaw = outwardDir:Angle().y
                local ang = Angle(0, yaw, 0)
                return tr.HitPos + Vector(0, 0, 10), ang
            end
        end
    end
    return nil, nil
end

function VNPC_CreateHutSite(camp)
    if not camp then return nil end
    local pos, ang = VNPC_CalculateCampHutPosition(camp)
    if not pos or not ang then return nil end
    return {
        pos = pos,
        ang = ang,
        stage = 0,
        props = {}
    }
end

function VNPC_ConstructPreyCampHut(camp)
    if not camps_enabled:GetBool() or not camp then return false end
    if not camp.activeHutSite then
        camp.activeHutSite = VNPC_CreateHutSite(camp)
    end
    local site = camp.activeHutSite
    if not site then return false end

    -- Check if an actual saved workshop dupe file is installed in data/dupes/ or data/advdupe2/
    if site.stage == 0 and file and file.Exists and duplicator then
        local dupePath = nil
        if file.Exists("dupes/slum_hut.dupe", "DATA") then
            dupePath = "dupes/slum_hut.dupe"
        elseif file.Exists("advdupe2/slum_hut.txt", "DATA") then
            dupePath = "advdupe2/slum_hut.txt"
        end
        if dupePath then
            local dupeData = file.Read(dupePath, "DATA")
            if dupeData and duplicator.Paste then
                local success, pastedEnts = pcall(duplicator.Paste, nil, dupeData, site.pos)
                if success and istable(pastedEnts) and #pastedEnts > 0 then
                    for _, prop in ipairs(pastedEnts) do
                        if IsValid(prop) then
                            prop.VNPC_IsPreyCampHutPiece = true
                            prop.VNPC_PreyCampID = camp.id
                            table.insert(site.props, prop)
                        end
                    end
                    local hut = {
                        id = #(camp.huts or {}) + 1,
                        pos = site.pos,
                        ang = site.ang,
                        props = site.props,
                        VNPC_IsPreyCampHut = true,
                        VNPC_PreyCampID = camp.id
                    }
                    camp.huts = camp.huts or {}
                    table.insert(camp.huts, hut)
                    camp.activeHutSite = nil
                    return true
                end
            end
        end
    end

    site.stage = (site.stage or 0) + 1
    local fwd = site.ang:Forward()
    local right = site.ang:Right()

    local pModel = "models/props_wasteland/wood_fence01a.mdl"
    local pPos = site.pos
    local pAng = site.ang

    if site.stage == 1 then
        -- Stage 1: Full 96x96 wooden plank floor platform
        pModel = "models/props_wasteland/wood_fence01a.mdl"
        pPos = site.pos + Vector(0, 0, 2)
        pAng = Angle(90, site.ang.y, 0)
    elseif site.stage == 2 then
        -- Stage 2: Back wall (96 units wide, flush at rear perimeter fwd * +46)
        pModel = "models/props_wasteland/wood_fence01a.mdl"
        pPos = site.pos + fwd * 46 + Vector(0, 0, 32)
        pAng = site.ang
    elseif site.stage == 3 then
        -- Stage 3: Left side wall (96 units long, flush at left perimeter right * +46)
        pModel = "models/props_wasteland/wood_fence01a.mdl"
        pPos = site.pos + right * 46 + Vector(0, 0, 32)
        pAng = Angle(0, site.ang.y + 90, 0)
    elseif site.stage == 4 then
        -- Stage 4: Right side wall (96 units long, flush at right perimeter right * -46)
        pModel = "models/props_wasteland/wood_fence01a.mdl"
        pPos = site.pos - right * 46 + Vector(0, 0, 32)
        pAng = Angle(0, site.ang.y - 90, 0)
    elseif site.stage == 5 then
        -- Stage 5: Front left upright pallet framing the doorway
        pModel = "models/props_junk/wood_pallet001a.mdl"
        pPos = site.pos - fwd * 46 + right * 24 + Vector(0, 0, 24)
        pAng = Angle(90, site.ang.y, 0)
    elseif site.stage == 6 then
        -- Stage 6: Front right upright pallet framing the doorway
        pModel = "models/props_junk/wood_pallet001a.mdl"
        pPos = site.pos - fwd * 46 - right * 24 + Vector(0, 0, 24)
        pAng = Angle(90, site.ang.y, 0)
    else
        -- Stage 7: Slanted wooden/corrugated roof covering the 96x96 shack (skip if indoors under low ceiling!)
        if camp.isIndoors then
            local trCeil = util.TraceLine({
                start = site.pos + Vector(0, 0, 10),
                endpos = site.pos + Vector(0, 0, 100),
                mask = MASK_SOLID_BRUSHONLY
            })
            if trCeil.Hit and (trCeil.Fraction * 90) < 75 then
                site.stage = 7
                local hut = {
                    pos = site.pos,
                    ang = site.ang,
                    props = site.props,
                    VNPC_IsPreyCampHut = true,
                    VNPC_PreyCampID = camp.id
                }
                camp.huts = camp.huts or {}
                table.insert(camp.huts, hut)
                camp.activeHutSite = nil
                return true
            end
        end
        pModel = "models/props_wasteland/wood_fence01a.mdl"
        pPos = site.pos + Vector(0, 0, 64)
        pAng = Angle(8, site.ang.y, 0)
    end

    if not util.IsValidModel(pModel) then
        pModel = "models/props_c17/fence01a.mdl"
    end

    local prop = ents.Create("prop_physics")
    if not IsValid(prop) then return false end

    prop:SetModel(pModel)
    prop:SetPos(pPos)
    prop:SetAngles(pAng)
    prop:Spawn()
    prop:Activate()

    prop.VNPC_IsPreyCampHutPiece = true
    prop.VNPC_PreyCampID = camp.id
    prop:SetHealth(100)

    local phys = prop:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(Vector(0,0,0))
        phys:EnableMotion(false)
        phys:Sleep()
    end

    if prop.EmitSound then
        prop:EmitSound("physics/wood/wood_box_impact_hard1.wav", 80, math.random(95, 105))
    end

    table.insert(site.props, prop)

    if site.stage >= 7 then
        local hut = {
            id = #(camp.huts or {}) + 1,
            pos = site.pos,
            ang = site.ang,
            props = site.props,
            VNPC_IsPreyCampHut = true,
            VNPC_PreyCampID = camp.id
        }
        camp.huts = camp.huts or {}
        table.insert(camp.huts, hut)
        camp.activeHutSite = nil
    end

    return true
end

function VNPC_PredatorBreachPreyCampHut(pred, hutOrPiece, camp)
    if not IsValid(pred) or not camp then return end
    local targetProp = hutOrPiece

    if istable(hutOrPiece) and hutOrPiece.props then
        for _, p in ipairs(hutOrPiece.props) do
            if IsValid(p) then
                targetProp = p
                break
            end
        end
    end

    if not IsValid(targetProp) then return end

    if pred.VNPC_IsInfiltratingFort and pred.VNPC_IsInfiltratingFort.id == camp.id then
        pred.VNPC_InfiltrationSwallowedWalls = pred.VNPC_InfiltrationSwallowedWalls or {}
        table.insert(pred.VNPC_InfiltrationSwallowedWalls, {
            mdl = targetProp:GetModel() or "models/props_wasteland/wood_fence01a.mdl",
            pos = targetProp:GetPos(),
            ang = targetProp:GetAngles(),
            health = targetProp:GetMaxHealth() or 100,
            isHutPiece = true
        })

        local belly = pred.VNPC_Belly or pred.Belly
        if IsValid(belly) and belly.AddPrey then
            pcall(belly.AddPrey, belly, targetProp)
        elseif pred.EatEntity then
            pcall(pred.EatEntity, pred, targetProp)
        else
            targetProp:SetNoDraw(true)
            targetProp:SetSolid(0)
            targetProp:SetParent(pred)
            timer.Simple(0.1, function()
                if IsValid(targetProp) then targetProp:Remove() end
            end)
        end
        return
    end

    local belly = pred.VNPC_Belly or pred.Belly
    if IsValid(belly) and belly.AddPrey then
        pcall(belly.AddPrey, belly, targetProp)
    elseif pred.EatEntity then
        pcall(pred.EatEntity, pred, targetProp)
    else
        targetProp:SetNoDraw(true)
        targetProp:SetSolid(0)
        targetProp:SetParent(pred)
        if pred.EmitSound then
            pred:EmitSound("physics/wood/wood_plank_break1.wav", 85, math.random(90, 105))
        end
        timer.Simple(0.1, function()
            if IsValid(targetProp) then targetProp:Remove() end
        end)
    end
end

function VNPC_ConstructPreyCampCourtyardDefense(camp)
    if not camps_enabled:GetBool() or not camp or not camp.fortified then return false end
    camp.courtyardDefenses = camp.courtyardDefenses or {}
    local maxDefenses = math.Clamp(math.floor(camp_max_walls:GetInt() * 0.5), 2, 12)
    if #camp.courtyardDefenses >= maxDefenses then return false end

    local center = (camp.center or camp.pos) + Vector(0, 0, 32)
    local angle = math.rad(math.random(0, 360))
    local dist = math.random(75, 180)
    local candidatePos = center + Vector(math.cos(angle) * dist, math.sin(angle) * dist, 50)

    local tr = util.TraceLine({
        start = candidatePos,
        endpos = candidatePos - Vector(0, 0, 200),
        mask = MASK_SOLID_BRUSHONLY
    })

    if not tr.Hit or tr.HitNormal.z < 0.65 then return false end

    for _, existing in ipairs(camp.courtyardDefenses) do
        if IsValid(existing) and existing:GetPos():DistToSqr(tr.HitPos) < (85 * 85) then
            return false
        end
    end
    for _, hut in ipairs(camp.huts or {}) do
        if IsValid(hut) and hut:GetPos():DistToSqr(tr.HitPos) < (100 * 100) then
            return false
        end
    end

    local prop = ents.Create("prop_physics")
    if not IsValid(prop) then return false end

    local models = {
        "models/props_fortifications/barricade01a.mdl",
        "models/props_c17/woodbarrel001.mdl",
        "models/props_junk/wood_crate001a.mdl",
        "models/props_wasteland/wood_fence01a.mdl"
    }
    local mdl = models[math.random(1, #models)]
    if not util.IsValidModel(mdl) then
        mdl = "models/props_c17/woodbarrel001.mdl"
    end

    prop:SetModel(mdl)
    prop:SetPos(tr.HitPos)
    prop:SetAngles(Angle(0, math.random(0, 360), 0))
    prop:Spawn()
    prop:Activate()

    local minZ = prop:OBBMins().z
    local zOffset = (minZ < 0) and math.abs(minZ) or 0
    prop:SetPos(tr.HitPos + Vector(0, 0, zOffset + 2))

    prop.VNPC_IsPreyCampWall = true
    prop.VNPC_IsCourtyardDefense = true
    prop.VNPC_PreyCampID = camp.id
    prop.VNPC_CampRef = camp
    prop:SetHealth(240)

    table.insert(camp.courtyardDefenses, prop)

    local phys = prop:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(Vector(0,0,0))
        phys:EnableMotion(false)
        phys:Sleep()
    end

    if prop.EmitSound then
        prop:EmitSound("physics/wood/wood_box_impact_hard1.wav", 75, math.random(95, 105))
    end

    return true
end

function VNPC_PreyCampLove_AI(camp, now)
    if not love_enabled:GetBool() or not camp or not camp.fortified then return end
    local maxMembers = camp_max_members:GetInt()
    if #camp.members >= maxMembers then return end

    local females = {}
    local males = {}
    for _, mem in ipairs(camp.members) do
        if IsValid(mem) and mem:Health() > 0 and (not VNPC_IsAdultPreyCitizen or VNPC_IsAdultPreyCitizen(mem)) then
            if VNPC_IsFemalePreyCitizen(mem) then
                table.insert(females, mem)
            elseif VNPC_IsMalePreyCitizen(mem) then
                table.insert(males, mem)
            end
        end
    end

    if #females == 0 or #males == 0 then return end

    -- 1. Check existing pregnancies for womb growth (value 10 to 50) and childbirth
    for _, f in ipairs(females) do
        if f.VNPC_IsPregnant then
            local dt = math.max(0.1, now - (f.VNPC_LastGrowthTime or now))
            f.VNPC_LastGrowthTime = now
            local gRate = GetConVar("vnpcs_prey_camp_baby_growth_rate") and GetConVar("vnpcs_prey_camp_baby_growth_rate"):GetFloat() or 1.0
            f.VNPC_BabyGrowthValue = (f.VNPC_BabyGrowthValue or 10.0) + (gRate * dt)

            if VNPC_ApplyPregnancyBellyBulge then
                VNPC_ApplyPregnancyBellyBulge(f, f.VNPC_BabyGrowthValue)
            end

            if f.VNPC_BabyGrowthValue >= 50.0 then
                if VNPC_StartChildbirthAnimation then
                    VNPC_StartChildbirthAnimation(f, f.VNPC_UnbornChild, camp)
                end
            end
        end
    end

    -- 2. Check if a couple falls in love or an existing monogamous couple mates inside the fort
    if (camp.lastLoveTriggerTime or 0) <= now and #camp.members < maxMembers then
        for _, f in ipairs(females) do
            if not f.VNPC_IsPregnant then
                local chosenMale = nil
                if IsValid(f.VNPC_LovedPartner) and f.VNPC_LovedPartner:Health() > 0 then
                    chosenMale = f.VNPC_LovedPartner
                else
                    for _, m in ipairs(males) do
                        if not IsValid(m.VNPC_LovedPartner) or m.VNPC_LovedPartner:Health() <= 0 then
                            chosenMale = m
                            f.VNPC_LovedPartner = m
                            m.VNPC_LovedPartner = f
                            break
                        end
                    end
                end

                if IsValid(chosenMale) then
                    camp.lastLoveTriggerTime = now + 25.0
                    if VNPC_InitiatePrivateMating then
                        VNPC_InitiatePrivateMating(f, chosenMale, camp)
                    else
                        f.VNPC_IsPregnant = true
                        f.VNPC_BabyGrowthValue = 10.0
                        f.VNPC_LastGrowthTime = now
                    end

                    -- Immediately spawn small citizen baby inside the female belly
                    local child = ents.Create("npc_citizen")
                    if IsValid(child) then
                        child:SetPos(f:GetPos() + Vector(0, 0, 32))
                        child:SetAngles(Angle(0, f:GetAngles().y, 0))
                        child:Spawn()
                        child:Activate()
                        child:SetModelScale(0.15, 0)
                        child:SetNoDraw(true)
                        child:SetSolid(0)
                        child:SetMoveType(MOVETYPE_NONE)
                        child:SetParent(f)
                        child.VNPC_IsUnbornBaby = true
                        child.VNPC_MotherRef = f
                        f.VNPC_UnbornChild = child
                    end

                    if f.EmitSound then
                        f:EmitSound("npc/citizen/vo/nice.wav", 75, math.random(105, 115))
                    end
                    break
                end
            end
        end
    end
end

function VNPC_PreyCampReclamation_AI(now)
    for _, abandoned in ipairs(VNPC_ActivePreyCamps) do
        if #abandoned.members == 0 and (now - (abandoned.abandonedTime or now)) > 4.0 then
            -- Find a surviving donor Prey Camp with at least 3 living citizens
            for _, donor in ipairs(VNPC_ActivePreyCamps) do
                if donor ~= abandoned and #donor.members >= 3 then
                    -- Dispatch an able-bodied citizen to retake the abandoned fort
                    for m = #donor.members, 1, -1 do
                        local citizen = donor.members[m]
                        if IsValid(citizen) and citizen:Health() > 0 and not citizen.Vored and not citizen.VNPC_Vored and not citizen.VNPC_IsPregnant then
                            table.remove(donor.members, m)
                            table.insert(abandoned.members, citizen)
                            citizen.VNPC_PreyCampID = abandoned.id
                            citizen.VNPC_PreyRole = "citizen"
                            abandoned.abandonedTime = nil
                            if citizen.SetLastPosition then pcall(citizen.SetLastPosition, citizen, abandoned.pos) end
                            if citizen.SetSchedule then pcall(citizen.SetSchedule, citizen, SCHED_FORCED_GO_RUN) end
                            print("[V-NPCs] Citizen " .. tostring(citizen) .. " from Prey Camp #" .. donor.id .. " was dispatched to RETAKE abandoned Prey Camp #" .. abandoned.id .. "!")
                            hook.Run("VNPC_OnPreyCampRetaken", citizen, abandoned)
                            break
                        end
                    end
                    if #abandoned.members > 0 then break end
                end
            end
        end
    end
end

function VNPC_PreyCampInfiltration_AI(now)
    for _, camp in ipairs(VNPC_ActivePreyCamps or {}) do
        if not camp.fortified and #(camp.walls or {}) == 0 then continue end
        if IsValid(camp.infiltrator) and camp.infiltrator:Health() > 0 then
            local pred = camp.infiltrator
            local victim = pred.VNPC_InfiltrationTarget
            if IsValid(victim) and (victim.Vored or victim.VNPC_Vored or victim:Health() <= 0) then
                -- INFILTRATION SWALLOW COMPLETE: Regurgitate/rebuild swallowed walls and repair wall damage to leave zero suspicion!
                if pred.VNPC_InfiltrationSwallowedWalls then
                    local belly = pred.VNPC_Belly or pred.Belly
                    for _, data in ipairs(pred.VNPC_InfiltrationSwallowedWalls) do
                        local newWall = ents.Create("prop_physics")
                        if IsValid(newWall) then
                            newWall:SetModel(data.mdl or "models/props_wasteland/wood_fence01a.mdl")
                            newWall:SetPos(data.pos)
                            newWall:SetAngles(data.ang)
                            newWall:Spawn()
                            newWall:Activate()
                            newWall:SetHealth(data.health or 350)
                            if data.isGate then
                                newWall.VNPC_IsPreyCampGate = true
                                newWall.VNPC_GateClosedAng = data.closedAng or data.ang
                                newWall.VNPC_GateOpenAng = data.openAng or data.ang
                            end
                            if data.isWall then
                                newWall.VNPC_IsPreyCampWall = true
                                newWall.VNPC_PreyCampID = camp.id
                                newWall.VNPC_CampRef = camp
                                table.insert(camp.walls, newWall)
                            elseif data.isHutPiece then
                                newWall.VNPC_IsPreyCampHutPiece = true
                                newWall.VNPC_PreyCampID = camp.id
                            end
                            local phys = newWall:GetPhysicsObject()
                            if IsValid(phys) then
                                phys:SetVelocity(Vector(0,0,0))
                                phys:EnableMotion(false)
                                phys:Sleep()
                            end
                        end
                        if IsValid(belly) and belly.Prey then
                            for pIdx = #belly.Prey, 1, -1 do
                                local pInfo = belly.Prey[pIdx]
                                if pInfo and IsValid(pInfo.Entity) and pInfo.Entity:GetModel() == data.mdl then
                                    pInfo.Entity:Remove()
                                    table.remove(belly.Prey, pIdx)
                                    break
                                end
                            end
                        end
                    end
                    pred.VNPC_InfiltrationSwallowedWalls = nil
                end

                if pred.VNPC_InfiltrationBreachedWalls then
                    for _, wall in ipairs(pred.VNPC_InfiltrationBreachedWalls) do
                        if IsValid(wall) then
                            wall:SetNoDraw(false)
                            wall:SetSolid(SOLID_VPHYSICS)
                            wall:SetHealth(350)
                        end
                    end
                    pred.VNPC_InfiltrationBreachedWalls = nil
                end
                camp.breachAlertTime = nil
                camp.suspicionLevel = 0
                camp.infiltrator = nil

                pred:RemoveFlags(FL_NOTARGET)
                pred.VNPC_IsInfiltratingFort = nil
                pred.VNPC_InfiltrationTarget = nil
                if pred.SetLastPosition then
                    local escapePos = pred:GetPos() + (pred:GetPos() - camp.pos):GetNormalized() * 900
                    pcall(pred.SetLastPosition, pred, escapePos)
                end
                if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_FORCED_GO_RUN) end
                if VNPC_AddPredatorXP then
                    VNPC_AddPredatorXP(pred, 250, "Stealth Fort Infiltration Complete")
                end
                print("[V-NPCs] Fort Infiltration Complete: Predator " .. tostring(pred) .. " swallowed sleeping prey " .. tostring(victim) .. " and REPAIRED all wall damage! Zero suspicion raised.")
                hook.Run("VNPC_OnFortInfiltrationComplete", pred, victim, camp)
            elseif IsValid(victim) then
                local dSqr = pred:GetPos():DistToSqr(victim:GetPos())
                if dSqr <= (150 * 150) and not pred.Swallowing then
                    if pred.EatEntity then
                        pred:EatEntity(victim)
                    elseif pred.VNPC_Belly and pred.VNPC_Belly.AddPrey then
                        pred.VNPC_Belly:AddPrey(victim)
                    end
                else
                    if (pred.VNPC_NextInfiltrateMoveTime or 0) <= now then
                        pred.VNPC_NextInfiltrateMoveTime = now + 1.5
                        if pred.SetLastPosition then pcall(pred.SetLastPosition, pred, victim:GetPos()) end
                        if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_FORCED_GO) end
                    end
                end
            else
                camp.infiltrator = nil
                pred:RemoveFlags(FL_NOTARGET)
                pred.VNPC_IsInfiltratingFort = nil
                pred.VNPC_InfiltrationTarget = nil
            end
            continue
        end

        -- Check if fort is unguarded (all members sleeping or out collecting scrap)
        local awakeSentries = 0
        local sleepingPrey = {}
        for _, mem in ipairs(camp.members or {}) do
            if IsValid(mem) and mem:Health() > 0 and not mem.Vored and not mem.VNPC_Vored then
                if mem.VNPC_IsSleeping then
                    table.insert(sleepingPrey, mem)
                elseif mem.VNPC_IsCollectingScrap then
                    -- Out collecting scrap away from fort
                else
                    awakeSentries = awakeSentries + 1
                end
            end
        end

        -- If zero awake sentries and sleeping prey present, fort is vulnerable to stealth infiltration!
        if awakeSentries == 0 and #sleepingPrey > 0 and (camp.nextInfiltrationCheckTime or 0) <= now then
            camp.nextInfiltrationCheckTime = now + 12.0
            local victim = sleepingPrey[math.random(1, #sleepingPrey)]
            local bestPred = nil
            local bestDistSqr = 2400 * 2400

            for _, pred in ipairs(ents.FindByClass("npc_*")) do
                if IsValid(pred) and pred:Health() > 0 and not pred.Vored and (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) then
                    if pred.VNPC_IsPermanentFortPredator or pred.VNPC_IsSleeping or pred.Swallowing or IsValid(pred:GetEnemy()) then continue end
                    local dSqr = pred:GetPos():DistToSqr(camp.pos)
                    if dSqr <= bestDistSqr then
                        bestPred = pred
                        bestDistSqr = dSqr
                    end
                end
            end

            if IsValid(bestPred) then
                bestPred.VNPC_IsInfiltratingFort = camp
                bestPred.VNPC_InfiltrationTarget = victim
                bestPred.VNPC_InfiltrationBreachedWalls = {}
                bestPred:AddFlags(FL_NOTARGET)
                camp.infiltrator = bestPred
                camp.suspicionLevel = 0
                if bestPred.SetLastPosition then pcall(bestPred.SetLastPosition, bestPred, victim:GetPos()) end
                if bestPred.SetSchedule then pcall(bestPred.SetSchedule, bestPred, SCHED_FORCED_GO) end
                print("[V-NPCs] Fort Vulnerable: Zero awake sentries at Prey Camp #" .. camp.id .. "! Predator " .. tostring(bestPred) .. " is sneaking in to swallow sleeping prey " .. tostring(victim) .. " alive!")
                hook.Run("VNPC_OnFortInfiltrationStart", bestPred, victim, camp)
            end
        end
    end
end

-- Main Prey Camps & Fortification AI Loop
hook.Add("Think", "VNPC_PreyCamps_AI_Loop", function()
    if not camps_enabled:GetBool() then return end

    local now = CurTime()

    -- 1. Enroll eligible prey NPCs into prey camps
    for _, ent in ipairs(ents.GetAll()) do
        if VNPC_IsEligiblePreyNPC(ent) and (not ent.VNPC_PreyCampID or ent.VNPC_PreyCampID == "wild") then
            ent.VNPC_PreyCampID = nil
            VNPC_AssignPreyToCamp(ent)
        end
    end

    if VNPC_PreyCampReclamation_AI then
        VNPC_PreyCampReclamation_AI(now)
    end
    if VNPC_PreyCampInfiltration_AI then
        VNPC_PreyCampInfiltration_AI(now)
    end

    -- 2. Update active prey camps and construct fortifications
    for i = #VNPC_ActivePreyCamps, 1, -1 do
        local camp = VNPC_ActivePreyCamps[i]
        if (camp.lastUpdateTime or 0) > (now - 1.0) then continue end
        local dt = now - (camp.lastUpdateTime or now)
        camp.lastUpdateTime = now

        -- Prune dead/invalid members
        for m = #camp.members, 1, -1 do
            local mem = camp.members[m]
            if not IsValid(mem) or mem:Health() <= 0 or mem.Vored or mem.VNPC_Vored then
                table.remove(camp.members, m)
            end
        end

        -- Prune destroyed walls
        for w = #camp.walls, 1, -1 do
            local wall = camp.walls[w]
            if not IsValid(wall) then
                table.remove(camp.walls, w)
            end
        end

        -- Prune destroyed huts
        camp.huts = camp.huts or {}
        for h = #camp.huts, 1, -1 do
            local hut = camp.huts[h]
            if not IsValid(hut) then
                table.remove(camp.huts, h)
            end
        end

        -- Prune destroyed courtyard defenses
        camp.courtyardDefenses = camp.courtyardDefenses or {}
        for d = #camp.courtyardDefenses, 1, -1 do
            local def = camp.courtyardDefenses[d]
            if not IsValid(def) then
                table.remove(camp.courtyardDefenses, d)
            end
        end

        camp.cookedMeals = camp.cookedMeals or {}
        for c = #camp.cookedMeals, 1, -1 do
            local meal = camp.cookedMeals[c]
            if not IsValid(meal) then
                table.remove(camp.cookedMeals, c)
            end
        end

        if not IsValid(camp.campfire) and (now - (camp.createTime or now)) > 3.0 then
            VNPC_ConstructPreyCampFire(camp)
        end

        VNPC_EnsurePreyCampLeader(camp)
        if not IsValid(camp.leaderTable) and (now - (camp.createTime or now)) > 4.0 then
            VNPC_ConstructPreyCampLeaderHut(camp)
        end
        if VNPC_PreyCampLeaderDecision_AI then
            VNPC_PreyCampLeaderDecision_AI(camp, now)
        end

        if VNPC_PreyCampCooking_AI then
            VNPC_PreyCampCooking_AI(camp, now)
        end
        if VNPC_PreyMealConsumption_AI then
            VNPC_PreyMealConsumption_AI(camp, now)
        end

        if VNPC_CheckPreyCampConquest then
            VNPC_CheckPreyCampConquest(camp)
        end

        if #camp.members == 0 then
            -- If camp has no surviving structures, remove it; otherwise keep it in VNPC_ActivePreyCamps so prey can retake it
            if #camp.walls == 0 and #(camp.huts or {}) == 0 and #(camp.courtyardDefenses or {}) == 0 and not camp.fortified then
                table.remove(VNPC_ActivePreyCamps, i)
            else
                camp.abandonedTime = camp.abandonedTime or now
            end
            continue
        else
            camp.abandonedTime = nil
        end

        -- Accumulate resources based on camp member count and base rate
        local baseRate = camp_resource_rate:GetFloat()
        camp.resources = (camp.resources or 0) + ((baseRate + #camp.members * 0.35) * dt)

        -- Intelligent Resource Harvesting: scan for nearby scrap/junk props around the camp to harvest
        for _, scrap in ipairs(ents.FindInSphere(camp.pos, 1000)) do
            if IsValid(scrap) and scrap:GetClass() == "prop_physics" and not scrap.VNPC_IsPreyCampWall and not scrap.VNPC_IsPreyCampHutPiece and not scrap.VNPC_IsCourtyardDefense and not scrap.VNPC_NoVore and not scrap.VNPC_IsCookedPropMeal then
                if scrap:GetPos():DistToSqr(camp.pos) < (300 * 300) then
                    camp.resources = (camp.resources or 0) + 10.0
                    scrap:Remove()
                    break
                end
            end
        end

        -- Courtyard Cover Defense Tactics: when fort is breached or under attack, defenders take cover behind courtyard defenses
        if (camp.breachAlertTime or 0) > (now - 15.0) and #(camp.courtyardDefenses or {}) > 0 then
            for _, mem in ipairs(camp.members) do
                if IsValid(mem) and mem:Health() > 0 and not mem.Vored and not mem.VNPC_IsSleeping then
                    if mem.SetLastPosition then pcall(mem.SetLastPosition, mem, camp.courtyardDefenses[1]:GetPos()) end
                    if mem.SetSchedule then pcall(mem.SetSchedule, mem, SCHED_TAKE_COVER_FROM_ENEMY) end
                end
            end
        end

        -- StormFox 2 Weather Compatibility: During rainstorms or freezing weather, citizens not on patrol seek shelter inside fort huts/house
        if (VNPC_IsStormFox2Raining and VNPC_IsStormFox2Raining()) or (VNPC_GetStormFox2Temperature and VNPC_GetStormFox2Temperature() < 8.0) then
            for _, mem in ipairs(camp.members) do
                if IsValid(mem) and mem:Health() > 0 and not mem.Vored and not mem.VNPC_IsSleeping and not mem.VNPC_IsCollectingScrap and not IsValid(mem:GetEnemy()) then
                    if camp.huts and #camp.huts > 0 then
                        local hut = camp.huts[math.random(1, #camp.huts)]
                        if hut and hut.pos and mem:GetPos():DistToSqr(hut.pos) > (150 * 150) then
                            if mem.SetLastPosition then pcall(mem.SetLastPosition, mem, hut.pos) end
                            if mem.SetSchedule then pcall(mem.SetSchedule, mem, SCHED_FORCED_GO_RUN) end
                        end
                    end
                end
            end
        end

        -- Build wall fortifications when resources permit
        local cost = camp_wall_cost:GetFloat()
        local maxWalls = camp_max_walls:GetInt()
        if camp.resources >= cost and #camp.walls < maxWalls then
            if VNPC_ConstructPreyCampWall(camp) then
                camp.resources = math.max(0, camp.resources - cost)
            end
        end

        -- Check if perimeter wall ring is finished (fortified!)
        camp.fortified = (#camp.walls >= maxWalls or #camp.walls >= 10)

        -- When fortified, build Little Huts in the inner courtyard for shelter
        local hutCost = camp_hut_cost:GetFloat()
        local maxHuts = camp_max_huts:GetInt()
        if camp.fortified and camp.resources >= hutCost and #camp.huts < maxHuts then
            if VNPC_ConstructPreyCampHut(camp) then
                camp.resources = math.max(0, camp.resources - hutCost)
            end
        end

        -- When fortified, dynamically build courtyard cover barricades & defensive checkpoints
        if camp.fortified and camp.resources >= 12.0 then
            if VNPC_ConstructPreyCampCourtyardDefense(camp) then
                camp.resources = math.max(0, camp.resources - 12.0)
            end
        end

        -- Instruct idle prey members to take shelter inside/near built little huts
        if #camp.huts > 0 then
            for idx, mem in ipairs(camp.members) do
                if IsValid(mem) and not IsValid(mem:GetEnemy()) then
                    local targetHut = camp.huts[((idx - 1) % #camp.huts) + 1]
                    if IsValid(targetHut) and mem:GetPos():DistToSqr(targetHut:GetPos()) > (160 * 160) then
                        if mem.SetLastPosition then pcall(mem.SetLastPosition, mem, targetHut:GetPos()) end
                        if mem.SetSchedule then pcall(mem.SetSchedule, mem, SCHED_FORCED_GO) end
                    end
                end
            end
        end

        -- 3. Check for predators breaching the camp perimeter by swallowing wall props
        for _, wall in ipairs(camp.walls) do
            if not IsValid(wall) then continue end
            local wallPos = wall:GetPos()
            for _, pred in ipairs(ents.FindInSphere(wallPos, 155)) do
                if not IsValid(pred) or pred:Health() <= 0 then continue end
                if pred.VNPC_PreyCampID and pred.VNPC_PreyCampID == camp.id then continue end
                if VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(pred) then continue end
                if pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator then
                    local belly = pred.VNPC_Belly or pred.Belly
                    local hasSpace = not IsValid(belly) or not belly.Prey or #belly.Prey < 5
                    if hasSpace and (pred.VNPC_NextWallBreachTime or 0) <= now then
                        pred.VNPC_NextWallBreachTime = now + 5.0
                        camp.breachAlertTime = now
                        VNPC_PredatorBreachPreyCampWall(pred, wall, camp)
                        break
                    end
                end
            end
        end

        -- 4. Check for predators swallowing Little Huts in the fort courtyard
        for _, hut in ipairs(camp.huts) do
            if not IsValid(hut) then continue end
            local hutPos = hut:GetPos()
            for _, pred in ipairs(ents.FindInSphere(hutPos, 160)) do
                if not IsValid(pred) or pred:Health() <= 0 then continue end
                if pred.VNPC_PreyCampID and pred.VNPC_PreyCampID == camp.id then continue end
                if VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(pred) then continue end
                if pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator then
                    local belly = pred.VNPC_Belly or pred.Belly
                    local hasSpace = not IsValid(belly) or not belly.Prey or #belly.Prey < 5
                    if hasSpace and (pred.VNPC_NextHutBreachTime or 0) <= now then
                        pred.VNPC_NextHutBreachTime = now + 5.0
                        camp.breachAlertTime = now
                        VNPC_PredatorBreachPreyCampHut(pred, hut, camp)
                        break
                    end
                end
            end
        end

        -- Dynamic Territory Expansion: Citizens actively expand their territory border outward as resources and population grow
        camp.territoryRadius = camp.territoryRadius or 450.0
        if camp.fortified and camp.resources >= 25.0 and #camp.members >= 5 and (camp.lastTerritoryExpandTime or 0) <= now then
            if camp.territoryRadius < 3000.0 then
                camp.lastTerritoryExpandTime = now + 40.0
                camp.resources = math.max(0, camp.resources - 25.0)
                camp.territoryRadius = math.min(3000.0, camp.territoryRadius + 200.0)
                camp.plannedWalls = nil
                camp.fortified = false
            end
        end

        -- Instruct able-bodied citizens to patrol out and secure the expanded territory borders
        if (camp.territoryRadius or 450.0) > 500.0 and (camp.lastPatrolOrderTime or 0) <= now then
            camp.lastPatrolOrderTime = now + 15.0
            for idx, mem in ipairs(camp.members) do
                if IsValid(mem) and mem:Health() > 0 and not mem.VNPC_IsPregnant and not IsValid(mem:GetEnemy()) then
                    if mem.VNPC_PreyRole ~= "emissary" and not mem.VNPC_IsPermanentFortPredator then
                        local ang = math.rad(math.random(0, 360))
                        local r = math.random(300, camp.territoryRadius * 0.9)
                        local pPos = camp.pos + Vector(math.cos(ang) * r, math.sin(ang) * r, 0)
                        if mem.SetLastPosition then pcall(mem.SetLastPosition, mem, pPos) end
                        if mem.SetSchedule then pcall(mem.SetSchedule, mem, SCHED_FORCED_GO) end
                    end
                end
            end
        end

        -- Dynamic threat-driven adaptive replan: when 30% or more of walls are breached, trigger a full perimeter replan
        if camp.fortified and #camp.walls < (maxWalls * 0.7) then
            camp.plannedWalls = nil
            camp.fortified = false
        end

        -- Dynamic AI Cover & Defense Behaviors: when enemies approach within 800 units, citizens & fort predators move to cover
        local nearEnemy = nil
        for _, ent in ipairs(ents.FindInSphere(camp.pos, 800)) do
            if IsValid(ent) and ent:Health() > 0 and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) then
                if not ent.VNPC_IsPermanentFortPredator then
                    nearEnemy = ent
                    break
                end
            end
        end

        if IsValid(nearEnemy) and #(camp.courtyardDefenses or {}) > 0 then
            for idx, mem in ipairs(camp.members) do
                if IsValid(mem) and mem:Health() > 0 then
                    local targetCover = camp.courtyardDefenses[((idx - 1) % #camp.courtyardDefenses) + 1]
                    if IsValid(targetCover) and mem:GetPos():DistToSqr(targetCover:GetPos()) > (130 * 130) then
                        if mem.SetLastPosition then pcall(mem.SetLastPosition, mem, targetCover:GetPos()) end
                        if mem.SetSchedule then pcall(mem.SetSchedule, mem, SCHED_FORCED_GO) end
                    end
                end
            end
        end

        -- 5. Population growth via Love & Pregnancy System in fortified camps with huts
        if camp.fortified and #camp.huts > 0 then
            VNPC_PreyCampLove_AI(camp, now)
        end

        -- 6. Intelligence Agency recon missions to scout predator camps & wild hotspots
        if VNPC_PreyCampIntelligence_AI then
            VNPC_PreyCampIntelligence_AI(camp, now)
        end
    end
end)

concommand.Add("vnpcs_prey_camps_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Prey Camps & Fortification AI Status")
    print("Enabled: " .. tostring(camps_enabled:GetBool()))
    print("Target Members/Camp: " .. tostring(camp_target_size:GetInt()))
    print("Resource Accumulation Rate: " .. tostring(camp_resource_rate:GetFloat()) .. " / sec")
    print("Wall Cost: " .. tostring(camp_wall_cost:GetFloat()))
    print("Max Walls/Camp: " .. tostring(camp_max_walls:GetInt()))
    print("Hut Cost: " .. tostring(camp_hut_cost:GetFloat()))
    print("Max Huts/Camp: " .. tostring(camp_max_huts:GetInt()))
    print("Love/Pregnancy Enabled: " .. tostring(love_enabled:GetBool()))
    print("-----------------------------------------")
    for idx, camp in ipairs(VNPC_ActivePreyCamps) do
        local pregCount = 0
        for _, m in ipairs(camp.members) do
            if IsValid(m) and m.VNPC_IsPregnant then
                pregCount = pregCount + 1
            end
        end
        local awakeSentries = 0
        for _, m in ipairs(camp.members) do
            if IsValid(m) and m:Health() > 0 and not m.Vored and not m.VNPC_Vored and not m.VNPC_IsSleeping and not m.VNPC_IsCollectingScrap then
                awakeSentries = awakeSentries + 1
            end
        end
        local stateStr = (#camp.members == 0) and " [ABANDONED - AVAILABLE FOR RETAKING]" or ""
        local guardStr = (awakeSentries == 0 and #camp.members > 0) and " [UNGUARDED - VULNERABLE TO INFILTRATION]" or string.format(" | Sentries: %d awake", awakeSentries)
        local infStr = IsValid(camp.infiltrator) and string.format(" | INFILTRATION IN PROGRESS: Pred [%d]", camp.infiltrator:EntIndex()) or ""
        local indoorStr = camp.isIndoors and " | Indoors: YES (House Fort)" or " | Indoors: NO"
        local leaderStr = IsValid(camp.leader) and string.format(" | Leader: #%d [%s]", camp.leader:EntIndex(), camp.leader.PrintName or camp.leader:GetClass()) or " | Leader: NONE"
        local hutStr = IsValid(camp.leaderTable) and " | Leader Hut & Table: BUILT" or " | Leader Hut & Table: NONE"
        local decStr = camp.leaderDecision and string.format(" | Strategy Decision: %s", camp.leaderDecision) or ""
        print(string.format(" -> Prey Camp [#%d] | Members: %d%s (Pregnant: %d)%s%s%s%s%s%s | Territory Radius: %d | Walls: %d | Huts: %d | Courtyard Defenses: %d | Resources: %.1f | Fortified: %s",
            camp.id, #camp.members, stateStr, pregCount, indoorStr, guardStr, infStr, leaderStr, hutStr, decStr, math.floor(camp.territoryRadius or 450), #camp.walls, #(camp.huts or {}), #(camp.courtyardDefenses or {}), camp.resources or 0, tostring(camp.fortified or false)))
    end
    print("Total active prey camps: " .. #VNPC_ActivePreyCamps)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Prey camp status printed to console. Active prey camps: " .. #VNPC_ActivePreyCamps)
    end
end)

concommand.Add("vnpcs_test_camp_leader", function(ply)
    print("=========================================")
    print("[V-NPCs] Testing Camp Leaders & Elections")
    for _, camp in ipairs(VNPC_ActivePreyCamps or {}) do
        local leader = VNPC_EnsurePreyCampLeader(camp)
        print(string.format(" - Prey Camp #%d -> Leader: %s | Decision: %s", camp.id, IsValid(leader) and string.format("#%d [%s]", leader:EntIndex(), leader.PrintName or leader:GetClass()) or "NONE", tostring(camp.leaderDecision or "N/A")))
    end
    for _, camp in ipairs(VNPC_ActivePredatorCamps or {}) do
        local leader = VNPC_EnsurePredatorCampLeader and VNPC_EnsurePredatorCampLeader(camp)
        print(string.format(" - Predator Camp #%d -> Leader: %s | Decision: %s", camp.id, IsValid(leader) and string.format("#%d [%s]", leader:EntIndex(), leader.PrintName or leader:GetClass()) or "NONE", tostring(camp.leaderDecision or "N/A")))
    end
    print("=========================================")
end)

concommand.Add("vnpcs_test_leader_hut", function(ply)
    local builtPrey = 0
    for _, camp in ipairs(VNPC_ActivePreyCamps or {}) do
        if not IsValid(camp.leaderTable) then
            if VNPC_ConstructPreyCampLeaderHut(camp) then
                builtPrey = builtPrey + 1
            end
        end
    end
    local builtPred = 0
    for _, camp in ipairs(VNPC_ActivePredatorCamps or {}) do
        if not IsValid(camp.leaderTable) then
            if VNPC_ConstructPredatorCampLeaderHut and VNPC_ConstructPredatorCampLeaderHut(camp) then
                builtPred = builtPred + 1
            end
        end
    end
    print(string.format("[V-NPCs] Test: Built Leader Huts & Tables for %d Prey Camp(s) and %d Predator Camp(s)!", builtPrey, builtPred))
end)

concommand.Add("vnpcs_test_leader_decision", function(ply, cmd, args)
    local targetDec = string.upper(args[1] or "COOK_MEAL_FEAST")
    for _, camp in ipairs(VNPC_ActivePreyCamps or {}) do
        camp.leaderDecision = targetDec
        local leader = camp.leader
        if IsValid(leader) and IsValid(camp.leaderTable) then
            if leader.SetLastPosition then pcall(leader.SetLastPosition, leader, camp.leaderTable:GetPos()) end
            if leader.SetSchedule then pcall(leader.SetSchedule, leader, SCHED_FORCED_GO_RUN) end
        end
    end
    for _, camp in ipairs(VNPC_ActivePredatorCamps or {}) do
        camp.leaderDecision = targetDec
        local leader = camp.leader
        if IsValid(leader) and IsValid(camp.leaderTable) then
            if leader.SetLastPosition then pcall(leader.SetLastPosition, leader, camp.leaderTable:GetPos()) end
            if leader.SetSchedule then pcall(leader.SetSchedule, leader, SCHED_FORCED_GO_RUN) end
        end
    end
    print(string.format("[V-NPCs] Test: Forced all Camp Leaders to order decision [%s] and assemble at their Leader Hut Table!", targetDec))
end)

concommand.Add("vnpcs_test_prey_love", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not VNPC_IsEligiblePreyNPC(target) then
        ply:ChatPrint("[V-NPCs] Please aim at a valid citizen in a Prey Camp to trigger love and pregnancy!")
        return
    end
    local camp = VNPC_GetPreyCamp(target)
    if not camp then
        camp = VNPC_AssignPreyToCamp(target, true)
    end
    target.VNPC_IsPregnant = true
    target.VNPC_BabyGrowthValue = 46.0
    target.VNPC_LastGrowthTime = CurTime()

    local child = ents.Create("npc_citizen")
    if IsValid(child) then
        child:SetPos(target:GetPos() + Vector(0, 0, 32))
        child:SetAngles(Angle(0, target:GetAngles().y, 0))
        child:Spawn()
        child:Activate()
        child:SetModelScale(0.30, 0)
        child:SetNoDraw(true)
        child:SetSolid(0)
        child:SetMoveType(MOVETYPE_NONE)
        child:SetParent(target)
        child.VNPC_IsUnbornBaby = true
        child.VNPC_MotherRef = target
        target.VNPC_UnbornChild = child
    end

    ply:ChatPrint("[V-NPCs] Triggered love & pregnancy on " .. tostring(target) .. " in Prey Camp #" .. camp.id .. "! Baby citizen inside womb at value 46 (birth at 50 in 4s)!")
end)

concommand.Add("vnpcs_test_create_prey_camp", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not VNPC_IsEligiblePreyNPC(target) then
        ply:ChatPrint("[V-NPCs] Please aim at a valid prey NPC to establish a Prey Camp!")
        return
    end
    target.VNPC_SpawnedByPlayer = true
    local camp = VNPC_CreatePreyCamp(tr.HitPos, target)
    ply:ChatPrint("[V-NPCs] Established Prey Camp #" .. tostring(camp and camp.id or "N/A") .. " for " .. tostring(target) .. "!")
end)

concommand.Add("vnpcs_test_prey_indoor_fort", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not VNPC_IsEligiblePreyNPC(target) then
        ply:ChatPrint("[V-NPCs] Please aim at an eligible citizen prey NPC inside a building to create an Indoor House Fort!")
        return
    end
    target.VNPC_SpawnedByPlayer = true
    local camp = VNPC_CreatePreyCamp(tr.HitPos, target)
    if camp then
        camp.isIndoors = true
        VNPC_PlanPreyCampLayout(camp)
        ply:ChatPrint("[V-NPCs] Established Indoor Prey Fort #" .. camp.id .. " inside house/building for " .. tostring(target) .. "! Barricading interior walls & doors.")
    end
end)

concommand.Add("vnpcs_test_prey_retake_camp", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not VNPC_IsEligiblePreyNPC(target) then
        ply:ChatPrint("[V-NPCs] Please aim at a valid citizen prey NPC to retake an abandoned Prey Camp!")
        return
    end

    -- Find an abandoned camp, or if none is abandoned, find another camp and empty its members so target can retake it
    local abandonedCamp = nil
    for _, camp in ipairs(VNPC_ActivePreyCamps) do
        if #camp.members == 0 and (#camp.walls > 0 or #(camp.huts or {}) > 0 or #(camp.courtyardDefenses or {}) > 0 or camp.fortified) then
            abandonedCamp = camp
            break
        end
    end

    if not abandonedCamp then
        for _, camp in ipairs(VNPC_ActivePreyCamps) do
            if camp.id ~= target.VNPC_PreyCampID and (#camp.walls > 0 or #(camp.huts or {}) > 0 or #(camp.courtyardDefenses or {}) > 0 or camp.fortified) then
                for _, m in ipairs(camp.members) do
                    if IsValid(m) then m.VNPC_PreyCampID = nil end
                end
                table.Empty(camp.members)
                abandonedCamp = camp
                break
            end
        end
    end

    if not abandonedCamp then
        ply:ChatPrint("[V-NPCs] No abandoned Prey Camp with structures found to retake! Establish and fortify a camp first.")
        return
    end

    -- Remove target from their old camp
    if target.VNPC_PreyCampID then
        for _, c in ipairs(VNPC_ActivePreyCamps) do
            if c.id == target.VNPC_PreyCampID then
                for idx, m in ipairs(c.members) do
                    if m == target then
                        table.remove(c.members, idx)
                        break
                    end
                end
                break
            end
        end
    end

    table.insert(abandonedCamp.members, target)
    target.VNPC_PreyCampID = abandonedCamp.id
    target.VNPC_PreyRole = "citizen"
    abandonedCamp.abandonedTime = nil

    if target.SetLastPosition then pcall(target.SetLastPosition, target, abandonedCamp.pos) end
    if target.SetSchedule then pcall(target.SetSchedule, target, SCHED_FORCED_GO_RUN) end

    ply:ChatPrint("[V-NPCs] Citizen " .. tostring(target) .. " has successfully RETAKEN abandoned Prey Camp #" .. abandonedCamp.id .. " (" .. #abandonedCamp.walls .. " walls, " .. #(abandonedCamp.huts or {}) .. " huts)!")
end)

concommand.Add("vnpcs_test_build_wall", function(ply)
    if not IsValid(ply) then return end
    local bestCamp = nil
    for _, camp in ipairs(VNPC_ActivePreyCamps) do
        bestCamp = camp
        break
    end
    if not bestCamp then
        ply:ChatPrint("[V-NPCs] No active prey camp found to build a wall!")
        return
    end
    if VNPC_ConstructPreyCampWall(bestCamp) then
        ply:ChatPrint("[V-NPCs] Forced construction of a defensive wall for Prey Camp #" .. bestCamp.id .. "!")
    else
        ply:ChatPrint("[V-NPCs] Could not find valid terrain geometry to place a wall around Prey Camp #" .. bestCamp.id .. "!")
    end
end)

concommand.Add("vnpcs_test_build_hut", function(ply)
    if not IsValid(ply) then return end
    local bestCamp = nil
    for _, camp in ipairs(VNPC_ActivePreyCamps) do
        bestCamp = camp
        break
    end
    if not bestCamp then
        ply:ChatPrint("[V-NPCs] No active prey camp found to build a hut!")
        return
    end
    bestCamp.fortified = true
    if VNPC_ConstructPreyCampHut(bestCamp) then
        ply:ChatPrint("[V-NPCs] Forced construction of a Little Hut for Prey Camp #" .. bestCamp.id .. "!")
    else
        ply:ChatPrint("[V-NPCs] Could not find valid courtyard terrain geometry to place a hut in Prey Camp #" .. bestCamp.id .. "!")
    end
end)

concommand.Add("vnpcs_test_prey_expand_territory", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not VNPC_IsEligiblePreyNPC(target) then
        ply:ChatPrint("[V-NPCs] Please aim at a valid citizen in a Prey Camp to test territory expansion!")
        return
    end
    local camp = VNPC_GetPreyCamp(target)
    if not camp then
        camp = VNPC_AssignPreyToCamp(target, true)
    end
    if camp then
        camp.territoryRadius = math.min(3000.0, (camp.territoryRadius or 450.0) + 300.0)
        camp.plannedWalls = nil
        camp.fortified = false
        ply:ChatPrint("[V-NPCs] Prey Camp #" .. camp.id .. " expanded territory radius to " .. math.floor(camp.territoryRadius) .. " units and triggered dynamic perimeter expansion!")
    end
end)

concommand.Add("vnpcs_clear_prey_camps", function(ply)
    local count = #VNPC_ActivePreyCamps
    for _, camp in ipairs(VNPC_ActivePreyCamps) do
        for _, wall in ipairs(camp.walls) do
            if IsValid(wall) then wall:Remove() end
        end
        for _, hut in ipairs(camp.huts or {}) do
            if IsValid(hut) then hut:Remove() end
        end
        for _, def in ipairs(camp.courtyardDefenses or {}) do
            if IsValid(def) then def:Remove() end
        end
    end
    for _, ent in ipairs(ents.GetAll()) do
        ent.VNPC_PreyCampID = nil
    end
    table.Empty(VNPC_ActivePreyCamps)
    print("[V-NPCs] Cleared " .. count .. " prey camps, defensive walls, and huts from the map.")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Cleared " .. count .. " prey camps, defensive walls, and huts from the map.")
    end
end)

concommand.Add("vnpcs_test_fort_infiltration", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at a predator or prey NPC to test fort infiltration!")
        return
    end

    local camp = nil
    local pred = nil
    local victim = nil

    if target.VNPC_PreyCampID and VNPC_GetPreyCamp then
        camp = VNPC_GetPreyCamp(target)
        victim = target
    elseif target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator then
        pred = target
        for _, c in ipairs(VNPC_ActivePreyCamps or {}) do
            if #(c.members or {}) > 0 then
                camp = c
                victim = c.members[1]
                break
            end
        end
    end

    if not camp or not IsValid(victim) then
        ply:ChatPrint("[V-NPCs] Could not find an active Prey Camp with a victim! Establish a fort first.")
        return
    end

    if not IsValid(pred) then
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            if IsValid(ent) and ent ~= victim and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) and not ent.VNPC_IsPermanentFortPredator then
                pred = ent
                break
            end
        end
    end

    if not IsValid(pred) then
        pred = VNPC_SpawnWildNPC(true, camp.pos + Vector(450, 0, 0))
    end

    -- 1. Put victim to sleep
    victim.VNPC_IsSleeping = true
    victim.VNPC_Sleepiness = 95.0
    if victim.SetSchedule then pcall(victim.SetSchedule, victim, SCHED_NPC_FREEZE) end

    -- 2. Initiate Predator Stealth Infiltration
    pred.VNPC_IsInfiltratingFort = camp
    pred.VNPC_InfiltrationTarget = victim
    pred.VNPC_InfiltrationBreachedWalls = {}
    pred:AddFlags(FL_NOTARGET)
    camp.infiltrator = pred
    camp.suspicionLevel = 0

    -- 3. Quietly swallow a wall to demonstrate stealth entry and repair/regurgitate!
    if camp.walls and #camp.walls > 0 then
        local wall = camp.walls[1]
        if IsValid(wall) then
            VNPC_PredatorBreachPreyCampWall(pred, wall, camp)
        end
    end

    if pred.SetLastPosition then pcall(pred.SetLastPosition, pred, victim:GetPos()) end
    if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_FORCED_GO_RUN) end

    ply:ChatPrint("[V-NPCs] Initiated Fort Infiltration! Predator " .. tostring(pred) .. " sneaking into Prey Camp #" .. camp.id .. " to swallow sleeping prey " .. tostring(victim) .. " and repair wall damage!")
end)

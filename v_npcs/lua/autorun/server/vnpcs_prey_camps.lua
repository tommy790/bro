-- V-NPCs Prey Camps & Fortification Engineering AI Engine (vnpcs_prey_camps.lua)
-- Prey form camps of at least 10 members, slowly gather resources, and build defensive walls using map geometry; predators breach camps by swallowing the wall props

local camps_enabled = CreateConVar("vnpcs_prey_camps_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable prey camp establishment and defensive wall fortifications")
local camp_target_size = CreateConVar("vnpcs_prey_camp_target_size", "10", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Target number of prey NPCs per camp (at least 10 prey)")
local camp_resource_rate = CreateConVar("vnpcs_prey_camp_resource_rate", "1.5", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Base resource accumulation rate per second for prey camps")
local camp_wall_cost = CreateConVar("vnpcs_prey_camp_wall_cost", "25.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Resource cost to construct one defensive wall prop")
local camp_max_walls = CreateConVar("vnpcs_prey_camp_max_walls", "16", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum number of defensive wall props around a prey camp perimeter")
local camp_hut_cost = CreateConVar("vnpcs_prey_camp_hut_cost", "45.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Resource cost to construct a little hut inside a fortified prey camp")
local camp_max_huts = CreateConVar("vnpcs_prey_camp_max_huts", "4", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum number of little huts inside a fortified prey camp courtyard")
local love_enabled = CreateConVar("vnpcs_prey_camp_love_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable love and pregnancy population growth in fortified prey camps")
local pregnancy_time = CreateConVar("vnpcs_prey_camp_pregnancy_time", "45.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Duration in seconds for a pregnant female citizen to bear a new citizen")
local camp_max_members = CreateConVar("vnpcs_prey_camp_max_members", "25", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum total member capacity per prey camp")

VNPC_ActivePreyCamps = VNPC_ActivePreyCamps or {}

local PREY_WALL_MODELS = {
    "models/props_c17/fence01a.mdl",
    "models/props_c17/fence01b.mdl",
    "models/props_wasteland/wood_fence01a.mdl",
    "models/props_fortifications/barricade01a.mdl",
    "models/props_c17/concrete_barrier001a.mdl",
    "models/props_junk/wood_crate001a.mdl"
}

local PREY_HUT_MODELS = {
    "models/props_wasteland/wood_room001a.mdl",       -- Small wooden shack / cabin
    "models/props_c17/FurnitureShack001a.mdl",        -- Compact tin/wood shack
    "models/props_buildings/collapsedbuilding01a.mdl",-- Small shelter
    "models/props_c17/canister01a.mdl",               -- Compact shelter canister
    "models/props_wasteland/cargo_container01.mdl"    -- Cargo container shelter
}

function VNPC_IsEligiblePreyNPC(ent)
    if not IsValid(ent) or ent:Health() <= 0 then return false end
    if ent.Vored or ent.VNPC_Vored or ent.VNPC_Surrendered then return false end
    if ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator then return false end
    if VNPC_IsShyPredator and VNPC_IsShyPredator(ent) then return false end
    return (ent:IsNPC() or ent:IsNextBot())
end

function VNPC_IsFemalePreyCitizen(ent)
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

    local camp = {
        id = math.random(100000, 999999),
        pos = origin,
        members = { founder },
        walls = {},
        huts = {},
        fortified = false,
        resources = 15.0,
        lastUpdateTime = CurTime()
    }

    founder.VNPC_PreyCampID = camp.id
    table.insert(VNPC_ActivePreyCamps, camp)
    return camp
end

function VNPC_AssignPreyToCamp(npc)
    if not camps_enabled:GetBool() or not VNPC_IsEligiblePreyNPC(npc) then return nil end
    if npc.VNPC_IsWildWanderer then return nil end

    if not npc.VNPC_PreyPersonality and not npc.PreyPersonality then
        local preyPersList = { "fighter", "passive", "panicked", "stubborn", "willing" }
        local rPers = preyPersList[math.random(1, #preyPersList)]
        npc.VNPC_PreyPersonality = rPers
        npc.PreyPersonality = rPers
    end

    local current = VNPC_GetPreyCamp(npc)
    if current then return current end

    local targetSize = camp_target_size:GetInt() or 10
    local npcPos = npc:GetPos()
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

-- Advanced math & map geometry geometry calculator for perimeter wall coordinates
function VNPC_CalculateCampWallPositions(camp)
    if not camp or not camp.pos then return nil, nil end
    local numWalls = math.Clamp(camp_max_walls:GetInt(), 6, 24)
    local radius = 280 + (#camp.members * 18)
    local center = camp.pos + Vector(0, 0, 32)

    for i = 0, numWalls - 1 do
        local theta = (i / numWalls) * (2 * math.pi)
        local candidatePos = center + Vector(math.cos(theta) * radius, math.sin(theta) * radius, 65)

        -- Downward raycast against map geometry to find terrain floor normal
        local tr = util.TraceLine({
            start = candidatePos,
            endpos = candidatePos - Vector(0, 0, 220),
            mask = MASK_SOLID_BRUSHONLY
        })

        if tr.Hit and tr.HitNormal.z > 0.6 then
            -- Verify minimum spacing from existing wall props
            local occupied = false
            for _, w in ipairs(camp.walls) do
                if IsValid(w) and w:GetPos():DistToSqr(tr.HitPos) < (110 * 110) then
                    occupied = true
                    break
                end
            end

            if not occupied then
                -- Outward-facing yaw and terrain-aligned roll/pitch
                local outwardDir = (tr.HitPos - center):GetNormalized()
                local yaw = outwardDir:Angle().y + 90
                local ang = Angle(0, yaw, 0)
                return tr.HitPos + Vector(0, 0, 10), ang
            end
        end
    end
    return nil, nil
end

function VNPC_ConstructPreyCampWall(camp)
    if not camps_enabled:GetBool() or not camp then return false end

    local pos, ang = VNPC_CalculateCampWallPositions(camp)
    if not pos or not ang then return false end

    local wall = ents.Create("prop_physics")
    if not IsValid(wall) then return false end

    local mdl = PREY_WALL_MODELS[math.random(1, #PREY_WALL_MODELS)]
    if not util.IsValidModel(mdl) then
        mdl = "models/props_c17/fence01a.mdl"
    end

    wall:SetModel(mdl)
    wall:SetPos(pos)
    wall:SetAngles(ang)
    wall:Spawn()
    wall:Activate()

    wall.VNPC_IsPreyCampWall = true
    wall.VNPC_PreyCampID = camp.id
    wall.VNPC_CampRef = camp
    wall:SetHealth(180)

    table.insert(camp.walls, wall)

    -- Freeze wall physics so it stands firm as a defensive fortification
    local phys = wall:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(Vector(0,0,0))
        phys:EnableMotion(false)
        phys:Sleep()
    end

    if wall.EmitSound then
        wall:EmitSound("physics/wood/wood_box_impact_hard1.wav", 75, math.random(95, 105))
    end

    for _, p in ipairs(player.GetAll()) do
        p:ChatPrint("[V-NPCs] Prey Camp #" .. camp.id .. " constructed a defensive wall using map geometry! (Active walls: " .. #camp.walls .. ")")
    end

    return true
end

function VNPC_PredatorBreachPreyCampWall(pred, wall, camp)
    if not IsValid(pred) or not IsValid(wall) or not camp then return end
    if not wall.VNPC_IsPreyCampWall then return end

    -- Remove wall from camp perimeter
    for idx, w in ipairs(camp.walls) do
        if w == wall then
            table.remove(camp.walls, idx)
            break
        end
    end

    -- Predator swallows the wall prop to breach the camp
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
end

function VNPC_CalculateCampHutPosition(camp)
    if not camp or not camp.pos then return nil, nil end
    local numHuts = math.Clamp(camp_max_huts:GetInt(), 1, 6)
    local radius = 90 + ((#(camp.huts or {})) * 55)
    local center = camp.pos + Vector(0, 0, 32)

    for i = 0, numHuts - 1 do
        local theta = (i / numHuts) * (2 * math.pi) + math.rad(45)
        local candidatePos = center + Vector(math.cos(theta) * radius, math.sin(theta) * radius, 65)

        local tr = util.TraceLine({
            start = candidatePos,
            endpos = candidatePos - Vector(0, 0, 220),
            mask = MASK_SOLID_BRUSHONLY
        })

        if tr.Hit and tr.HitNormal.z > 0.6 then
            local occupied = false
            for _, h in ipairs(camp.huts or {}) do
                if IsValid(h) and h:GetPos():DistToSqr(tr.HitPos) < (130 * 130) then
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

function VNPC_ConstructPreyCampHut(camp)
    if not camps_enabled:GetBool() or not camp then return false end

    local pos, ang = VNPC_CalculateCampHutPosition(camp)
    if not pos or not ang then return false end

    local hut = ents.Create("prop_physics")
    if not IsValid(hut) then return false end

    local mdl = PREY_HUT_MODELS[math.random(1, #PREY_HUT_MODELS)]
    if not util.IsValidModel(mdl) then
        mdl = "models/props_c17/FurnitureShack001a.mdl"
    end

    hut:SetModel(mdl)
    hut:SetPos(pos)
    hut:SetAngles(ang)
    hut:Spawn()
    hut:Activate()

    hut.VNPC_IsPreyCampHut = true
    hut.VNPC_PreyCampID = camp.id
    hut.VNPC_CampRef = camp
    hut:SetHealth(300)

    camp.huts = camp.huts or {}
    table.insert(camp.huts, hut)

    local phys = hut:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(Vector(0,0,0))
        phys:EnableMotion(false)
        phys:Sleep()
    end

    if hut.EmitSound then
        hut:EmitSound("physics/wood/wood_box_impact_hard1.wav", 80, math.random(90, 105))
    end

    return true
end

function VNPC_PredatorBreachPreyCampHut(pred, hut, camp)
    if not IsValid(pred) or not IsValid(hut) or not camp then return end
    if not hut.VNPC_IsPreyCampHut then return end

    if camp.huts then
        for idx, h in ipairs(camp.huts) do
            if h == hut then
                table.remove(camp.huts, idx)
                break
            end
        end
    end

    local belly = pred.VNPC_Belly or pred.Belly
    if IsValid(belly) and belly.AddPrey then
        pcall(belly.AddPrey, belly, hut)
    elseif pred.EatEntity then
        pcall(pred.EatEntity, pred, hut)
    else
        hut:SetNoDraw(true)
        hut:SetSolid(0)
        hut:SetParent(pred)
        if pred.EmitSound then
            pred:EmitSound("physics/wood/wood_box_break1.wav", 85, math.random(90, 105))
        end
        timer.Simple(0.1, function()
            if IsValid(hut) then hut:Remove() end
        end)
    end
end

function VNPC_PreyCampLove_AI(camp, now)
    if not love_enabled:GetBool() or not camp or not camp.fortified then return end
    local maxMembers = camp_max_members:GetInt()
    if #camp.members >= maxMembers then return end

    local females = {}
    local males = {}
    for _, mem in ipairs(camp.members) do
        if IsValid(mem) and mem:Health() > 0 then
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

    -- 2. Check if a new couple falls in love inside the fort
    if (camp.lastLoveTriggerTime or 0) <= now and #camp.members < maxMembers then
        for _, f in ipairs(females) do
            if not f.VNPC_IsPregnant then
                f.VNPC_IsPregnant = true
                f.VNPC_BabyGrowthValue = 10.0
                f.VNPC_LastGrowthTime = now
                camp.lastLoveTriggerTime = now + 25.0

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

-- Main Prey Camps & Fortification AI Loop
hook.Add("Think", "VNPC_PreyCamps_AI_Loop", function()
    if not camps_enabled:GetBool() then return end

    local now = CurTime()

    -- 1. Enroll eligible prey NPCs into prey camps
    for _, ent in ipairs(ents.GetAll()) do
        if VNPC_IsEligiblePreyNPC(ent) and not ent.VNPC_PreyCampID then
            VNPC_AssignPreyToCamp(ent)
        end
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

        if VNPC_CheckPreyCampConquest then
            VNPC_CheckPreyCampConquest(camp)
        end

        if #camp.members == 0 then
            table.remove(VNPC_ActivePreyCamps, i)
            continue
        end

        -- Accumulate resources based on camp member count and base rate
        local baseRate = camp_resource_rate:GetFloat()
        camp.resources = (camp.resources or 0) + ((baseRate + #camp.members * 0.35) * dt)

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
                if pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator then
                    local belly = pred.VNPC_Belly or pred.Belly
                    local hasSpace = not IsValid(belly) or not belly.Prey or #belly.Prey < 5
                    if hasSpace and (pred.VNPC_NextWallBreachTime or 0) <= now then
                        pred.VNPC_NextWallBreachTime = now + 5.0
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
                if pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator then
                    local belly = pred.VNPC_Belly or pred.Belly
                    local hasSpace = not IsValid(belly) or not belly.Prey or #belly.Prey < 5
                    if hasSpace and (pred.VNPC_NextHutBreachTime or 0) <= now then
                        pred.VNPC_NextHutBreachTime = now + 5.0
                        VNPC_PredatorBreachPreyCampHut(pred, hut, camp)
                        break
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
        print(string.format(" -> Prey Camp [#%d] | Members: %d (Pregnant: %d) | Walls: %d | Huts: %d | Resources: %.1f | Fortified: %s",
            camp.id, #camp.members, pregCount, #camp.walls, #(camp.huts or {}), camp.resources or 0, tostring(camp.fortified or false)))
    end
    print("Total active prey camps: " .. #VNPC_ActivePreyCamps)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Prey camp status printed to console. Active prey camps: " .. #VNPC_ActivePreyCamps)
    end
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
        camp = VNPC_AssignPreyToCamp(target)
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
    local camp = VNPC_CreatePreyCamp(tr.HitPos, target)
    ply:ChatPrint("[V-NPCs] Established Prey Camp #" .. tostring(camp and camp.id or "N/A") .. " for " .. tostring(target) .. "!")
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

concommand.Add("vnpcs_clear_prey_camps", function(ply)
    local count = #VNPC_ActivePreyCamps
    for _, camp in ipairs(VNPC_ActivePreyCamps) do
        for _, wall in ipairs(camp.walls) do
            if IsValid(wall) then wall:Remove() end
        end
        for _, hut in ipairs(camp.huts or {}) do
            if IsValid(hut) then hut:Remove() end
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

-- V-NPCs Prey Camps & Fortification Engineering AI Engine (vnpcs_prey_camps.lua)
-- Prey form camps of at least 10 members, slowly gather resources, and build defensive walls using map geometry; predators breach camps by swallowing the wall props

local camps_enabled = CreateConVar("vnpcs_prey_camps_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable prey camp establishment and defensive wall fortifications")
local camp_target_size = CreateConVar("vnpcs_prey_camp_target_size", "10", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Target number of prey NPCs per camp (at least 10 prey)")
local camp_resource_rate = CreateConVar("vnpcs_prey_camp_resource_rate", "1.5", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Base resource accumulation rate per second for prey camps")
local camp_wall_cost = CreateConVar("vnpcs_prey_camp_wall_cost", "25.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Resource cost to construct one defensive wall prop")
local camp_max_walls = CreateConVar("vnpcs_prey_camp_max_walls", "16", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum number of defensive wall props around a prey camp perimeter")

VNPC_ActivePreyCamps = VNPC_ActivePreyCamps or {}

local PREY_WALL_MODELS = {
    "models/props_c17/fence01a.mdl",
    "models/props_c17/fence01b.mdl",
    "models/props_wasteland/wood_fence01a.mdl",
    "models/props_fortifications/barricade01a.mdl",
    "models/props_c17/concrete_barrier001a.mdl",
    "models/props_junk/wood_crate001a.mdl"
}

function VNPC_IsEligiblePreyNPC(ent)
    if not IsValid(ent) or ent:Health() <= 0 then return false end
    if ent.Vored or ent.VNPC_Vored or ent.VNPC_Surrendered then return false end
    if ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator then return false end
    if VNPC_IsShyPredator and VNPC_IsShyPredator(ent) then return false end
    return (ent:IsNPC() or ent:IsNextBot())
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
        resources = 15.0,
        lastUpdateTime = CurTime()
    }

    founder.VNPC_PreyCampID = camp.id
    table.insert(VNPC_ActivePreyCamps, camp)
    return camp
end

function VNPC_AssignPreyToCamp(npc)
    if not camps_enabled:GetBool() or not VNPC_IsEligiblePreyNPC(npc) then return nil end
    local current = VNPC_GetPreyCamp(npc)
    if current then return current end

    local targetSize = camp_target_size:GetInt() or 10
    local npcPos = npc:GetPos()
    local bestCamp = nil
    local bestDistSqr = 2500 * 2500

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

    for _, p in ipairs(player.GetAll()) do
        p:ChatPrint("[V-NPCs] WARNING! Predator " .. pred:GetClass() .. " swallowed a defensive wall prop and breached Prey Camp #" .. camp.id .. "!")
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
    print("-----------------------------------------")
    for idx, camp in ipairs(VNPC_ActivePreyCamps) do
        print(string.format(" -> Prey Camp [#%d] | Members: %d | Walls: %d | Resources: %.1f | Pos: (%d, %d, %d)",
            camp.id, #camp.members, #camp.walls, camp.resources or 0, camp.pos.x, camp.pos.y, camp.pos.z))
    end
    print("Total active prey camps: " .. #VNPC_ActivePreyCamps)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Prey camp status printed to console. Active prey camps: " .. #VNPC_ActivePreyCamps)
    end
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

concommand.Add("vnpcs_clear_prey_camps", function(ply)
    local count = #VNPC_ActivePreyCamps
    for _, camp in ipairs(VNPC_ActivePreyCamps) do
        for _, wall in ipairs(camp.walls) do
            if IsValid(wall) then wall:Remove() end
        end
    end
    for _, ent in ipairs(ents.GetAll()) do
        ent.VNPC_PreyCampID = nil
    end
    table.Empty(VNPC_ActivePreyCamps)
    print("[V-NPCs] Cleared " .. count .. " prey camps and all defensive walls from the map.")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Cleared " .. count .. " prey camps and all defensive walls from the map.")
    end
end)

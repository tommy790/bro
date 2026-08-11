-- V-NPCs Tactical Predator Pack Camping & Foraging AI Engine (vnpcs_camps_ai.lua)
-- Predators form camps far apart on the map; when hungry, foragers capture prey and bring them back to camp for hungry campmates to swallow

local camps_enabled = CreateConVar("vnpcs_camps_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable predator camps and foraging squads")
local camp_min_dist = CreateConVar("vnpcs_camp_min_distance", "1400.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Minimum distance required between distinct predator camps")
local camp_cap = CreateConVar("vnpcs_camp_member_cap", "4", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum number of sister predators belonging to a single camp")
local camp_hunger_thresh = CreateConVar("vnpcs_camp_hunger_thresh", "45.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Hunger percentage required for a camp to dispatch foragers to capture prey")
local camp_max_tents = CreateConVar("vnpcs_pred_camp_max_tents", "2", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum number of tents built at a predator camp")

VNPC_ActivePredatorCamps = VNPC_ActivePredatorCamps or {}

local PRED_TENT_MODELS = {
    "models/props_wasteland/wood_room001a.mdl",       -- Wooden cabin / tent shelter
    "models/props_c17/FurnitureShack001a.mdl",        -- Tin/wood shack shelter
    "models/props_c17/canister01a.mdl",               -- Compact shelter
    "models/props_wasteland/cargo_container01.mdl"    -- Container shelter
}

function VNPC_GetPredatorCamp(pred)
    if not IsValid(pred) or not pred.VNPC_CampID then return nil end
    for _, camp in ipairs(VNPC_ActivePredatorCamps) do
        if camp.id == pred.VNPC_CampID then
            return camp
        end
    end
    return nil
end

function VNPC_CreatePredatorCamp(pos, founder)
    if not camps_enabled:GetBool() then return nil end
    if not IsValid(founder) then return nil end

    local origin = pos or founder:GetPos()
    local minDist = camp_min_dist:GetFloat()
    local minDistSqr = minDist * minDist

    -- Verify distance from existing camps; if too close, offset to a far location
    for _, existing in ipairs(VNPC_ActivePredatorCamps) do
        if existing.pos:DistToSqr(origin) < minDistSqr then
            local angle = math.rad(math.random(0, 360))
            origin = existing.pos + Vector(math.cos(angle) * minDist * 1.1, math.sin(angle) * minDist * 1.1, 0)
            break
        end
    end

    local myFaction = (VNPC_GetPredatorFaction and VNPC_GetPredatorFaction(founder)) or "metrocop"
    local camp = {
        id = math.random(100000, 999999),
        pos = origin,
        members = { founder },
        tents = {},
        faction = myFaction,
        createTime = CurTime(),
        state = "idle",
        lastUpdateTime = CurTime()
    }

    founder.VNPC_CampID = camp.id
    founder.VNPC_CampRole = "stayer"

    table.insert(VNPC_ActivePredatorCamps, camp)
    return camp
end

function VNPC_AssignPredatorToCamp(pred, force)
    if not camps_enabled:GetBool() then return nil end
    if not IsValid(pred) or pred:Health() <= 0 then return nil end
    if pred.VNPC_IsPermanentFortPredator then return nil end

    if not pred.VNPC_PredatorPersonality and not (pred.VoreSettings and pred.VoreSettings.PredatorPersonality) then
        local predPersList = { "aggressive", "opportunistic", "glutton", "shy", "selective", "gentle", "loving" }
        local pPers = predPersList[math.random(1, #predPersList)]
        pred.VNPC_PredatorPersonality = pPers
        if pred.VoreSettings then
            pred.VoreSettings.PredatorPersonality = pPers
        end
        if VNPC_RandomizePersonalities then
            pcall(VNPC_RandomizePersonalities, pred)
        end
    end

    local currentCamp = VNPC_GetPredatorCamp(pred)
    if currentCamp then return currentCamp end

    local myFaction = (VNPC_GetPredatorFaction and VNPC_GetPredatorFaction(pred)) or "metrocop"
    local maxCap = camp_cap:GetInt() or 4
    local predPos = pred:GetPos()
    local bestCamp = nil
    local bestDistSqr = 3000 * 3000

    for _, camp in ipairs(VNPC_ActivePredatorCamps) do
        if #camp.members < maxCap and camp.faction == myFaction then
            local dSqr = camp.pos:DistToSqr(predPos)
            if dSqr <= bestDistSqr then
                bestCamp = camp
                bestDistSqr = dSqr
            end
        end
    end

    if bestCamp then
        table.insert(bestCamp.members, pred)
        pred.VNPC_CampID = bestCamp.id
        pred.VNPC_CampRole = "stayer"
        return bestCamp
    else
        return VNPC_CreatePredatorCamp(predPos, pred)
    end
end

function VNPC_ConstructPredatorCampTent(camp)
    if not camps_enabled:GetBool() or not camp or not camp.pos then return false end
    local maxTents = camp_max_tents:GetInt()
    camp.tents = camp.tents or {}
    if #camp.tents >= maxTents then return false end

    local angle = math.rad(math.random(0, 360))
    local dist = 60 + (#camp.tents * 55)
    local candidatePos = camp.pos + Vector(math.cos(angle) * dist, math.sin(angle) * dist, 50)

    local tr = util.TraceLine({
        start = candidatePos,
        endpos = candidatePos - Vector(0, 0, 200),
        mask = MASK_SOLID_BRUSHONLY
    })

    if not tr.Hit or tr.HitNormal.z < 0.6 then return false end

    local tent = ents.Create("prop_physics")
    if not IsValid(tent) then return false end

    local mdl = PRED_TENT_MODELS[math.random(1, #PRED_TENT_MODELS)]
    if not util.IsValidModel(mdl) then
        mdl = "models/props_c17/FurnitureShack001a.mdl"
    end

    tent:SetModel(mdl)
    tent:SetPos(tr.HitPos)
    tent:SetAngles(Angle(0, math.random(0, 360), 0))
    tent:Spawn()
    tent:Activate()

    local minZ = tent:OBBMins().z
    local zOffset = (minZ < 0) and math.abs(minZ) or 0
    tent:SetPos(tr.HitPos + Vector(0, 0, zOffset + 2))

    tent.VNPC_IsPredatorTent = true
    tent.VNPC_PredatorCampID = camp.id
    tent:SetHealth(400)

    table.insert(camp.tents, tent)

    local phys = tent:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(Vector(0,0,0))
        phys:EnableMotion(false)
        phys:Sleep()
    end

    if tent.EmitSound then
        tent:EmitSound("physics/wood/wood_box_impact_hard1.wav", 80, math.random(90, 105))
    end

    return true
end

function VNPC_ConstructPredatorCampFire(camp)
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

    fire.VNPC_IsPredatorCampFire = true
    fire.VNPC_PredatorCampID = camp.id
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

function VNPC_ConstructPredatorCampWater(camp)
    if not camps_enabled:GetBool() or not camp or not camp.pos then return false end
    if IsValid(camp.watersource) then return false end

    local angle = math.rad(math.random(0, 360))
    local candidatePos = camp.pos + Vector(math.cos(angle) * 75, math.sin(angle) * 75, 40)
    local tr = util.TraceLine({
        start = candidatePos,
        endpos = candidatePos - Vector(0, 0, 150),
        mask = MASK_SOLID_BRUSHONLY
    })
    if not tr.Hit or tr.HitNormal.z < 0.65 then return false end

    local water = ents.Create("prop_physics")
    if not IsValid(water) then return false end

    water:SetModel("models/props_c17/FurnitureBoiler001a.mdl")
    water:SetPos(tr.HitPos)
    water:SetAngles(Angle(0, math.random(0, 360), 0))
    water:Spawn()
    water:Activate()

    local minZ = water:OBBMins().z
    local zOffset = (minZ < 0) and math.abs(minZ) or 0
    water:SetPos(tr.HitPos + Vector(0, 0, zOffset + 2))

    water.VNPC_IsPredatorCampWater = true
    water.VNPC_PredatorCampID = camp.id
    water:SetHealth(400)

    local phys = water:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(Vector(0,0,0))
        phys:EnableMotion(false)
        phys:Sleep()
    end

    camp.watersource = water
    return true
end

function VNPC_ConstructPredatorCampBarricades(camp)
    if not camps_enabled:GetBool() or not camp or not camp.pos then return false end
    camp.barricades = camp.barricades or {}
    for b = #camp.barricades, 1, -1 do
        if not IsValid(camp.barricades[b]) then
            table.remove(camp.barricades, b)
        end
    end
    if #camp.barricades >= 6 then return false end

    local idx = #camp.barricades
    local angle = math.rad(idx * 60 + math.random(-10, 10))
    local radius = 190
    local candidatePos = camp.pos + Vector(math.cos(angle) * radius, math.sin(angle) * radius, 40)

    local tr = util.TraceLine({
        start = candidatePos,
        endpos = candidatePos - Vector(0, 0, 200),
        mask = MASK_SOLID_BRUSHONLY
    })
    if not tr.Hit or tr.HitNormal.z < 0.65 then return false end

    local barricade = ents.Create("prop_physics")
    if not IsValid(barricade) then return false end

    barricade:SetModel("models/props_fortifications/barricade01a.mdl")
    barricade:SetPos(tr.HitPos)
    local outwardDir = (tr.HitPos - camp.pos):GetNormalized()
    barricade:SetAngles(Angle(0, outwardDir:Angle().y + 90, 0))
    barricade:Spawn()
    barricade:Activate()

    local minZ = barricade:OBBMins().z
    local zOffset = (minZ < 0) and math.abs(minZ) or 0
    barricade:SetPos(tr.HitPos + Vector(0, 0, zOffset + 2))

    barricade.VNPC_IsPredatorCampBarricade = true
    barricade.VNPC_PredatorCampID = camp.id
    barricade:SetHealth(400)

    local phys = barricade:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(Vector(0,0,0))
        phys:EnableMotion(false)
        phys:Sleep()
    end

    table.insert(camp.barricades, barricade)
    return true
end

function VNPC_ForagerFeedCamp(forager, camp, belly)
    if not IsValid(forager) or not IsValid(belly) or not camp then return false end
    if not belly.Prey or #belly.Prey == 0 then return false end

    -- Find a hungry sister at camp
    local hungrySister = nil
    for _, member in ipairs(camp.members) do
        if IsValid(member) and member ~= forager and member:Health() > 0 then
            local sBelly = member.VNPC_Belly or member.Belly
            if IsValid(sBelly) and ((not sBelly.Prey) or #sBelly.Prey == 0) and (sBelly.DigestionPhase or 0) == 0 then
                hungrySister = member
                break
            end
        end
    end

    if IsValid(hungrySister) then
        local transferred = 0
        if VNPC_TransferPrey then
            transferred = VNPC_TransferPrey(forager, hungrySister)
        end

        if transferred > 0 then
            if VNPC_AddPredatorXP then
                VNPC_AddPredatorXP(forager, 75, "Fed campmate sister")
            end
            forager.VNPC_IsCarryingPreyForCamp = false
            forager.VNPC_CampWaitStartTime = nil
            belly.VNPC_NoDigestion = false
            belly.DigestionStrength = forager.VoreSettings and forager.VoreSettings.DigestionStrength or 2

            local wasDangerous = false
            local sBelly = hungrySister.VNPC_Belly or hungrySister.Belly
            if IsValid(sBelly) then
                sBelly.VNPC_NoDigestion = false
                sBelly.DigestionStrength = hungrySister.VoreSettings and hungrySister.VoreSettings.DigestionStrength or 2
                if sBelly.Prey then
                    for _, pTable in ipairs(sBelly.Prey) do
                        if pTable and IsValid(pTable.Entity) and VNPC_IsDangerousPrey and VNPC_IsDangerousPrey(pTable.Entity) then
                            wasDangerous = true
                            pTable.Value = (pTable.Value or 50) * 2.0
                            pTable.TrueValue = (pTable.TrueValue or 50) * 2.0
                        end
                    end
                end
            end

            if wasDangerous then
                for _, m in ipairs(camp.members) do
                    if IsValid(m) then
                        m.VNPC_Hunger = math.max(0, (m.VNPC_Hunger or 0) - 30)
                    end
                end
            end

            if hungrySister.EmitSound then
                hungrySister:EmitSound("belly/snd_digeststart.wav", 80, math.random(95, 105))
            end

            local now = CurTime()
            camp.lastFeedMsgTime = now + 6.0

            hook.Run("VNPC_OnForagerFedCamp", forager, hungrySister, camp)
            return true
        end
    else
        -- No hungry sister waiting at camp right now
        local now = CurTime()
        forager.VNPC_CampWaitStartTime = forager.VNPC_CampWaitStartTime or now
        if (now - forager.VNPC_CampWaitStartTime) > 15.0 then
            -- Fall back to digesting prey herself after waiting 15 seconds
            forager.VNPC_IsCarryingPreyForCamp = false
            forager.VNPC_CampWaitStartTime = nil
            belly.VNPC_NoDigestion = false
            belly.DigestionStrength = forager.VoreSettings and forager.VoreSettings.DigestionStrength or 2
            return true
        end
    end
    return false
end

-- Hook into swallow loop to mark captured prey for camp when foraging
hook.Add("VNPC_OnPreySwallowed", "VNPC_CampForagerPreyCapture", function(pred, prey, belly)
    if not camps_enabled:GetBool() then return end
    if not IsValid(pred) or not IsValid(belly) then return end

    local camp = VNPC_GetPredatorCamp(pred)
    if camp and camp.state == "foraging" and pred.VNPC_CampRole == "forager" then
        pred.VNPC_IsCarryingPreyForCamp = true
        belly.VNPC_NoDigestion = true
        belly.DigestionStrength = 0
    end
end)

-- Main Camp AI Loop
hook.Add("Think", "VNPC_PredatorCamps_AI_Loop", function()
    if not camps_enabled:GetBool() then return end

    local now = CurTime()

    -- 1. Ensure all female V-NPC predators belong to a camp
    for _, pred in ipairs(ents.GetAll()) do
        if not IsValid(pred) or pred:Health() <= 0 then continue end
        local isPred = (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator or (VNPC_IsFemaleModelNPC and VNPC_IsFemaleModelNPC(pred)))
        if not isPred then continue end
        if not pred.VNPC_FemaleModelVore and VNPC_GiveFemaleModelVore then
            VNPC_GiveFemaleModelVore(pred)
        end
        if (not pred.VNPC_CampID or pred.VNPC_CampID == "wild") and not pred.VNPC_IsPermanentFortPredator then
            pred.VNPC_CampID = nil
            VNPC_AssignPredatorToCamp(pred)
        end
    end

    -- 2. Evaluate and coordinate active camps
    for i = #VNPC_ActivePredatorCamps, 1, -1 do
        local camp = VNPC_ActivePredatorCamps[i]
        if (camp.lastUpdateTime or 0) > (now - 1.0) then continue end
        camp.lastUpdateTime = now

        -- Prune dead / invalid members
        for m = #camp.members, 1, -1 do
            local mem = camp.members[m]
            if not IsValid(mem) or mem:Health() <= 0 or mem.Vored or mem.VNPC_Vored then
                table.remove(camp.members, m)
            end
        end

        if #camp.members == 0 then
            table.remove(VNPC_ActivePredatorCamps, i)
            continue
        end

        -- Prune destroyed tents
        camp.tents = camp.tents or {}
        for t = #camp.tents, 1, -1 do
            local tent = camp.tents[t]
            if not IsValid(tent) then
                table.remove(camp.tents, t)
            end
        end

        -- Construct a Camp Tent/Shelter when resting at camp
        if camp.state == "idle" and #camp.tents < camp_max_tents:GetInt() and (now - (camp.createTime or now)) > 15.0 and (camp.lastTentBuildTime or 0) <= now then
            if VNPC_ConstructPredatorCampTent(camp) then
                camp.lastTentBuildTime = now + 35.0
            end
        end

        -- Construct Campfire, Water Source, and Barricades when resting at camp
        if camp.state == "idle" then
            if not IsValid(camp.campfire) and (now - (camp.createTime or now)) > 5.0 then
                VNPC_ConstructPredatorCampFire(camp)
            end
            if not IsValid(camp.watersource) and (now - (camp.createTime or now)) > 6.0 then
                VNPC_ConstructPredatorCampWater(camp)
            end
            camp.barricades = camp.barricades or {}
            if #camp.barricades < 6 and (now - (camp.createTime or now)) > 8.0 and (camp.lastBarricadeBuildTime or 0) <= now then
                if VNPC_ConstructPredatorCampBarricades(camp) then
                    camp.lastBarricadeBuildTime = now + 12.0
                end
            end
        end

        -- Count how many members are hungry
        local hungryCount = 0
        local hThresh = camp_hunger_thresh:GetFloat()
        for _, member in ipairs(camp.members) do
            local belly = member.VNPC_Belly or member.Belly
            local isEmpty = IsValid(belly) and ((not belly.Prey) or #belly.Prey == 0) and (belly.DigestionPhase or 0) == 0
            local isHungry = isEmpty or ((member.VNPC_Hunger or 0) >= hThresh)
            if isHungry then
                hungryCount = hungryCount + 1
            end
        end

        -- Evaluate camp state
        local majorityHungry = (hungryCount >= math.ceil(#camp.members * 0.5))
        if majorityHungry then
            camp.state = "foraging"

            -- Assign 1 or 2 able-bodied members as foragers, rest as stayers
            local foragerCount = 0
            for _, member in ipairs(camp.members) do
                local belly = member.VNPC_Belly or member.Belly
                local isEmpty = IsValid(belly) and ((not belly.Prey) or #belly.Prey == 0) and (belly.DigestionPhase or 0) == 0
                if isEmpty and foragerCount < math.max(1, math.floor(#camp.members * 0.5)) then
                    member.VNPC_CampRole = "forager"
                    foragerCount = foragerCount + 1
                else
                    if member.VNPC_CampRole ~= "forager" then
                        member.VNPC_CampRole = "stayer"
                    end
                end
            end
        else
            camp.state = "idle"
            for _, member in ipairs(camp.members) do
                member.VNPC_CampRole = "stayer"
            end
        end

        -- Execute role behaviors
        for _, member in ipairs(camp.members) do
            if not IsValid(member) or member:Health() <= 0 then continue end
            local belly = member.VNPC_Belly or member.Belly

            if member.VNPC_CampRole == "forager" and camp.state == "foraging" then
                if member.VNPC_IsCarryingPreyForCamp and IsValid(belly) and belly.Prey and #belly.Prey > 0 then
                    -- Carrying captured prey: abort hunting and sprint back to camp
                    if member.SetEnemy then pcall(member.SetEnemy, member, nil) end
                    if member.SetLastPosition then pcall(member.SetLastPosition, member, camp.pos) end
                    if member.SetSchedule then pcall(member.SetSchedule, member, SCHED_FORCED_GO_RUN) end

                    -- Check anti-stuck recovery while carrying prey home
                    if member.GetVelocity and member:GetVelocity():Length2DSqr() < 4 then
                        member.VNPC_StuckTime = (member.VNPC_StuckTime or now) + 1.0
                        if (now - member.VNPC_StuckTime) > 3.0 then
                            member.VNPC_StuckTime = now
                            member:SetPos(member:GetPos() + Vector(0, 0, 12))
                        end
                    else
                        member.VNPC_StuckTime = nil
                    end

                    local distSqr = member:GetPos():DistToSqr(camp.pos)
                    if distSqr <= (250 * 250) then
                        VNPC_ForagerFeedCamp(member, camp, belly)
                    end
                end
            else
                -- Stayer: keep within camp perimeter (StormFox 2: gather by warm campfire at night or in freezing weather)
                if not IsValid(member:GetEnemy()) and not member.VNPC_IsSleeping then
                    local coldOrNight = (VNPC_IsStormFox2Night and VNPC_IsStormFox2Night()) or (VNPC_GetStormFox2Temperature and VNPC_GetStormFox2Temperature() < 8.0)
                    local targetPos = (coldOrNight and IsValid(camp.campfire)) and camp.campfire:GetPos() or camp.pos
                    local maxD = coldOrNight and (140 * 140) or (450 * 450)
                    if member:GetPos():DistToSqr(targetPos) > maxD then
                        if member.SetLastPosition then pcall(member.SetLastPosition, member, targetPos) end
                        if member.SetSchedule then pcall(member.SetSchedule, member, SCHED_FORCED_GO) end
                    end
                end
            end
        end
    end
end)

hook.Add("EntityTakeDamage", "VNPC_PredatorCamp_SisterDefenseHook", function(target, dmginfo)
    if not IsValid(target) or not target.VNPC_CampID then return end
    local attacker = dmginfo:GetAttacker()
    if not IsValid(attacker) or attacker == target or attacker.VNPC_CampID == target.VNPC_CampID then return end

    local camp = VNPC_GetPredatorCamp(target)
    if camp and camp.members then
        for _, sister in ipairs(camp.members) do
            if IsValid(sister) and sister ~= target and sister:Health() > 0 and not sister.VNPC_IsSleeping then
                if sister:GetPos():DistToSqr(target:GetPos()) <= (1500 * 1500) then
                    if sister.SetEnemy then pcall(sister.SetEnemy, sister, attacker) end
                    if sister.SetLastPosition then pcall(sister.SetLastPosition, sister, attacker:GetPos()) end
                    if sister.SetSchedule then pcall(sister.SetSchedule, sister, SCHED_FORCED_GO_RUN) end
                end
            end
        end
    end
end)

concommand.Add("vnpcs_camps_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Tactical Predator Pack Camping & Foraging Status")
    print("Enabled: " .. tostring(camps_enabled:GetBool()))
    print("Min Camp Distance: " .. tostring(camp_min_dist:GetFloat()) .. " units")
    print("Max Members/Camp: " .. tostring(camp_cap:GetInt()))
    print("Hunger Threshold: " .. tostring(camp_hunger_thresh:GetFloat()) .. "%")
    print("-----------------------------------------")
    for idx, camp in ipairs(VNPC_ActivePredatorCamps) do
        local cfStr = IsValid(camp.campfire) and "YES" or "NO"
        print(string.format(" -> Camp [#%d] | Faction: %s | State: %s | Members: %d | Campfire: %s | Barricades: %d | Pos: (%d, %d, %d)",
            camp.id, string.upper(camp.faction or "METROCOP"), string.upper(camp.state), #camp.members, cfStr, #(camp.barricades or {}), camp.pos.x, camp.pos.y, camp.pos.z))
        for mIdx, mem in ipairs(camp.members) do
            if IsValid(mem) then
                print(string.format("      -> Member [%d] %s | Role: %s | Carrying Prey: %s",
                    mem:EntIndex(), mem:GetClass(), tostring(mem.VNPC_CampRole), tostring(mem.VNPC_IsCarryingPreyForCamp or false)))
            end
        end
    end
    print("Total active predator camps: " .. #VNPC_ActivePredatorCamps)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Predator camp status printed to console. Active camps: " .. #VNPC_ActivePredatorCamps)
    end
end)

concommand.Add("vnpcs_test_create_camp", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a female V-NPC predator to establish a new camp!")
        return
    end
    target.VNPC_SpawnedByPlayer = true
    local camp = VNPC_CreatePredatorCamp(tr.HitPos, target)
    ply:ChatPrint("[V-NPCs] Established Camp #" .. tostring(camp and camp.id or "N/A") .. " for " .. tostring(target) .. "!")
end)

concommand.Add("vnpcs_test_camp_forage", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a female V-NPC predator to trigger camp foraging!")
        return
    end
    local camp = VNPC_GetPredatorCamp(target)
    if not camp then
        camp = VNPC_AssignPredatorToCamp(target, true)
    end
    if camp then
        camp.state = "foraging"
        target.VNPC_CampRole = "forager"
        ply:ChatPrint("[V-NPCs] Forced Camp #" .. camp.id .. " into FORAGING mode and set " .. tostring(target) .. " as FORAGER!")
    end
end)

concommand.Add("vnpcs_test_create_pred_tent", function(ply)
    if not IsValid(ply) then return end
    local bestCamp = nil
    for _, camp in ipairs(VNPC_ActivePredatorCamps) do
        bestCamp = camp
        break
    end
    if not bestCamp then
        ply:ChatPrint("[V-NPCs] No active predator camp found to construct a tent!")
        return
    end
    if VNPC_ConstructPredatorCampTent(bestCamp) then
        ply:ChatPrint("[V-NPCs] Forced construction of a Camp Tent for Predator Camp #" .. bestCamp.id .. "!")
    else
        ply:ChatPrint("[V-NPCs] Could not find valid ground geometry to construct a tent in Predator Camp #" .. bestCamp.id .. "!")
    end
end)

concommand.Add("vnpcs_clear_camps", function(ply)
    local count = #VNPC_ActivePredatorCamps
    for _, camp in ipairs(VNPC_ActivePredatorCamps) do
        for _, t in ipairs(camp.tents or {}) do
            if IsValid(t) then t:Remove() end
        end
    end
    for _, pred in ipairs(ents.GetAll()) do
        pred.VNPC_CampID = nil
        pred.VNPC_CampRole = nil
        pred.VNPC_IsCarryingPreyForCamp = false
    end
    table.Empty(VNPC_ActivePredatorCamps)
    print("[V-NPCs] Cleared " .. count .. " predator camps and all tents from the map.")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Cleared " .. count .. " predator camps and all tents from the map.")
    end
end)

concommand.Add("vnpcs_test_force_pred_camps", function(ply)
    local assigned = 0
    for _, pred in ipairs(ents.GetAll()) do
        if IsValid(pred) and pred:Health() > 0 and not pred.VNPC_IsPermanentFortPredator then
            local isPred = (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator or (VNPC_IsFemaleModelNPC and VNPC_IsFemaleModelNPC(pred)))
            if isPred then
                if not pred.VNPC_FemaleModelVore and VNPC_GiveFemaleModelVore then
                    VNPC_GiveFemaleModelVore(pred)
                end
                if not pred.VNPC_CampID then
                    local camp = VNPC_AssignPredatorToCamp(pred, true)
                    if camp then
                        assigned = assigned + 1
                    end
                end
            end
        end
    end
    local msg = "[V-NPCs] Scanned predators and forced camp formation. Assigned predators: " .. assigned
    print(msg)
    if IsValid(ply) then ply:ChatPrint(msg) end
end)

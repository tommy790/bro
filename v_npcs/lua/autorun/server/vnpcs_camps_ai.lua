-- V-NPCs Tactical Predator Pack Camping & Foraging AI Engine (vnpcs_camps_ai.lua)
-- Predators form camps far apart on the map; when hungry, foragers capture prey and bring them back to camp for hungry campmates to swallow

local camps_enabled = CreateConVar("vnpcs_camps_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable predator camps and foraging squads")
local camp_min_dist = CreateConVar("vnpcs_camp_min_distance", "1400.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Minimum distance required between distinct predator camps")
local camp_cap = CreateConVar("vnpcs_camp_member_cap", "4", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum number of sister predators belonging to a single camp")
local camp_hunger_thresh = CreateConVar("vnpcs_camp_hunger_thresh", "45.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Hunger percentage required for a camp to dispatch foragers to capture prey")

VNPC_ActivePredatorCamps = VNPC_ActivePredatorCamps or {}

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

    local camp = {
        id = math.random(100000, 999999),
        pos = origin,
        members = { founder },
        state = "idle",
        lastUpdateTime = CurTime()
    }

    founder.VNPC_CampID = camp.id
    founder.VNPC_CampRole = "stayer"

    table.insert(VNPC_ActivePredatorCamps, camp)
    return camp
end

function VNPC_AssignPredatorToCamp(pred)
    if not camps_enabled:GetBool() then return nil end
    if not IsValid(pred) or pred:Health() <= 0 then return nil end

    local currentCamp = VNPC_GetPredatorCamp(pred)
    if currentCamp then return currentCamp end

    local maxCap = camp_cap:GetInt() or 4
    local predPos = pred:GetPos()
    local bestCamp = nil
    local bestDistSqr = 1800 * 1800

    for _, camp in ipairs(VNPC_ActivePredatorCamps) do
        if #camp.members < maxCap then
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
            forager.VNPC_IsCarryingPreyForCamp = false
            forager.VNPC_CampWaitStartTime = nil
            belly.VNPC_NoDigestion = false
            belly.DigestionStrength = forager.VoreSettings and forager.VoreSettings.DigestionStrength or 2

            local sBelly = hungrySister.VNPC_Belly or hungrySister.Belly
            if IsValid(sBelly) then
                sBelly.VNPC_NoDigestion = false
                sBelly.DigestionStrength = hungrySister.VoreSettings and hungrySister.VoreSettings.DigestionStrength or 2
            end

            if hungrySister.EmitSound then
                hungrySister:EmitSound("belly/snd_digeststart.wav", 80, math.random(95, 105))
            end

            local now = CurTime()
            if (camp.lastFeedMsgTime or 0) <= now then
                camp.lastFeedMsgTime = now + 6.0
                for _, p in ipairs(player.GetAll()) do
                    p:ChatPrint("[V-NPCs] Forager " .. forager:GetClass() .. " returns to camp and feeds captured prey to her hungry sister " .. hungrySister:GetClass() .. "!")
                end
            end

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
        if not (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) then continue end
        if not pred.VNPC_CampID then
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

                    local distSqr = member:GetPos():DistToSqr(camp.pos)
                    if distSqr <= (250 * 250) then
                        VNPC_ForagerFeedCamp(member, camp, belly)
                    end
                end
            else
                -- Stayer: keep within camp perimeter
                if not IsValid(member:GetEnemy()) then
                    local distSqr = member:GetPos():DistToSqr(camp.pos)
                    if distSqr > (450 * 450) then
                        if member.SetLastPosition then pcall(member.SetLastPosition, member, camp.pos) end
                        if member.SetSchedule then pcall(member.SetSchedule, member, SCHED_FORCED_GO) end
                    end
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
        print(string.format(" -> Camp [#%d] | State: %s | Members: %d | Pos: (%d, %d, %d)",
            camp.id, string.upper(camp.state), #camp.members, camp.pos.x, camp.pos.y, camp.pos.z))
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
        camp = VNPC_AssignPredatorToCamp(target)
    end
    if camp then
        camp.state = "foraging"
        target.VNPC_CampRole = "forager"
        ply:ChatPrint("[V-NPCs] Forced Camp #" .. camp.id .. " into FORAGING mode and set " .. tostring(target) .. " as FORAGER!")
    end
end)

concommand.Add("vnpcs_clear_camps", function(ply)
    local count = #VNPC_ActivePredatorCamps
    for _, pred in ipairs(ents.GetAll()) do
        pred.VNPC_CampID = nil
        pred.VNPC_CampRole = nil
        pred.VNPC_IsCarryingPreyForCamp = false
    end
    table.Empty(VNPC_ActivePredatorCamps)
    print("[V-NPCs] Cleared " .. count .. " predator camps from the map.")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Cleared " .. count .. " predator camps from the map.")
    end
end)

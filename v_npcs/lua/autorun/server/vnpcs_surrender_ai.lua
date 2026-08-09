-- V-NPCs AI Surrendering & Fattening System (vnpcs_surrender_ai.lua)
-- Defeated/surrendering female NPCs get fed prey with zero digestion, then are devoured by predators once they have eaten at least 2 prey.

CreateConVar("vnpcs_surrender_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable AI surrendering system where defeated female NPCs are fed prey before being eaten")
CreateConVar("vnpcs_surrender_hp_threshold", "35", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Health threshold below which an NPC will surrender to a predator")
CreateConVar("vnpcs_surrender_min_prey", "2", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Minimum prey a surrendered female must eat before the predator swallows her")

function VNPC_MakeSurrender(npc, pred)
    if not IsValid(npc) or npc.VNPC_Surrendered or npc.Vored or npc.VNPC_Vored then return false end
    if not npc:IsNPC() and not npc:IsNextBot() then return false end

    local enabled = GetConVar("vnpcs_surrender_enabled")
    if enabled and not enabled:GetBool() then return false end

    local belly = npc.VNPC_Belly or npc.Belly
    if not IsValid(belly) then
        -- Males or NPCs without a belly never surrender to get fed; they get eaten directly by the predator!
        return false
    end

    npc.VNPC_Surrendered = true
    npc.VNPC_SurrenderMaster = pred
    npc.VNPC_SurrenderFedCount = 0

    -- Stop hostile combat between surrendered NPC and predator
    if npc.SetEnemy then pcall(npc.SetEnemy, npc, nil) end
    if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_IDLE_STAND) end

    if IsValid(pred) then
        if npc.AddEntityRelationship then pcall(npc.AddEntityRelationship, npc, pred, D_LI, 99) end
        if pred.AddEntityRelationship then pcall(pred.AddEntityRelationship, pred, npc, D_LI, 99) end
        if pred.SetEnemy and pred:GetEnemy() == npc then pcall(pred.SetEnemy, pred, nil) end
    end

    -- TURN OFF DIGESTION so swallowed prey stay alive inside her without digestion
    belly.VNPC_NoDigestion = true
    belly.DigestionStrength = 0
    if belly.SetDigestionPower then
        belly:SetDigestionPower(0)
    end

    return true
end

-- Ensure digestion remains 0 on any surrendered female's belly
hook.Add("Think", "VNPC_Surrender_ZeroDigestion", function()
    local enabled = GetConVar("vnpcs_surrender_enabled")
    if enabled and not enabled:GetBool() then return end

    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) and npc.VNPC_Surrendered then
            local belly = npc.VNPC_Belly or npc.Belly
            if IsValid(belly) and belly.DigestionStrength ~= 0 then
                belly.VNPC_NoDigestion = true
                belly.DigestionStrength = 0
                if belly.SetDigestionPower then
                    belly:SetDigestionPower(0)
                end
            end
        end
    end
end)

-- Main AI Think loop for surrendering females to get fed prey, then get eaten once #Prey >= 2
hook.Add("Think", "VNPC_Surrender_AI_ThinkLoop", function()
    local enabled = GetConVar("vnpcs_surrender_enabled")
    if enabled and not enabled:GetBool() then return end

    local now = CurTime()
    local min_prey = GetConVar("vnpcs_surrender_min_prey"):GetInt() or 2

    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if not IsValid(npc) or not npc.VNPC_Surrendered or npc.Vored or npc.VNPC_Vored then continue end
        if (npc.VNPC_NextSurrenderThink or 0) > now then continue end
        npc.VNPC_NextSurrenderThink = now + 0.5

        local belly = npc.VNPC_Belly or npc.Belly
        local preyCount = IsValid(belly) and (belly.Prey and #belly.Prey or 0) or 0
        local pred = npc.VNPC_SurrenderMaster

        -- If master predator is dead or missing, find any nearby predator to become master
        if not IsValid(pred) or pred.Vored or pred.VNPC_Vored then
            for _, candidate in ipairs(ents.FindInSphere(npc:GetPos(), 1000)) do
                if IsValid(candidate) and candidate ~= npc and not candidate.VNPC_Surrendered and (candidate.IsDrGNextbot or candidate.VNPC_FemaleModelVore or candidate.Predator) then
                    npc.VNPC_SurrenderMaster = candidate
                    pred = candidate
                    break
                end
            end
        end

        if preyCount < min_prey then
            -- STATE 1: Surrendered female has eaten < 2 prey -> Feed her nearby prey with zero digestion!
            local fed = false
            for _, food in ipairs(ents.FindInSphere(npc:GetPos(), 500)) do
                if not IsValid(food) or food == npc or food == pred or food.VNPC_Surrendered or food.Vored or food.VNPC_Vored then continue end
                if not (food:IsPlayer() or food:IsNPC() or food:GetClass() == "prop_ragdoll" or food.VNPC_IsCorpse) then continue end

                local dist = npc:GetPos():Distance(food:GetPos())
                if dist <= 120 then
                    -- Swallow the food into her undigested belly
                    if npc.EatEntity and npc:EatEntity(food) then
                        fed = true
                        break
                    elseif IsValid(belly) and belly.AddPrey and belly:AddPrey(food) then
                        fed = true
                        break
                    end
                elseif dist <= 500 then
                    -- Chase toward prey to swallow them
                    if npc.SetEnemy then pcall(npc.SetEnemy, npc, food) end
                    if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_CHASE_ENEMY) end
                    break
                end
            end
        else
            -- STATE 2: Surrendered female has eaten at least 2 prey!
            -- She is plump and full -> Master predator swallows her alive!
            if IsValid(pred) then
                local dist = pred:GetPos():Distance(npc:GetPos())
                if dist <= 140 then
                    -- Reset relationship so predator can eat her
                    if pred.EatEntity then
                        pred:EatEntity(npc)
                    elseif IsValid(pred.VNPC_Belly or pred.Belly) then
                        local pBelly = pred.VNPC_Belly or pred.Belly
                        if pBelly.AddPrey then pBelly:AddPrey(npc) end
                    end
                else
                    -- Command predator to chase the plump surrendered female
                    if pred.SetEnemy then pcall(pred.SetEnemy, pred, npc) end
                    if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_CHASE_ENEMY) end
                end
            end
        end
    end
end)

concommand.Add("vnpcs_surrender_status", function(ply)
    print("===============================================================")
    print("           V-NPCs AI SURRENDERING SYSTEM STATUS                ")
    print("===============================================================")
    print(" - Surrender System Enabled: " .. tostring(GetConVar("vnpcs_surrender_enabled"):GetBool()))
    print(" - Surrender HP Threshold: " .. tostring(GetConVar("vnpcs_surrender_hp_threshold"):GetInt()) .. " HP")
    print(" - Minimum Prey Before Devouring: " .. tostring(GetConVar("vnpcs_surrender_min_prey"):GetInt()))
    local count = 0
    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) and npc.VNPC_Surrendered then
            count = count + 1
            local belly = npc.VNPC_Belly or npc.Belly
            local preyCount = IsValid(belly) and (belly.Prey and #belly.Prey or 0) or 0
            local predName = IsValid(npc.VNPC_SurrenderMaster) and (npc.VNPC_SurrenderMaster.PrintName or npc.VNPC_SurrenderMaster:GetClass()) or "NONE"
            print(string.format(" - Surrendered #%d [%s]: Eaten Prey = %d (Digestion = OFF) | Master Predator = %s", npc:EntIndex(), npc.PrintName or npc:GetClass(), preyCount, predName))
        end
    end
    if count == 0 then
        print(" - Active Surrendered NPCs: NONE currently spawned")
    end
    print("===============================================================")
end)

-- V-NPCs Full Belly Sleeping & Nap System (vnpcs_sleep_ai.lua)
-- Predators who remain in a full state outside of combat for long enough get tired and fall asleep using a modified full Bream Satel dif bone pose.

CreateConVar("vnpcs_sleep_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable full predators falling asleep after being full for a while")
CreateConVar("vnpcs_sleep_delay", "30", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Seconds a predator must be full outside of battle before falling asleep")

hook.Add("Think", "VNPCS_SleepSystem_Loop", function()
    local enabled = GetConVar("vnpcs_sleep_enabled")
    if enabled and not enabled:GetBool() then return end

    local now = CurTime()
    local delay = GetConVar("vnpcs_sleep_delay"):GetFloat() or 30

    for _, pred in ipairs(ents.FindByClass("npc_*")) do
        if not IsValid(pred) or pred.Vored or pred.VNPC_Vored then continue end
        if not (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) then continue end
        if (pred.VNPC_NextSleepThink or 0) > now then continue end
        pred.VNPC_NextSleepThink = now + 1.0

        local belly = pred.VNPC_Belly or pred.Belly
        local hasPrey = IsValid(belly) and ((belly.Prey and #belly.Prey > 0) or belly.DigestionPhase == 2 or (belly.BaseScale and belly.BaseScale >= 0.2) or hook.Run("VNPC_ShouldPredatorSleep", pred, belly))
        local inCombat = IsValid(pred:GetEnemy()) or (pred.IsMoving and pred:IsMoving())

        if not hasPrey or inCombat then
            -- Wake up immediately if enemy attacks or belly becomes empty
            if pred.VNPC_IsSleeping then
                pred.VNPC_IsSleeping = false
                if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_IDLE_STAND) end
            end
            pred.VNPC_FullStartTime = nil
            continue
        end

        if not pred.VNPC_FullStartTime then
            pred.VNPC_FullStartTime = now
        end

        local elapsed = now - pred.VNPC_FullStartTime
        if elapsed >= delay and not pred.VNPC_IsSleeping then
            pred.VNPC_IsSleeping = true
            if pred.SetEnemy then pcall(pred.SetEnemy, pred, nil) end
            if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_IDLE_STAND) end
        end
    end
end)

hook.Add("EntityTakeDamage", "VNPCS_SleepSystem_WakeOnDamage", function(ent, dmginfo)
    if IsValid(ent) and ent.VNPC_IsSleeping then
        ent.VNPC_IsSleeping = false
        ent.VNPC_FullStartTime = nil
        local attacker = dmginfo:GetAttacker()
        if IsValid(attacker) and ent.SetEnemy then
            pcall(ent.SetEnemy, ent, attacker)
        end
    end
end)

concommand.Add("vnpcs_sleep_status", function(ply)
    print("===============================================================")
    print("           V-NPCs FULL BELLY SLEEP SYSTEM STATUS               ")
    print("===============================================================")
    print(" - Sleep System Enabled: " .. tostring(GetConVar("vnpcs_sleep_enabled"):GetBool()))
    print(" - Sleep Delay Threshold: " .. tostring(GetConVar("vnpcs_sleep_delay"):GetFloat()) .. " sec")
    local count = 0
    for _, pred in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(pred) and (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) then
            count = count + 1
            local sleeping = pred.VNPC_IsSleeping and "SLEEPING (Bream Satel Sitting Pose)" or "AWAKE"
            local fullTime = pred.VNPC_FullStartTime and math.floor(CurTime() - pred.VNPC_FullStartTime) or 0
            print(string.format(" - Predator #%d [%s]: State = %s | Full Time = %d sec", pred:EntIndex(), pred.PrintName or pred:GetClass(), sleeping, fullTime))
        end
    end
    if count == 0 then
        print(" - Active Predators: NONE currently spawned")
    end
    print("===============================================================")
end)

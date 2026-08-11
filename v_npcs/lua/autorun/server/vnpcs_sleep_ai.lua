-- V-NPCs Universal Sleepiness & Camp Rest System (vnpcs_sleep_ai.lua)
-- Every female V-NPC predator and female citizen in Prey Camps tracks a Sleepiness bar (0-100%).
-- When sleepy (>= 80%), they retire to their camp tents/barricades or fort huts/buildings to rest and sleep safely.

CreateConVar("vnpcs_sleep_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable sleepiness bar and camp rest cycle for predators and prey camp females")
CreateConVar("vnpcs_sleep_thresh", "80.0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Sleepiness percentage required to fall asleep at camp")

function VNPC_IsSleepEligible(ent)
    if not IsValid(ent) or ent:Health() <= 0 or ent.Vored or ent.VNPC_Vored then return false end
    local isPred = (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator or (VNPC_IsFemaleModelNPC and VNPC_IsFemaleModelNPC(ent)))
    if isPred then return true, "predator" end
    if VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(ent) and ent.VNPC_PreyCampID then
        return true, "prey_female"
    end
    return false, nil
end

hook.Add("Think", "VNPCS_SleepSystem_Loop", function()
    local enabled = GetConVar("vnpcs_sleep_enabled")
    if enabled and not enabled:GetBool() then return end

    local now = CurTime()
    local thresh = GetConVar("vnpcs_sleep_thresh"):GetFloat() or 80.0

    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        local ok, role = VNPC_IsSleepEligible(ent)
        if not ok then continue end
        if (ent.VNPC_NextSleepThink or 0) > now then continue end
        ent.VNPC_NextSleepThink = now + 1.0

        local inCombat = IsValid(ent:GetEnemy()) or (ent.IsMoving and ent:IsMoving() and not ent.VNPC_IsReturningToCampToSleep)

        if ent.VNPC_IsSleeping then
            -- Drain sleepiness bar while sleeping
            ent.VNPC_Sleepiness = math.max(0, (ent.VNPC_Sleepiness or 80.0) - 3.5)

            if inCombat or ent.VNPC_Sleepiness <= 0.0 then
                -- Wake up refreshed or to defend!
                ent.VNPC_IsSleeping = false
                ent.VNPC_IsReturningToCampToSleep = nil
                if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_IDLE_STAND) end
            end
        else
            -- Increase sleepiness bar over time when awake
            ent.VNPC_Sleepiness = math.Clamp((ent.VNPC_Sleepiness or 0.0) + 0.35, 0, 100)

            if ent.VNPC_Sleepiness >= thresh and not inCombat then
                -- Seek safe shelter at camp before falling asleep
                local campPos = nil
                if role == "predator" and ent.VNPC_CampID and VNPC_GetPredatorCamp then
                    local pCamp = VNPC_GetPredatorCamp(ent)
                    if pCamp and pCamp.pos then campPos = pCamp.pos end
                elseif role == "prey_female" and ent.VNPC_PreyCampID and VNPC_GetPreyCamp then
                    local rCamp = VNPC_GetPreyCamp(ent)
                    if rCamp and rCamp.pos then campPos = rCamp.pos end
                end

                if campPos and ent:GetPos():DistToSqr(campPos) > (260 * 260) then
                    ent.VNPC_IsReturningToCampToSleep = true
                    if ent.SetLastPosition then pcall(ent.SetLastPosition, ent, campPos) end
                    if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_FORCED_GO_RUN) end
                else
                    ent.VNPC_IsSleeping = true
                    ent.VNPC_IsReturningToCampToSleep = nil
                    if ent.SetEnemy then pcall(ent.SetEnemy, ent, nil) end
                    if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_IDLE_STAND) end
                end
            end
        end
    end
end)

hook.Add("EntityTakeDamage", "VNPCS_SleepSystem_WakeOnDamage", function(ent, dmginfo)
    if IsValid(ent) and ent.VNPC_IsSleeping then
        ent.VNPC_IsSleeping = false
        ent.VNPC_Sleepiness = 0.0
        ent.VNPC_IsReturningToCampToSleep = nil
        local attacker = dmginfo:GetAttacker()
        if IsValid(attacker) and ent.SetEnemy then
            pcall(ent.SetEnemy, ent, attacker)
        end
    end
end)

concommand.Add("vnpcs_sleep_status", function(ply)
    print("===============================================================")
    print("      V-NPCs UNIVERSAL SLEEPINESS BAR & CAMP REST STATUS       ")
    print("===============================================================")
    print(" - Sleep System Enabled: " .. tostring(GetConVar("vnpcs_sleep_enabled"):GetBool()))
    print(" - Sleepiness Threshold: " .. tostring(GetConVar("vnpcs_sleep_thresh"):GetFloat()) .. "%")
    local count = 0
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        local ok, role = VNPC_IsSleepEligible(ent)
        if ok then
            count = count + 1
            local stateStr = ent.VNPC_IsSleeping and "SLEEPING (At Camp)" or (ent.VNPC_IsReturningToCampToSleep and "RETURNING TO CAMP TO SLEEP" or "AWAKE")
            print(string.format(" - [%s] #%d [%s]: State = %s | Sleepiness Bar = %.1f%%", string.upper(role), ent:EntIndex(), ent.PrintName or ent:GetClass(), stateStr, ent.VNPC_Sleepiness or 0))
        end
    end
    if count == 0 then
        print(" - Active Eligible Predators / Prey Females: NONE currently spawned")
    end
    print("===============================================================")
end)

concommand.Add("vnpcs_test_sleep_pred", function(ply)
    local count = 0
    for _, pred in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(pred) and (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) then
            pred.VNPC_Sleepiness = 95.0
            pred.VNPC_IsSleeping = true
            count = count + 1
        end
    end
    local msg = "[V-NPCs] Forced sleepiness bar to 95% on " .. count .. " predators! They are now resting."
    print(msg)
    if IsValid(ply) then ply:ChatPrint(msg) end
end)

concommand.Add("vnpcs_test_sleep_prey", function(ply)
    local count = 0
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(ent) and ent.VNPC_PreyCampID then
            ent.VNPC_Sleepiness = 95.0
            ent.VNPC_IsSleeping = true
            count = count + 1
        end
    end
    local msg = "[V-NPCs] Forced sleepiness bar to 95% on " .. count .. " prey camp females! They are now resting."
    print(msg)
    if IsValid(ply) then ply:ChatPrint(msg) end
end)

concommand.Add("vnpcs_test_wake_all", function(ply)
    local count = 0
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if ent.VNPC_IsSleeping then
            ent.VNPC_IsSleeping = false
            ent.VNPC_Sleepiness = 0.0
            ent.VNPC_IsReturningToCampToSleep = nil
            count = count + 1
        end
    end
    local msg = "[V-NPCs] Woke up " .. count .. " sleeping predators and prey camp females!"
    print(msg)
    if IsValid(ply) then ply:ChatPrint(msg) end
end)

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
        -- Secret assassins stay awake on mission (undercover / night raid / escape).
        if ent.VNPC_IsSecretAssassin then continue end
        if (ent.VNPC_NextSleepThink or 0) > now then continue end
        ent.VNPC_NextSleepThink = now + 1.0

        local inCombat = IsValid(VNPC_GetEntityEnemy and VNPC_GetEntityEnemy(ent) or nil) or (ent.IsMoving and ent:IsMoving() and not ent.VNPC_IsReturningToCampToSleep)

        if ent.VNPC_IsSleeping then
            -- Drain sleepiness bar while sleeping and regenerate health from peaceful rest
            ent.VNPC_Sleepiness = math.max(0, (ent.VNPC_Sleepiness or 80.0) - 3.5)
            if ent.Health and ent.GetMaxHealth and ent:Health() < ent:GetMaxHealth() then
                ent:SetHealth(math.min(ent:GetMaxHealth(), ent:Health() + 2))
            end

            if inCombat or ent.VNPC_Sleepiness <= 0.0 then
                -- Wake up refreshed or to defend!
                ent.VNPC_IsSleeping = false
                ent.VNPC_IsReturningToCampToSleep = nil
                if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_IDLE_STAND) end
            end
        else
            -- Increase sleepiness bar over time when awake (2x faster during StormFox 2 nighttime!)
            local sleepRate = (VNPC_IsStormFox2Night and VNPC_IsStormFox2Night()) and 0.70 or 0.35
            -- Activity span bias: diurnal sleeps more at night, nocturnal more by day, etc.
            if VNPC_GetActivitySpanData and VNPC_EnsureWelfare then
                VNPC_EnsureWelfare(ent)
                local act = VNPC_GetActivitySpanData(ent)
                local night = VNPC_IsStormFox2Night and VNPC_IsStormFox2Night()
                local bias = night and (act.sleepBiasNight or 0) or (act.sleepBiasDay or 0)
                sleepRate = math.max(0.05, sleepRate * (1.0 + bias))
                -- Off-peak also accelerates sleepiness slightly
                if VNPC_IsInActivePeriod and not VNPC_IsInActivePeriod(ent) then
                    sleepRate = sleepRate * 1.25
                end
            end
            -- Dormant sun baskers get very sleepy / sluggish
            if ent.VNPC_IsDormant then
                sleepRate = sleepRate * 1.5
            end
            ent.VNPC_Sleepiness = math.Clamp((ent.VNPC_Sleepiness or 0.0) + sleepRate, 0, 100)

            if ent.VNPC_Sleepiness >= 75.0 and (ent.VNPC_NextSleepYawnTime or 0) <= now then
                ent.VNPC_NextSleepYawnTime = now + 15.0
                if ent.EmitSound then
                    ent:EmitSound("npc/alyx/sigh01.wav", 75, math.random(88, 94))
                end
            end

            local effectiveThresh = (VNPC_IsStormFox2Night and VNPC_IsStormFox2Night()) and math.min(60.0, thresh) or thresh
            if ent.VNPC_IsDormant then
                effectiveThresh = math.min(effectiveThresh, 50.0)
            end
            if ent.VNPC_Sleepiness >= effectiveThresh and not inCombat then
                -- Seek safe shelter at camp before falling asleep
                local campPos = nil
                if role == "predator" and ent.VNPC_CampID and VNPC_GetPredatorCamp then
                    local pCamp = VNPC_GetPredatorCamp(ent)
                    if pCamp then
                        local hutList = pCamp.huts or pCamp.tents or {}
                        if #hutList > 0 then
                            campPos = (VNPC_GetHutInteriorPos and VNPC_GetHutInteriorPos(hutList[1])) or hutList[1].pos or pCamp.pos
                        else
                            campPos = pCamp.pos
                        end
                    end
                elseif role == "prey_female" and ent.VNPC_PreyCampID and VNPC_GetPreyCamp then
                    local rCamp = VNPC_GetPreyCamp(ent)
                    if rCamp then
                        if rCamp.huts and #rCamp.huts > 0 then
                            campPos = (VNPC_GetHutInteriorPos and VNPC_GetHutInteriorPos(rCamp.huts[1])) or rCamp.huts[1].pos or rCamp.pos
                        else
                            campPos = rCamp.pos
                        end
                    end
                end

                if campPos and ent:GetPos():DistToSqr(campPos) > (90 * 90) then
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
        local attacker = dmginfo:GetAttacker()
        if IsValid(attacker) and (attacker.VNPC_IsInfiltratingFort or (VNPC_IsAssassinNightHunting and VNPC_IsAssassinNightHunting(attacker))) then
            -- Infiltrating / night-raid assassin quietly swallowing sleeping prey — do not wake the victim.
            return
        end
        ent.VNPC_IsSleeping = false
        ent.VNPC_Sleepiness = 0.0
        ent.VNPC_IsReturningToCampToSleep = nil
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

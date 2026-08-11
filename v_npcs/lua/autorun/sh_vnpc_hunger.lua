-- V-NPCs Universal Hunger System (sh_vnpc_hunger.lua)
-- Gives every predator NPC dynamic hunger that increases swallowing appetite without ever killing or damaging them.

CreateConVar("vnpcs_hunger_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable dynamic hunger system for V-NPC predators (does not damage health)")
CreateConVar("vnpcs_hunger_rate", "1.5", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "How fast hunger increases per second when belly is empty (0 to 100 scale)")
CreateConVar("vnpcs_hunger_max_mult", "3.0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Maximum multiplier applied to sight range and swallowing desire when starving")
CreateConVar("vnpcs_thirst_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable dynamic thirst and water drinking for predators")
CreateConVar("vnpcs_thirst_rate", "0.6", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "How fast thirst increases per second (0 to 100 scale)")

function VNPC_GetThirst(ent)
    if not IsValid(ent) then return 0 end
    if not ent.VNPC_Thirst then
        ent.VNPC_Thirst = math.random(30, 50) -- Start moderately thirsty
    end
    return ent.VNPC_Thirst
end

function VNPC_SetThirst(ent, val)
    if not IsValid(ent) then return end
    ent.VNPC_Thirst = math.Clamp(val or 50, 0, 100)
    if SERVER and ent.SetNWFloat then
        ent:SetNWFloat("VNPC_Thirst", ent.VNPC_Thirst)
    end
end

function VNPC_FindRecognizedWaterSource(pred)
    if not IsValid(pred) then return nil end
    local myPos = pred:GetPos()

    if pred.VNPC_RememberedWaterSource and myPos:DistToSqr(pred.VNPC_RememberedWaterSource) < (4000 * 4000) then
        return pred.VNPC_RememberedWaterSource
    end

    -- 1. Check Predator Camp water source barrel / boiler
    if pred.VNPC_CampID and VNPC_GetPredatorCamp then
        local camp = VNPC_GetPredatorCamp(pred)
        if camp and IsValid(camp.watersource) then
            pred.VNPC_RememberedWaterSource = camp.watersource:GetPos()
            return pred.VNPC_RememberedWaterSource
        end
    end

    -- 2. Check water props / dispensers / barrels within range
    local bestPos = nil
    local bestDistSqr = 2500 * 2500
    for _, ent in ipairs(ents.FindInSphere(myPos, 2500)) do
        if not IsValid(ent) or ent == pred then continue end
        local mdl = string.lower(ent:GetModel() or "")
        if mdl:find("boiler") or mdl:find("barrel") or mdl:find("fountain") or mdl:find("sink") or mdl:find("cooler") or mdl:find("oildrum") then
            local dSqr = myPos:DistToSqr(ent:GetPos())
            if dSqr <= bestDistSqr then
                bestPos = ent:GetPos()
                bestDistSqr = dSqr
            end
        end
    end
    if bestPos then
        pred.VNPC_RememberedWaterSource = bestPos
        return bestPos
    end

    -- 3. Check natural map water (rivers, lakes, ponds)
    for r = 200, 2400, 400 do
        for s = 1, 12 do
            local angle = math.rad((s - 1) * 30)
            local testPos = myPos + Vector(math.cos(angle) * r, math.sin(angle) * r, 10)
            if bit.band(util.PointContents(testPos), CONTENTS_WATER) ~= 0 then
                pred.VNPC_RememberedWaterSource = testPos
                return testPos
            end
        end
    end
    return nil
end

function VNPC_GetHunger(ent)
    if not IsValid(ent) then return 0 end
    if not ent.VNPC_Hunger then
        ent.VNPC_Hunger = 50 -- Start moderately hungry
    end
    return ent.VNPC_Hunger
end

function VNPC_SetHunger(ent, val)
    if not IsValid(ent) then return end
    ent.VNPC_Hunger = math.Clamp(val or 50, 0, 100)
    if SERVER and ent.SetNWFloat then
        ent:SetNWFloat("VNPC_Hunger", ent.VNPC_Hunger)
    end
end

function VNPC_FeedHunger(ent, amount)
    if not IsValid(ent) then return end
    local current = VNPC_GetHunger(ent)
    VNPC_SetHunger(ent, current - (amount or 40))
end

function VNPC_GetHungerMultiplier(ent)
    if not IsValid(ent) then return 1.0 end
    local enabled = GetConVar("vnpcs_hunger_enabled")
    if enabled and not enabled:GetBool() then return 1.0 end

    local hunger = VNPC_GetHunger(ent)
    local max_mult = GetConVar("vnpcs_hunger_max_mult")
    local max_val = max_mult and max_mult:GetFloat() or 3.0
    return 1.0 + (hunger / 100.0) * (max_val - 1.0)
end

if SERVER then
    local nextHungerUpdate = 0
    hook.Add("Think", "VNPCS_Hunger_UpdateLoop", function()
        local now = CurTime()
        if now < nextHungerUpdate then return end
        nextHungerUpdate = now + 1.0

        local enabled = GetConVar("vnpcs_hunger_enabled")
        if enabled and not enabled:GetBool() then return end

        local rate = GetConVar("vnpcs_hunger_rate")
        local incRate = rate and rate:GetFloat() or 1.5

        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator or ent.EatEntity) then
                if ent:IsPlayer() then continue end
                local belly = ent.VNPC_Belly or ent.Belly or ent.belly
                local hasPrey = IsValid(belly) and (belly.DigestionPhase ~= 0 or (belly.Prey and #belly.Prey > 0))
                local cur = VNPC_GetHunger(ent)

                if hasPrey then
                    -- Smoothly satisfy hunger while digesting prey
                    VNPC_SetHunger(ent, cur - 3.0)
                else
                    -- Hunger grows over time when empty, increasing swallowing desire
                    VNPC_SetHunger(ent, cur + incRate)
                end

                -- Dynamically boost sight range and hunt willingness based on hunger
                if ent.SightRange and not ent.VNPC_BaseSightRange then
                    ent.VNPC_BaseSightRange = ent.SightRange
                end
                if ent.VNPC_BaseSightRange then
                    ent.SightRange = ent.VNPC_BaseSightRange * VNPC_GetHungerMultiplier(ent)
                end

                -- Thirst & Water Drinking Engine: dynamically expand belly as they drink water
                if GetConVar("vnpcs_thirst_enabled"):GetBool() and not ent.VNPC_IsSleeping and not IsValid(ent:GetEnemy()) then
                    local curThirst = VNPC_GetThirst(ent)
                    if ent.VNPC_IsDrinkingWater then
                        ent.VNPC_WaterDrank = (ent.VNPC_WaterDrank or 0) + 6.0
                        VNPC_SetThirst(ent, math.max(0, curThirst - 8.0))
                        if IsValid(belly) and belly.SetBellySize then
                            belly.VNPC_WaterWeight = ent.VNPC_WaterDrank
                            belly:SetBellySize()
                        end
                        if ent.EmitSound then
                            ent:EmitSound("gulps/g" .. math.random(1, 10) .. ".wav", 80, math.random(95, 105))
                        end
                        if curThirst <= 0 or (ent.VNPC_WaterDrank or 0) >= (ent.VNPC_TargetWaterAmount or 60.0) then
                            ent.VNPC_IsDrinkingWater = false
                            if ent.SetNWBool then ent:SetNWBool("VNPC_IsDrinkingWater", false) end
                            ent.VNPC_TargetWaterAmount = nil
                            if ent.EmitSound then ent:EmitSound("npc/alyx/sigh01.wav", 80, 105) end
                            if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_IDLE_STAND) end
                        end
                    else
                        local thirstRate = GetConVar("vnpcs_thirst_rate"):GetFloat() or 0.6
                        VNPC_SetThirst(ent, curThirst + thirstRate)
                        if IsValid(belly) and belly.VNPC_WaterWeight and belly.VNPC_WaterWeight > 0 then
                            belly.VNPC_WaterWeight = math.max(0, belly.VNPC_WaterWeight - 0.5)
                            if belly.SetBellySize then belly:SetBellySize() end
                        end

                        if curThirst >= 75.0 then
                            local waterPos = VNPC_FindRecognizedWaterSource(ent)
                            if waterPos then
                                local dSqr = ent:GetPos():DistToSqr(waterPos)
                                if dSqr > (130 * 130) then
                                    if ent.SetLastPosition then pcall(ent.SetLastPosition, ent, waterPos) end
                                    if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_FORCED_GO_RUN) end
                                else
                                    ent.VNPC_IsDrinkingWater = true
                                    if ent.SetNWBool then ent:SetNWBool("VNPC_IsDrinkingWater", true) end
                                    ent.VNPC_TargetWaterAmount = math.Clamp(curThirst * 0.85, 30.0, 85.0)
                                    if ent.SetEnemy then pcall(ent.SetEnemy, ent, nil) end
                                    if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_IDLE_STAND) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

concommand.Add("vnpcs_hunger_status", function(ply)
    print("===============================================================")
    print("           V-NPCs DYNAMIC HUNGER SYSTEM STATUS                 ")
    print("===============================================================")
    print(" - Hunger System Enabled: " .. tostring(GetConVar("vnpcs_hunger_enabled"):GetBool()))
    print(" - Hunger Growth Rate: " .. tostring(GetConVar("vnpcs_hunger_rate"):GetFloat()) .. " / sec")
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) and not ent:IsPlayer() then
            count = count + 1
            local hunger = VNPC_GetHunger(ent)
            local mult = VNPC_GetHungerMultiplier(ent)
            print(string.format(" - Predator #%d [%s]: Hunger = %.1f%% (Sight/Hunt Multiplier = %.2fx)", ent:EntIndex(), ent.PrintName or ent:GetClass(), hunger, mult))
        end
    end
    if count == 0 then
        print(" - Active Predators: NONE currently spawned")
    end
    print("===============================================================")
end)

concommand.Add("vnpcs_thirst_status", function(ply)
    print("===============================================================")
    print("      V-NPCs DYNAMIC THIRST & WATER DRINKING SYSTEM STATUS     ")
    print("===============================================================")
    print(" - Thirst System Enabled: " .. tostring(GetConVar("vnpcs_thirst_enabled"):GetBool()))
    print(" - Thirst Growth Rate: " .. tostring(GetConVar("vnpcs_thirst_rate"):GetFloat()) .. " / sec")
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) and not ent:IsPlayer() then
            count = count + 1
            local thirst = VNPC_GetThirst(ent)
            local stateStr = ent.VNPC_IsDrinkingWater and "DRINKING WATER (Scaled Belly Expansion)" or "SEEKING WATER/AWAKE"
            print(string.format(" - Predator #%d [%s]: Thirst = %.1f%% | State = %s | Water Drank = %.1f", ent:EntIndex(), ent.PrintName or ent:GetClass(), thirst, stateStr, ent.VNPC_WaterDrank or 0))
        end
    end
    if count == 0 then
        print(" - Active Predators: NONE currently spawned")
    end
    print("===============================================================")
end)

CreateConVar("vnpcs_pred_xp_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable predator experience (XP) and leveling system")
CreateConVar("vnpcs_pred_xp_mult", "1.0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Experience points multiplier for predator actions")

function VNPC_GetXPForLevel(level)
    local lvl = math.max(1, tonumber(level) or 1)
    return math.floor(100 * (lvl ^ 1.5))
end

function VNPC_GetPredatorLevel(pred)
    if not IsValid(pred) then return 1 end
    if not pred.VNPC_Level then pred.VNPC_Level = 1 end
    return pred.VNPC_Level
end

function VNPC_GetPredatorXP(pred)
    if not IsValid(pred) then return 0 end
    if not pred.VNPC_XP then pred.VNPC_XP = 0 end
    return pred.VNPC_XP
end

function VNPC_PredatorLevelUp(pred)
    if not IsValid(pred) then return end
    pred.VNPC_Level = (pred.VNPC_Level or 1) + 1
    pred.VNPC_NextLevelXP = VNPC_GetXPForLevel(pred.VNPC_Level)

    if SERVER then
        -- 1. Increase Max Health and heal
        local baseMaxHP = pred.VNPC_BaseMaxHealth or pred:GetMaxHealth() or 100
        pred.VNPC_BaseMaxHealth = baseMaxHP
        local newMaxHP = baseMaxHP + (pred.VNPC_Level - 1) * 15
        pred:SetMaxHealth(newMaxHP)
        pred:SetHealth(newMaxHP)

        -- 2. Increase Digestion Strength
        if pred.VoreSettings then
            local baseDig = pred.VoreSettings.BaseDigestionStrength or pred.VoreSettings.DigestionStrength or 2.0
            pred.VoreSettings.BaseDigestionStrength = baseDig
            pred.VoreSettings.DigestionStrength = baseDig + (pred.VNPC_Level - 1) * 0.25
        end

        -- 3. Increase Belly Capacity
        local belly = pred.VNPC_Belly or pred.Belly or pred.belly
        if IsValid(belly) then
            belly.VNPC_LevelCapacityBonus = math.floor((pred.VNPC_Level - 1) * 0.5)
        end

        if pred.EmitSound then
            pred:EmitSound("belly/snd_digeststart.wav", 85, math.Clamp(100 + pred.VNPC_Level * 2, 100, 130))
        end

        print("[V-NPCs] Predator Level Up: Predator " .. tostring(pred) .. " reached LEVEL " .. pred.VNPC_Level .. "! (MaxHP: " .. newMaxHP .. ", XP for Next: " .. pred.VNPC_NextLevelXP .. ")")
        hook.Run("VNPC_OnPredatorLevelUp", pred, pred.VNPC_Level)
    end

    if pred.SetNWInt then
        pred:SetNWInt("VNPC_Level", pred.VNPC_Level)
        pred:SetNWInt("VNPC_XP", pred.VNPC_XP)
    end
end

function VNPC_AddPredatorXP(pred, amount, reason)
    if not IsValid(pred) then return end
    local enabled = GetConVar("vnpcs_pred_xp_enabled")
    if enabled and not enabled:GetBool() then return end

    local mult = GetConVar("vnpcs_pred_xp_mult") and GetConVar("vnpcs_pred_xp_mult"):GetFloat() or 1.0
    local gained = math.floor((tonumber(amount) or 0) * mult)
    if gained <= 0 then return end

    pred.VNPC_XP = (pred.VNPC_XP or 0) + gained
    pred.VNPC_NextLevelXP = pred.VNPC_NextLevelXP or VNPC_GetXPForLevel(pred.VNPC_Level or 1)

    while pred.VNPC_XP >= pred.VNPC_NextLevelXP and (pred.VNPC_Level or 1) < 100 do
        pred.VNPC_XP = pred.VNPC_XP - pred.VNPC_NextLevelXP
        VNPC_PredatorLevelUp(pred)
    end

    if pred.SetNWInt then
        pred:SetNWInt("VNPC_XP", pred.VNPC_XP)
        pred:SetNWInt("VNPC_Level", pred.VNPC_Level or 1)
    end
end

concommand.Add("vnpcs_pred_xp_status", function(ply)
    print("===============================================================")
    print("         V-NPCs PREDATOR EXPERIENCE & LEVELING STATUS          ")
    print("===============================================================")
    print(" - XP System Enabled: " .. tostring(GetConVar("vnpcs_pred_xp_enabled"):GetBool()))
    print(" - XP Multiplier: " .. tostring(GetConVar("vnpcs_pred_xp_mult"):GetFloat()) .. "x")
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) and not ent:IsPlayer() then
            count = count + 1
            local lvl = VNPC_GetPredatorLevel(ent)
            local xp = VNPC_GetPredatorXP(ent)
            local nextXP = ent.VNPC_NextLevelXP or VNPC_GetXPForLevel(lvl)
            print(string.format(" - Predator #%d [%s]: Level %d | XP = %d / %d | MaxHP = %d", ent:EntIndex(), ent.PrintName or ent:GetClass(), lvl, xp, nextXP, ent:GetMaxHealth()))
        end
    end
    if count == 0 then
        print(" - Active Predators: NONE currently spawned")
    end
    print("===============================================================")
end)

concommand.Add("vnpcs_test_add_xp", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        local count = 0
        for _, pred in ipairs(ents.GetAll()) do
            if IsValid(pred) and (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) and not pred:IsPlayer() then
                VNPC_AddPredatorXP(pred, 250, "vnpcs_test_add_xp command")
                count = count + 1
            end
        end
        ply:ChatPrint("[V-NPCs] Added +250 XP to all " .. count .. " active predators!")
        return
    end
    VNPC_AddPredatorXP(target, 250, "vnpcs_test_add_xp command")
    ply:ChatPrint("[V-NPCs] Added +250 XP to predator " .. tostring(target) .. "! Level: " .. VNPC_GetPredatorLevel(target))
end)

concommand.Add("vnpcs_test_level_up", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        local count = 0
        for _, pred in ipairs(ents.GetAll()) do
            if IsValid(pred) and (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) and not pred:IsPlayer() then
                VNPC_PredatorLevelUp(pred)
                count = count + 1
            end
        end
        ply:ChatPrint("[V-NPCs] Leveled up all " .. count .. " active predators!")
        return
    end
    VNPC_PredatorLevelUp(target)
    ply:ChatPrint("[V-NPCs] Leveled up predator " .. tostring(target) .. " to Level " .. VNPC_GetPredatorLevel(target) .. "!")
end)

concommand.Add("vnpcs_test_set_level", function(ply, cmd, args)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a predator NPC to set their level!")
        return
    end
    local targetLevel = math.Clamp(tonumber(args[1]) or 20, 1, 100)
    target.VNPC_Level = targetLevel - 1
    target.VNPC_XP = 0
    VNPC_PredatorLevelUp(target)
    ply:ChatPrint("[V-NPCs] Set predator " .. tostring(target) .. " to Level " .. targetLevel .. "!")
end)

concommand.Add("vnpcs_stormfox2_status", function(ply)
    print("===============================================================")
    print("        V-NPCs STORMFOX 2 ENVIRONMENTAL INTEGRATION STATUS     ")
    print("===============================================================")
    print(" - StormFox 2 Integration Enabled: " .. tostring(GetConVar("vnpcs_stormfox2_enabled"):GetBool()))
    print(" - StormFox 2 Addon Installed: " .. tostring(VNPC_IsStormFox2Present()))
    print(" - Currently Raining / Storming: " .. tostring(VNPC_IsStormFox2Raining()) .. " (Rain = Outdoor Ground is Water Source)")
    print(" - Currently Nighttime: " .. tostring(VNPC_IsStormFox2Night()) .. " (Night = 2x Sleepiness Growth, 60% Sleep Thresh)")
    print(" - Current Outdoor Temperature: " .. string.format("%.1f C", VNPC_GetStormFox2Temperature()))
    print(" - Dynamic Thirst Growth Multiplier: " .. string.format("%.2fx", VNPC_GetStormFox2ThirstMultiplier()) .. " (Hot Weather > 28C = 1.50x)")
    print(" - Dynamic Hunger Growth Multiplier: " .. string.format("%.2fx", VNPC_GetStormFox2HungerMultiplier()) .. " (Freezing Weather < 5C = 1.35x)")
    print(" - Wild Ecology Spawn Capacity Multiplier: " .. string.format("%.2fx", VNPC_GetStormFox2EcologyMultiplier()) .. " (Rain = 0.75x, Night = 0.85x)")
    print("===============================================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] StormFox 2 environmental integration status printed to console.")
    end
end)

concommand.Add("vnpcs_test_stormfox2_rain", function(ply, cmd, args)
    local state = string.lower(args[1] or "rain")
    if state == "off" or state == "0" or state == "clear" then
        VNPC_SimulatedStormFox2Weather = "clear"
        ply:ChatPrint("[V-NPCs] Set simulated StormFox 2 weather to: CLEAR")
    else
        VNPC_SimulatedStormFox2Weather = "rain"
        ply:ChatPrint("[V-NPCs] Set simulated StormFox 2 weather to: RAIN (All outdoor ground is now a water source for thirsty predators!)")
    end
end)

concommand.Add("vnpcs_test_stormfox2_night", function(ply, cmd, args)
    local state = string.lower(args[1] or "night")
    if state == "off" or state == "0" or state == "day" then
        VNPC_SimulatedStormFox2Time = "day"
        ply:ChatPrint("[V-NPCs] Set simulated StormFox 2 time of day to: DAY")
    else
        VNPC_SimulatedStormFox2Time = "night"
        ply:ChatPrint("[V-NPCs] Set simulated StormFox 2 time of day to: NIGHT (Predators & citizens get sleepy faster and sleep through the night!)")
    end
end)

concommand.Add("vnpcs_test_stormfox2_temp", function(ply, cmd, args)
    local temp = tonumber(args[1]) or 20.0
    VNPC_SimulatedStormFox2Temp = temp
    ply:ChatPrint("[V-NPCs] Set simulated StormFox 2 outdoor temperature to: " .. temp .. " C")
end)

-- V-NPCs Universal Hunger System (sh_vnpc_hunger.lua)
-- Gives every predator NPC dynamic hunger that increases swallowing appetite without ever killing or damaging them.

CreateConVar("vnpcs_hunger_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable dynamic hunger system for V-NPC predators (does not damage health)")
CreateConVar("vnpcs_hunger_rate", "1.5", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "How fast hunger increases per second when belly is empty (0 to 100 scale)")
CreateConVar("vnpcs_hunger_max_mult", "3.0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Maximum multiplier applied to sight range and swallowing desire when starving")
CreateConVar("vnpcs_thirst_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable dynamic thirst and water drinking for predators")
CreateConVar("vnpcs_thirst_rate", "0.6", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "How fast thirst increases per second (0 to 100 scale)")
CreateConVar("vnpcs_prey_hunger_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable dynamic hunger system for prey NPCs")
CreateConVar("vnpcs_prey_hunger_rate", "0.8", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "How fast hunger increases per second for prey NPCs (0 to 100 scale)")
CreateConVar("vnpcs_prey_thirst_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable dynamic thirst system for prey NPCs")
CreateConVar("vnpcs_prey_thirst_rate", "0.5", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "How fast thirst increases per second for prey NPCs (0 to 100 scale)")
CreateConVar("vnpcs_stormfox2_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable StormFox 2 weather, time-of-day, and temperature compatibility")

VNPC_SimulatedStormFox2Weather = VNPC_SimulatedStormFox2Weather or "clear"
VNPC_SimulatedStormFox2Time = VNPC_SimulatedStormFox2Time or "day"
VNPC_SimulatedStormFox2Temp = VNPC_SimulatedStormFox2Temp or 20.0

function VNPC_IsStormFox2Present()
    return (StormFox2 ~= nil) or (StormFox ~= nil)
end

function VNPC_IsStormFox2Raining()
    local enabled = GetConVar("vnpcs_stormfox2_enabled")
    if enabled and not enabled:GetBool() then return false end
    if VNPC_SimulatedStormFox2Weather == "rain" or VNPC_SimulatedStormFox2Weather == "storm" then
        return true
    end
    if StormFox2 then
        if StormFox2.Weather and StormFox2.Weather.IsRaining and StormFox2.Weather.IsRaining() then
            return true
        end
        if StormFox2.Weather and StormFox2.Weather.GetCurrent then
            local w = StormFox2.Weather.GetCurrent()
            if w and (string.lower(w.Name or ""):find("rain") or string.lower(w.Name or ""):find("storm") or string.lower(w.Name or ""):find("thunder")) then
                return true
            end
        end
    elseif StormFox and StormFox.IsRaining and StormFox.IsRaining() then
        return true
    end
    return false
end

function VNPC_IsStormFox2Night()
    local enabled = GetConVar("vnpcs_stormfox2_enabled")
    if enabled and not enabled:GetBool() then return false end
    if VNPC_SimulatedStormFox2Time == "night" then
        return true
    end
    if StormFox2 and StormFox2.Time then
        if StormFox2.Time.IsNight and StormFox2.Time.IsNight() then
            return true
        end
        if StormFox2.Time.Get then
            local t = StormFox2.Time.Get()
            if t and (t >= 1200 or t < 360) then -- 20:00 to 06:00
                return true
            end
        end
    elseif StormFox and StormFox.IsNight and StormFox.IsNight() then
        return true
    end
    return false
end

function VNPC_GetStormFox2Temperature()
    local enabled = GetConVar("vnpcs_stormfox2_enabled")
    if enabled and not enabled:GetBool() then return 20.0 end
    if VNPC_SimulatedStormFox2Temp ~= 20.0 then
        return VNPC_SimulatedStormFox2Temp
    end
    if StormFox2 and StormFox2.Temperature and StormFox2.Temperature.Get then
        return StormFox2.Temperature.Get() or 20.0
    elseif StormFox and StormFox.GetTemperature then
        return StormFox.GetTemperature() or 20.0
    end
    return 20.0
end

function VNPC_GetStormFox2ThirstMultiplier()
    local temp = VNPC_GetStormFox2Temperature()
    if temp > 28.0 then
        return 1.5 -- Hot weather increases thirst by 50%
    end
    return 1.0
end

function VNPC_GetStormFox2HungerMultiplier()
    local temp = VNPC_GetStormFox2Temperature()
    if temp < 5.0 then
        return 1.35 -- Freezing/cold weather increases hunger by 35%
    end
    return 1.0
end

function VNPC_GetStormFox2EcologyMultiplier()
    if VNPC_IsStormFox2Raining() then
        return 0.75 -- Heavy rain/storm reduces active wilderness wanderer spawn rate
    end
    if VNPC_IsStormFox2Night() then
        return 0.85 -- Clear night slightly reduces active wanderer spawn rate
    end
    return 1.0
end

function VNPC_HasEnemy(ent)
    if not IsValid(ent) then return false end
    if ent.GetEnemy and pcall(ent.GetEnemy, ent) then
        local ok, enemy = pcall(ent.GetEnemy, ent)
        if ok and IsValid(enemy) then
            return true
        end
    end
    if ent.GetTarget and pcall(ent.GetTarget, ent) then
        local ok, target = pcall(ent.GetTarget, ent)
        if ok and IsValid(target) then
            return true
        end
    end
    return false
end

function VNPC_IsRunningToDestination(ent)
    if not IsValid(ent) then return false end
    if ent.IsMoving and not ent:IsMoving() then return false end
    if ent.GetSchedule and pcall(ent.GetSchedule, ent) then
        local ok, sched = pcall(ent.GetSchedule, ent)
        if ok and (sched == SCHED_FORCED_GO_RUN or sched == SCHED_CHASE_ENEMY) then
            return true
        end
    end
    if VNPC_HasEnemy(ent) then
        return true
    end
    if ent.GetVelocity and pcall(ent.GetVelocity, ent) then
        local ok, vel = pcall(ent.GetVelocity, ent)
        if ok and vel and vel:Length2DSqr() > (150 * 150) then
            return true
        end
    end
    return false
end

function VNPC_IsPreyNPC(ent)
    if not IsValid(ent) or ent:IsPlayer() or ent:Health() <= 0 then return false end
    if not (ent:IsNPC() or ent:IsNextBot()) then return false end
    if ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator or ent.EatEntity then return false end
    if ent.Vored or ent.VNPC_Vored or ent.VNPC_Surrendered then return false end
    local cls = string.lower(ent:GetClass() or "")
    if cls:find("citizen") or cls:find("rebel") or cls:find("refugee") or cls:find("alyx") or cls:find("mossman") or ent.VNPC_PreyCampID or (ent.Classify and ent:Classify() == CLASS_CITIZEN) then
        return true
    end
    return false
end

if SERVER then
    hook.Add("EntityTakeDamage", "VNPC_CampFire_NoDamage", function(target, dmginfo)
        if not IsValid(target) then return end
        if target.VNPC_PreyCampID or target.VNPC_CampID or target.VNPC_IsCitizenPrey or VNPC_IsPreyNPC(target) or target.VNPC_FemaleModelVore or target.IsDrGNextbot then
            if dmginfo:IsDamageType(DMG_BURN) or dmginfo:IsDamageType(DMG_SLOWBURN) then
                dmginfo:SetDamage(0)
                if target.Extinguish then pcall(target.Extinguish, target) end
                return true
            end
            local inf = dmginfo:GetInflictor()
            local att = dmginfo:GetAttacker()
            if (IsValid(inf) and (inf.VNPC_IsPreyCampFire or inf.VNPC_IsPredatorCampFire or inf:GetClass() == "entityflame" or string.find(string.lower(inf:GetClass()), "fire"))) or
               (IsValid(att) and (att.VNPC_IsPreyCampFire or att.VNPC_IsPredatorCampFire or att:GetClass() == "entityflame" or string.find(string.lower(att:GetClass()), "fire"))) then
                dmginfo:SetDamage(0)
                if target.Extinguish then pcall(target.Extinguish, target) end
                return true
            end
        end
    end)
end

VNPC_PreyCookedMealModels = VNPC_PreyCookedMealModels or {
    hotdog = {
        model = "models/food/hotdog.mdl",
        fallback = "models/props_junk/garbage_takeoutcarton001a.mdl",
        name = "Hotdog",
        type = "food",
        hungerRelief = 60.0,
        thirstRelief = 10.0,
        mealBellyWeight = 45.0
    },
    burger = {
        model = "models/food/burger.mdl",
        fallback = "models/props_junk/garbage_takeoutcarton001a.mdl",
        name = "Burger",
        type = "food",
        hungerRelief = 75.0,
        thirstRelief = 10.0,
        mealBellyWeight = 60.0
    },
    soda = {
        model = "models/props_junk/popcan01a.mdl",
        fallback = "models/props_junk/popcan01a.mdl",
        name = "Soda",
        type = "drink",
        hungerRelief = 15.0,
        thirstRelief = 75.0,
        mealBellyWeight = 50.0
    }
}

function VNPC_GetCookedMealModel(mealType)
    local data = VNPC_PreyCookedMealModels[mealType] or VNPC_PreyCookedMealModels.hotdog
    if util.IsValidModel(data.model) then
        return data.model
    end
    return data.fallback
end

function VNPC_GetPreyBellyAnchorBone(ent)
    if not IsValid(ent) then return 0 end
    local bones = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine2", "Spine", "Spine1"}
    for _, name in ipairs(bones) do
        local bone = ent:LookupBone(name)
        if bone and bone >= 0 then
            return bone
        end
    end
    return 0
end

function VNPC_EnsureFemalePreyBelly(ent)
    if not SERVER or not IsValid(ent) then return nil end
    if IsValid(ent.VNPC_Belly or ent.Belly) then
        return ent.VNPC_Belly or ent.Belly
    end

    local belly = ents.Create("ent_vore_belly")
    if not IsValid(belly) then return nil end

    ent.Belly_Angles = ent.Belly_Angles or Angle(0, 90, 90)
    ent.Belly_Offset = ent.Belly_Offset or (VNPC_GetFixedFemaleBellyOffset and VNPC_GetFixedFemaleBellyOffset(ent) or Vector(0, 3.5, 0))
    ent.BellyProperties = ent.BellyProperties or {
        BellyColor = Color(195,145,122),
        WeightGainAmount = 0.5,
        DigestionStrength = 3,
        AbsorptionPower = 2,
        MaxBaseSize = 0.5,
        FatFoldsMaxSize = 1
    }

    belly:SetPos(ent:GetPos())
    belly:SetParent(ent)
    belly:SetProperties(ent.BellyProperties, ent)
    belly:SetNPC(ent)
    belly:Spawn()
    belly:Activate()

    local spineBone = VNPC_GetPreyBellyAnchorBone(ent)
    belly:FollowBone(ent, spineBone)
    if not belly:GetParent() or belly:GetParent() ~= ent then
        belly:SetParent(ent)
    end
    belly:SetLocalAngles(ent.Belly_Angles)
    belly:SetLocalPos(ent.Belly_Offset)
    if belly.SetBellySize then
        belly:SetBellySize()
    end

    ent.VNPC_Belly = belly
    ent.Belly = belly
    if ent.SetNWEntity then
        ent:SetNWEntity("Belly", belly)
    end
    return belly
end

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
                if GetConVar("vnpcs_thirst_enabled"):GetBool() and not ent.VNPC_IsSleeping and not VNPC_HasEnemy(ent) then
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

                -- 30-Second Monster Growth Tick: update and maintain monster scale
                if (now - (ent.VNPC_LastMonsterTickTime or now)) >= 30.0 and (ent.VNPC_MonsterGrowth or 0) > 0 then
                    ent.VNPC_LastMonsterTickTime = now
                    VNPC_PredatorMonsterGrowth(ent, 0)
                end
            elseif VNPC_IsPreyNPC(ent) then
                if GetConVar("vnpcs_prey_hunger_enabled"):GetBool() and not ent.VNPC_IsSleeping and not VNPC_HasEnemy(ent) and not ent.VNPC_IsEatingMeal then
                    local preyHungerRate = (GetConVar("vnpcs_prey_hunger_rate"):GetFloat() or 0.8) * VNPC_GetStormFox2HungerMultiplier()
                    VNPC_SetHunger(ent, VNPC_GetHunger(ent) + preyHungerRate)
                end
                if GetConVar("vnpcs_prey_thirst_enabled"):GetBool() and not ent.VNPC_IsSleeping and not VNPC_HasEnemy(ent) and not ent.VNPC_IsEatingMeal then
                    local preyThirstRate = (GetConVar("vnpcs_prey_thirst_rate"):GetFloat() or 0.5) * VNPC_GetStormFox2ThirstMultiplier()
                    VNPC_SetThirst(ent, VNPC_GetThirst(ent) + preyThirstRate)
                end

                if (ent.VNPC_FoodMealWeight or 0) > 0 then
                    ent.VNPC_FoodMealWeight = math.max(0, ent.VNPC_FoodMealWeight - 1.2)
                    if IsValid(ent.VNPC_Belly) then
                        ent.VNPC_Belly.VNPC_FoodMealWeight = ent.VNPC_FoodMealWeight
                        if ent.VNPC_Belly.SetBellySize then
                            ent.VNPC_Belly:SetBellySize()
                        end
                    end
                end

                if GetConVar("vnpcs_prey_stamina_enabled"):GetBool() then
                    local curStam = VNPC_GetPreyStamina(ent)
                    local isRunning = VNPC_IsRunningToDestination(ent)
                    if isRunning then
                        local newStam = math.max(0, curStam - 3.5)
                        VNPC_SetPreyStamina(ent, newStam)
                        if newStam <= 0 and not ent.VNPC_IsExhausted then
                            ent.VNPC_IsExhausted = true
                            if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_FORCED_GO) end
                            if ent.EmitSound and (ent.VNPC_NextExhaustSound or 0) <= now then
                                ent.VNPC_NextExhaustSound = now + 12.0
                                ent:EmitSound("npc/alyx/sigh01.wav", 75, math.random(90, 98))
                            end
                        end
                    else
                        local newStam = math.min(100, curStam + 2.5)
                        VNPC_SetPreyStamina(ent, newStam)
                        if newStam >= 30.0 then
                            ent.VNPC_IsExhausted = nil
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
    print(" - Predator Hunger Enabled: " .. tostring(GetConVar("vnpcs_hunger_enabled"):GetBool()) .. " | Rate: " .. tostring(GetConVar("vnpcs_hunger_rate"):GetFloat()) .. " / sec")
    print(" - Prey Hunger Enabled: " .. tostring(GetConVar("vnpcs_prey_hunger_enabled"):GetBool()) .. " | Rate: " .. tostring(GetConVar("vnpcs_prey_hunger_rate"):GetFloat()) .. " / sec")
    local predCount = 0
    local preyCount = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() then
            if ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator then
                predCount = predCount + 1
                local hunger = VNPC_GetHunger(ent)
                local mult = VNPC_GetHungerMultiplier(ent)
                print(string.format(" - Predator #%d [%s]: Hunger = %.1f%% (Sight/Hunt Multiplier = %.2fx)", ent:EntIndex(), ent.PrintName or ent:GetClass(), hunger, mult))
            elseif VNPC_IsPreyNPC(ent) then
                preyCount = preyCount + 1
                local hunger = VNPC_GetHunger(ent)
                local mealState = "NORMAL"
                if ent.VNPC_IsCookingMeal then
                    mealState = "COOKING " .. string.upper(ent.VNPC_CookingMealType or "MEAL")
                elseif ent.VNPC_IsEatingMeal then
                    if VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(ent) then
                        mealState = "SWALLOWING " .. string.upper(ent.VNPC_EatingMealType or "MEAL") .. " WHOLE (Belly Expanded)"
                    else
                        mealState = "CHEWING " .. string.upper(ent.VNPC_EatingMealType or "MEAL") .. " (No Belly Expansion)"
                    end
                elseif (ent.VNPC_FoodMealWeight or 0) > 0 then
                    mealState = string.format("DIGESTING SWALLOWED FOOD (Belly Expanded | Food Weight = %.1f)", ent.VNPC_FoodMealWeight)
                elseif hunger >= 60.0 then
                    mealState = "SEEKING COOKED PROP MEAL (Hungry)"
                end
                print(string.format(" - Prey #%d [%s]: Hunger = %.1f%% | Meal State = %s", ent:EntIndex(), ent.PrintName or ent:GetClass(), hunger, mealState))
            end
        end
    end
    if predCount == 0 and preyCount == 0 then
        print(" - Active Predators/Prey: NONE currently spawned")
    end
    print("===============================================================")
end)

concommand.Add("vnpcs_thirst_status", function(ply)
    print("===============================================================")
    print("      V-NPCs DYNAMIC THIRST & WATER DRINKING SYSTEM STATUS     ")
    print("===============================================================")
    print(" - Predator Thirst Enabled: " .. tostring(GetConVar("vnpcs_thirst_enabled"):GetBool()) .. " | Rate: " .. tostring(GetConVar("vnpcs_thirst_rate"):GetFloat()) .. " / sec")
    print(" - Prey Thirst Enabled: " .. tostring(GetConVar("vnpcs_prey_thirst_enabled"):GetBool()) .. " | Rate: " .. tostring(GetConVar("vnpcs_prey_thirst_rate"):GetFloat()) .. " / sec")
    local predCount = 0
    local preyCount = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() then
            if ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator then
                predCount = predCount + 1
                local thirst = VNPC_GetThirst(ent)
                local stateStr = ent.VNPC_IsDrinkingWater and "DRINKING WATER (Scaled Belly Expansion)" or "SEEKING WATER/AWAKE"
                print(string.format(" - Predator #%d [%s]: Thirst = %.1f%% | State = %s | Water Drank = %.1f", ent:EntIndex(), ent.PrintName or ent:GetClass(), thirst, stateStr, ent.VNPC_WaterDrank or 0))
            elseif VNPC_IsPreyNPC(ent) then
                preyCount = preyCount + 1
                local thirst = VNPC_GetThirst(ent)
                local stateStr = "NORMAL"
                if ent.VNPC_IsCookingMeal and ent.VNPC_CookingMealType == "soda" then
                    stateStr = "COOKING SODA"
                elseif ent.VNPC_IsEatingMeal and ent.VNPC_EatingMealType == "soda" then
                    if VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(ent) then
                        stateStr = "SWALLOWING SODA WHOLE (Belly Expanded)"
                    else
                        stateStr = "DRINKING SODA (No Belly Expansion)"
                    end
                elseif (ent.VNPC_FoodMealWeight or 0) > 0 then
                    stateStr = string.format("DIGESTING SWALLOWED SODA/MEAL (Belly Expanded | Food Weight = %.1f)", ent.VNPC_FoodMealWeight)
                elseif thirst >= 60.0 then
                    stateStr = "THIRSTY (Seeking Cooked Soda / Water)"
                end
                print(string.format(" - Prey #%d [%s]: Thirst = %.1f%% | State = %s", ent:EntIndex(), ent.PrintName or ent:GetClass(), thirst, stateStr))
            end
        end
    end
    if predCount == 0 and preyCount == 0 then
        print(" - Active Predators/Prey: NONE currently spawned")
    end
    print("===============================================================")
end)

concommand.Add("vnpcs_test_prey_hunger", function(ply)
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if VNPC_IsPreyNPC(ent) then
            VNPC_SetHunger(ent, 85.0)
            count = count + 1
        end
    end
    print("[V-NPCs] Set Hunger to 85.0% for " .. count .. " prey NPC(s).")
end)

concommand.Add("vnpcs_test_prey_thirst", function(ply)
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if VNPC_IsPreyNPC(ent) then
            VNPC_SetThirst(ent, 85.0)
            count = count + 1
        end
    end
    print("[V-NPCs] Set Thirst to 85.0% for " .. count .. " prey NPC(s).")
end)

concommand.Add("vnpcs_test_prey_cook_meal", function(ply, cmd, args)
    local mealType = string.lower(args[1] or "hotdog")
    if not VNPC_PreyCookedMealModels[mealType] then
        mealType = "hotdog"
    end
    local found = 0
    for _, ent in ipairs(ents.GetAll()) do
        if VNPC_IsPreyNPC(ent) and (VNPC_IsFemalePreyCitizen(ent) or string.lower(ent:GetModel() or ""):find("female") or string.lower(ent:GetModel() or ""):find("f_") or string.lower(ent:GetModel() or ""):find("alyx")) then
            ent.VNPC_ForceCookMeal = mealType
            VNPC_SetHunger(ent, 85.0)
            VNPC_SetThirst(ent, 85.0)
            found = found + 1
        end
    end
    print("[V-NPCs] Ordered " .. found .. " female citizen prey at prey camps to cook a prop meal (" .. string.upper(mealType) .. ").")
end)

concommand.Add("vnpcs_test_prey_swallow_meal", function(ply, cmd, args)
    local mealType = string.lower(args[1] or "burger")
    local mealData = VNPC_PreyCookedMealModels[mealType] or VNPC_PreyCookedMealModels.burger
    local found = 0
    for _, ent in ipairs(ents.GetAll()) do
        if VNPC_IsPreyNPC(ent) and (VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(ent) or string.lower(ent:GetModel() or ""):find("female") or string.lower(ent:GetModel() or ""):find("f_") or string.lower(ent:GetModel() or ""):find("alyx")) then
            VNPC_EnsureFemalePreyBelly(ent)
            ent.VNPC_NoBellyExpansionFromMeal = false
            ent.VNPC_FoodMealWeight = (ent.VNPC_FoodMealWeight or 0) + (mealData.mealBellyWeight or 60.0)
            if IsValid(ent.VNPC_Belly) then
                ent.VNPC_Belly.VNPC_FoodMealWeight = ent.VNPC_FoodMealWeight
                if ent.VNPC_Belly.SetBellySize then
                    ent.VNPC_Belly:SetBellySize()
                end
            end
            if ent.EmitSound then
                ent:EmitSound("gulps/g" .. math.random(1, 10) .. ".wav", 75, math.random(95, 105))
            end
            found = found + 1
            print(string.format("[V-NPCs] Test: Female Citizen Prey #%d swallowed a %s whole without chewing! Belly expanded! (Food Weight = %.1f)", ent:EntIndex(), string.upper(mealType), ent.VNPC_FoodMealWeight))
        end
    end
    print("[V-NPCs] Commanded " .. found .. " female citizen prey to swallow a " .. string.upper(mealType) .. " whole (Belly Expanded!).")
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

CreateConVar("vnpcs_prey_stamina_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable dynamic stamina bar for prey NPCs")

function VNPC_GetPreyStamina(ent)
    if not IsValid(ent) then return 100.0 end
    if not ent.VNPC_Stamina then
        ent.VNPC_Stamina = 100.0
    end
    return ent.VNPC_Stamina
end

function VNPC_SetPreyStamina(ent, val)
    if not IsValid(ent) then return end
    ent.VNPC_Stamina = math.Clamp(val or 100.0, 0.0, 100.0)
    if SERVER and ent.SetNWFloat then
        ent:SetNWFloat("VNPC_Stamina", ent.VNPC_Stamina)
    end
end

VNPC_LifeCycleGrowthStages = {
    { id = "hatchling",  minProgress = 0,   maxProgress = 24,  scale = 0.25, name = "Hatchling" },
    { id = "juvenile",   minProgress = 25,  maxProgress = 49,  scale = 0.45, name = "Juvenile" },
    { id = "adolescent", minProgress = 50,  maxProgress = 74,  scale = 0.65, name = "Adolescent" },
    { id = "subadult",   minProgress = 75,  maxProgress = 99,  scale = 0.85, name = "Subadult" },
    { id = "adult",      minProgress = 100, maxProgress = 149, scale = 1.00, name = "Adult" },
    { id = "elder",      minProgress = 150, maxProgress = 199, scale = 1.10, name = "Elder (10% Bigger)" },
    { id = "monster",    minProgress = 200, maxProgress = 999, scale = 1.20, name = "Monster (20% Bigger)" }
}

function VNPC_GetGrowthStageInfo(progress)
    local val = tonumber(progress) or 100
    for _, stage in ipairs(VNPC_LifeCycleGrowthStages) do
        if val >= stage.minProgress and val <= stage.maxProgress then
            return stage
        end
    end
    return VNPC_LifeCycleGrowthStages[5] -- Default Adult
end

function VNPC_GetGrowthStage(ent)
    if not IsValid(ent) then return "adult", VNPC_LifeCycleGrowthStages[5] end
    local progress = ent.VNPC_GrowthProgress or (ent.VNPC_IsGrowingBaby and 0 or 100)
    local info = VNPC_GetGrowthStageInfo(progress)
    return info.id, info
end

function VNPC_UpdateGrowthStageScale(ent)
    if not IsValid(ent) or ent:IsPlayer() then return end
    local progress = ent.VNPC_GrowthProgress or (ent.VNPC_IsGrowingBaby and 0 or 100)
    local stageID, stageInfo = VNPC_GetGrowthStage(ent)
    local oldStage = ent.VNPC_CurrentGrowthStage or stageID

    -- Smooth scale calculation within stage or exact stage scale
    local targetScale = stageInfo.scale
    if progress < 100 and stageID ~= "adult" then
        -- Interpolate smoothly from 0.25 to 1.00 for children (progress 0 to 100)
        targetScale = math.Clamp(0.25 + (progress / 100.0) * 0.75, 0.25, 1.00)
    elseif progress >= 100 then
        -- Exact stage scale: Adult = 1.00x, Elder = 1.10x, Monster = 1.20x
        targetScale = stageInfo.scale
    end

    ent:SetModelScale(targetScale, 1)
    ent.VNPC_CurrentGrowthStage = stageID
    ent.VNPC_MonsterScale = targetScale

    if progress >= 100 and ent.VNPC_IsGrowingBaby then
        ent.VNPC_IsGrowingBaby = nil
        ent.VNPC_ProtectedChild = nil
        if (ent.VNPC_AdoptedByPredator or ent.VNPC_BornSister) and VNPC_TransformToPredator then
            VNPC_TransformToPredator(ent, ent.VNPC_AdoptedByPredator or ent.VNPC_MotherRef)
            return
        end
    end

    if SERVER then
        if stageID == "elder" or stageID == "monster" then
            local baseHP = ent.VNPC_BaseMaxHealth or ent:GetMaxHealth() or 100
            ent.VNPC_BaseMaxHealth = baseHP
            local bonusHP = (stageID == "monster") and 150 or 75
            local newMax = baseHP + bonusHP
            ent:SetMaxHealth(newMax)
            if ent:Health() < newMax then
                ent:SetHealth(math.min(newMax, ent:Health() + 25))
            end
        end

        if oldStage ~= stageID then
            print("[V-NPCs] Growth Stage Advance: " .. tostring(ent) .. " reached the " .. string.upper(stageInfo.name) .. " stage (Scale: " .. string.format("%.2fx", targetScale) .. ")!")
            hook.Run("VNPC_OnGrowthStageAdvance", ent, stageID, targetScale)
        end
    end
end

function VNPC_AddGrowthProgress(ent, amount, reason)
    if not IsValid(ent) or ent:IsPlayer() then return end
    local current = ent.VNPC_GrowthProgress or (ent.VNPC_IsGrowingBaby and 0 or 100)
    ent.VNPC_GrowthProgress = math.Clamp(current + (tonumber(amount) or 0), 0, 250)
    VNPC_UpdateGrowthStageScale(ent)
    if reason and SERVER then
        local stageID, info = VNPC_GetGrowthStage(ent)
        print("[V-NPCs] Growth Progress: " .. tostring(ent) .. " gained +" .. tostring(amount) .. " growth (" .. reason .. ") -> Progress: " .. math.floor(ent.VNPC_GrowthProgress) .. " [" .. info.name .. "]")
    end
end

-- Backward compatibility wrapper for adult monster growth calls
function VNPC_PredatorMonsterGrowth(pred, count)
    if not IsValid(pred) or pred.VNPC_IsGrowingBaby or (pred:GetModelScale() or 1.0) < 0.95 then return end
    -- Adult absorbing prey gains +25 Growth Progress (from Adult 100 -> Elder 150 -> Monster 200)
    VNPC_AddGrowthProgress(pred, (tonumber(count) or 1) * 25.0, "Absorbed prey in stomach")
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
    print(" - Currently Raining / Storming: " .. tostring(VNPC_IsStormFox2Raining()) .. " (Rain = Citizens Seek Storm Shelter in Forts)")
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
        ply:ChatPrint("[V-NPCs] Set simulated StormFox 2 weather to: RAIN (Citizens now seek storm shelter inside fort huts/houses!)")
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

concommand.Add("vnpcs_prey_stamina_status", function(ply)
    print("===============================================================")
    print("          V-NPCs PREY STAMINA & EXHAUSTION STATUS              ")
    print("===============================================================")
    print(" - Stamina System Enabled: " .. tostring(GetConVar("vnpcs_prey_stamina_enabled"):GetBool()))
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and (ent:GetClass():find("citizen") or ent:GetClass():find("rebel") or ent:GetClass():find("refugee") or ent.VNPC_PreyCampID) then
            count = count + 1
            local stam = VNPC_GetPreyStamina(ent)
            local stateStr = ent.VNPC_IsExhausted and "EXHAUSTED (Sprinting Disabled)" or "READY"
            print(string.format(" - Prey #%d [%s]: Stamina = %.1f%% | State = %s", ent:EntIndex(), ent.PrintName or ent:GetClass(), stam, stateStr))
        end
    end
    if count == 0 then
        print(" - Active Prey Citizens: NONE currently spawned")
    end
    print("===============================================================")
end)

concommand.Add("vnpcs_test_prey_exhaust", function(ply)
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and (ent:GetClass():find("citizen") or ent:GetClass():find("rebel") or ent:GetClass():find("refugee") or ent.VNPC_PreyCampID) then
            VNPC_SetPreyStamina(ent, 0)
            ent.VNPC_IsExhausted = true
            count = count + 1
        end
    end
    local msg = "[V-NPCs] Forced stamina bar to 0% on " .. count .. " prey citizens! They are now exhausted."
    print(msg)
    if IsValid(ply) then ply:ChatPrint(msg) end
end)

concommand.Add("vnpcs_monster_growth_status", function(ply)
    print("===============================================================")
    print("         V-NPCs 7-STAGE LIFE-CYCLE GROWTH STAGE STATUS         ")
    print("===============================================================")
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator or ent.VNPC_IsGrowingBaby or ent.VNPC_PreyCampID) then
            count = count + 1
            local stageID, info = VNPC_GetGrowthStage(ent)
            local progress = ent.VNPC_GrowthProgress or (ent.VNPC_IsGrowingBaby and 0 or 100)
            local scale = ent:GetModelScale() or info.scale
            print(string.format(" - NPC #%d [%s]: Stage = %s (Scale: %.2fx) | Growth Progress = %.1f / 250", ent:EntIndex(), ent.PrintName or ent:GetClass(), string.upper(info.name), scale, progress))
        end
    end
    if count == 0 then
        print(" - Active Eligible Females / Predators: NONE currently spawned")
    end
    print("===============================================================")
end)

concommand.Add("vnpcs_test_monster_grow", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        local count = 0
        for _, pred in ipairs(ents.GetAll()) do
            if IsValid(pred) and (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) and not pred:IsPlayer() then
                VNPC_AddGrowthProgress(pred, 50.0, "vnpcs_test_monster_grow command")
                count = count + 1
            end
        end
        ply:ChatPrint("[V-NPCs] Added +50 Growth Progress to all " .. count .. " active predators!")
        return
    end
    VNPC_AddGrowthProgress(target, 50.0, "vnpcs_test_monster_grow command")
    local id, info = VNPC_GetGrowthStage(target)
    ply:ChatPrint("[V-NPCs] Added +50 Growth Progress to predator " .. tostring(target) .. "! Stage: " .. string.upper(info.name) .. " (" .. string.format("%.2fx", target:GetModelScale()) .. ")")
end)

concommand.Add("vnpcs_test_set_growth_stage", function(ply, cmd, args)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at an NPC to set their growth stage!")
        return
    end

    local stageName = string.lower(args[1] or "elder")
    local mapProg = {
        ["hatchling"] = 10,
        ["juvenile"] = 30,
        ["adolescent"] = 60,
        ["subadult"] = 80,
        ["adult"] = 110,
        ["elder"] = 160,
        ["monster"] = 210
    }
    local prog = mapProg[stageName] or 160
    target.VNPC_GrowthProgress = prog
    VNPC_UpdateGrowthStageScale(target)
    local id, info = VNPC_GetGrowthStage(target)
    ply:ChatPrint("[V-NPCs] Set " .. tostring(target) .. " to growth stage: " .. string.upper(info.name) .. " (Scale: " .. string.format("%.2fx", target:GetModelScale()) .. ")!")
end)

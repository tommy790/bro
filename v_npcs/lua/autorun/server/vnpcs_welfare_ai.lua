-- V-NPCs Welfare AI (vnpcs_welfare_ai.lua)
-- Ticks social / sun / cleanliness bars and drives seek-company, bask, clean, rest.

if not SERVER then return end

local function welfareEligible(ent)
    if not IsValid(ent) or ent:Health() <= 0 then return false end
    if ent.Vored or ent.VNPC_Vored then return false end
    if ent.VNPC_IsUnbornBaby or ent.VNPC_IsGrowingBaby or ent.VNPC_ProtectedChild then return false end
    if ent.VNPC_IsSecretAssassin and ent.VNPC_AssassinPhase ~= "night" then return false end
    if ent:IsPlayer() then return false end
    return (ent:IsNPC() or ent:IsNextBot() or ent.IsDrGNextbot or ent.Predator or ent.VNPC_FemaleModelVore
        or (VNPC_ShouldBePredator and VNPC_ShouldBePredator(ent))
        or (VNPC_ShouldBePrey and VNPC_ShouldBePrey(ent)))
end

local function moveTo(ent, pos, run)
    if not IsValid(ent) or not pos then return end
    if ent.SetLastPosition then pcall(ent.SetLastPosition, ent, pos) end
    if ent.SetSchedule then
        pcall(ent.SetSchedule, ent, run and SCHED_FORCED_GO_RUN or SCHED_FORCED_GO)
    end
end

local function isInWater(ent)
    if not IsValid(ent) then return false end
    if ent.WaterLevel and ent:WaterLevel() >= 1 then return true end
    local pos = ent:GetPos() + Vector(0, 0, 8)
    return bit.band(util.PointContents(pos), CONTENTS_WATER) ~= 0
end

local function groundMaterialHint(ent)
    if not IsValid(ent) then return "dirt" end
    local tr = util.TraceLine({
        start = ent:GetPos() + Vector(0, 0, 20),
        endpos = ent:GetPos() - Vector(0, 0, 80),
        mask = MASK_SOLID_BRUSHONLY,
        filter = ent,
    })
    if not tr.Hit then return "dirt" end
    local mat = string.lower(tostring(tr.MatType or ""))
    -- Source MAT_ enums sometimes come through as numbers
    local matNum = tonumber(tr.MatType)
    if matNum == MAT_MUD or mat:find("mud") then return "mud" end
    if matNum == MAT_SAND or mat:find("sand") then return "dust" end
    if matNum == MAT_DIRT or mat:find("dirt") then return "dust" end
    if matNum == MAT_GRASS then return "dust" end
    if isInWater(ent) then return "water" end
    -- Wet outdoors after rain leans mud
    if VNPC_IsStormFox2Raining and VNPC_IsStormFox2Raining() then
        return "mud"
    end
    return "dirt"
end

local function findWaterCleanSpot(ent)
    if VNPC_FindRecognizedWaterSource then
        local p = VNPC_FindRecognizedWaterSource(ent)
        if p then return p end
    end
    local myPos = ent:GetPos()
    for r = 150, 1800, 300 do
        for s = 1, 10 do
            local ang = math.rad((s - 1) * 36)
            local test = myPos + Vector(math.cos(ang) * r, math.sin(ang) * r, 12)
            if bit.band(util.PointContents(test), CONTENTS_WATER) ~= 0 then
                return test
            end
        end
    end
    return nil
end

local function findDustCleanSpot(ent)
    local myPos = ent:GetPos()
    -- Prefer open dry ground away from water
    for attempt = 1, 12 do
        local ang = math.rad(math.random(0, 359))
        local dist = math.random(80, 500)
        local cand = myPos + Vector(math.cos(ang) * dist, math.sin(ang) * dist, 40)
        local tr = util.TraceLine({
            start = cand,
            endpos = cand - Vector(0, 0, 120),
            mask = MASK_SOLID_BRUSHONLY,
        })
        if tr.Hit and tr.HitNormal.z > 0.7 then
            if bit.band(util.PointContents(tr.HitPos + Vector(0, 0, 4)), CONTENTS_WATER) == 0 then
                return tr.HitPos + Vector(0, 0, 2)
            end
        end
    end
    return myPos
end

local function findMudCleanSpot(ent)
    local myPos = ent:GetPos()
    -- Look for wet/low ground; after rain almost any dirt works
    if VNPC_IsStormFox2Raining and VNPC_IsStormFox2Raining() then
        return findDustCleanSpot(ent)
    end
    for attempt = 1, 14 do
        local ang = math.rad(math.random(0, 359))
        local dist = math.random(100, 700)
        local cand = myPos + Vector(math.cos(ang) * dist, math.sin(ang) * dist, 30)
        local tr = util.TraceLine({
            start = cand,
            endpos = cand - Vector(0, 0, 140),
            mask = MASK_SOLID_BRUSHONLY,
        })
        if not tr.Hit then continue end
        local nearWater = false
        for _, off in ipairs({ Vector(40, 0, 5), Vector(-40, 0, 5), Vector(0, 40, 5), Vector(0, -40, 5) }) do
            if bit.band(util.PointContents(tr.HitPos + off), CONTENTS_WATER) ~= 0 then
                nearWater = true
                break
            end
        end
        if nearWater or (tr.MatType == MAT_MUD) then
            return tr.HitPos + Vector(0, 0, 2)
        end
    end
    return findDustCleanSpot(ent)
end

local function findCleanSpot(ent, methodId)
    if methodId == "water" then
        return findWaterCleanSpot(ent)
    elseif methodId == "mud" then
        return findMudCleanSpot(ent)
    end
    return findDustCleanSpot(ent)
end

local function isAtPreferredCleanSpot(ent, methodId)
    if methodId == "water" then
        return isInWater(ent)
    end
    local hint = groundMaterialHint(ent)
    if methodId == "mud" then
        return hint == "mud" or (VNPC_IsStormFox2Raining and VNPC_IsStormFox2Raining() and hint ~= "water")
    end
    -- dust
    return hint == "dust" or hint == "dirt"
end

local function findSunBaskSpot(ent)
    local myPos = ent:GetPos()
    if VNPC_IsInDirectSunlight(ent) then return myPos end
    for attempt = 1, 16 do
        local ang = math.rad(math.random(0, 359))
        local dist = math.random(60, 600)
        local cand = myPos + Vector(math.cos(ang) * dist, math.sin(ang) * dist, 40)
        local tr = util.TraceLine({
            start = cand,
            endpos = cand - Vector(0, 0, 120),
            mask = MASK_SOLID_BRUSHONLY,
        })
        if not tr.Hit or tr.HitNormal.z < 0.7 then continue end
        local sky = util.TraceLine({
            start = tr.HitPos + Vector(0, 0, 48),
            endpos = tr.HitPos + Vector(0, 0, 2000),
            mask = MASK_SOLID_BRUSHONLY,
        })
        if sky.HitSky or not sky.Hit then
            return tr.HitPos + Vector(0, 0, 2)
        end
    end
    return nil
end

local function findCompanyTarget(ent)
    local myPos = ent:GetPos()
    local best, bestD = nil, 1600 * 1600
    local myCls = string.lower(ent:GetClass() or "")
    local myCamp = ent.VNPC_CampID
    local myPreyCamp = ent.VNPC_PreyCampID
    for _, other in ipairs(ents.FindInSphere(myPos, 1600)) do
        if not IsValid(other) or other == ent then continue end
        if other.Vored or other.VNPC_Vored or other.VNPC_IsSleeping then continue end
        local ok = false
        if myCamp and other.VNPC_CampID == myCamp then ok = true end
        if myPreyCamp and other.VNPC_PreyCampID == myPreyCamp then ok = true end
        if string.lower(other:GetClass() or "") == myCls then ok = true end
        if not ok then continue end
        local d = myPos:DistToSqr(other:GetPos())
        if d < bestD and d > (90 * 90) then
            bestD = d
            best = other
        end
    end
    return best
end

local function findAloneSpot(ent)
    local myPos = ent:GetPos()
    local bestPos, bestScore = nil, -1e9
    for attempt = 1, 14 do
        local ang = math.rad(math.random(0, 359))
        local dist = math.random(400, 1400)
        local cand = myPos + Vector(math.cos(ang) * dist, math.sin(ang) * dist, 40)
        local tr = util.TraceLine({
            start = cand,
            endpos = cand - Vector(0, 0, 160),
            mask = MASK_SOLID_BRUSHONLY,
        })
        if not tr.Hit or tr.HitNormal.z < 0.7 then continue end
        local nearby = 0
        for _, o in ipairs(ents.FindInSphere(tr.HitPos, 350)) do
            if IsValid(o) and o ~= ent and (o:IsNPC() or o:IsNextBot() or o.IsDrGNextbot) then
                nearby = nearby + 1
            end
        end
        local score = 10 - nearby * 3 + math.random() * 0.5
        if score > bestScore then
            bestScore = score
            bestPos = tr.HitPos + Vector(0, 0, 2)
        end
    end
    return bestPos
end

function VNPC_WelfareTickEntity(ent, dt)
    if not welfareEligible(ent) then return end
    local enabled = GetConVar("vnpcs_welfare_enabled")
    if enabled and not enabled:GetBool() then return end

    VNPC_EnsureWelfare(ent)
    dt = math.Clamp(dt or 1.0, 0.1, 3.0)
    local now = CurTime()

    local socialData = VNPC_GetSocialPrefData(ent)
    local actData = VNPC_GetActivitySpanData(ent)
    local cleanData = VNPC_GetCleaningMethodData(ent)
    local active = VNPC_IsInActivePeriod(ent)
    ent.VNPC_IsActivePeriod = active
    if ent.SetNWBool then ent:SetNWBool("VNPC_IsActivePeriod", active) end

    -- ---- Cleanliness drain / clean ----
    local dirtRate = (GetConVar("vnpcs_welfare_dirt_rate") and GetConVar("vnpcs_welfare_dirt_rate"):GetFloat()) or 0.35
    if not active then dirtRate = dirtRate * 0.45 end
    if ent.VNPC_IsCleaning then
        if isAtPreferredCleanSpot(ent, cleanData.id) then
            local gain = (cleanData.cleanRate or 10) * dt
            VNPC_SetCleanliness(ent, VNPC_GetCleanliness(ent) + gain)
            if VNPC_GetCleanliness(ent) >= 92 then
                ent.VNPC_IsCleaning = nil
                ent.VNPC_CleanTargetPos = nil
                if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_IDLE_STAND) end
            end
        else
            -- Still traveling to clean spot
            if ent.VNPC_CleanTargetPos then
                moveTo(ent, ent.VNPC_CleanTargetPos, true)
            end
        end
    else
        VNPC_SetCleanliness(ent, VNPC_GetCleanliness(ent) - dirtRate * dt)
    end

    -- ---- Social or Sun wellbeing ----
    local socialRate = (GetConVar("vnpcs_welfare_social_rate") and GetConVar("vnpcs_welfare_social_rate"):GetFloat()) or 0.55
    if ent.VNPC_UsesSunWellbeing then
        local sunRate = (GetConVar("vnpcs_welfare_sun_rate") and GetConVar("vnpcs_welfare_sun_rate"):GetFloat()) or 0.70
        if VNPC_IsInDirectSunlight(ent) then
            VNPC_SetSocialWelfare(ent, VNPC_GetSunWellbeing(ent) + sunRate * 2.2 * dt)
            ent.VNPC_IsBasking = true
        else
            VNPC_SetSocialWelfare(ent, VNPC_GetSunWellbeing(ent) - sunRate * dt)
            ent.VNPC_IsBasking = nil
        end
        local thresh = (GetConVar("vnpcs_welfare_dormant_thresh") and GetConVar("vnpcs_welfare_dormant_thresh"):GetFloat()) or 18
        local wasDormant = ent.VNPC_IsDormant
        ent.VNPC_IsDormant = VNPC_GetSunWellbeing(ent) < thresh
        if ent.SetNWBool then ent:SetNWBool("VNPC_IsDormant", ent.VNPC_IsDormant and true or false) end
        if ent.VNPC_IsDormant and not wasDormant then
            if ent.EmitSound then ent:EmitSound("npc/antlion/idle3.wav", 60, 80) end
        end
    else
        local nearby = VNPC_CountNearbySameSpecies(ent, 420)
        local delta = 0
        if socialData.seekCompany then
            if nearby <= 0 then
                delta = socialData.aloneBonus * socialRate * dt -- negative
            elseif nearby <= (socialData.maxComfortable or 8) then
                local ideal = socialData.idealCompany or 3
                local closeness = 1.0 - math.min(1, math.abs(nearby - ideal) / math.max(1, ideal))
                delta = (0.4 + closeness * 1.1) * socialRate * dt
            else
                delta = -socialData.crowdPenalty * socialRate * 0.5 * dt
            end
        else
            -- solitary
            if nearby <= 0 then
                delta = math.abs(socialData.aloneBonus or 0.8) * socialRate * dt
            else
                delta = -socialData.crowdPenalty * socialRate * nearby * 0.35 * dt
            end
        end
        VNPC_SetSocialWelfare(ent, VNPC_GetSocialWelfare(ent) + delta)
        ent.VNPC_NearbySameSpecies = nearby
    end

    -- ---- Drive behaviors (priority) ----
    if ent.VNPC_IsSleeping or ent.Swallowing or (VNPC_IsBusyMating and VNPC_IsBusyMating(ent)) then
        return
    end
    if ent.GetEnemy then
        local ok, en = pcall(ent.GetEnemy, ent)
        if ok and IsValid(en) then return end
    end

    local cleanThresh = (GetConVar("vnpcs_welfare_clean_thresh") and GetConVar("vnpcs_welfare_clean_thresh"):GetFloat()) or 35

    -- 1) Dormant sun baskers must bask
    if ent.VNPC_UsesSunWellbeing and (ent.VNPC_IsDormant or VNPC_GetSunWellbeing(ent) < 40) then
        if not VNPC_IsInDirectSunlight(ent) then
            if (ent.VNPC_NextBaskSeek or 0) <= now then
                ent.VNPC_NextBaskSeek = now + 4.0
                local spot = findSunBaskSpot(ent)
                if spot then
                    ent.VNPC_BaskTargetPos = spot
                    moveTo(ent, spot, true)
                end
            elseif ent.VNPC_BaskTargetPos then
                moveTo(ent, ent.VNPC_BaskTargetPos, false)
            end
        else
            if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_IDLE_STAND) end
        end
        return
    end

    -- 2) Cleaning when dirty
    if VNPC_GetCleanliness(ent) < cleanThresh and not ent.VNPC_IsCleaning then
        ent.VNPC_IsCleaning = true
        ent.VNPC_CleanTargetPos = findCleanSpot(ent, cleanData.id)
        if ent.VNPC_CleanTargetPos then
            moveTo(ent, ent.VNPC_CleanTargetPos, true)
            if GetConVar("vnpcs_welfare_debug") and GetConVar("vnpcs_welfare_debug"):GetBool() then
                print(string.format("[V-NPCs][Welfare] #%d seeking %s clean spot", ent:EntIndex(), cleanData.id))
            end
        end
        return
    end
    if ent.VNPC_IsCleaning then return end

    -- 3) Social needs
    if not ent.VNPC_UsesSunWellbeing then
        local social = VNPC_GetSocialWelfare(ent)
        if socialData.seekCompany and social < 45 then
            local buddy = findCompanyTarget(ent)
            if IsValid(buddy) then
                moveTo(ent, buddy:GetPos(), social < 25)
            end
            return
        end
        if (not socialData.seekCompany) and social < 50 and (ent.VNPC_NearbySameSpecies or 0) > 0 then
            if (ent.VNPC_NextAloneSeek or 0) <= now then
                ent.VNPC_NextAloneSeek = now + 6.0
                local alone = findAloneSpot(ent)
                if alone then moveTo(ent, alone, true) end
            end
            return
        end
    end

    -- 4) Off-peak: rest / idle rather than hunt hard
    if not active and not ent.VNPC_IsReturningToCampToSleep then
        -- Mild rest posture
        if math.random() < 0.15 then
            if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_IDLE_STAND) end
        end
    end
end

hook.Add("Think", "VNPC_Welfare_AI_Loop", function()
    local enabled = GetConVar("vnpcs_welfare_enabled")
    if enabled and not enabled:GetBool() then return end
    local now = CurTime()
    if (VNPC_NextWelfareThink or 0) > now then return end
    VNPC_NextWelfareThink = now + 1.0

    for _, ent in ipairs(ents.GetAll()) do
        if welfareEligible(ent) then
            if (ent.VNPC_NextWelfareTick or 0) > now then continue end
            ent.VNPC_NextWelfareTick = now + 1.0 + math.Rand(0, 0.4)
            VNPC_WelfareTickEntity(ent, 1.0)
        end
    end
end)

-- Activity / dormant modifiers on hunter range
hook.Add("Think", "VNPC_Welfare_ApplyCombatMods", function()
    local enabled = GetConVar("vnpcs_welfare_enabled")
    if enabled and not enabled:GetBool() then return end
    local now = CurTime()
    if (VNPC_NextWelfareCombatMod or 0) > now then return end
    VNPC_NextWelfareCombatMod = now + 2.0

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end
        if not (ent.Predator or ent.VNPC_FemaleModelVore or ent.IsDrGNextbot) then continue end
        VNPC_EnsureWelfare(ent)
        local vMult = VNPC_GetWelfareVisionMult(ent)
        ent.VNPC_WelfareVisionMult = vMult
        ent.VNPC_WelfareSpeedMult = VNPC_GetWelfareSpeedMult(ent)
        -- Soft-clear enemy when fully dormant so they don't chase while sunken
        if ent.VNPC_IsDormant and ent.SetEnemy and ent.GetEnemy then
            local ok, en = pcall(ent.GetEnemy, ent)
            if ok and IsValid(en) and math.random() < 0.4 then
                pcall(ent.SetEnemy, ent, nil)
            end
        end
    end
end)

concommand.Add("vnpcs_welfare_status", function(ply)
    print("===============================================================")
    print("           V-NPCs WELFARE PREFERENCES STATUS                  ")
    print("===============================================================")
    print(" Enabled: " .. tostring(GetConVar("vnpcs_welfare_enabled"):GetBool()))
    print(" Time (min): " .. tostring(math.floor(VNPC_GetTimeOfDayMinutes())))
    print(" Night: " .. tostring(VNPC_IsStormFox2Night and VNPC_IsStormFox2Night()))
    local n = 0
    for _, ent in ipairs(ents.GetAll()) do
        if not welfareEligible(ent) then continue end
        VNPC_EnsureWelfare(ent)
        n = n + 1
        if n > 24 then continue end
        local sData, sid = VNPC_GetSocialPrefData(ent)
        local aData, aid = VNPC_GetActivitySpanData(ent)
        local cData, cid = VNPC_GetCleaningMethodData(ent)
        print(string.format(
            " -> #%d [%s] social=%s act=%s clean=%s | dirt=%.0f socialBar=%.0f sun=%s%.0f active=%s dormant=%s nearby=%s",
            ent:EntIndex(),
            ent.PrintName or ent:GetClass(),
            sid, aid, cid,
            VNPC_GetCleanliness(ent),
            ent.VNPC_UsesSunWellbeing and VNPC_GetSunWellbeing(ent) or VNPC_GetSocialWelfare(ent),
            ent.VNPC_UsesSunWellbeing and "YES/" or "no/",
            VNPC_GetSunWellbeing(ent),
            tostring(VNPC_IsInActivePeriod(ent)),
            tostring(ent.VNPC_IsDormant),
            tostring(ent.VNPC_NearbySameSpecies or VNPC_CountNearbySameSpecies(ent, 420))
        ))
    end
    if n == 0 then print(" - No eligible NPCs.") end
    print(" Total eligible: " .. n)
    print("===============================================================")
    if IsValid(ply) then ply:ChatPrint("[V-NPCs] Welfare status printed (" .. n .. " NPCs).") end
end)

concommand.Add("vnpcs_test_welfare", function(ply, cmd, args)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or not (ent:IsNPC() or ent:IsNextBot() or ent.IsDrGNextbot) then
        ply:ChatPrint("[V-NPCs] Aim at an NPC to set/test welfare prefs.")
        return
    end
    VNPC_EnsureWelfare(ent)
    local what = string.lower(args[1] or "status")
    local val = string.lower(args[2] or "")
    if what == "social" and val ~= "" then
        if VNPC_SetSocialPref(ent, val) then
            ply:ChatPrint("[V-NPCs] Set social pref to " .. val)
        else
            ply:ChatPrint("[V-NPCs] Use solitary / sociable / herd")
        end
    elseif what == "activity" and val ~= "" then
        if VNPC_SetActivitySpan(ent, val) then
            ply:ChatPrint("[V-NPCs] Set activity span to " .. val)
        else
            ply:ChatPrint("[V-NPCs] Use diurnal / nocturnal / crepuscular")
        end
    elseif what == "clean" and val ~= "" then
        if VNPC_SetCleaningMethod(ent, val) then
            ply:ChatPrint("[V-NPCs] Set cleaning method to " .. val)
        else
            ply:ChatPrint("[V-NPCs] Use water / dust / mud")
        end
    elseif what == "sun" then
        local on = val ~= "0" and val ~= "off" and val ~= "false"
        VNPC_SetUsesSunWellbeing(ent, on)
        if on then VNPC_SetSocialWelfare(ent, 25) end
        ply:ChatPrint("[V-NPCs] Sun wellbeing: " .. tostring(on))
    elseif what == "dirty" then
        VNPC_SetCleanliness(ent, 15)
        ply:ChatPrint("[V-NPCs] Forced dirty — they should seek their cleaning method.")
    elseif what == "lonely" then
        VNPC_SetUsesSunWellbeing(ent, false)
        VNPC_SetSocialWelfare(ent, 15)
        ply:ChatPrint("[V-NPCs] Forced low social welfare.")
    else
        ply:ChatPrint(string.format(
            "[V-NPCs] #%d social=%s act=%s clean=%s sun=%s dirt=%.0f bar=%.0f",
            ent:EntIndex(),
            tostring(ent.VNPC_SocialPref),
            tostring(ent.VNPC_ActivitySpan),
            tostring(ent.VNPC_CleaningMethod),
            tostring(ent.VNPC_UsesSunWellbeing),
            VNPC_GetCleanliness(ent),
            VNPC_GetSocialWelfare(ent)
        ))
    end
end)

concommand.Add("vnpcs_test_time_period", function(ply, cmd, args)
    local p = string.lower(args[1] or "day")
    if p == "night" then
        VNPC_SimulatedStormFox2Time = "night"
        VNPC_SimulatedTimeMinutes = 2 * 60
    elseif p == "dawn" then
        VNPC_SimulatedStormFox2Time = "dawn"
        VNPC_SimulatedTimeMinutes = 6 * 60 + 30
    elseif p == "dusk" then
        VNPC_SimulatedStormFox2Time = "dusk"
        VNPC_SimulatedTimeMinutes = 19 * 60
    else
        VNPC_SimulatedStormFox2Time = "day"
        VNPC_SimulatedTimeMinutes = 12 * 60
    end
    local msg = "[V-NPCs] Simulated time period: " .. p .. " (" .. tostring(VNPC_GetTimeOfDayMinutes()) .. " min)"
    print(msg)
    if IsValid(ply) then ply:ChatPrint(msg) end
end)

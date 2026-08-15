-- V-NPCs Welfare Preferences (sh_vnpc_welfare.lua)
-- Social preference, activity span, cleaning method, and sun wellbeing.
-- Applied to predators and person-like prey automatically on spawn.

CreateConVar("vnpcs_welfare_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable social / activity / cleanliness / sun welfare system")
CreateConVar("vnpcs_welfare_dirt_rate", "0.35", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "How fast cleanliness drops per second when dirtying (0-100 scale)")
CreateConVar("vnpcs_welfare_social_rate", "0.55", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "How fast social welfare changes per second")
CreateConVar("vnpcs_welfare_sun_rate", "0.70", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "How fast sun wellbeing drops without direct light")
CreateConVar("vnpcs_welfare_dormant_thresh", "18", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Sun wellbeing below this enters dormant/sluggish state")
CreateConVar("vnpcs_welfare_clean_thresh", "35", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Cleanliness below this triggers seeking a cleaning spot")
CreateConVar("vnpcs_welfare_debug", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Print welfare AI decisions")

-- ---------------------------------------------------------------------------
-- Preference tables
-- ---------------------------------------------------------------------------

VNPC_SOCIAL_PREFS = {
    solitary = {
        id = "solitary",
        name = "Solitary",
        description = "Prefers living alone. Same-species crowding lowers social welfare and pack size.",
        idealCompany = 0,
        maxComfortable = 1,       -- self only
        packLimit = 1,
        crowdPenalty = 1.35,      -- social drain multiplier when others nearby
        aloneBonus = 0.8,         -- social recovery when alone
        seekCompany = false,
    },
    sociable = {
        id = "sociable",
        name = "Sociable / Herd",
        description = "Thrives in packs/herds. Needs companionship for high social welfare.",
        idealCompany = 3,
        maxComfortable = 8,
        packLimit = 6,
        crowdPenalty = 0.25,
        aloneBonus = -0.9,        -- loses social when alone
        seekCompany = true,
    },
    herd = {
        id = "herd",
        name = "Sociable / Herd",
        description = "Thrives in packs/herds. Needs companionship for high social welfare.",
        idealCompany = 4,
        maxComfortable = 12,
        packLimit = 8,
        crowdPenalty = 0.15,
        aloneBonus = -1.1,
        seekCompany = true,
    },
}

VNPC_ACTIVITY_SPANS = {
    diurnal = {
        id = "diurnal",
        name = "Diurnal",
        description = "Active in daylight (roughly 08:00–20:00).",
        -- StormFox time units: minutes from midnight (0-1440)
        peaks = { { start = 8 * 60, finish = 20 * 60 } },
        offPeakSlow = 0.55,
        offPeakVision = 0.45,
        sleepBiasDay = -0.25,
        sleepBiasNight = 0.85,
    },
    nocturnal = {
        id = "nocturnal",
        name = "Nocturnal",
        description = "Active at night (roughly 23:00–05:00).",
        peaks = { { start = 23 * 60, finish = 24 * 60 }, { start = 0, finish = 5 * 60 } },
        offPeakSlow = 0.50,
        offPeakVision = 0.40,
        sleepBiasDay = 0.90,
        sleepBiasNight = -0.30,
    },
    crepuscular = {
        id = "crepuscular",
        name = "Crepuscular",
        description = "Active at dawn and dusk transitions.",
        peaks = {
            { start = 5 * 60, finish = 9 * 60 },
            { start = 17 * 60, finish = 21 * 60 },
        },
        offPeakSlow = 0.60,
        offPeakVision = 0.55,
        sleepBiasDay = 0.35,
        sleepBiasNight = 0.45,
    },
}

VNPC_CLEANING_METHODS = {
    water = {
        id = "water",
        name = "Water Bath",
        description = "Cleans by bathing in rivers, lakes, or camp water sources.",
        cleanRate = 12.0,
        keywords = { "water", "river", "lake", "pond", "bath" },
    },
    dust = {
        id = "dust",
        name = "Dust Bath",
        description = "Cleans by rolling in dry dirt / dust-bathing spots.",
        cleanRate = 10.0,
        keywords = { "dust", "dirt", "sand", "dry" },
    },
    mud = {
        id = "mud",
        name = "Mud Wallow",
        description = "Cleans by wallowing in mud pits (woodland / wet dirt).",
        cleanRate = 11.0,
        keywords = { "mud", "wallow", "swamp", "marsh" },
    },
}

local SOCIAL_IDS = { "solitary", "sociable", "herd" }
local ACTIVITY_IDS = { "diurnal", "nocturnal", "crepuscular" }
local CLEAN_IDS = { "water", "dust", "mud" }

-- ---------------------------------------------------------------------------
-- Time-of-day helper (StormFox minutes, with simulation fallback)
-- ---------------------------------------------------------------------------

function VNPC_GetTimeOfDayMinutes()
    -- Prefer StormFox 2 minutes-from-midnight
    if StormFox2 and StormFox2.Time and StormFox2.Time.Get then
        local t = StormFox2.Time.Get()
        if isnumber(t) then return t % 1440 end
    end
    if StormFox and StormFox.GetTime then
        local t = StormFox.GetTime()
        if isnumber(t) then return t % 1440 end
    end

    -- Simulated day cycle when StormFox is absent / forced.
    if VNPC_SimulatedStormFox2Time == "night" then
        return 2 * 60 -- 02:00
    end
    if VNPC_SimulatedStormFox2Time == "dawn" then
        return 6 * 60 + 30
    end
    if VNPC_SimulatedStormFox2Time == "dusk" then
        return 19 * 60
    end
    if VNPC_SimulatedTimeMinutes and isnumber(VNPC_SimulatedTimeMinutes) then
        return VNPC_SimulatedTimeMinutes % 1440
    end

    -- Fallback: wall-clock hour mapped into the day (so something still cycles).
    local h = tonumber(os.date("%H")) or 12
    local m = tonumber(os.date("%M")) or 0
    return h * 60 + m
end

local function timeInRange(mins, startM, finishM)
    if startM <= finishM then
        return mins >= startM and mins < finishM
    end
    -- wraps midnight
    return mins >= startM or mins < finishM
end

function VNPC_IsActivityPeakTime(activityId, mins)
    local data = VNPC_ACTIVITY_SPANS[activityId or "diurnal"] or VNPC_ACTIVITY_SPANS.diurnal
    mins = mins or VNPC_GetTimeOfDayMinutes()
    for _, span in ipairs(data.peaks or {}) do
        if timeInRange(mins, span.start, span.finish) then
            return true
        end
    end
    return false
end

function VNPC_GetActivitySpanData(ent)
    local id = (IsValid(ent) and ent.VNPC_ActivitySpan) or "diurnal"
    return VNPC_ACTIVITY_SPANS[id] or VNPC_ACTIVITY_SPANS.diurnal, id
end

function VNPC_GetSocialPrefData(ent)
    local id = (IsValid(ent) and ent.VNPC_SocialPref) or "sociable"
    if id == "herd" then id = "herd" end
    return VNPC_SOCIAL_PREFS[id] or VNPC_SOCIAL_PREFS.sociable, id
end

function VNPC_GetCleaningMethodData(ent)
    local id = (IsValid(ent) and ent.VNPC_CleaningMethod) or "water"
    return VNPC_CLEANING_METHODS[id] or VNPC_CLEANING_METHODS.water, id
end

-- ---------------------------------------------------------------------------
-- Assignment / getters
-- ---------------------------------------------------------------------------

local function pickWeighted(ids, weights)
    local total = 0
    for i, id in ipairs(ids) do
        total = total + (weights[i] or 1)
    end
    local r = math.random() * total
    local acc = 0
    for i, id in ipairs(ids) do
        acc = acc + (weights[i] or 1)
        if r <= acc then return id end
    end
    return ids[1]
end

function VNPC_RollWelfarePreferences(ent)
    if not IsValid(ent) then return end

    -- Social: loving/gentle lean sociable; aggressive/shy lean solitary.
    local socialWeights = { 1.0, 1.4, 0.9 } -- solitary, sociable, herd
    if VNPC_GetPredatorPersonality then
        local pers = select(1, VNPC_GetPredatorPersonality(ent))
        if pers == "loving" or pers == "gentle" then
            socialWeights = { 0.4, 1.6, 1.4 }
        elseif pers == "shy" or pers == "selective" then
            socialWeights = { 1.8, 0.7, 0.3 }
        elseif pers == "aggressive" or pers == "glutton" then
            socialWeights = { 1.3, 1.1, 0.6 }
        end
    end
    if not ent.VNPC_SocialPref then
        ent.VNPC_SocialPref = pickWeighted(SOCIAL_IDS, socialWeights)
    end

    -- Activity: night_hunter trait / random.
    local actWeights = { 1.5, 0.7, 0.9 } -- diurnal, nocturnal, crepuscular
    if VNPC_HasTrait and VNPC_HasTrait(ent, "night_hunter") then
        actWeights = { 0.3, 2.0, 0.8 }
    end
    if not ent.VNPC_ActivitySpan then
        ent.VNPC_ActivitySpan = pickWeighted(ACTIVITY_IDS, actWeights)
    end

    -- Cleaning: slight bias by personality/environment keywords later.
    if not ent.VNPC_CleaningMethod then
        ent.VNPC_CleaningMethod = pickWeighted(CLEAN_IDS, { 1.2, 1.0, 0.9 })
    end

    -- Sun wellbeing: uncommon special that REPLACES social bar.
    if ent.VNPC_UsesSunWellbeing == nil then
        local chance = 0.12
        if VNPC_HasTrait and (VNPC_HasTrait(ent, "night_hunter") == false) then
            -- slightly more common on non-night hunters
            chance = 0.14
        end
        -- Prey a bit more likely to be sun baskers (lizards / herbivore vibe)
        if VNPC_ShouldBePrey and VNPC_ShouldBePrey(ent) and not (VNPC_ShouldBePredator and VNPC_ShouldBePredator(ent)) then
            chance = 0.18
        end
        ent.VNPC_UsesSunWellbeing = math.random() < chance
    end

    ent.VNPC_Cleanliness = ent.VNPC_Cleanliness or math.random(55, 90)
    ent.VNPC_SocialWelfare = ent.VNPC_SocialWelfare or math.random(45, 80)
    ent.VNPC_SunWellbeing = ent.VNPC_SunWellbeing or math.random(50, 85)
    ent.VNPC_IsDormant = ent.VNPC_IsDormant or false

    if SERVER and ent.SetNWString then
        ent:SetNWString("VNPC_SocialPref", ent.VNPC_SocialPref or "sociable")
        ent:SetNWString("VNPC_ActivitySpan", ent.VNPC_ActivitySpan or "diurnal")
        ent:SetNWString("VNPC_CleaningMethod", ent.VNPC_CleaningMethod or "water")
        ent:SetNWBool("VNPC_UsesSunWellbeing", ent.VNPC_UsesSunWellbeing and true or false)
        ent:SetNWFloat("VNPC_Cleanliness", ent.VNPC_Cleanliness)
        ent:SetNWFloat("VNPC_SocialWelfare", ent.VNPC_SocialWelfare)
        ent:SetNWFloat("VNPC_SunWellbeing", ent.VNPC_SunWellbeing)
        ent:SetNWBool("VNPC_IsDormant", ent.VNPC_IsDormant and true or false)
        ent:SetNWBool("VNPC_IsActivePeriod", true)
    end
end

function VNPC_EnsureWelfare(ent)
    if not IsValid(ent) then return end
    if ent.VNPC_SocialPref and ent.VNPC_ActivitySpan and ent.VNPC_CleaningMethod then
        return
    end
    VNPC_RollWelfarePreferences(ent)
end

function VNPC_SetSocialPref(ent, id)
    if not IsValid(ent) or not VNPC_SOCIAL_PREFS[id] then return false end
    ent.VNPC_SocialPref = id
    if ent.SetNWString then ent:SetNWString("VNPC_SocialPref", id) end
    return true
end

function VNPC_SetActivitySpan(ent, id)
    if not IsValid(ent) or not VNPC_ACTIVITY_SPANS[id] then return false end
    ent.VNPC_ActivitySpan = id
    if ent.SetNWString then ent:SetNWString("VNPC_ActivitySpan", id) end
    return true
end

function VNPC_SetCleaningMethod(ent, id)
    if not IsValid(ent) or not VNPC_CLEANING_METHODS[id] then return false end
    ent.VNPC_CleaningMethod = id
    if ent.SetNWString then ent:SetNWString("VNPC_CleaningMethod", id) end
    return true
end

function VNPC_SetUsesSunWellbeing(ent, enabled)
    if not IsValid(ent) then return false end
    ent.VNPC_UsesSunWellbeing = enabled and true or false
    if ent.SetNWBool then ent:SetNWBool("VNPC_UsesSunWellbeing", ent.VNPC_UsesSunWellbeing) end
    return true
end

function VNPC_GetCleanliness(ent)
    if not IsValid(ent) then return 100 end
    return ent.VNPC_Cleanliness or 100
end

function VNPC_SetCleanliness(ent, val)
    if not IsValid(ent) then return end
    ent.VNPC_Cleanliness = math.Clamp(val or 100, 0, 100)
    if SERVER and ent.SetNWFloat then ent:SetNWFloat("VNPC_Cleanliness", ent.VNPC_Cleanliness) end
end

function VNPC_GetSocialWelfare(ent)
    if not IsValid(ent) then return 100 end
    if ent.VNPC_UsesSunWellbeing then
        return ent.VNPC_SunWellbeing or 100
    end
    return ent.VNPC_SocialWelfare or 100
end

function VNPC_SetSocialWelfare(ent, val)
    if not IsValid(ent) then return end
    if ent.VNPC_UsesSunWellbeing then
        ent.VNPC_SunWellbeing = math.Clamp(val or 100, 0, 100)
        if SERVER and ent.SetNWFloat then ent:SetNWFloat("VNPC_SunWellbeing", ent.VNPC_SunWellbeing) end
        return
    end
    ent.VNPC_SocialWelfare = math.Clamp(val or 100, 0, 100)
    if SERVER and ent.SetNWFloat then ent:SetNWFloat("VNPC_SocialWelfare", ent.VNPC_SocialWelfare) end
end

function VNPC_GetSunWellbeing(ent)
    if not IsValid(ent) then return 100 end
    return ent.VNPC_SunWellbeing or 100
end

function VNPC_IsInActivePeriod(ent)
    if not IsValid(ent) then return true end
    VNPC_EnsureWelfare(ent)
    local data = VNPC_GetActivitySpanData(ent)
    return VNPC_IsActivityPeakTime(data.id, VNPC_GetTimeOfDayMinutes())
end

function VNPC_GetPackLimit(ent)
    if not IsValid(ent) then return 4 end
    VNPC_EnsureWelfare(ent)
    local data = VNPC_GetSocialPrefData(ent)
    return data.packLimit or 4
end

function VNPC_GetWelfareSpeedMult(ent)
    if not IsValid(ent) then return 1 end
    local enabled = GetConVar("vnpcs_welfare_enabled")
    if enabled and not enabled:GetBool() then return 1 end
    VNPC_EnsureWelfare(ent)

    local mult = 1.0
    local act = VNPC_GetActivitySpanData(ent)
    if not VNPC_IsInActivePeriod(ent) then
        mult = mult * (act.offPeakSlow or 0.55)
    end
    if ent.VNPC_IsDormant then
        mult = mult * 0.35
    end
    local clean = VNPC_GetCleanliness(ent)
    if clean < 25 then
        mult = mult * 0.75
    elseif clean < 45 then
        mult = mult * 0.90
    end
    local social = VNPC_GetSocialWelfare(ent)
    if social < 20 then
        mult = mult * 0.80
    end
    return math.Clamp(mult, 0.25, 1.15)
end

function VNPC_GetWelfareVisionMult(ent)
    if not IsValid(ent) then return 1 end
    local enabled = GetConVar("vnpcs_welfare_enabled")
    if enabled and not enabled:GetBool() then return 1 end
    VNPC_EnsureWelfare(ent)
    local mult = 1.0
    local act = VNPC_GetActivitySpanData(ent)
    if not VNPC_IsInActivePeriod(ent) then
        mult = mult * (act.offPeakVision or 0.5)
    end
    if ent.VNPC_IsDormant then
        mult = mult * 0.40
    end
    return math.Clamp(mult, 0.25, 1.25)
end

function VNPC_CountNearbySameSpecies(ent, radius)
    if not IsValid(ent) then return 0 end
    radius = radius or 420
    local rSqr = radius * radius
    local myPos = ent:GetPos()
    local myCls = string.lower(ent:GetClass() or "")
    local myCamp = ent.VNPC_CampID
    local myPreyCamp = ent.VNPC_PreyCampID
    local count = 0
    for _, other in ipairs(ents.FindInSphere(myPos, radius)) do
        if not IsValid(other) or other == ent then continue end
        if other.Vored or other.VNPC_Vored then continue end
        if not (other:IsNPC() or other:IsNextBot() or other.IsDrGNextbot or other:IsPlayer()) then continue end
        local same = false
        if myCamp and other.VNPC_CampID and myCamp == other.VNPC_CampID then
            same = true
        elseif myPreyCamp and other.VNPC_PreyCampID and myPreyCamp == other.VNPC_PreyCampID then
            same = true
        elseif string.lower(other:GetClass() or "") == myCls then
            same = true
        end
        if same then
            count = count + 1
        end
    end
    return count
end

-- Direct sunlight: outdoor + not night + sky trace.
function VNPC_IsInDirectSunlight(ent)
    if not IsValid(ent) then return false end
    if VNPC_IsStormFox2Night and VNPC_IsStormFox2Night() then return false end
    if VNPC_IsStormFox2Raining and VNPC_IsStormFox2Raining() then return false end

    local mins = VNPC_GetTimeOfDayMinutes()
    -- No meaningful sun late night / deep night
    if mins < 5 * 60 or mins > 21 * 60 then return false end

    local pos = ent:GetPos() + Vector(0, 0, 48)
    local tr = util.TraceLine({
        start = pos,
        endpos = pos + Vector(0, 0, 2000),
        mask = MASK_SOLID_BRUSHONLY,
        filter = ent,
    })
    -- Hit sky or nothing solid above = sun exposure
    if tr.HitSky then return true end
    if not tr.Hit then return true end
    return false
end

if SERVER then
    hook.Add("OnEntityCreated", "VNPC_Welfare_AutoRoll", function(ent)
        timer.Simple(0.35, function()
            if not IsValid(ent) then return end
            if not (ent:IsNPC() or ent:IsNextBot() or ent.IsDrGNextbot or ent.Predator or ent.VNPC_FemaleModelVore) then
                return
            end
            if ent.VNPC_IsUnbornBaby or ent.VNPC_IsGrowingBaby then return end
            VNPC_RollWelfarePreferences(ent)
        end)
    end)
end

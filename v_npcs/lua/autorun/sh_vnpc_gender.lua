-- V-NPCs Universal Gender Roles (sh_vnpc_gender.lua)
-- Any female-looking NPC is a predator. Any male-looking NPC is prey.
-- Custom workshop NPCs work automatically from model/bones/class name —
-- no per-NPC name lists required.

CreateConVar("vnpcs_universal_gender_roles", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Any female NPC is a predator; any male NPC is prey (supports custom NPCs automatically)")
CreateConVar("vnpcs_auto_female_pred", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Automatically give vore to any female NPC/nextbot on spawn")
CreateConVar("vnpcs_wild_use_custom_npcs", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Wild ecology can spawn custom registered female preds / male prey from the NPC spawn menu")

VNPC_GenderCache = VNPC_GenderCache or {} -- [model] = "female"|"male"|"unknown"
VNPC_DiscoveredFemaleSpawn = VNPC_DiscoveredFemaleSpawn or {} -- { {cls=, mdl=}, ... }
VNPC_DiscoveredMaleSpawn = VNPC_DiscoveredMaleSpawn or {}
VNPC_NextGenderCatalogRefresh = VNPC_NextGenderCatalogRefresh or 0

local FEMALE_NAME_TOKENS = {
    "female", "woman", "girl", "lady", "fema", "alyx", "mossman",
    "witch", "mom", "mother", "sister", "wife", "daughter", "queen",
    "princess", "miss", "mrs", "maid", "nun", "cheer", "schoolgirl",
    "f_", "_f_", "/f/", "f01", "f02", "f03", "f04", "f05", "f06", "f07",
    "citizen_female", "humans/group01/female", "humans/group02/female",
    "humans/group03/female", "humans/group03m/female",
}

local MALE_NAME_TOKENS = {
    "male", "man", "boy", "guy", "father", "dad", "brother", "husband",
    "son", "king", "prince", "mr", "monk", "barney", "eli", "kleiner",
    "breen", "gman", "odessa", "grigori", "magnusson",
    "m_", "_m_", "/m/", "m01", "m02", "m03", "m04", "m05", "m06", "m07", "m08", "m09",
    "citizen_male", "humans/group01/male", "humans/group02/male",
    "humans/group03/male", "humans/group03m/male",
}

-- Classes that are never auto-gendered as people (machines, props, etc.)
local NON_PERSON_CLASS = {
    "prop_", "func_", "weapon_", "gmod_", "env_", "trigger_", "point_",
    "info_", "logic_", "beam", "sprite", "path_", "keyframe", "move_rope",
}

local function textHasToken(hay, tokens)
    if not hay or hay == "" then return false end
    for _, tok in ipairs(tokens) do
        if hay:find(tok, 1, true) then
            return true
        end
    end
    return false
end

local function isPersonLikeEntity(ent)
    if not IsValid(ent) then return false end
    if ent:IsPlayer() then return true end
    if not (ent:IsNPC() or ent:IsNextBot() or ent.IsDrGNextbot) then return false end
    local cls = string.lower(ent:GetClass() or "")
    for _, bad in ipairs(NON_PERSON_CLASS) do
        if cls:find(bad, 1, true) then return false end
    end
    if cls:find("grenade") or cls:find("missile") or cls:find("rocket") then return false end
    return true
end

function VNPC_TextLooksFemale(str)
    str = string.lower(tostring(str or ""))
    if str == "" then return false end
    -- Male tokens that contain "female" substrings first
    if textHasToken(str, FEMALE_NAME_TOKENS) then return true end
    return false
end

function VNPC_TextLooksMale(str)
    str = string.lower(tostring(str or ""))
    if str == "" then return false end
    if VNPC_TextLooksFemale(str) then return false end
    if textHasToken(str, MALE_NAME_TOKENS) then return true end
    return false
end

function VNPC_ClassifyGenderFromText(cls, mdl, name)
    local blob = string.lower(table.concat({
        tostring(cls or ""), " ",
        tostring(mdl or ""), " ",
        tostring(name or ""),
    }))
    if VNPC_TextLooksFemale(blob) then return "female" end
    if VNPC_TextLooksMale(blob) then return "male" end
    return "unknown"
end

function VNPC_GetEntityGender(ent)
    if not IsValid(ent) then return "unknown" end

    if ent.VNPC_ChildGender == "female" or ent.VNPC_ForcedGender == "female" then
        return "female"
    end
    if ent.VNPC_ChildGender == "male" or ent.VNPC_ForcedGender == "male" then
        return "male"
    end

    -- Explicit predator flags from V-NPC base / female vore already count female.
    if ent.VNPC_FemaleModelVore or ent.VNPC_ForceFemaleVore then
        return "female"
    end

    local mdl = string.lower(ent:GetModel() or "")
    if mdl ~= "" and VNPC_GenderCache[mdl] then
        return VNPC_GenderCache[mdl]
    end

    -- Breast / female skeleton bones (works for custom models).
    if VNPC_HasFemaleModelBones and VNPC_HasFemaleModelBones(ent) then
        if mdl ~= "" then VNPC_GenderCache[mdl] = "female" end
        return "female"
    end

    local cls = string.lower(ent:GetClass() or "")
    local name = string.lower(tostring(ent.PrintName or ent.Name or ""))
    local fromText = VNPC_ClassifyGenderFromText(cls, mdl, name)
    if fromText ~= "unknown" then
        if mdl ~= "" then VNPC_GenderCache[mdl] = fromText end
        return fromText
    end

    -- Players: use model path / bodygroups heuristics only.
    if ent:IsPlayer() then
        if mdl:find("female") or mdl:find("/f_") or mdl:find("_f_") then
            return "female"
        end
        if mdl:find("male") or mdl:find("/m_") or mdl:find("_m_") then
            return "male"
        end
        return "unknown"
    end

    if mdl ~= "" and isPersonLikeEntity(ent) then
        -- Unmarked humanoid default: treat as male prey so camps still fill.
        -- Custom female models usually have bones or "female" in the path.
        VNPC_GenderCache[mdl] = "unknown"
    end
    return "unknown"
end

function VNPC_IsAnyFemale(ent)
    if not IsValid(ent) then return false end
    return VNPC_GetEntityGender(ent) == "female"
end

function VNPC_IsAnyMale(ent)
    if not IsValid(ent) then return false end
    return VNPC_GetEntityGender(ent) == "male"
end

-- True when this entity should act as a predator under universal roles.
function VNPC_ShouldBePredator(ent)
    if not IsValid(ent) then return false end
    if ent.Vored or ent.VNPC_Vored then return false end
    if ent.VNPC_IsUnbornBaby or ent.VNPC_IsGrowingBaby or ent.VNPC_ProtectedChild then
        return false
    end
    -- Explicit V-NPC predators always stay preds.
    if ent.IsDrGNextbot or ent.Base == "npc_vore_base" or ent.Predator or ent.VNPC_FemaleModelVore then
        return true
    end
    local roles = GetConVar("vnpcs_universal_gender_roles")
    if roles and not roles:GetBool() then
        return false
    end
    if not isPersonLikeEntity(ent) and not ent:IsNextBot() then
        -- Still allow nextbots / custom NPCs that look female.
        if not (ent:IsNPC() or ent:IsNextBot()) then return false end
    end
    return VNPC_IsAnyFemale(ent)
end

-- True when this entity should act as prey under universal roles.
function VNPC_ShouldBePrey(ent)
    if not IsValid(ent) then return false end
    if ent:IsPlayer() then return true end
    if ent.Vored or ent.VNPC_Vored or ent.VNPC_Surrendered then return false end
    if ent.VNPC_IsSecretAssassin then return false end
    if ent.VNPC_IsPermanentFortPredator then return false end
    if VNPC_ShouldBePredator(ent) then return false end
    if ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator or ent.EatEntity then
        return false
    end
    if not (ent:IsNPC() or ent:IsNextBot()) then return false end

    local roles = GetConVar("vnpcs_universal_gender_roles")
    if roles and not roles:GetBool() then
        return false
    end

    if VNPC_IsAnyMale(ent) then return true end

    -- Non-gendered creatures (headcrabs, antlions, etc.) remain eligible prey
    -- for ecology, but humanoid unknowns default to prey so custom male models
    -- without "male" in the path still work.
    local gender = VNPC_GetEntityGender(ent)
    if gender == "unknown" and isPersonLikeEntity(ent) then
        return true
    end
    if gender == "unknown" then
        -- Monsters / animals: still prey targets.
        local cls = string.lower(ent:GetClass() or "")
        if cls:find("headcrab") or cls:find("antlion") or cls:find("zombie")
            or cls:find("fastzombie") or cls:find("poison") or cls:find("crow")
            or cls:find("pigeon") or cls:find("seagull") or cls:find("dog") then
            return true
        end
    end
    return false
end

local function coerceString(v)
    if v == nil then return nil end
    if isstring(v) then return v end
    if istable(v) then
        -- Spawn menu / SENT data sometimes stores Class/Model as a list.
        for _, item in ipairs(v) do
            if isstring(item) and item ~= "" then return item end
        end
        for _, item in pairs(v) do
            if isstring(item) and item ~= "" then return item end
        end
        return nil
    end
    if isnumber(v) or isbool(v) then return tostring(v) end
    local ok, s = pcall(tostring, v)
    if ok and isstring(s) and s ~= "" and s ~= "nil" and s ~= "table" then
        return s
    end
    return nil
end

local function catalogAdd(list, cls, mdl, seen)
    cls = coerceString(cls)
    mdl = coerceString(mdl)
    if not cls or cls == "" then return end
    cls = string.lower(cls)
    if mdl then mdl = string.lower(mdl) end
    local key = cls .. "|" .. (mdl or "")
    if seen[key] then return end
    seen[key] = true
    table.insert(list, { cls = cls, mdl = mdl })
end

local function classifySpawnEntry(cls, mdl, name)
    cls = coerceString(cls)
    mdl = coerceString(mdl)
    name = coerceString(name)
    local g = VNPC_ClassifyGenderFromText(cls, mdl, name)
    if g ~= "unknown" then return g end
    -- If only a model path is known, try loading keywords from it alone.
    if mdl and mdl ~= "" then
        if VNPC_TextLooksFemale(mdl) then return "female" end
        if VNPC_TextLooksMale(mdl) then return "male" end
    end
    return "unknown"
end

function VNPC_RefreshGenderSpawnCatalog(force)
    if not SERVER then return end
    local now = CurTime()
    if not force and (VNPC_NextGenderCatalogRefresh or 0) > now then return end
    VNPC_NextGenderCatalogRefresh = now + 30

    local females, males, seenF, seenM = {}, {}, {}, {}

    -- 1) Sandbox NPC spawn menu (includes most workshop NPCs).
    if list and list.Get then
        local ok, npcList = pcall(list.Get, "NPC")
        if ok and istable(npcList) then
            for spawnName, data in pairs(npcList) do
                if not istable(data) then continue end
                local cls = coerceString(data.Class or data.class) or coerceString(spawnName)
                local mdl = coerceString(data.Model or data.model)
                local name = coerceString(data.Name or data.PrintName or spawnName)
                local g = classifySpawnEntry(cls, mdl, name)
                if g == "female" then
                    catalogAdd(females, cls, mdl, seenF)
                elseif g == "male" then
                    catalogAdd(males, cls, mdl, seenM)
                end
            end
        end
    end

    -- 2) Scripted entities that look like NPCs.
    if scripted_ents and scripted_ents.GetList then
        local ok, sentList = pcall(scripted_ents.GetList)
        if ok and istable(sentList) then
            for clsKey, data in pairs(sentList) do
                local t = istable(data) and (data.t or data) or nil
                if not istable(t) then continue end
                local cls = coerceString(clsKey) or coerceString(t.Class or t.class)
                if not cls then continue end
                local base = string.lower(tostring(t.Base or t.base or ""))
                local typ = string.lower(tostring(t.Type or t.type or ""))
                local clsLower = string.lower(cls)
                if not (base:find("npc") or base:find("nextbot") or base:find("drg")
                    or typ == "ai" or typ == "nextbot" or clsLower:find("npc_")) then
                    continue
                end
                local mdl = coerceString(t.Model or t.model)
                local name = coerceString(t.PrintName or t.Name) or cls
                local g = classifySpawnEntry(cls, mdl, name)
                if g == "female" then
                    catalogAdd(females, cls, mdl, seenF)
                elseif g == "male" then
                    catalogAdd(males, cls, mdl, seenM)
                end
            end
        end
    end

    -- 3) Already-spawned map NPCs (discovers custom models currently in play).
    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) or not (ent:IsNPC() or ent:IsNextBot() or ent.IsDrGNextbot) then
            continue
        end
        local cls = ent:GetClass()
        local mdl = ent:GetModel()
        local g = VNPC_GetEntityGender(ent)
        if g == "female" then
            catalogAdd(females, cls, mdl, seenF)
        elseif g == "male" then
            catalogAdd(males, cls, mdl, seenM)
        end
    end

    -- 4) Safe HL2 fallbacks so empty catalogs still work.
    if #females == 0 then
        catalogAdd(females, "npc_citizen", "models/humans/group01/female_01.mdl", seenF)
        catalogAdd(females, "npc_citizen", "models/humans/group01/female_02.mdl", seenF)
        catalogAdd(females, "npc_alyx", "models/alyx.mdl", seenF)
        catalogAdd(females, "npc_mossman", "models/mossman.mdl", seenF)
    end
    if #males == 0 then
        catalogAdd(males, "npc_citizen", "models/humans/group01/male_01.mdl", seenM)
        catalogAdd(males, "npc_citizen", "models/humans/group01/male_02.mdl", seenM)
        catalogAdd(males, "npc_citizen", "models/humans/group01/male_03.mdl", seenM)
    end

    VNPC_DiscoveredFemaleSpawn = females
    VNPC_DiscoveredMaleSpawn = males
    return females, males
end

function VNPC_PickRandomFemaleSpawnInfo()
    if SERVER then VNPC_RefreshGenderSpawnCatalog(false) end
    local listF = VNPC_DiscoveredFemaleSpawn or {}
    if #listF == 0 then
        return { cls = "npc_citizen", mdl = "models/humans/group01/female_01.mdl" }
    end
    return listF[math.random(1, #listF)]
end

function VNPC_PickRandomMaleSpawnInfo()
    if SERVER then VNPC_RefreshGenderSpawnCatalog(false) end
    local listM = VNPC_DiscoveredMaleSpawn or {}
    if #listM == 0 then
        return { cls = "npc_citizen", mdl = "models/humans/group01/male_01.mdl" }
    end
    return listM[math.random(1, #listM)]
end

if SERVER then
    hook.Add("InitPostEntity", "VNPC_GenderCatalog_Init", function()
        timer.Simple(2, function()
            VNPC_RefreshGenderSpawnCatalog(true)
        end)
    end)

    concommand.Add("vnpcs_gender_catalog_status", function(ply)
        VNPC_RefreshGenderSpawnCatalog(true)
        print("===============================================================")
        print("        V-NPCs UNIVERSAL GENDER ROLES / CUSTOM NPC CATALOG    ")
        print("===============================================================")
        print(" - Universal roles: " .. tostring(GetConVar("vnpcs_universal_gender_roles"):GetBool()))
        print(" - Auto female pred: " .. tostring(GetConVar("vnpcs_auto_female_pred"):GetBool()))
        print(" - Wild custom NPCs: " .. tostring(GetConVar("vnpcs_wild_use_custom_npcs"):GetBool()))
        print(" - Discovered female spawn entries: " .. tostring(#(VNPC_DiscoveredFemaleSpawn or {})))
        for i, info in ipairs(VNPC_DiscoveredFemaleSpawn or {}) do
            if i > 12 then print("   ...") break end
            print(string.format("   F %s | %s", tostring(info.cls), tostring(info.mdl or "-")))
        end
        print(" - Discovered male spawn entries: " .. tostring(#(VNPC_DiscoveredMaleSpawn or {})))
        for i, info in ipairs(VNPC_DiscoveredMaleSpawn or {}) do
            if i > 12 then print("   ...") break end
            print(string.format("   M %s | %s", tostring(info.cls), tostring(info.mdl or "-")))
        end
        local fCount, mCount, pCount = 0, 0, 0
        for _, ent in ipairs(ents.GetAll()) do
            if not IsValid(ent) or not (ent:IsNPC() or ent:IsNextBot() or ent.IsDrGNextbot) then continue end
            if VNPC_IsAnyFemale(ent) then fCount = fCount + 1 end
            if VNPC_IsAnyMale(ent) then mCount = mCount + 1 end
            if VNPC_ShouldBePredator(ent) then pCount = pCount + 1 end
        end
        print(string.format(" - Live map: females=%d males=%d shouldBePred=%d", fCount, mCount, pCount))
        print("===============================================================")
        if IsValid(ply) then
            ply:ChatPrint(string.format("[V-NPCs] Gender catalog: %d female / %d male spawn entries. Live F=%d M=%d preds=%d",
                #(VNPC_DiscoveredFemaleSpawn or {}), #(VNPC_DiscoveredMaleSpawn or {}), fCount, mCount, pCount))
        end
    end)
end

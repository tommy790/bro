-- V-NPCs Faction-Based Predator Camps & Camp Clashing / War AI Engine (vnpcs_camp_factions.lua)
-- Predator camps are organized into Factions (mostly Metrocop & Zombie); rival camps accumulate tension and clash in open vore battles

local clashing_enabled = CreateConVar("vnpcs_camp_clashing_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable predator camp faction wars and tension clashing")
local tension_rate = CreateConVar("vnpcs_camp_tension_rate", "1.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Tension growth per second between rival predator camps within 3500 units")
local war_thresh = CreateConVar("vnpcs_camp_war_thresh", "100.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Tension threshold required to trigger an open Faction War battle")

VNPC_CampTensions = VNPC_CampTensions or {}

function VNPC_GetPredatorFaction(pred)
    if not IsValid(pred) then return "citizen" end
    if pred.VNPC_PredatorFaction then return pred.VNPC_PredatorFaction end

    local cls = string.lower(pred:GetClass() or "")
    local mdl = string.lower(pred:GetModel() or "")

    if cls:find("police") or cls:find("metropolice") or cls:find("combine") or cls:find("metro") or mdl:find("police") or mdl:find("combine") or mdl:find("metrocop") then
        pred.VNPC_PredatorFaction = "metrocop"
        return "metrocop"
    end
    if cls:find("zombie") or cls:find("fastzombie") or cls:find("poisonzombie") or cls:find("headcrab") or mdl:find("zombie") or mdl:find("corpse") then
        pred.VNPC_PredatorFaction = "zombie"
        return "zombie"
    end
    if cls:find("antlion") or cls:find("vortigaunt") or cls:find("alien") or cls:find("drg_") then
        pred.VNPC_PredatorFaction = "alien"
        return "alien"
    end

    -- Mostly Female Metrocops and Female Zombies as default predator factions
    local defaultFactions = { "metrocop", "metrocop", "zombie", "zombie", "citizen" }
    pred.VNPC_PredatorFaction = defaultFactions[math.random(1, #defaultFactions)]
    return pred.VNPC_PredatorFaction
end

function VNPC_GetTensionKey(id1, id2)
    return math.min(id1, id2) .. "_" .. math.max(id1, id2)
end

function VNPC_TriggerCampWar(campA, campB)
    if not campA or not campB then return end

    campA.state = "war"
    campA.enemyCampID = campB.id
    campB.state = "war"
    campB.enemyCampID = campA.id

    local key = VNPC_GetTensionKey(campA.id, campB.id)
    VNPC_CampTensions[key] = 0

    for _, p in ipairs(player.GetAll()) do
        p:EmitSound("ambient/alarms/siren.wav", 80, 100)
        p:ChatPrint("[V-NPCs] CAMP WAR! High tension between Faction " .. string.upper(campA.faction or "METROCOP") .. " Camp #" .. campA.id .. " and Faction " .. string.upper(campB.faction or "ZOMBIE") .. " Camp #" .. campB.id .. " has erupted into an open Vore Battle!")
    end
end

hook.Add("Think", "VNPC_PredatorCampFactions_Loop", function()
    if not clashing_enabled:GetBool() then return end
    local now = CurTime()
    if (VNPC_NextFactionWarThink or 0) > now then return end
    VNPC_NextFactionWarThink = now + 1.0

    local camps = VNPC_ActivePredatorCamps or {}
    if #camps < 2 then return end

    for i = 1, #camps do
        local campA = camps[i]
        campA.faction = campA.faction or (campA.members[1] and VNPC_GetPredatorFaction(campA.members[1]) or "metrocop")

        -- Check active war state
        if campA.state == "war" and campA.enemyCampID then
            local enemyCamp = nil
            for _, c in ipairs(camps) do
                if c.id == campA.enemyCampID then
                    enemyCamp = c
                    break
                end
            end

            -- Check if enemy camp was defeated
            if not enemyCamp or #enemyCamp.members == 0 then
                campA.state = "idle"
                campA.enemyCampID = nil
                for _, p in ipairs(player.GetAll()) do
                    p:ChatPrint("[V-NPCs] CAMP WAR VICTORY! Faction " .. string.upper(campA.faction) .. " Camp #" .. campA.id .. " defeated their rival camp!")
                end
                continue
            end

            -- Active war: command members to attack enemy campmates
            for _, memA in ipairs(campA.members) do
                if not IsValid(memA) or memA:Health() <= 0 then continue end
                local targetMem = nil
                for _, memB in ipairs(enemyCamp.members) do
                    if IsValid(memB) and memB:Health() > 0 and not memB.Vored and not memB.VNPC_Vored then
                        targetMem = memB
                        break
                    end
                end
                if IsValid(targetMem) then
                    if memA.SetEnemy then pcall(memA.SetEnemy, memA, targetMem) end
                    if memA.SetTarget then pcall(memA.SetTarget, memA, targetMem) end
                    if memA.SetLastPosition then pcall(memA.SetLastPosition, memA, targetMem:GetPos()) end
                    if memA.SetSchedule then pcall(memA.SetSchedule, memA, SCHED_FORCED_GO_RUN) end
                end
            end
        else
            -- Check tension with other camps of different factions
            for j = i + 1, #camps do
                local campB = camps[j]
                campB.faction = campB.faction or (campB.members[1] and VNPC_GetPredatorFaction(campB.members[1]) or "zombie")

                if campA.faction ~= campB.faction and campB.state ~= "war" then
                    local dist = campA.pos:Distance(campB.pos)
                    if dist <= 3500 then
                        local key = VNPC_GetTensionKey(campA.id, campB.id)
                        local current = VNPC_CampTensions[key] or 25.0
                        local rate = (1.0 + (3500 - dist) / 1500) * tension_rate:GetFloat()
                        local newTension = math.min(100.0, current + rate)
                        VNPC_CampTensions[key] = newTension

                        if newTension >= war_thresh:GetFloat() then
                            VNPC_TriggerCampWar(campA, campB)
                            break
                        end
                    end
                end
            end
        end
    end
end)

concommand.Add("vnpcs_camp_factions_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Predator Camp Factions & Clashing / War AI Status")
    print("Enabled: " .. tostring(clashing_enabled:GetBool()))
    print("Tension Rate: " .. tostring(tension_rate:GetFloat()) .. " / sec")
    print("War Threshold: " .. tostring(war_thresh:GetFloat()))
    print("-----------------------------------------")
    local camps = VNPC_ActivePredatorCamps or {}
    for idx, camp in ipairs(camps) do
        print(string.format(" -> Camp [#%d] | Faction: %s | State: %s | Members: %d",
            camp.id, string.upper(camp.faction or "N/A"), string.upper(camp.state or "IDLE"), #camp.members))
    end
    print("-----------------------------------------")
    for k, v in pairs(VNPC_CampTensions) do
        print(string.format(" -> Tension [%s]: %.1f / %.1f", k, v, war_thresh:GetFloat()))
    end
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Factions status printed to console. Camps: " .. #camps)
    end
end)

concommand.Add("vnpcs_test_camp_war", function(ply)
    if not IsValid(ply) then return end
    local camps = VNPC_ActivePredatorCamps or {}
    if #camps < 2 then
        ply:ChatPrint("[V-NPCs] At least 2 active predator camps are needed to trigger a Faction War!")
        return
    end
    local campA, campB = camps[1], camps[2]
    campA.faction = "metrocop"
    campB.faction = "zombie"
    VNPC_TriggerCampWar(campA, campB)
    ply:ChatPrint("[V-NPCs] Triggered Faction War between Camp #" .. campA.id .. " (METROCOP) and Camp #" .. campB.id .. " (ZOMBIE)!")
end)

concommand.Add("vnpcs_set_pred_faction", function(ply, cmd, args)
    if not IsValid(ply) then return end
    local faction = args[1] and string.lower(args[1]) or "metrocop"
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a female V-NPC predator! Usage: vnpcs_set_pred_faction <metrocop|zombie|citizen|alien>")
        return
    end
    target.VNPC_PredatorFaction = faction
    local camp = VNPC_GetPredatorCamp and VNPC_GetPredatorCamp(target)
    if camp then
        camp.faction = faction
    end
    ply:ChatPrint("[V-NPCs] Set " .. tostring(target) .. "'s faction to: " .. string.upper(faction))
end)

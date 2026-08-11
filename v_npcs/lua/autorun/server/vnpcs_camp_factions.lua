-- V-NPCs Faction-Based Predator Camps & Camp Clashing / War AI Engine (vnpcs_camp_factions.lua)
-- Predator camps are organized into Factions (mostly Metrocop & Zombie); rival camps accumulate tension and clash in open vore battles

local clashing_enabled = CreateConVar("vnpcs_camp_clashing_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable predator camp faction wars and tension clashing")
local tension_rate = CreateConVar("vnpcs_camp_tension_rate", "1.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Tension growth per second between rival predator camps within 3500 units")
local tension_passive_rate = CreateConVar("vnpcs_camp_tension_passive_rate", "0.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Passive distance-based tension growth (0 = dynamic incident-only tension)")
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
    if cls:find("citizen") or cls:find("rebel") or cls:find("refugee") or cls:find("alyx") or cls:find("mossman") or mdl:find("citizen") or mdl:find("group0") then
        pred.VNPC_PredatorFaction = "citizen"
        return "citizen"
    end

    -- Mostly Female Metrocops and Female Zombies as default predator factions
    local defaultFactions = { "metrocop", "metrocop", "zombie", "zombie", "citizen" }
    pred.VNPC_PredatorFaction = defaultFactions[math.random(1, #defaultFactions)]
    return pred.VNPC_PredatorFaction
end

function VNPC_GetTensionKey(id1, id2)
    return math.min(id1, id2) .. "_" .. math.max(id1, id2)
end

function VNPC_AddCampTension(campA, campB, amount, reason)
    if not clashing_enabled:GetBool() or not campA or not campB then return end
    if campA == campB or campA.faction == campB.faction then return end

    local key = VNPC_GetTensionKey(campA.id, campB.id)
    local current = VNPC_CampTensions[key] or 0
    local newTension = math.Clamp(current + amount, 0, 100.0)
    VNPC_CampTensions[key] = newTension

    if newTension >= war_thresh:GetFloat() and campA.state ~= "war" and campB.state ~= "war" then
        VNPC_TriggerCampWar(campA, campB)
    end
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
                        local rate = (1.0 + (3500 - dist) / 1500) * tension_passive_rate:GetFloat()
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

-- Incident 1: Predator-on-predator swallowing (+45.0 Tension)
hook.Add("VNPC_OnPreySwallowed", "VNPC_CampTension_VoreIncident", function(pred, prey, belly)
    if not clashing_enabled:GetBool() then return end
    if not IsValid(pred) or not IsValid(prey) then return end
    if not (prey.IsDrGNextbot or prey.VNPC_FemaleModelVore or prey.Predator) then return end

    local predCamp = VNPC_GetPredatorCamp and VNPC_GetPredatorCamp(pred)
    local preyCamp = VNPC_GetPredatorCamp and VNPC_GetPredatorCamp(prey)

    if predCamp and preyCamp and predCamp ~= preyCamp and predCamp.faction ~= preyCamp.faction then
        VNPC_AddCampTension(predCamp, preyCamp, 45.0, pred:GetClass() .. " swallowed rival " .. prey:GetClass())
    elseif predCamp and not preyCamp then
        -- Poaching incident (+20.0 Tension) when swallowing prey near a rival camp
        for _, campB in ipairs(VNPC_ActivePredatorCamps or {}) do
            if campB ~= predCamp and campB.faction ~= predCamp.faction then
                if prey:GetPos():DistToSqr(campB.pos) < (900 * 900) then
                    VNPC_AddCampTension(predCamp, campB, 20.0, pred:GetClass() .. " poached prey near Camp #" .. campB.id)
                    break
                end
            end
        end
    end
end)

-- Incident 2: Attacking / Damaging a Rival Campmate (+15.0 Tension)
hook.Add("EntityTakeDamage", "VNPC_CampTension_DamageIncident", function(target, dmginfo)
    if not clashing_enabled:GetBool() then return end
    local attacker = dmginfo:GetAttacker()
    if not IsValid(attacker) or not IsValid(target) or attacker == target then return end
    if not (attacker.IsDrGNextbot or attacker.VNPC_FemaleModelVore or attacker.Predator) then return end
    if not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then return end

    local campA = VNPC_GetPredatorCamp and VNPC_GetPredatorCamp(attacker)
    local campB = VNPC_GetPredatorCamp and VNPC_GetPredatorCamp(target)

    if campA and campB and campA ~= campB and campA.faction ~= campB.faction then
        local now = CurTime()
        local key = VNPC_GetTensionKey(campA.id, campB.id)
        VNPC_NextDamageTensionMsg = VNPC_NextDamageTensionMsg or {}
        if (VNPC_NextDamageTensionMsg[key] or 0) <= now then
            VNPC_NextDamageTensionMsg[key] = now + 8.0
            VNPC_AddCampTension(campA, campB, 15.0, attacker:GetClass() .. " attacked rival " .. target:GetClass())
        end
    end
end)

concommand.Add("vnpcs_camp_factions_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Predator Camp Factions & Clashing / War AI Status")
    print("Enabled: " .. tostring(clashing_enabled:GetBool()))
    print("Dynamic Incident Tension: ACTIVE (+45 Vore, +15 Damage, +20 Poaching)")
    print("Passive Distance Rate: " .. tostring(tension_passive_rate:GetFloat()) .. " / sec (0 = Dynamic Only)")
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

concommand.Add("vnpcs_test_camp_tension", function(ply, cmd, args)
    if not IsValid(ply) then return end
    local amt = tonumber(args[1]) or 45.0
    local camps = VNPC_ActivePredatorCamps or {}
    if #camps < 2 then
        ply:ChatPrint("[V-NPCs] At least 2 active predator camps are needed to test tension!")
        return
    end
    local campA, campB = camps[1], camps[2]
    campA.faction = "metrocop"
    campB.faction = "zombie"
    VNPC_AddCampTension(campA, campB, amt, "Testing Dynamic Tension Command")
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

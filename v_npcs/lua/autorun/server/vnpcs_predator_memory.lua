-- V-NPCs Predator Camp Memory & Emissary Mate Recognition Engine (vnpcs_predator_memory.lua)
-- Predator camps remember recognized male emissaries, greeting them warmly and bypassing boredom when their loved mate returns

local memory_enabled = CreateConVar("vnpcs_pred_memory_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable predator camps remembering recognized emissary mates and giving warm welcomes")

function VNPC_RecordRecognizedMate(predCamp, pred, emissary)
    if not memory_enabled:GetBool() or not predCamp or not IsValid(pred) or not IsValid(emissary) then return end

    predCamp.recognizedMates = predCamp.recognizedMates or {}
    local existing = predCamp.recognizedMates[emissary]
    local count = existing and existing.visits or 0

    predCamp.recognizedMates[emissary] = {
        mateEnt = pred,
        name = emissary.PrintName or emissary:GetClass() or "Emissary",
        lastVisitTime = CurTime(),
        visits = count + 1
    }

    emissary.VNPC_LovedPredator = pred
    pred.VNPC_LovedMate = emissary
end

function VNPC_CheckRecognizedMateWelcome(predCamp, emissary, preyCamp)
    if not memory_enabled:GetBool() or not predCamp or not IsValid(emissary) then return false end

    predCamp.recognizedMates = predCamp.recognizedMates or {}
    local rec = predCamp.recognizedMates[emissary]
    local lovedPred = emissary.VNPC_LovedPredator or (rec and rec.mateEnt)

    if not IsValid(lovedPred) or lovedPred:Health() <= 0 or lovedPred.VNPC_CampID ~= predCamp.id then
        return false
    end

    -- 1. Give a warm welcome by the camp on subsequent visits
    local now = CurTime()
    if (predCamp.lastWelcomeTime or 0) <= now then
        predCamp.lastWelcomeTime = now + 30.0
        for _, mem in ipairs(predCamp.members) do
            if IsValid(mem) and mem.EmitSound then
                mem:EmitSound("npc/citizen/vo/nice.wav", 80, math.random(106, 114))
            end
        end
        for _, p in ipairs(player.GetAll()) do
            p:ChatPrint("[V-NPCs] WARM WELCOME! Predator Camp #" .. predCamp.id .. " recognizes returning Emissary " .. (emissary.PrintName or emissary:GetClass()) .. " and greets him as an honored mate!")
        end
    end

    -- 2. Her loved mate says YES immediately without requiring boredom
    if not IsValid(lovedPred:GetEnemy()) and predCamp.state ~= "war" and not lovedPred.VNPC_IsVisitingPreyCamp then
        VNPC_PredatorAgreeToEmissary(lovedPred, emissary, preyCamp, predCamp)
        if lovedPred.EmitSound then
            lovedPred:EmitSound("npc/citizen/vo/nice.wav", 85, 115)
        end
        for _, p in ipairs(player.GetAll()) do
            p:ChatPrint("[V-NPCs] LOVED MATE RECOGNIZED! Predator " .. lovedPred:GetClass() .. " recognized her returning mate " .. (emissary.PrintName or emissary:GetClass()) .. " and agreed immediately without needing to be bored!")
        end
        return true
    end

    return false
end

function VNPC_PredatorCampMatesGreeting_AI(camp, now)
    if not memory_enabled:GetBool() or not camp or not camp.pos or camp.state == "war" then return end

    local nearbyMales = {}
    for _, ent in ipairs(ents.FindInSphere(camp.pos, 500)) do
        if IsValid(ent) and ent:Health() > 0 and not ent.Vored and not ent.VNPC_Vored then
            if VNPC_IsMalePreyCitizen and VNPC_IsMalePreyCitizen(ent) then
                table.insert(nearbyMales, ent)
            end
        end
    end

    if #nearbyMales == 0 then return end

    for _, pred in ipairs(camp.members) do
        if not IsValid(pred) or pred:Health() <= 0 or pred.Vored or pred.VNPC_Vored then continue end
        if IsValid(pred:GetEnemy()) or (now - (pred.VNPC_LastDamagedTime or 0)) < 15.0 then continue end
        if (pred.VNPC_NextMateHelloTime or 0) > now then continue end

        local predPos = pred:GetPos()
        for _, male in ipairs(nearbyMales) do
            if predPos:DistToSqr(male:GetPos()) <= (250 * 250) then
                pred.VNPC_NextMateHelloTime = now + 20.0

                if pred.EmitSound then
                    local helloSounds = {
                        "npc/citizen/vo/hello.wav",
                        "npc/citizen/vo/hi.wav",
                        "npc/alyx/vo/hello.wav",
                        "npc/alyx/vo/hi.wav",
                        "npc/citizen/vo/nice.wav"
                    }
                    local snd = helloSounds[math.random(1, #helloSounds)]
                    pred:EmitSound(snd, 75, math.random(106, 114))
                end

                for _, p in ipairs(player.GetAll()) do
                    p:ChatPrint("[V-NPCs] " .. pred:GetClass() .. " says hello to " .. (male.PrintName or male:GetClass()) .. " at Predator Camp #" .. camp.id .. "!")
                end
                break
            end
        end
    end
end

hook.Add("Think", "VNPC_PredatorMatesGreeting_Loop", function()
    if not memory_enabled:GetBool() then return end
    local now = CurTime()
    if (VNPC_NextMateGreetingThink or 0) > now then return end
    VNPC_NextMateGreetingThink = now + 1.0

    for _, camp in ipairs(VNPC_ActivePredatorCamps or {}) do
        VNPC_PredatorCampMatesGreeting_AI(camp, now)
    end
end)

concommand.Add("vnpcs_pred_memory_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Predator Camp Memory & Emissary Mate Recognition Status")
    print("Enabled: " .. tostring(memory_enabled:GetBool()))
    print("-----------------------------------------")
    local totalMates = 0
    for idx, camp in ipairs(VNPC_ActivePredatorCamps or {}) do
        local count = 0
        for mateEnt, info in pairs(camp.recognizedMates or {}) do
            if IsValid(mateEnt) then
                count = count + 1
                totalMates = totalMates + 1
                print(string.format(" -> Camp [#%d] remembers Mate [%s] | Partner: %s | Visits: %d",
                    camp.id, tostring(info.name), tostring(info.mateEnt), info.visits or 1))
            end
        end
        if count == 0 then
            print(" -> Camp [#" .. camp.id .. "] remembers 0 mates.")
        end
    end
    print("Total recognized emissary mates across all camps: " .. totalMates)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Predator memory status printed to console. Recognized mates: " .. totalMates)
    end
end)

concommand.Add("vnpcs_test_record_mate", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at an Emissary/Citizen to record as a recognized mate!")
        return
    end
    local predCamp = nil
    for _, camp in ipairs(VNPC_ActivePredatorCamps or {}) do
        predCamp = camp
        break
    end
    if not predCamp or #predCamp.members == 0 then
        ply:ChatPrint("[V-NPCs] No active Predator Camp with members found!")
        return
    end
    local pred = predCamp.members[1]
    VNPC_RecordRecognizedMate(predCamp, pred, target)
    ply:ChatPrint("[V-NPCs] Recorded " .. tostring(target) .. " as a recognized mate for Predator Camp #" .. predCamp.id .. " with partner " .. tostring(pred) .. "!")
end)

concommand.Add("vnpcs_test_pred_hello", function(ply)
    if not IsValid(ply) then return end
    local count = 0
    for _, camp in ipairs(VNPC_ActivePredatorCamps or {}) do
        for _, pred in ipairs(camp.members) do
            if IsValid(pred) and pred.EmitSound then
                count = count + 1
                local helloSounds = {
                    "npc/citizen/vo/hello.wav",
                    "npc/citizen/vo/hi.wav",
                    "npc/alyx/vo/hello.wav",
                    "npc/alyx/vo/hi.wav"
                }
                pred:EmitSound(helloSounds[math.random(1, #helloSounds)], 80, math.random(106, 114))
            end
        end
    end
    ply:ChatPrint("[V-NPCs] Tested friendly greeting: " .. count .. " predators say hello!")
end)

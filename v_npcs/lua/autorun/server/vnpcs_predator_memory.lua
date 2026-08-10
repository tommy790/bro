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

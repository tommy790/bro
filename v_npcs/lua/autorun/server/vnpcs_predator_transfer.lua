-- V-NPCs Predator-on-Predator Belly Transfer & Nested Vore Engine (vnpcs_predator_transfer.lua)
-- Seamlessly transfers trapped prey and belly fat when a predator is swallowed alive

local transfer_enabled = CreateConVar("vnpcs_nested_vore_transfer", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Transfer prey from a swallowed predator into the master predator's stomach")
local transfer_fat_enabled = CreateConVar("vnpcs_transfer_belly_fat", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Transfer swallowed predator's BaseScale belly fat to the master predator")

function VNPC_PerformPredatorTransfer(masterPred, swallowedPred)
    if not transfer_enabled:GetBool() then return 0 end
    if not IsValid(masterPred) or not IsValid(swallowedPred) then return 0 end

    local masterBelly = masterPred.VNPC_Belly or masterPred.Belly
    local slaveBelly = swallowedPred.VNPC_Belly or swallowedPred.Belly
    if not IsValid(masterBelly) or not IsValid(slaveBelly) then return 0 end

    local transferred = 0
    if VNPC_TransferPrey then
        transferred = VNPC_TransferPrey(swallowedPred, masterPred)
    end

    if transfer_fat_enabled:GetBool() then
        local slaveFat = slaveBelly.BaseScale or 0
        if slaveFat > 0.05 and masterBelly.GainBellyFat then
            masterBelly:GainBellyFat(math.floor(slaveFat * 140))
            if slaveBelly.SetBaseScale then
                slaveBelly:SetBaseScale(0, 0)
            else
                slaveBelly.BaseScale = 0
            end
        end
    end

    if transferred > 0 and masterPred.EmitSound then
        masterPred:EmitSound("belly/snd_digeststart.wav", 80, math.random(90, 110))
    end

    return transferred
end

-- Hook into swallow loop
hook.Add("VNPC_OnPreySwallowed", "VNPC_PredatorOnPredatorTransfer", function(pred, prey, belly)
    if not transfer_enabled:GetBool() then return end
    if not IsValid(pred) or not IsValid(prey) then return end

    local preyBelly = prey.VNPC_Belly or prey.Belly
    if IsValid(preyBelly) then
        VNPC_PerformPredatorTransfer(pred, prey)
    end
end)

concommand.Add("vnpcs_nested_vore_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Nested Vore & Belly Transfer Status")
    print("Prey Transfer Enabled: " .. tostring(transfer_enabled:GetBool()))
    print("Belly Fat Transfer Enabled: " .. tostring(transfer_fat_enabled:GetBool()))
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Nested vore status printed to console.")
    end
end)

concommand.Add("vnpcs_test_pred_transfer", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsPlayer() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at a swallowed/slave predator to transfer prey to yourself!")
        return
    end
    local count = VNPC_PerformPredatorTransfer(ply, target)
    ply:ChatPrint("[V-NPCs] Transferred " .. count .. " prey from target to you!")
end)

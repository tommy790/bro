-- V-NPCs Existing Belly Fat Integration Engine (vnpcs_belly_fat_integration.lua)
-- Integrates the existing GainBellyFat/BaseScale system with hunger, sleeping naps, and slosh foley

local fat_integration_enabled = CreateConVar("vnpcs_fat_integration_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable integration between existing belly fat, sleep naps, and hunger")
local fat_sleep_threshold = CreateConVar("vnpcs_fat_sleep_threshold", "0.2", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Minimum BaseScale belly fat required to enable full-belly sleeping nap after digestion")
local fat_burn_rate = CreateConVar("vnpcs_fat_burn_rate", "0.005", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Rate at which belly fat is burned to slow starvation hunger")

function VNPC_GetExistingBellyFat(ent)
    if not IsValid(ent) then return 0 end
    local belly = ent.VNPC_Belly or ent.Belly
    if not IsValid(belly) then return 0 end
    return belly.BaseScale or 0
end

-- Hook into hunger engine to burn existing belly fat when starving
hook.Add("Think", "VNPC_ExistingBellyFat_HungerBurn", function()
    if not fat_integration_enabled:GetBool() then return end

    local dt = 0.5
    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end
        if not (ent:IsNPC() or ent:IsPlayer() or ent:IsNextBot()) then continue end

        local belly = ent.VNPC_Belly or ent.Belly
        if not IsValid(belly) then continue end

        local baseScale = belly.BaseScale or 0
        if baseScale > 0.05 and ent.VNPC_Hunger and ent.VNPC_Hunger > 50 then
            -- Burn existing belly fat to reduce hunger growth
            local burn = fat_burn_rate:GetFloat() * dt
            if belly.SetBaseScale then
                belly:SetBaseScale(math.max(0, baseScale - burn), baseScale)
            else
                belly.BaseScale = math.max(0, baseScale - burn)
            end
            ent.VNPC_Hunger = math.max(0, ent.VNPC_Hunger - (burn * 150))
        end
    end
end)

-- Hook into sleep AI: allow heavy fat predators to nap even when stomach is empty
hook.Add("VNPC_ShouldPredatorSleep", "VNPC_ExistingBellyFat_SleepThreshold", function(pred, belly)
    if not fat_integration_enabled:GetBool() then return nil end
    if not IsValid(belly) then return nil end

    local baseScale = belly.BaseScale or 0
    if baseScale >= fat_sleep_threshold:GetFloat() then
        return true
    end
    return nil
end)

concommand.Add("vnpcs_belly_fat_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Existing Belly Fat Integration Status")
    print("Integration Enabled: " .. tostring(fat_integration_enabled:GetBool()))
    print("Sleep Threshold BaseScale: " .. tostring(fat_sleep_threshold:GetFloat()))
    print("Fat Burn Rate: " .. tostring(fat_burn_rate:GetFloat()))
    print("-----------------------------------------")
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and (ent:IsNPC() or ent:IsPlayer() or ent:IsNextBot()) then
            local fat = VNPC_GetExistingBellyFat(ent)
            if fat > 0.01 then
                count = count + 1
                local belly = ent.VNPC_Belly or ent.Belly
                print(string.format(" -> [%d] %s | BaseScale: %.3f | MaxBaseScale: %s",
                    ent:EntIndex(), ent:GetClass(), fat, tostring(belly.MaxBaseScale or "N/A")))
            end
        end
    end
    print("Total predators with belly fat: " .. count)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Belly fat status printed to console. Active fat predators: " .. count)
    end
end)

concommand.Add("vnpcs_test_add_belly_fat", function(ply, cmd, args)
    if not IsValid(ply) then return end
    local power = tonumber(args[1]) or 25
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsPlayer() or target:IsNextBot()) then
        target = ply
    end
    local belly = target.VNPC_Belly or target.Belly
    if IsValid(belly) and belly.GainBellyFat then
        belly:GainBellyFat(power)
        ply:ChatPrint(string.format("[V-NPCs] Added belly fat (power %d) to %s! New BaseScale: %.3f", power, tostring(target), belly.BaseScale or 0))
    else
        ply:ChatPrint("[V-NPCs] Target has no valid vore belly or GainBellyFat method!")
    end
end)

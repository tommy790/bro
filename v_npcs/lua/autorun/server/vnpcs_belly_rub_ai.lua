-- V-NPCs Dynamic Belly Rubbing & Comfort AI Engine (vnpcs_belly_rub_ai.lua)
-- Calm full predators comfort-heal HP and emit digestive purr foley while resting with their hands on their belly

local rub_enabled = CreateConVar("vnpcs_belly_rub_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable belly rubbing comfort healing and contented foley on calm full predators")
local rub_heal_rate = CreateConVar("vnpcs_belly_rub_heal_rate", "2.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Health regeneration per second for calm full-belly rubbing predators")
local rub_sound_interval = CreateConVar("vnpcs_belly_rub_sound_interval", "14.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Interval in seconds between contented digest/burp foley when rubbing belly")

function VNPC_PerformBellyRubComfort(pred, belly)
    if not rub_enabled:GetBool() then return end
    if not IsValid(pred) or not IsValid(belly) then return end

    local maxHP = pred:GetMaxHealth() or 100
    local curHP = pred:Health()
    if curHP < maxHP and curHP > 0 then
        local heal = rub_heal_rate:GetFloat()
        pred:SetHealth(math.min(maxHP, curHP + heal))
    end

    local now = CurTime()
    if not pred.VNPC_NextRubSound or now >= pred.VNPC_NextRubSound then
        if pred.EmitSound then
            local snd = math.random() < 0.5 and "belly/snd_digestpassive.wav" or ("burps/burp" .. math.random(1, 23) .. ".wav")
            pred:EmitSound(snd, 70, math.random(88, 104))
        end
        pred.VNPC_NextRubSound = now + rub_sound_interval:GetFloat()
    end
end

hook.Add("Think", "VNPC_BellyRubComfort_Loop", function()
    if not rub_enabled:GetBool() then return end

    local now = CurTime()
    for _, pred in ipairs(ents.GetAll()) do
        if not IsValid(pred) or pred.Vored or pred.VNPC_Vored then continue end
        if not (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) then continue end
        if (pred.VNPC_NextRubThink or 0) > now then continue end
        pred.VNPC_NextRubThink = now + 1.0

        local belly = pred.VNPC_Belly or pred.Belly
        if not IsValid(belly) then continue end

        local hasPrey = (belly.Prey and #belly.Prey > 0) or (belly.DigestionPhase and belly.DigestionPhase > 0)
        if not hasPrey then continue end

        -- Must be calm (not in combat, not recently damaged)
        local isCalm = true
        if VNPC_IsPredatorCalm then
            isCalm = VNPC_IsPredatorCalm(pred)
        else
            isCalm = not IsValid(pred:GetEnemy()) and not (pred.IsMoving and pred:IsMoving())
        end

        if isCalm then
            VNPC_PerformBellyRubComfort(pred, belly)
        end
    end
end)

concommand.Add("vnpcs_belly_rub_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Belly Rubbing & Comfort AI Status")
    print("Comfort Enabled: " .. tostring(rub_enabled:GetBool()))
    print("Heal Rate: " .. tostring(rub_heal_rate:GetFloat()) .. " HP/sec")
    print("Sound Interval: " .. tostring(rub_sound_interval:GetFloat()) .. "s")
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Belly rub comfort status printed to console.")
    end
end)

concommand.Add("vnpcs_test_belly_rub", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a V-NPC predator to test belly rub comfort!")
        return
    end
    local belly = target.VNPC_Belly or target.Belly
    if IsValid(belly) then
        VNPC_PerformBellyRubComfort(target, belly)
        ply:ChatPrint("[V-NPCs] Tested belly rub comfort heal and sound on " .. tostring(target))
    else
        ply:ChatPrint("[V-NPCs] Target has no valid vore belly!")
    end
end)

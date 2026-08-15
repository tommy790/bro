-- V-NPCs Tactical Pack Hunting & Sister Predator Call-for-Help Engine (vnpcs_pack_hunting.lua)
-- Coordinates sister predators to converge on high-HP targets and boss enemies

local pack_enabled = CreateConVar("vnpcs_pack_hunting_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable pack hunting and call-for-help among sister predators")
local pack_radius = CreateConVar("vnpcs_pack_call_radius", "450", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Search radius for calling nearby sister predators")
local pack_hp_threshold = CreateConVar("vnpcs_pack_boss_hp_threshold", "180", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Minimum target HP to trigger a pack call-for-help alert")

function VNPC_CallSisterPredators(caller, enemy)
    if not pack_enabled:GetBool() then return 0 end
    if not IsValid(caller) or not IsValid(enemy) then return 0 end

    -- Solitary predators refuse pack calls.
    if VNPC_GetPackLimit and VNPC_GetPackLimit(caller) <= 1 then
        return 0
    end
    if caller.VNPC_IsDormant then return 0 end
    if VNPC_IsInActivePeriod and not VNPC_IsInActivePeriod(caller) then
        -- Off-peak: rarely bother calling a pack
        if math.random() > 0.25 then return 0 end
    end

    local now = CurTime()
    if (caller.VNPC_NextPackCall or 0) > now then return 0 end
    caller.VNPC_NextPackCall = now + 8.0

    local origin = caller:GetPos()
    local radiusSqr = pack_radius:GetFloat() ^ 2
    local count = 0
    local maxPack = (VNPC_GetPackLimit and VNPC_GetPackLimit(caller)) or 6
    -- already "has" self
    local room = math.max(0, maxPack - 1)

    for _, sister in ipairs(ents.GetAll()) do
        if count >= room then break end
        if not IsValid(sister) or sister == caller then continue end
        if not (sister.IsDrGNextbot or sister.VNPC_FemaleModelVore or sister.Predator) then continue end
        if sister.VNPC_IsDormant then continue end
        if VNPC_GetPackLimit and VNPC_GetPackLimit(sister) <= 1 then continue end -- solitary won't join

        -- Check distance
        if sister:GetPos():DistToSqr(origin) > radiusSqr then continue end

        -- Must not already be full
        local belly = sister.VNPC_Belly or sister.Belly
        if IsValid(belly) and ((belly.Prey and #belly.Prey > 0) or belly.DigestionPhase == 2) then continue end

        -- Command sister to converge on target
        if sister.SetEnemy then pcall(sister.SetEnemy, sister, enemy) end
        if sister.SetTarget then pcall(sister.SetTarget, sister, enemy) end
        sister.VNPC_PackTarget = enemy
        sister.VNPC_PackLeader = caller
        count = count + 1
    end

    if count > 0 and caller.EmitSound then
        caller:EmitSound("belly/snd_digeststart.wav", 85, 110)
    end

    return count
end

hook.Add("Think", "VNPC_PackHunting_AI_Loop", function()
    if not pack_enabled:GetBool() then return end

    local now = CurTime()
    for _, pred in ipairs(ents.GetAll()) do
        if not IsValid(pred) or pred.Vored or pred.VNPC_Vored then continue end
        if not (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) then continue end
        if (pred.VNPC_NextPackThink or 0) > now then continue end
        pred.VNPC_NextPackThink = now + 1.25

        local enemy = nil
        if pred.GetEnemy then
            local ok, en = pcall(pred.GetEnemy, pred)
            if ok then enemy = en end
        end
        if not IsValid(enemy) then continue end

        local maxHP = enemy:GetMaxHealth() or 100
        local curHP = enemy:Health()
        if curHP >= pack_hp_threshold:GetFloat() or maxHP >= pack_hp_threshold:GetFloat() or enemy:IsPlayer() then
            VNPC_CallSisterPredators(pred, enemy)
        end
    end
end)

concommand.Add("vnpcs_pack_hunting_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Pack Hunting & Sister Predator AI Status")
    print("Pack Hunting Enabled: " .. tostring(pack_enabled:GetBool()))
    print("Call Radius: " .. tostring(pack_radius:GetFloat()) .. " units")
    print("HP Threshold: " .. tostring(pack_hp_threshold:GetFloat()) .. " HP")
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Pack hunting status printed to console.")
    end
end)

concommand.Add("vnpcs_test_pack_call", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a female V-NPC predator to test pack calling!")
        return
    end
    local count = VNPC_CallSisterPredators(target, ply)
    ply:ChatPrint("[V-NPCs] Tested pack call from " .. tostring(target) .. " — alerted " .. count .. " sister predators!")
end)

-- V-NPCs Shy Predator Embarrassment AI Engine (vnpcs_shy_embarrassment.lua)
-- Shy predators get flustered, blush, and cover their big belly when prey or players stare at them

local embarrass_enabled = CreateConVar("vnpcs_shy_embarrass_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable shy predator embarrassment when seen with a big belly")
local embarrass_radius = CreateConVar("vnpcs_shy_embarrass_radius", "450.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Detection radius for prey or players to trigger shy embarrassment")
local embarrass_fat = CreateConVar("vnpcs_shy_embarrass_fat_thresh", "0.12", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Minimum BaseScale belly fat required to count as a big belly if empty of active prey")

function VNPC_IsShyPredator(pred)
    if not IsValid(pred) then return false end
    if pred.VNPC_ForceShyPredator then return true end
    if pred.VNPC_PredatorPersonality == "shy" or (pred.VoreSettings and pred.VoreSettings.PredatorPersonality == "shy") then
        return true
    end
    if VNPC_GetPredatorPersonality then
        local pers, _ = VNPC_GetPredatorPersonality(pred)
        if string.lower(tostring(pers or "")) == "shy" then
            return true
        end
    end
    return false
end

function VNPC_HasBigBelly(pred)
    if not IsValid(pred) then return false end
    local belly = pred.VNPC_Belly or pred.Belly
    if not IsValid(belly) then return false end

    if belly.Prey and #belly.Prey > 0 then
        return true
    end
    if belly.DigestionPhase and belly.DigestionPhase > 0 then
        return true
    end
    if belly.BaseScale and belly.BaseScale >= embarrass_fat:GetFloat() then
        return true
    end
    return false
end

function VNPC_TriggerShyEmbarrassment(pred, watcher, belly)
    if not embarrass_enabled:GetBool() then return end
    if not IsValid(pred) or pred:Health() <= 0 then return end
    if not IsValid(watcher) then return end

    local now = CurTime()
    pred.VNPC_IsEmbarrassed = now + 7.5

    if (pred.VNPC_NextEmbarrassSoundTime or 0) <= now then
        pred.VNPC_NextEmbarrassSoundTime = now + 12.0

        if pred.EmitSound then
            local snd = "npc/alyx/gasp03.wav"
            local rnd = math.random(1, 3)
            if rnd == 1 then
                snd = "npc/citizen/gasp02.wav"
            elseif rnd == 2 then
                snd = "npc/citizen/sigh01.wav"
            end
            pred:EmitSound(snd, 75, math.random(106, 114))
        end

        if pred.SetFacialExpression then
            pcall(pred.SetFacialExpression, pred, 4) -- Blushing / flustered face
            timer.Simple(2.5, function()
                if IsValid(pred) and pred.SetFacialExpression then
                    pcall(pred.SetFacialExpression, pred, 2)
                end
            end)
        end
    end

    -- Shy Tactical Behavior: turn away or retreat to cover away from the watcher
    local distSqr = pred:GetPos():DistToSqr(watcher:GetPos())
    if distSqr > (110 * 110) then
        if pred.SetSchedule then
            pcall(pred.SetSchedule, pred, SCHED_TAKE_COVER_FROM_ORIGIN)
        end
    else
        -- Panic-swallow if watcher gets uncomfortably close while she is embarrassed
        if watcher ~= pred and not watcher.Vored and not watcher.VNPC_Vored and pred.EatEntity then
            pcall(pred.EatEntity, pred, watcher)
        end
    end

    if watcher:IsPlayer() and (watcher.VNPC_NextShyNoticeTime or 0) <= now then
        watcher.VNPC_NextShyNoticeTime = now + 14.0
        watcher:ChatPrint("[V-NPCs] " .. (pred.PrintName or pred:GetClass()) .. " blushes and covers her big belly, embarrassed that you caught her full of prey!")
    end
end

hook.Add("Think", "VNPC_ShyEmbarrassment_Loop", function()
    if not embarrass_enabled:GetBool() then return end

    local now = CurTime()
    local radius = embarrass_radius:GetFloat()
    local radiusSqr = radius * radius

    for _, pred in ipairs(ents.GetAll()) do
        if not IsValid(pred) or pred:Health() <= 0 then continue end
        if not (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) then continue end
        if (pred.VNPC_NextShyThink or 0) > now then continue end
        pred.VNPC_NextShyThink = now + 0.6

        if not VNPC_IsShyPredator(pred) then continue end
        if not VNPC_HasBigBelly(pred) then
            pred.VNPC_IsEmbarrassed = nil
            continue
        end

        local belly = pred.VNPC_Belly or pred.Belly
        local predPos = pred:GetPos() + Vector(0, 0, 38)

        for _, watcher in ipairs(ents.FindInSphere(predPos, radius)) do
            if not IsValid(watcher) or watcher:Health() <= 0 or watcher == pred then continue end
            if watcher.Vored or watcher.VNPC_Vored then continue end
            if watcher.IsDrGNextbot or watcher.VNPC_FemaleModelVore or watcher.Predator then continue end
            if not (watcher:IsNPC() or watcher:IsPlayer() or watcher:IsNextBot()) then continue end

            -- Check if watcher is looking toward the shy predator
            local eye = watcher.EyePos and watcher:EyePos() or (watcher:GetPos() + Vector(0, 0, 50))
            local aim = watcher:GetAimVector() or watcher:GetForward()
            local toPred = (predPos - eye):GetNormalized()
            if aim:Dot(toPred) < 0.35 then continue end

            -- Check Line of Sight
            local tr = util.TraceLine({
                start = eye,
                endpos = predPos,
                filter = {watcher, pred, belly},
                mask = MASK_SOLID_BRUSHONLY
            })

            if not tr.Hit or tr.Fraction > 0.85 then
                VNPC_TriggerShyEmbarrassment(pred, watcher, belly)
                break
            end
        end
    end
end)

concommand.Add("vnpcs_shy_embarrass_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Shy Predator Embarrassment AI Status")
    print("Enabled: " .. tostring(embarrass_enabled:GetBool()))
    print("Detection Radius: " .. tostring(embarrass_radius:GetFloat()) .. " units")
    print("Big Belly Fat Threshold: " .. tostring(embarrass_fat:GetFloat()))
    print("-----------------------------------------")
    local count = 0
    for _, pred in ipairs(ents.GetAll()) do
        if IsValid(pred) and (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) and VNPC_IsShyPredator(pred) then
            local big = VNPC_HasBigBelly(pred)
            local emb = (pred.VNPC_IsEmbarrassed or 0) > CurTime()
            count = count + 1
            print(string.format(" -> Shy Predator [%s] | Big Belly: %s | Embarrassed: %s",
                tostring(pred), tostring(big), tostring(emb)))
        end
    end
    print("Total shy predators in map: " .. count)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Shy embarrassment status printed to console. Shy preds: " .. count)
    end
end)

concommand.Add("vnpcs_test_shy_embarrass", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a female V-NPC predator to test shy embarrassment!")
        return
    end
    target.VNPC_PredatorPersonality = "shy"
    if target.VoreSettings then target.VoreSettings.PredatorPersonality = "shy" end
    local belly = target.VNPC_Belly or target.Belly
    VNPC_TriggerShyEmbarrassment(target, ply, belly)
    ply:ChatPrint("[V-NPCs] Set " .. tostring(target) .. " as SHY and triggered embarrassment!")
end)

concommand.Add("vnpcs_set_shy", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a female V-NPC predator to set her as SHY!")
        return
    end
    target.VNPC_PredatorPersonality = "shy"
    if target.VoreSettings then target.VoreSettings.PredatorPersonality = "shy" end
    ply:ChatPrint("[V-NPCs] Set " .. tostring(target) .. " personality to SHY!")
end)

concommand.Add("vnpcs_test_embarrassed_pose", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a female V-NPC predator to test the embarrassed pose!")
        return
    end
    target.VNPC_IsEmbarrassed = CurTime() + 15.0
    if target.SetFacialExpression then
        pcall(target.SetFacialExpression, target, 4)
    end
    ply:ChatPrint("[V-NPCs] Triggered embarrassed pose on " .. tostring(target) .. " for 15 seconds!")
end)

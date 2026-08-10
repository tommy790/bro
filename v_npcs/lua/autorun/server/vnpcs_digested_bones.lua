-- V-NPCs Digested Bones Spitting & AI Alert Engine (vnpcs_digested_bones.lua)
-- When digestion finishes, predators spit out bones that freeze on the floor and alert nearby prey

local bones_enabled = CreateConVar("vnpcs_digested_bones_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable spitting digested bones after digestion finishes to alert nearby prey")
local bone_delay = CreateConVar("vnpcs_bone_spit_delay", "3.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Delay in seconds after digestion finishes before bones come out of the predator's mouth")
local bone_count = CreateConVar("vnpcs_bone_spit_count", "3", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Number of bone props ejected when digestion finishes")
local bone_freeze_delay = CreateConVar("vnpcs_bone_freeze_delay", "2.5", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Seconds after ejection before bones freeze in place on the floor")
local bone_alert_radius = CreateConVar("vnpcs_bone_alert_radius", "350", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Radius around frozen bones within which prey NPCs can notice them and become alerted")

local VNPC_BONE_MODELS = {
    "models/Gibs/HGIBS.mdl",         -- Human Skull
    "models/Gibs/HGIBS_ribf.mdl",    -- Ribcage
    "models/Gibs/HGIBS_spine.mdl",   -- Spine
    "models/Gibs/HGIBS_scapula.mdl", -- Scapula
    "models/Gibs/HGIBS_bone.mdl",    -- Long bone
}

VNPC_ActiveDigestedBones = VNPC_ActiveDigestedBones or {}

function VNPC_FreezeBoneProp(bone)
    if not IsValid(bone) or not bone.VNPC_DigestedBone then return end
    if bone.VNPC_FrozenBone then return end

    bone.VNPC_FrozenBone = true
    local phys = bone:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(Vector(0,0,0))
        phys:EnableMotion(false)
        phys:Sleep()
    end
end

function VNPC_SpitDigestedBones(pred, countOverride)
    if not bones_enabled:GetBool() then return end
    if not IsValid(pred) or pred:Health() <= 0 then return end
    if pred.Swallowing then return end
    if VNPC_IsHL2ScriptedScene and VNPC_IsHL2ScriptedScene(pred) then return end

    local count = countOverride or bone_count:GetInt() or 3

    -- Open mouth / burp facial expression
    if pred.SetFacialExpression then
        pcall(pred.SetFacialExpression, pred, 3)
        timer.Simple(1.35, function()
            if IsValid(pred) and pred.SetFacialExpression then
                pcall(pred.SetFacialExpression, pred, 0)
            end
        end)
    end

    -- Play burp / regurgitation sound
    if pred.EmitSound then
        local snd = "burps/burp" .. math.random(1, 23) .. ".wav"
        pred:EmitSound(snd, 85, math.random(92, 108))
    end

    -- Calculate mouth ejection origin
    local fwd = pred:GetForward()
    local up = pred:GetUp()
    local right = pred:GetRight()
    local origin = pred:GetPos() + Vector(0, 0, (pred:OBBMaxs().z or 65) * 0.78) + fwd * 18

    local headBone = pred:LookupBone("ValveBiped.Bip01_Head1") or pred:LookupBone("Head1")
    if headBone then
        local bPos = pred:GetBonePosition(headBone)
        if isvector(bPos) and bPos ~= vector_origin then
            origin = bPos + fwd * 16 + up * 4
        end
    elseif pred.EyePos then
        local ePos = pred:EyePos()
        if isvector(ePos) and ePos ~= vector_origin then
            origin = ePos + fwd * 16 - up * 4
        end
    end

    for i = 1, count do
        local bone = ents.Create("prop_physics")
        if not IsValid(bone) then continue end

        local mdlIndex = ((i - 1) % #VNPC_BONE_MODELS) + 1
        local mdl = VNPC_BONE_MODELS[mdlIndex]
        if not util.IsValidModel(mdl) then
            mdl = "models/Gibs/HGIBS_bone.mdl"
        end

        bone:SetModel(mdl)
        bone:SetPos(origin + fwd * (i * 3) + right * math.random(-6, 6) + up * math.random(-2, 4))
        bone:SetAngles(Angle(math.random(0,360), pred:GetAngles().y, math.random(0,360)))
        bone:Spawn()
        bone:Activate()

        bone.VNPC_DigestedBone = true
        bone.VNPC_BoneOwner = pred
        bone.VNPC_BoneSpawnTime = CurTime()
        bone:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

        table.insert(VNPC_ActiveDigestedBones, bone)

        -- Prune oldest bones if map exceeds 40 active bone props
        while #VNPC_ActiveDigestedBones > 40 do
            local oldBone = table.remove(VNPC_ActiveDigestedBones, 1)
            if IsValid(oldBone) then
                oldBone:Remove()
            end
        end

        local phys = bone:GetPhysicsObject()
        if IsValid(phys) then
            phys:Wake()
            local force = fwd * math.random(150, 240) + right * math.random(-40, 40) + up * math.random(90, 150)
            phys:SetVelocity(force)
            phys:AddAngleVelocity(Vector(math.random(-250, 250), math.random(-250, 250), math.random(-250, 250)))
        end

        -- Schedule freezing in place on floor
        local fDelay = math.max(0.5, bone_freeze_delay:GetFloat())
        timer.Simple(fDelay, function()
            if IsValid(bone) then
                VNPC_FreezeBoneProp(bone)
            end
        end)
    end

    if VNPC_CreateTerritoryScentNode then
        VNPC_CreateTerritoryScentNode(pred, origin, "bones")
    end
end

function VNPC_ScheduleDigestedBoneSpit(pred, belly)
    if not bones_enabled:GetBool() then return end
    if not IsValid(pred) then return end

    local now = CurTime()
    if (pred.VNPC_NextBoneSpitSchedule or 0) > now then return end
    pred.VNPC_NextBoneSpitSchedule = now + 5.0 -- Debounce so only one bone spit per meal

    local delay = math.max(0.5, bone_delay:GetFloat())
    timer.Simple(delay, function()
        if IsValid(pred) and pred:Health() > 0 then
            VNPC_SpitDigestedBones(pred, bone_count:GetInt())
        end
    end)
end

function VNPC_FindNearestPredator(pos, radius)
    local best = nil
    local bestDist = radius * radius
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent:Health() > 0 and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) then
            local dist = ent:GetPos():DistToSqr(pos)
            if dist <= bestDist then
                best = ent
                bestDist = dist
            end
        end
    end
    return best
end

hook.Add("Think", "VNPC_DigestedBones_AI_Loop", function()
    if not bones_enabled:GetBool() then return end

    local now = CurTime()
    local fDelay = math.max(0.5, bone_freeze_delay:GetFloat())
    local alertRadius = bone_alert_radius:GetFloat()
    local alertRadiusSqr = alertRadius * alertRadius

    for i = #VNPC_ActiveDigestedBones, 1, -1 do
        local bone = VNPC_ActiveDigestedBones[i]
        if not IsValid(bone) then
            table.remove(VNPC_ActiveDigestedBones, i)
            continue
        end

        -- Safety freeze check
        if not bone.VNPC_FrozenBone and now >= (bone.VNPC_BoneSpawnTime + fDelay) then
            VNPC_FreezeBoneProp(bone)
        end

        -- Once frozen on the floor, alert nearby prey NPCs
        if bone.VNPC_FrozenBone then
            for _, npc in ipairs(ents.FindInSphere(bone:GetPos(), alertRadius)) do
                if not IsValid(npc) or npc:Health() <= 0 or npc == bone.VNPC_BoneOwner then continue end
                if npc.Vored or npc.VNPC_Vored then continue end
                if npc.IsDrGNextbot or npc.VNPC_FemaleModelVore or npc.Predator then continue end

                -- Player alert chat notification
                if npc:IsPlayer() then
                    if (npc.VNPC_NextPlayerBoneNoticeTime or 0) <= now then
                        npc.VNPC_NextPlayerBoneNoticeTime = now + 15.0
                        npc:ChatPrint("[V-NPCs] You notice digested bones on the floor... A predator is nearby!")
                    end
                    continue
                end

                if not (npc:IsNPC() or npc:IsNextBot()) then continue end
                if (npc.VNPC_NextBoneAlertTime or 0) > now then continue end

                -- Check line of sight from NPC to bone
                local eye = npc.EyePos and npc:EyePos() or (npc:GetPos() + Vector(0, 0, 50))
                local tr = util.TraceLine({
                    start = eye,
                    endpos = bone:GetPos() + Vector(0, 0, 8),
                    filter = {npc, bone},
                    mask = MASK_SOLID_BRUSHONLY
                })

                if not tr.Hit or tr.Fraction > 0.85 then
                    npc.VNPC_NextBoneAlertTime = now + 12.0
                    npc.VNPC_NoticedBones = true

                    if npc.EmitSound then
                        local alertSnd = math.random() < 0.5 and "npc/citizen/fear01.wav" or "npc/combine_soldier/vo/alert1.wav"
                        npc:EmitSound(alertSnd, 75, math.random(95, 105))
                    end

                    local pred = bone.VNPC_BoneOwner
                    if not IsValid(pred) or pred:Health() <= 0 then
                        pred = VNPC_FindNearestPredator(bone:GetPos(), 800)
                    end

                    if IsValid(pred) and pred:Health() > 0 then
                        local cls = npc:GetClass() or ""
                        local isCitizen = (npc.Classify and npc:Classify() == CLASS_CITIZEN) or cls:find("citizen") or cls:find("hostage")
                        if isCitizen then
                            -- Shy / civilian prey panics and flees from the predator
                            if npc.SetEnemy then pcall(npc.SetEnemy, npc, pred) end
                            if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_RUN_FROM_ENEMY) end
                        else
                            -- Armed combatant alerts to combat and targets the predator
                            if npc.SetEnemy then pcall(npc.SetEnemy, npc, pred) end
                            if npc.SetTarget then pcall(npc.SetTarget, npc, pred) end
                            if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_ALERT_STAND) end
                            if npc.UpdateEnemyMemory then pcall(npc.UpdateEnemyMemory, npc, pred, bone:GetPos()) end
                        end
                        hook.Run("VNPC_OnPreyNoticedBones", npc, bone, pred)
                    end
                end
            end
        end
    end
end)

concommand.Add("vnpcs_bone_spit_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Digested Bones & Alert AI Status")
    print("Enabled: " .. tostring(bones_enabled:GetBool()))
    print("Spit Delay: " .. tostring(bone_delay:GetFloat()) .. "s")
    print("Bone Count: " .. tostring(bone_count:GetInt()))
    print("Freeze Delay: " .. tostring(bone_freeze_delay:GetFloat()) .. "s")
    print("Alert Radius: " .. tostring(bone_alert_radius:GetFloat()) .. " units")
    print("-----------------------------------------")
    local count = 0
    for _, bone in ipairs(VNPC_ActiveDigestedBones) do
        if IsValid(bone) then
            count = count + 1
            print(string.format(" -> Bone [%d] %s | Owner: %s | Frozen: %s",
                bone:EntIndex(), bone:GetModel() or "N/A", tostring(bone.VNPC_BoneOwner), tostring(bone.VNPC_FrozenBone or false)))
        end
    end
    print("Total active digested bones: " .. count)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Bone spit status printed to console. Active bones: " .. count)
    end
end)

concommand.Add("vnpcs_test_bone_spit", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsPlayer() or target:IsNextBot()) then
        target = ply
    end
    VNPC_SpitDigestedBones(target, bone_count:GetInt())
    ply:ChatPrint("[V-NPCs] Tested digested bone spit from " .. tostring(target))
end)

concommand.Add("vnpcs_clear_bones", function(ply)
    local removed = 0
    for i = #VNPC_ActiveDigestedBones, 1, -1 do
        local bone = VNPC_ActiveDigestedBones[i]
        if IsValid(bone) then
            bone:Remove()
            removed = removed + 1
        end
        table.remove(VNPC_ActiveDigestedBones, i)
    end
    print("[V-NPCs] Removed " .. removed .. " digested bones from the map.")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Removed " .. removed .. " digested bones from the map.")
    end
end)

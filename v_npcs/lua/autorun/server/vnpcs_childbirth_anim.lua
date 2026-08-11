-- V-NPCs Pregnant Citizen Womb Growth & Childbirth Bone Pose Engine (vnpcs_childbirth_anim.lua)
-- Spawns unborn baby citizens inside pregnant mothers; grows from value 10 to 50; mother sits with legs separated to give birth; baby grows to full size 1.0 in 60s

local growth_rate = CreateConVar("vnpcs_prey_camp_baby_growth_rate", "1.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Growth value gained per second for unborn babies inside the womb (value 10 to 50)")
local child_grow_time = CreateConVar("vnpcs_prey_camp_child_grow_time", "60.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Duration in seconds for a born baby citizen to grow from 0.35 to full size 1.0")
local childbirth_enabled = CreateConVar("vnpcs_childbirth_anim_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable sitting childbirth bone pose animation and pregnancy belly bulge")

function VNPC_IsProtectedChildPrey(ent)
    if not IsValid(ent) then return false end
    if ent.VNPC_IsUnbornBaby or ent.VNPC_IsGrowingBaby or ent.VNPC_ProtectedChild then return true end
    if ent.VNPC_PreyCampID and (ent:GetModelScale() or 1) < 0.95 then return true end
    return false
end

function VNPC_IsAdultPreyCitizen(ent)
    if not IsValid(ent) or ent:Health() <= 0 then return false end
    if ent.VNPC_IsUnbornBaby or ent.VNPC_IsGrowingBaby or ent.VNPC_ProtectedChild then return false end
    if (ent:GetModelScale() or 1) < 0.95 then return false end
    return true
end

VNPC_ChildbirthSittingPoseKeyframe = {
    ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(15, 0, 0) },
    ["ValveBiped.Bip01_Spine"] = { pos = Vector(0, 0, 0), ang = Angle(-12, 0, 0) },
    ["ValveBiped.Bip01_Spine1"] = { pos = Vector(0, 0, 0), ang = Angle(-10, 0, 0) },
    ["ValveBiped.Bip01_Spine2"] = { pos = Vector(0, 0, 0), ang = Angle(-8, 0, 0) },
    ["ValveBiped.Bip01_Pelvis"] = { pos = Vector(0, 0, -22), ang = Angle(-15, 0, 0) },
    ["ValveBiped.Bip01_R_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(-75, -45, 0) },
    ["ValveBiped.Bip01_L_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(-75, 45, 0) },
    ["ValveBiped.Bip01_R_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(110, 0, 0) },
    ["ValveBiped.Bip01_L_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(110, 0, 0) },
    ["ValveBiped.Bip01_R_Foot"] = { pos = Vector(0, 0, 0), ang = Angle(-20, 0, 0) },
    ["ValveBiped.Bip01_L_Foot"] = { pos = Vector(0, 0, 0), ang = Angle(-20, 0, 0) },
    ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(35, -25, 15) },
    ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(35, 25, -15) },
    ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-60, 20, -10) },
    ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-60, -20, 10) }
}

function VNPC_ApplyPregnancyBellyBulge(mother, val)
    if not IsValid(mother) or not mother.LookupBone or not mother.ManipulateBoneScale then return end
    local spineBone = mother:LookupBone("ValveBiped.Bip01_Spine") or mother:LookupBone("Spine")
    local pelvisBone = mother:LookupBone("ValveBiped.Bip01_Pelvis") or mother:LookupBone("Pelvis")
    local factor = math.Clamp((val - 10) / 40, 0, 1)
    local scaleVec = Vector(1.0 + factor * 0.45, 1.0 + factor * 0.40, 1.0 + factor * 0.35)

    if spineBone then
        mother:ManipulateBoneScale(spineBone, scaleVec)
    end
    if pelvisBone then
        mother:ManipulateBoneScale(pelvisBone, Vector(1.0 + factor * 0.25, 1.0 + factor * 0.25, 1.0 + factor * 0.20))
    end
end

function VNPC_ResetPregnancyBellyBulge(mother)
    if not IsValid(mother) or not mother.LookupBone or not mother.ManipulateBoneScale then return end
    local spineBone = mother:LookupBone("ValveBiped.Bip01_Spine") or mother:LookupBone("Spine")
    local pelvisBone = mother:LookupBone("ValveBiped.Bip01_Pelvis") or mother:LookupBone("Pelvis")
    if spineBone then
        mother:ManipulateBoneScale(spineBone, Vector(1, 1, 1))
    end
    if pelvisBone then
        mother:ManipulateBoneScale(pelvisBone, Vector(1, 1, 1))
    end
end

function VNPC_ApplyChildbirthBonePose(mother, apply)
    if not IsValid(mother) or not mother.LookupBone then return end
    for boneName, data in pairs(VNPC_ChildbirthSittingPoseKeyframe) do
        local boneID = mother:LookupBone(boneName)
        if boneID then
            if apply then
                if data.ang then mother:ManipulateBoneAngles(boneID, data.ang) end
                if data.pos then mother:ManipulateBonePosition(boneID, data.pos) end
            else
                mother:ManipulateBoneAngles(boneID, angle_zero)
                mother:ManipulateBonePosition(boneID, vector_origin)
            end
        end
    end
end

function VNPC_StartChildbirthAnimation(mother, child, camp)
    if not IsValid(mother) then return end

    mother.VNPC_IsPregnant = nil
    mother.VNPC_UnbornChild = nil
    mother.VNPC_BabyGrowthValue = nil

    -- 1. Apply Sitting Childbirth Pose with legs separated
    if childbirth_enabled:GetBool() then
        if mother.SetSchedule then pcall(mother.SetSchedule, mother, SCHED_NPC_FREEZE) end
        mother.VNPC_InChildbirthPose = CurTime() + 4.5
        VNPC_ApplyChildbirthBonePose(mother, true)
        if mother.EmitSound then
            local snd = math.random() < 0.5 and "npc/alyx/sigh01.wav" or "npc/citizen/vo/citizen_we_are_safe.wav"
            mother:EmitSound(snd, 80, math.random(105, 115))
        end
    end

    -- 2. Ensure child exists and eject onto ground between separated knees
    if not IsValid(child) then
        child = ents.Create("npc_citizen")
        if IsValid(child) then
            child:SetPos(mother:GetPos() + mother:GetForward() * 24 + Vector(0, 0, 5))
            child:SetAngles(Angle(0, mother:GetAngles().y, 0))
            child:Spawn()
            child:Activate()
        end
    end

    if IsValid(child) then
        child:SetParent(nil)
        child:SetNoDraw(false)
        child:SetSolid(SOLID_BBOX)
        child:SetMoveType(MOVETYPE_STEP)
        child:SetPos(mother:GetPos() + mother:GetForward() * 26 + Vector(0, 0, 6))
        child:SetAngles(Angle(0, mother:GetAngles().y, 0))
        child:SetModelScale(0.35, 0)

        child.VNPC_ChildGender = math.random() < 0.5 and "female" or "male"
        if child.VNPC_ChildGender == "female" then
            child:SetModel("models/Humans/Group01/Female_01.mdl")
        else
            child:SetModel("models/Humans/Group01/Male_01.mdl")
        end

        child.VNPC_IsUnbornBaby = nil
        child.VNPC_IsGrowingBaby = true
        child.VNPC_ProtectedChild = true
        child.VNPC_BabyBirthTime = CurTime()
        child.VNPC_BabyGrowDuration = child_grow_time:GetFloat()

        if camp and camp.members then
            if not table.HasValue(camp.members, child) then
                table.insert(camp.members, child)
            end
            child.VNPC_PreyCampID = camp.id
        end
        if mother.VNPC_PreyCampBabyMother then
            child.VNPC_BornSister = nil
            child.VNPC_AdoptedByPredator = nil
            child.VNPC_MotherRef = nil
        end

        if child.EmitSound then
            child:EmitSound("npc/citizen/vo/nice.wav", 80, 135)
        end
    end

    -- 3. Restore mother after 4.5 seconds of resting in childbirth pose
    timer.Simple(4.5, function()
        if IsValid(mother) then
            VNPC_ApplyChildbirthBonePose(mother, false)
            VNPC_ResetPregnancyBellyBulge(mother)
            if mother.SetSchedule then pcall(mother.SetSchedule, mother, SCHED_IDLE_STAND) end
        end
    end)
end

-- 1-Minute Baby Citizen Growth Loop
hook.Add("Think", "VNPC_BabyCitizenGrowth_Loop", function()
    local now = CurTime()

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) or ent:Health() <= 0 then continue end

        -- 1. Unborn Baby inside Womb: sync position with mother
        if ent.VNPC_IsUnbornBaby and IsValid(ent.VNPC_MotherRef) then
            ent:SetPos(ent.VNPC_MotherRef:GetPos() + Vector(0, 0, 32))
            continue
        end

        -- 2. Born Baby Citizen: grow from 0.35 to 1.0 over 60 seconds
        if ent.VNPC_IsGrowingBaby then
            local duration = ent.VNPC_BabyGrowDuration or 60.0
            local tNorm = math.Clamp((now - (ent.VNPC_BabyBirthTime or now)) / duration, 0, 1)
            local scale = 0.35 + (tNorm * 0.65)
            ent:SetModelScale(scale, 0)

            if tNorm >= 1.00 then
                ent:SetModelScale(1.0, 0)
                ent.VNPC_IsGrowingBaby = nil
                ent.VNPC_ProtectedChild = nil

                if (ent.VNPC_AdoptedByPredator or ent.VNPC_BornSister) and VNPC_TransformToPredator then
                    VNPC_TransformToPredator(ent, ent.VNPC_AdoptedByPredator or ent.VNPC_MotherRef)
                    return
                end

                if ent.EmitSound then
                    ent:EmitSound("npc/citizen/vo/readytohelp.wav", 80, 105)
                end
            end
        end
    end
end)

concommand.Add("vnpcs_childbirth_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Pregnant Citizen Womb Growth & Childbirth Status")
    print("Enabled: " .. tostring(childbirth_enabled:GetBool()))
    print("Womb Growth Rate: " .. tostring(growth_rate:GetFloat()) .. " / sec")
    print("Child Grow Time: " .. tostring(child_grow_time:GetFloat()) .. "s")
    print("-----------------------------------------")
    local pregCount, growCount = 0, 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) then
            if ent.VNPC_IsPregnant and ent.VNPC_BabyGrowthValue then
                pregCount = pregCount + 1
                print(string.format(" -> Pregnant Citizen [%d] | Growth Value: %.1f / 50.0", ent:EntIndex(), ent.VNPC_BabyGrowthValue))
            end
            if ent.VNPC_IsGrowingBaby then
                growCount = growCount + 1
                local pct = math.Clamp((CurTime() - (ent.VNPC_BabyBirthTime or 0)) / (ent.VNPC_BabyGrowDuration or 60) * 100, 0, 100)
                print(string.format(" -> Growing Baby [%d] %s | Scale: %.2f (%.1f%% grown)", ent:EntIndex(), ent:GetClass(), ent:GetModelScale() or 0.35, pct))
            end
        end
    end
    print("Total pregnant mothers: " .. pregCount .. " | Active growing babies: " .. growCount)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Childbirth status printed to console. Pregnant: " .. pregCount .. " | Babies: " .. growCount)
    end
end)

concommand.Add("vnpcs_test_childbirth", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at a female citizen to test childbirth!")
        return
    end
    local camp = VNPC_GetPreyCamp and VNPC_GetPreyCamp(target) or nil
    VNPC_StartChildbirthAnimation(target, target.VNPC_UnbornChild, camp)
    ply:ChatPrint("[V-NPCs] Triggered sitting childbirth bone pose animation and baby birth on " .. tostring(target) .. "!")
end)

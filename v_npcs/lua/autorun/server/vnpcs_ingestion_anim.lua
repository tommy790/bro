-- V-NPCs 3D Bone-Pose Interactive Ingestion Animation System (vnpcs_ingestion_anim.lua)
-- Animates prey being grabbed, lifted to the open mouth, and swallowed stage-by-stage with progressive bone deflation (head -> torso -> legs) to eliminate clipping.

CreateConVar("vnpcs_ingestion_animation", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable 3D bone-pose based interactive swallowing animation where prey head/body deflates smoothly into the predator's mouth")
CreateConVar("vnpcs_ingestion_duration", "1.2", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Total duration in seconds of the interactive swallowing/ingestion animation")

local activeIngestions = {}

local function classifyBone(name)
    if not name then return "other" end
    local l = string.lower(name)
    if l:find("head") or l:find("neck") or l:find("jaw") or l:find("eye") or l:find("face") or l:find("hair") or l:find("ear") then
        return "head"
    elseif l:find("spine") or l:find("clavicle") or l:find("upperarm") or l:find("forearm") or l:find("hand") or l:find("finger") or l:find("chest") or l:find("arm") then
        return "torso"
    elseif l:find("pelvis") or l:find("thigh") or l:find("calf") or l:find("foot") or l:find("toe") or l:find("leg") or l:find("butt") then
        return "legs"
    end
    return "other"
end

local function deflateBoneCategory(ent, category, targetScale)
    if not IsValid(ent) then return end
    local count = ent:GetBoneCount() or 0
    for i = 0, count - 1 do
        local name = ent:GetBoneName(i)
        if name and classifyBone(name) == category then
            ent:ManipulateBoneScale(i, targetScale or Vector(0.01, 0.01, 0.01))
        end
    end
end

local function resetAllBoneManipulations(ent)
    if not IsValid(ent) then return end
    local count = ent:GetBoneCount() or 0
    for i = 0, count - 1 do
        ent:ManipulateBoneScale(i, Vector(1, 1, 1))
        ent:ManipulateBoneAngles(i, angle_zero)
    end
end

VNPC_PreyStruggleProfiles = {
    ["chiku"] = {
        spine = function(now) return Angle(0, 25, math.sin(now * 16) * 18) end,
        armR = function(now) return Angle(math.sin(now * 18) * 45 - 20, -25, 15) end,
        armL = function(now) return Angle(-math.sin(now * 18) * 45 + 20, -25, -15) end,
        foreR = function(now) return Angle(math.cos(now * 20) * 40 - 35, 0, 0) end,
        foreL = function(now) return Angle(-math.cos(now * 20) * 40 + 35, 0, 0) end,
        kickA = function(now) return math.sin(now * 18) * 55 - 10 end,
        kickB = function(now) return -math.sin(now * 18) * 55 - 10 end,
        calf = function(now) return math.abs(math.cos(now * 18)) * 55 + 15 end
    },
    ["bonfie"] = {
        spine = function(now) return Angle(0, math.sin(now * 10) * 20, 0) end,
        armR = function(now) return Angle(60, -30, 20) end,
        armL = function(now) return Angle(60, 30, -20) end,
        foreR = function(now) return Angle(-40, 20, 0) end,
        foreL = function(now) return Angle(-40, -20, 0) end,
        kickA = function(now) return math.sin(now * 12) * 45 - 20 end,
        kickB = function(now) return -math.sin(now * 12) * 45 - 20 end,
        calf = function(now) return math.abs(math.cos(now * 12)) * 40 + 10 end
    },
    ["breamsatel"] = {
        spine = function(now) return Angle(0, 0, math.sin(now * 14) * 15) end,
        armR = function(now) return Angle(75, -15, 0) end,
        armL = function(now) return Angle(75, 15, 0) end,
        foreR = function(now) return Angle(-50, 0, 0) end,
        foreL = function(now) return Angle(-50, 0, 0) end,
        kickA = function(now) return math.cos(now * 14) * 40 - 15 end,
        kickB = function(now) return math.cos(now * 14) * 40 - 15 end,
        calf = function(now) return math.abs(math.sin(now * 14)) * 50 + 10 end
    },
    ["ballerpuppy"] = {
        spine = function(now) return Angle(0, math.sin(now * 15) * 18, math.cos(now * 15) * 12) end,
        armR = function(now) return Angle(20, -50, -30) end,
        armL = function(now) return Angle(20, 50, 30) end,
        foreR = function(now) return Angle(-70, 0, 0) end,
        foreL = function(now) return Angle(-70, 0, 0) end,
        kickA = function(now) return math.sin(now * 16) * 50 - 15 end,
        kickB = function(now) return -math.sin(now * 16) * 50 - 15 end,
        calf = function(now) return math.abs(math.cos(now * 16)) * 60 + 15 end
    },
    ["carmelita"] = {
        spine = function(now) return Angle(math.sin(now * 12) * 10, 0, math.cos(now * 14) * 15) end,
        armR = function(now) return Angle(35, -25, 10) end,
        armL = function(now) return Angle(35, 25, -10) end,
        foreR = function(now) return Angle(-25, 45, 0) end,
        foreL = function(now) return Angle(-25, -45, 0) end,
        kickA = function(now) return math.sin(now * 14) * 40 - 10 end,
        kickB = function(now) return -math.sin(now * 14 + 0.5) * 40 - 10 end,
        calf = function(now) return math.abs(math.cos(now * 14)) * 45 + 10 end
    },
    ["dasha"] = {
        spine = function(now) return Angle(0, math.sin(now * 18) * 12, 0) end,
        armR = function(now) return Angle(15, -40, -10) end,
        armL = function(now) return Angle(15, 40, 10) end,
        foreR = function(now) return Angle(-80, 0, 0) end,
        foreL = function(now) return Angle(-80, 0, 0) end,
        kickA = function(now) return math.sin(now * 20) * 35 - 12 end,
        kickB = function(now) return -math.sin(now * 20) * 35 - 12 end,
        calf = function(now) return math.abs(math.cos(now * 20)) * 35 + 10 end
    },
    ["femasriel"] = {
        spine = function(now) return Angle(0, math.sin(now * 10) * 14, math.cos(now * 8) * 10) end,
        armR = function(now) return Angle(40, -20, 15) end,
        armL = function(now) return Angle(40, 20, -15) end,
        foreR = function(now) return Angle(-60, 20, 0) end,
        foreL = function(now) return Angle(-60, -20, 0) end,
        kickA = function(now) return math.sin(now * 10) * 45 - 15 end,
        kickB = function(now) return -math.sin(now * 10) * 45 - 15 end,
        calf = function(now) return math.abs(math.cos(now * 10)) * 45 + 10 end
    },
    ["default"] = {
        spine = function(now) return Angle(0, math.sin(now * 12) * 15, math.cos(now * 10) * 10) end,
        armR = function(now) return Angle(math.sin(now * 14) * 30 - 15, -20, 10) end,
        armL = function(now) return Angle(-math.sin(now * 14) * 30 + 15, -20, -10) end,
        foreR = function(now) return Angle(math.cos(now * 16) * 35 - 30, 0, 0) end,
        foreL = function(now) return Angle(-math.cos(now * 16) * 35 + 30, 0, 0) end,
        kickA = function(now) return math.sin(now * 15) * 40 - 15 end,
        kickB = function(now) return -math.sin(now * 15) * 40 - 15 end,
        calf = function(now) return math.abs(math.cos(now * 15)) * 50 + 10 end
    }
}

local function VNPC_AnimatePreyStruggling(prey, stage, tNorm, movesetName)
    if not IsValid(prey) then return end
    local now = CurTime()
    local profile = VNPC_PreyStruggleProfiles[string.lower(tostring(movesetName or "default"))] or VNPC_PreyStruggleProfiles["default"]

    local spine = prey:LookupBone("ValveBiped.Bip01_Spine1") or prey:LookupBone("Spine1") or prey:LookupBone("ValveBiped.Bip01_Spine")
    if spine and profile.spine then
        prey:ManipulateBoneAngles(spine, profile.spine(now))
    end

    if stage < 2 then
        local rArm = prey:LookupBone("ValveBiped.Bip01_R_UpperArm") or prey:LookupBone("R_UpperArm")
        local lArm = prey:LookupBone("ValveBiped.Bip01_L_UpperArm") or prey:LookupBone("L_UpperArm")
        local rFore = prey:LookupBone("ValveBiped.Bip01_R_Forearm") or prey:LookupBone("R_Forearm")
        local lFore = prey:LookupBone("ValveBiped.Bip01_L_Forearm") or prey:LookupBone("L_Forearm")

        if rArm and profile.armR then prey:ManipulateBoneAngles(rArm, profile.armR(now)) end
        if lArm and profile.armL then prey:ManipulateBoneAngles(lArm, profile.armL(now)) end
        if rFore and profile.foreR then prey:ManipulateBoneAngles(rFore, profile.foreR(now)) end
        if lFore and profile.foreL then prey:ManipulateBoneAngles(lFore, profile.foreL(now)) end
    end

    if stage < 3 then
        local rThigh = prey:LookupBone("ValveBiped.Bip01_R_Thigh") or prey:LookupBone("R_Thigh")
        local lThigh = prey:LookupBone("ValveBiped.Bip01_L_Thigh") or prey:LookupBone("L_Thigh")
        local rCalf = prey:LookupBone("ValveBiped.Bip01_R_Calf") or prey:LookupBone("R_Calf")
        local lCalf = prey:LookupBone("ValveBiped.Bip01_L_Calf") or prey:LookupBone("L_Calf")

        local kA = profile.kickA(now)
        local kB = profile.kickB(now)
        local cA = profile.calf(now)

        if rThigh then prey:ManipulateBoneAngles(rThigh, Angle(0, kA, 0)) end
        if lThigh then prey:ManipulateBoneAngles(lThigh, Angle(0, kB, 0)) end
        if rCalf then prey:ManipulateBoneAngles(rCalf, Angle(0, cA, 0)) end
        if lCalf then prey:ManipulateBoneAngles(lCalf, Angle(0, cA, 0)) end
    end
end

function VNPC_StartIngestionAnimation(pred, prey, belly)
    if not IsValid(pred) or not IsValid(prey) or not IsValid(belly) then return false end
    local enabled = GetConVar("vnpcs_ingestion_animation")
    if enabled and not enabled:GetBool() then return false end

    local dur_cv = GetConVar("vnpcs_ingestion_duration")
    local duration = dur_cv and dur_cv:GetFloat() or 1.2
    local calm_swallow_cv = GetConVar("vnpcs_calm_swallow_animation")
    if calm_swallow_cv and calm_swallow_cv:GetBool() and not IsValid(pred:GetEnemy()) then
        duration = 5.0
    end
    if duration <= 0.1 then return false end

    -- Keep prey visible during ingestion animation
    prey:SetNoDraw(false)
    prey.VNPC_IsBeingSwallowed = true

    -- Position prey at predator's mouth / head area
    local headBone = pred:LookupBone("ValveBiped.Bip01_Head1") or pred:LookupBone("Head") or pred:LookupBone("head")
    if headBone then
        local headPos = pred:GetBonePosition(headBone)
        if headPos then
            prey:SetPos(headPos + pred:GetForward() * 15 - pred:GetUp() * 5)
        end
    end
    prey:SetParent(pred)

    -- Ensure predator opens mouth wide for swallowing
    if pred.SetFacialExpression then
        pcall(pred.SetFacialExpression, pred, 1)
    end

    table.insert(activeIngestions, {
        pred = pred,
        prey = prey,
        belly = belly,
        startTime = CurTime(),
        duration = duration,
        stage = 0
    })

    return true
end

function VNPC_ResetEsophagusBulge(pred)
    if not IsValid(pred) or not pred.LookupBone or not pred.ManipulateBoneScale then return end
    local neckBone = pred:LookupBone("ValveBiped.Bip01_Neck1") or pred:LookupBone("Neck1") or pred:LookupBone("neck")
    local chestBone = pred:LookupBone("ValveBiped.Bip01_Spine2") or pred:LookupBone("Spine2") or pred:LookupBone("spine2")
    if neckBone then
        pred:ManipulateBoneScale(neckBone, Vector(1, 1, 1))
    end
    if chestBone then
        pred:ManipulateBoneScale(chestBone, Vector(1, 1, 1))
    end
end

function VNPC_ApplyEsophagusBulge(pred, tNorm)
    if not IsValid(pred) or not pred.LookupBone or not pred.ManipulateBoneScale then return end
    local neckBone = pred:LookupBone("ValveBiped.Bip01_Neck1") or pred:LookupBone("Neck1") or pred:LookupBone("neck")
    local chestBone = pred:LookupBone("ValveBiped.Bip01_Spine2") or pred:LookupBone("Spine2") or pred:LookupBone("spine2")

    if tNorm >= 0.05 and tNorm < 0.38 then
        -- Wave passing Neck/Throat
        if neckBone then
            pred:ManipulateBoneScale(neckBone, Vector(1.35, 1.35, 1.10))
        end
        if chestBone then
            pred:ManipulateBoneScale(chestBone, Vector(1, 1, 1))
        end
    elseif tNorm >= 0.38 and tNorm < 0.75 then
        -- Wave passing Chest/Upper Esophagus
        if neckBone then
            pred:ManipulateBoneScale(neckBone, Vector(1, 1, 1))
        end
        if chestBone then
            pred:ManipulateBoneScale(chestBone, Vector(1.40, 1.35, 1.25))
        end
    else
        VNPC_ResetEsophagusBulge(pred)
    end
end

hook.Add("Think", "VNPCS_IngestionAnimation_Loop", function()
    local enabled = GetConVar("vnpcs_ingestion_animation")
    if enabled and not enabled:GetBool() then return end

    local now = CurTime()

    for i = #activeIngestions, 1, -1 do
        local anim = activeIngestions[i]
        local pred = anim.pred
        local prey = anim.prey
        local belly = anim.belly

        if not IsValid(pred) or not IsValid(prey) or not IsValid(belly) then
            if IsValid(prey) then
                resetAllBoneScales(prey)
                prey:SetNoDraw(true)
                prey.VNPC_IsBeingSwallowed = false
            end
            if IsValid(pred) then
                VNPC_ResetEsophagusBulge(pred)
            end
            table.remove(activeIngestions, i)
            continue
        end

        local tNorm = math.Clamp((now - anim.startTime) / anim.duration, 0, 1)
        prey.VNPC_IngestionDepth = math.sin(tNorm * math.pi * 0.5)

        if IsValid(belly) and belly.SetBellySize then
            belly:SetBellySize()
        end

        -- Keep prey positioned at predator's mouth as she swallows
        local headBone = pred:LookupBone("ValveBiped.Bip01_Head1") or pred:LookupBone("Head") or pred:LookupBone("head")
        if headBone then
            local headPos, headAng = pred:GetBonePosition(headBone)
            if headPos then
                -- Move prey inward toward throat as tNorm increases
                local inOffset = LerpVector(math.Clamp(tNorm, 0, 1), pred:GetForward() * 18, -pred:GetForward() * 5 - pred:GetUp() * 12)
                prey:SetPos(headPos + inOffset)
            end
        end

        VNPC_AnimatePreyStruggling(prey, anim.stage, tNorm, pred.VNPC_AssignedMoveset)
        VNPC_ApplyEsophagusBulge(pred, tNorm)

        -- STAGE 1 (tNorm >= 0.05): Head enters mouth -> Deflate head & neck bones so there is zero clipping!
        if tNorm >= 0.05 and anim.stage < 1 then
            anim.stage = 1
            deflateBoneCategory(prey, "head", Vector(0.01, 0.01, 0.01))
        end

        -- STAGE 2 (tNorm >= 0.35): Upper body enters throat -> Deflate torso, arms, and collarbones!
        if tNorm >= 0.35 and anim.stage < 2 then
            anim.stage = 2
            deflateBoneCategory(prey, "torso", Vector(0.01, 0.01, 0.01))
        end

        -- STAGE 3 (tNorm >= 0.70): Legs and feet slide in -> Deflate lower body!
        if tNorm >= 0.70 and anim.stage < 3 then
            anim.stage = 3
            deflateBoneCategory(prey, "legs", Vector(0.01, 0.01, 0.01))
            if pred.SetFacialExpression then
                pcall(pred.SetFacialExpression, pred, 4) -- Final Gulp face!
            end
        end

        -- STAGE 4 (tNorm >= 1.00): Ingestion complete! Store prey inside belly and reset bone manipulations!
        if tNorm >= 1.00 then
            resetAllBoneManipulations(prey)
            if VNPC_HideSwallowedPrey then
                VNPC_HideSwallowedPrey(prey, belly)
            else
                prey:SetNoDraw(true)
                prey:SetParent(belly)
                prey:SetPos(belly:GetPos())
            end
            prey.VNPC_IsBeingSwallowed = false
            prey.VNPC_IngestionDepth = 1.0

            if IsValid(belly) and belly.SetBellySize then
                belly:SetBellySize()
            end

            if pred.SetFacialExpression then
                pcall(pred.SetFacialExpression, pred, 2) -- Full Belly face!
            end
            VNPC_ResetEsophagusBulge(pred)

            table.remove(activeIngestions, i)
        end
    end
end)

concommand.Add("vnpcs_ingestion_status", function(ply)
    print("===============================================================")
    print("        V-NPCs 3D INTERACTIVE INGESTION ANIMATION STATUS       ")
    print("===============================================================")
    print(" - Ingestion Animation Enabled: " .. tostring(GetConVar("vnpcs_ingestion_animation"):GetBool()))
    print(" - Ingestion Duration: " .. tostring(GetConVar("vnpcs_ingestion_duration"):GetFloat()) .. " sec")
    print(" - Active Ingestions Count: " .. #activeIngestions)
    for index, anim in ipairs(activeIngestions) do
        if IsValid(anim.pred) and IsValid(anim.prey) then
            local pct = math.Clamp((CurTime() - anim.startTime) / anim.duration * 100, 0, 100)
            print(string.format("   #%d: Predator [%s] swallowing [%s] -> Stage %d (%.1f%% complete)", index, anim.pred.PrintName or anim.pred:GetClass(), anim.prey.PrintName or anim.prey:GetClass(), anim.stage, pct))
        end
    end
    print("===============================================================")
end)

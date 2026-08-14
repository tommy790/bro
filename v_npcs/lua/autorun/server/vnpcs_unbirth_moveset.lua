-- V-NPCs "Unbirth" Moveset & Interactive Womb Ingestion Animation Engine (vnpcs_unbirth_moveset.lua)
-- Predator jumps onto prey; prey's head immediately enters womb; prey struggles fruitlessly as pred settles down and absorbs prey into womb

-- 1. Register 5-Phase "Unbirth" Bone Animation Table
VNPC_UnbirthAnimatedBoneList = {
    [0] = { -- rest (seductive/waiting standing pose)
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 10, -5) },
        ["ValveBiped.Bip01_Spine"] = { pos = Vector(0, 0, 0), ang = Angle(5, 0, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(15, -10, 10) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(15, 10, -10) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-30, 10, 0) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-30, -10, 0) }
    },
    [1] = { -- swallow (Unbirth mount: pred leaps/squats down over prey, legs spread wide around prey's upper body)
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(25, 0, 0) },
        ["ValveBiped.Bip01_Spine"] = { pos = Vector(0, 0, -15), ang = Angle(30, 0, 0) },
        ["ValveBiped.Bip01_Spine1"] = { pos = Vector(0, 0, 0), ang = Angle(15, 0, 0) },
        ["ValveBiped.Bip01_Pelvis"] = { pos = Vector(0, 0, -18), ang = Angle(-25, 0, 0) },
        ["ValveBiped.Bip01_R_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(-70, -45, 0) },
        ["ValveBiped.Bip01_L_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(-70, 45, 0) },
        ["ValveBiped.Bip01_R_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(110, 0, 0) },
        ["ValveBiped.Bip01_L_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(110, 0, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(55, -25, 30) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(55, 25, -30) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-80, 20, 0) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-80, -20, 0) }
    },
    [2] = { -- full belly / pregnant womb pose (hands resting protectively on lower belly/womb)
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(-15, 0, 0) },
        ["ValveBiped.Bip01_Spine"] = { pos = Vector(0, 0, 0), ang = Angle(-10, 0, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(45, -30, 25) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(45, 30, -25) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-110, 40, -30) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-110, -40, 30) },
        ["ValveBiped.Bip01_R_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(20, 0, 45) },
        ["ValveBiped.Bip01_L_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(20, 0, -45) }
    },
    [3] = { -- burp / absorption sigh (arch back slightly with hands cradling full womb)
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(-25, 10, 0) },
        ["ValveBiped.Bip01_Spine"] = { pos = Vector(0, 0, 0), ang = Angle(-18, 0, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(50, -30, 30) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(50, 30, -30) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-120, 45, -30) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-120, -45, 30) }
    },
    [4] = { -- final gulp / womb absorption settling
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(-5, 0, 0) },
        ["ValveBiped.Bip01_Spine"] = { pos = Vector(0, 0, 0), ang = Angle(-5, 0, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(40, -25, 20) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(40, 25, -20) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-100, 35, -25) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-100, -35, 25) }
    }
}

-- 2. Register with VNPC_BoneMovesets registry
if VNPC_RegisterBoneMoveset then
    VNPC_RegisterBoneMoveset("unbirth", VNPC_UnbirthAnimatedBoneList)
elseif VNPC_BoneMovesets then
    VNPC_BoneMovesets["unbirth"] = VNPC_UnbirthAnimatedBoneList
end

-- Add to personality weights (aggressive & shy predators both value unbirth)
if VNPC_PersonalityMovesetWeights then
    VNPC_PersonalityMovesetWeights["aggressive"]["unbirth"] = 4
    VNPC_PersonalityMovesetWeights["shy"]["unbirth"] = 4
    VNPC_PersonalityMovesetWeights["opportunistic"]["unbirth"] = 3
end

-- 3. Register Unbirth Struggling Profile (Prey kicks furiously downward while shoulders/head are pinned inside womb)
if VNPC_PreyStruggleProfiles then
    VNPC_PreyStruggleProfiles["unbirth"] = {
        spine = function(now) return Angle(math.sin(now * 22) * 20, 0, math.cos(now * 20) * 15) end,
        armR = function(now) return Angle(math.sin(now * 25) * 55 - 10, -40, 30) end,
        armL = function(now) return Angle(-math.sin(now * 25) * 55 + 10, 40, -30) end,
        foreR = function(now) return Angle(-90, 30, 0) end,
        foreL = function(now) return Angle(-90, -30, 0) end,
        kickA = function(now) return math.sin(now * 24) * 65 - 20 end,
        kickB = function(now) return -math.sin(now * 24) * 65 - 20 end,
        calf = function(now) return math.abs(math.cos(now * 24)) * 65 + 15 end
    }
end

-- 4. Custom Unbirth Ingestion Kinematic Positioning
-- When predator moveset == "unbirth", prey's head immediately enters womb (pelvis/belly area),
-- then pred settles down while prey's struggling body slides up into the womb over duration.
function VNPC_ApplyUnbirthIngestionPositioning(pred, prey, tNorm)
    if not IsValid(pred) or not IsValid(prey) then return false end

    -- Lookup predator pelvis/belly bone as womb entrance anchor
    local wombBone = pred:LookupBone("ValveBiped.Bip01_Pelvis") or pred:LookupBone("Pelvis") or pred:LookupBone("pelvis")
    local origin = pred:GetPos() + Vector(0, 0, 32)
    local fwd = pred:GetForward()
    local up = pred:GetUp()

    if wombBone then
        local bPos = pred:GetBonePosition(wombBone)
        if isvector(bPos) and bPos ~= vector_origin then
            origin = bPos + fwd * 8 - up * 4
        end
    end

    -- At tNorm=0.0: head immediately enters womb, body hangs downward
    -- At tNorm=1.0: entire body is drawn up inside womb
    local descendOffset = LerpVector(math.Clamp(tNorm, 0, 1), -up * 38 + fwd * 6, vector_origin)
    prey:SetPos(origin + descendOffset)
    prey:SetAngles(Angle(0, pred:GetAngles().y, 0))

    -- Progressive womb deflation: head/shoulders immediately inside at 0.05, torso at 0.30, legs at 0.70
    if tNorm >= 0.05 then
        if deflateBoneCategory then deflateBoneCategory(prey, "head", Vector(0.01, 0.01, 0.01)) end
    end
    if tNorm >= 0.30 then
        if deflateBoneCategory then deflateBoneCategory(prey, "torso", Vector(0.01, 0.01, 0.01)) end
    end
    if tNorm >= 0.70 then
        if deflateBoneCategory then deflateBoneCategory(prey, "legs", Vector(0.01, 0.01, 0.01)) end
    end

    return true
end

concommand.Add("vnpcs_test_unbirth_moveset", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a female V-NPC predator to assign the Unbirth moveset!")
        return
    end
    target.VNPC_AssignedMoveset = "unbirth"
    ply:ChatPrint("[V-NPCs] Assigned 'unbirth' moveset to " .. tostring(target) .. "!")
end)

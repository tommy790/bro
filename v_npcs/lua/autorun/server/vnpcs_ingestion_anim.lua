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

function VNPC_GetPreySpecies(prey)
    if not IsValid(prey) then return "human" end
    local cls = string.lower(prey:GetClass() or "")
    local mdl = string.lower(prey:GetModel() or "")

    if cls:find("antlionguard") or mdl:find("antlion_guard") or mdl:find("antlionguard") then
        return "antlionguard"
    elseif cls:find("antlion") or mdl:find("antlion") then
        return "antlion"
    elseif cls:find("headcrab") or mdl:find("headcrab") then
        return "headcrab"
    elseif cls:find("zombie") or mdl:find("zombie") then
        return "zombie"
    elseif cls:find("vortigaunt") or mdl:find("vortigaunt") then
        return "vortigaunt"
    else
        return "human"
    end
end

function VNPC_AnimateSpeciesStruggling(prey, species, stage, tNorm, movesetName)
    if not IsValid(prey) then return end
    local now = CurTime()
    local count = prey:GetBoneCount() or 0

    if species == "antlionguard" then
        -- Antlion Guard: Heavy, powerful stomping and massive body thrashing
        for i = 0, count - 1 do
            local bName = string.lower(prey:GetBoneName(i) or "")
            if bName:find("spine") or bName:find("body") or bName:find("thorax") then
                prey:ManipulateBoneAngles(i, Angle(math.sin(now * 8) * 20, math.cos(now * 6) * 12, 0))
            elseif bName:find("head") or bName:find("horn") or bName:find("jaw") then
                if stage < 1 then
                    prey:ManipulateBoneAngles(i, Angle(math.sin(now * 10) * 25, 0, math.cos(now * 10) * 15))
                end
            elseif bName:find("arm") or bName:find("claw") or bName:find("hand") then
                if stage < 2 then
                    prey:ManipulateBoneAngles(i, Angle(math.sin(now * 12 + i) * 35, -25, math.cos(now * 12 + i) * 20))
                end
            elseif bName:find("leg") or bName:find("thigh") or bName:find("calf") or bName:find("foot") then
                if stage < 3 then
                    prey:ManipulateBoneAngles(i, Angle(math.sin(now * 14 + i) * 45, 0, math.cos(now * 14 + i) * 25))
                end
            end
        end

    elseif species == "antlion" then
        -- Antlion: Frantic insectoid scuttling, wing buzzing, and leg thrashing
        for i = 0, count - 1 do
            local bName = string.lower(prey:GetBoneName(i) or "")
            if bName:find("wing") then
                prey:ManipulateBoneAngles(i, Angle(math.sin(now * 40 + i) * 55, 0, 0))
            elseif bName:find("spine") or bName:find("body") or bName:find("thorax") then
                prey:ManipulateBoneAngles(i, Angle(0, math.sin(now * 16) * 18, math.cos(now * 14) * 15))
            elseif bName:find("head") or bName:find("mandible") or bName:find("jaw") then
                if stage < 1 then
                    prey:ManipulateBoneAngles(i, Angle(0, math.sin(now * 22) * 30, 0))
                end
            elseif bName:find("leg") or bName:find("arm") or bName:find("claw") or bName:find("thigh") or bName:find("calf") then
                if stage < 3 then
                    prey:ManipulateBoneAngles(i, Angle(math.sin(now * 24 + i) * 40, math.cos(now * 24 + i) * 25, 0))
                end
            end
        end

    elseif species == "headcrab" then
        -- Headcrab: Frantic pouncing, twisting, and crab claw swiping
        for i = 0, count - 1 do
            local bName = string.lower(prey:GetBoneName(i) or "")
            if bName:find("body") or bName:find("spine") then
                prey:ManipulateBoneAngles(i, Angle(math.sin(now * 16) * 22, 0, math.cos(now * 16) * 18))
            elseif bName:find("leg") or bName:find("claw") or bName:find("finger") then
                if stage < 3 then
                    prey:ManipulateBoneAngles(i, Angle(math.sin(now * 22 + i) * 45, math.cos(now * 22 + i) * 30, 0))
                end
            end
        end

    elseif species == "zombie" then
        -- Zombie: Wild, erratic claw swiping and back-arching zombie thrashing
        for i = 0, count - 1 do
            local bName = string.lower(prey:GetBoneName(i) or "")
            if bName:find("spine") or bName:find("body") or bName:find("pelvis") then
                prey:ManipulateBoneAngles(i, Angle(math.sin(now * 14) * 24, 0, math.cos(now * 10) * 16))
            elseif bName:find("head") or bName:find("neck") then
                if stage < 1 then
                    prey:ManipulateBoneAngles(i, Angle(math.sin(now * 16) * 25, math.cos(now * 14) * 20, 0))
                end
            elseif bName:find("arm") or bName:find("hand") or bName:find("clavicle") then
                if stage < 2 then
                    prey:ManipulateBoneAngles(i, Angle(math.sin(now * 16 + i) * 45 - 15, math.cos(now * 16 + i) * 35, 0))
                end
            elseif bName:find("thigh") or bName:find("calf") or bName:find("leg") or bName:find("foot") then
                if stage < 3 then
                    prey:ManipulateBoneAngles(i, Angle(0, math.sin(now * 15 + i) * 45, 0))
                end
            end
        end

    elseif species == "vortigaunt" then
        -- Vortigaunt: Sweeping alien arm thrashing and energetic body writhing
        for i = 0, count - 1 do
            local bName = string.lower(prey:GetBoneName(i) or "")
            if bName:find("spine") or bName:find("body") then
                prey:ManipulateBoneAngles(i, Angle(math.sin(now * 12) * 18, math.cos(now * 10) * 15, 0))
            elseif bName:find("arm") or bName:find("hand") or bName:find("wrist") or bName:find("claw") then
                if stage < 2 then
                    prey:ManipulateBoneAngles(i, Angle(math.sin(now * 15 + i) * 45, math.cos(now * 15 + i) * 35, 20))
                end
            elseif bName:find("thigh") or bName:find("calf") or bName:find("leg") or bName:find("foot") then
                if stage < 3 then
                    prey:ManipulateBoneAngles(i, Angle(math.sin(now * 14 + i) * 40, 0, math.cos(now * 14 + i) * 20))
                end
            end
        end

    else
        -- Human / Citizen / Combine / Metropolice: Humanoid struggling profiles
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
end

local function VNPC_AnimatePreyStruggling(prey, stage, tNorm, movesetName)
    if not IsValid(prey) then return end
    local species = VNPC_GetPreySpecies(prey)
    VNPC_AnimateSpeciesStruggling(prey, species, stage, tNorm, movesetName)
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

    local species = VNPC_GetPreySpecies(prey)
    local isHeavyGround = (species == "antlionguard" or prey.VNPC_IsHeavyGroundPrey or (prey.GetMaxHealth and prey:GetMaxHealth() >= 250))
    if isHeavyGround then
        duration = math.max(duration, 7.5)
        prey.VNPC_IsHeavyGroundPrey = true
        prey.VNPC_GroundIngestStartPos = prey:GetPos()
        pred.VNPC_IsMountingHeavyPrey = true
        pred.VNPC_MountStartPos = pred:GetPos()
        if pred.SetNWBool then pred:SetNWBool("VNPC_IsMountingHeavyPrey", true) end
        prey:SetParent(nil)
        print("[V-NPCs] Heavy Ground Ingestion: Predator " .. tostring(pred) .. " leaped onto grounded " .. tostring(prey) .. " (" .. string.upper(species) .. ") and is slowly swallowing it alive over " .. duration .. "s!")
    else
        -- Position prey at predator's mouth / head area
        local headBone = pred:LookupBone("ValveBiped.Bip01_Head1") or pred:LookupBone("Head") or pred:LookupBone("head")
        if headBone then
            local headPos = pred:GetBonePosition(headBone)
            if headPos then
                prey:SetPos(headPos + pred:GetForward() * 15 - pred:GetUp() * 5)
            end
        end
        prey:SetParent(pred)
    end

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

        local isUnbirth = (pred.VNPC_AssignedMoveset == "unbirth")
        if prey.VNPC_IsHeavyGroundPrey then
            -- HEAVY GROUND INGESTION: Heavy prey stays grounded while predator leaps onto it and swallows it slowly!
            local startP = pred.VNPC_MountStartPos or pred:GetPos()
            local targetP = (prey.VNPC_GroundIngestStartPos or prey:GetPos()) + Vector(0, 0, 8)
            local fwd = (targetP - startP):GetNormalized()
            fwd.z = 0
            if fwd:Length2DSqr() > 0.01 then
                pred:SetAngles(fwd:Angle())
            end

            if tNorm < 0.35 then
                -- Leap/jump onto the heavy ground prey with mouth wide open!
                local pNorm = tNorm / 0.35
                local arcZ = math.sin(pNorm * math.pi) * 35
                local curP = LerpVector(pNorm, startP, targetP - fwd * 25) + Vector(0, 0, arcZ)
                pred:SetPos(curP)
                if pred.SetFacialExpression then pcall(pred.SetFacialExpression, pred, 1) end
            else
                -- Slow grounded swallowing: envelope prey from head to tail while prey stays on ground!
                local sNorm = (tNorm - 0.35) / 0.65
                local curP = LerpVector(sNorm, targetP - fwd * 25, targetP + fwd * 10)
                pred:SetPos(curP)
                if pred.SetFacialExpression then pcall(pred.SetFacialExpression, pred, 1) end
            end
            prey:SetPos(prey.VNPC_GroundIngestStartPos or prey:GetPos())
        elseif isUnbirth and VNPC_ApplyUnbirthIngestionPositioning then
            VNPC_ApplyUnbirthIngestionPositioning(pred, prey, tNorm)
        else
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
        end

        VNPC_AnimatePreyStruggling(prey, anim.stage, tNorm, pred.VNPC_AssignedMoveset)
        if not isUnbirth then
            VNPC_ApplyEsophagusBulge(pred, tNorm)
        end

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
            if prey.VNPC_IsHeavyGroundPrey then
                prey.VNPC_IsHeavyGroundPrey = nil
                pred.VNPC_IsMountingHeavyPrey = nil
                pred.VNPC_MountStartPos = nil
                if pred.SetNWBool then pred:SetNWBool("VNPC_IsMountingHeavyPrey", false) end
            end
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
            local species = VNPC_GetPreySpecies(anim.prey)
            print(string.format("   #%d: Predator [%s] swallowing [%s] (Species: %s) -> Stage %d (%.1f%% complete)", index, anim.pred.PrintName or anim.pred:GetClass(), anim.prey.PrintName or anim.prey:GetClass(), string.upper(species), anim.stage, pct))
        end
    end
    print("===============================================================")
end)

hook.Add("Think", "VNPCS_InsideBellyPreyStruggle_Loop", function()
    local now = CurTime()
    if (VNPC_NextBellyStruggleThink or 0) > now then return end
    VNPC_NextBellyStruggleThink = now + 0.1

    for _, belly in ipairs(ents.FindByClass("ent_*_belly")) do
        if IsValid(belly) and belly.Prey then
            for _, info in ipairs(belly.Prey) do
                if info and IsValid(info.Entity) and (info.Alive == true or info.Entity:Health() > 0) and not info.Absorbing then
                    VNPC_AnimatePreyStruggling(info.Entity, 1, 1.0, belly.MovesetName or "default")
                end
            end
        end
    end
end)

concommand.Add("vnpcs_test_prey_struggle", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsPlayer() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at an NPC to test species swallowed struggling animations!")
        return
    end

    local species = VNPC_GetPreySpecies(target)
    VNPC_AnimateSpeciesStruggling(target, species, 1, 0.5, "default")
    ply:ChatPrint("[V-NPCs] Tested species swallowed struggling animation for species: [" .. string.upper(species) .. "] on target " .. tostring(target) .. "!")
end)

concommand.Add("vnpcs_test_heavy_ground_ingestion", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local prey = tr.Entity
    if not IsValid(prey) or not (prey:IsNPC() or prey:IsPlayer() or prey:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at an NPC to test heavy ground ingestion!")
        return
    end

    local pred = nil
    local bestDistSqr = 1200 * 1200
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(ent) and ent ~= prey and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) then
            local dSqr = ent:GetPos():DistToSqr(prey:GetPos())
            if dSqr <= bestDistSqr then
                pred = ent
                bestDistSqr = dSqr
            end
        end
    end

    if not IsValid(pred) then
        ply:ChatPrint("[V-NPCs] No active V-NPC predator found near target to test heavy ground ingestion!")
        return
    end

    local belly = pred.VNPC_Belly or pred.Belly
    if not IsValid(belly) and VNPC_AttachFemaleModelVore then
        VNPC_AttachFemaleModelVore(pred)
        belly = pred.VNPC_Belly or pred.Belly
    end

    if IsValid(belly) then
        prey.VNPC_IsHeavyGroundPrey = true
        VNPC_StartIngestionAnimation(pred, prey, belly)
        ply:ChatPrint("[V-NPCs] Started Heavy Ground Ingestion: Predator " .. tostring(pred) .. " leaping onto grounded " .. tostring(prey) .. "!")
    end
end)

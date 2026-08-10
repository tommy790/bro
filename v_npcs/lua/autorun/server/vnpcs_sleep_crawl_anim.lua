-- V-NPCs 6-9 Second Willing Prey Sleep-Crawl Animation System (vnpcs_sleep_crawl_anim.lua)
-- Willing prey NPCs crawl head-first into a sleeping predator's open mouth and slither down her esophagus into her belly over 7.5 seconds without waking her.

CreateConVar("vnpcs_sleep_crawl_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable willing prey crawling into sleeping predators' mouths over 7.5 seconds")
CreateConVar("vnpcs_sleep_crawl_duration", "7.5", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Duration in seconds of willing prey crawling into a sleeping predator's belly (6 to 9 seconds)")

local activeSleepCrawls = {}

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

local function animateCrawlingPrey(prey, tNorm)
    if not IsValid(prey) then return end
    local now = CurTime()

    -- Crawling spine arch and wriggle as they push into the mouth
    local spine = prey:LookupBone("ValveBiped.Bip01_Spine1") or prey:LookupBone("Spine1") or prey:LookupBone("ValveBiped.Bip01_Spine")
    if spine then
        prey:ManipulateBoneAngles(spine, Angle(15, math.sin(now * 8) * 12, math.cos(now * 8) * 8))
    end

    -- Crawling arm reaching (reaching forward into her mouth to pull themselves in)
    if tNorm < 0.50 then
        local rArm = prey:LookupBone("ValveBiped.Bip01_R_UpperArm") or prey:LookupBone("R_UpperArm")
        local lArm = prey:LookupBone("ValveBiped.Bip01_L_UpperArm") or prey:LookupBone("L_UpperArm")
        local rFore = prey:LookupBone("ValveBiped.Bip01_R_Forearm") or prey:LookupBone("R_Forearm")
        local lFore = prey:LookupBone("ValveBiped.Bip01_L_Forearm") or prey:LookupBone("L_Forearm")

        if rArm then prey:ManipulateBoneAngles(rArm, Angle(45 + math.sin(now * 10) * 15, -10, 10)) end
        if lArm then prey:ManipulateBoneAngles(lArm, Angle(45 - math.sin(now * 10) * 15, -10, -10)) end
        if rFore then prey:ManipulateBoneAngles(rFore, Angle(-20, 10, 0)) end
        if lFore then prey:ManipulateBoneAngles(lFore, Angle(-20, -10, 0)) end
    end

    -- Slow rhythmic crawling/pushing legs from outside the mouth
    if tNorm < 0.80 then
        local rThigh = prey:LookupBone("ValveBiped.Bip01_R_Thigh") or prey:LookupBone("R_Thigh")
        local lThigh = prey:LookupBone("ValveBiped.Bip01_L_Thigh") or prey:LookupBone("L_Thigh")
        local rCalf = prey:LookupBone("ValveBiped.Bip01_R_Calf") or prey:LookupBone("R_Calf")
        local lCalf = prey:LookupBone("ValveBiped.Bip01_L_Calf") or prey:LookupBone("L_Calf")

        local kA = math.sin(now * 8) * 35
        local kB = -math.sin(now * 8) * 35
        if rThigh then prey:ManipulateBoneAngles(rThigh, Angle(0, kA, 0)) end
        if lThigh then prey:ManipulateBoneAngles(lThigh, Angle(0, kB, 0)) end
        if rCalf then prey:ManipulateBoneAngles(rCalf, Angle(0, math.abs(kA) * 0.8, 0)) end
        if lCalf then prey:ManipulateBoneAngles(lCalf, Angle(0, math.abs(kB) * 0.8, 0)) end
    end
end

function VNPC_StartSleepingCrawlAnimation(pred, prey)
    if not IsValid(pred) or not IsValid(prey) or prey.Vored or prey.VNPC_Vored or prey.VNPC_IsCrawlingInBelly then return false end
    local enabled = GetConVar("vnpcs_sleep_crawl_enabled")
    if enabled and not enabled:GetBool() then return false end

    local dur_cv = GetConVar("vnpcs_sleep_crawl_duration")
    local duration = dur_cv and dur_cv:GetFloat() or 7.5
    if duration < 3.0 then duration = 7.5 end

    local belly = pred.VNPC_Belly or pred.Belly
    if not IsValid(belly) then return false end

    prey.VNPC_IsCrawlingInBelly = true
    pred.VNPC_IsSleepCrawled = true
    prey:SetNoDraw(false)
    prey:SetSolid(SOLID_NONE)
    prey:SetMoveType(MOVETYPE_NONE)
    prey:SetParent(nil)
    if prey.SetEnemy then pcall(prey.SetEnemy, prey, nil) end
    if prey.SetSchedule then pcall(prey.SetSchedule, prey, SCHED_IDLE_STAND) end

    -- Position prey facing head-first toward predator's mouth
    local headBone = pred:LookupBone("ValveBiped.Bip01_Head1") or pred:LookupBone("Head") or pred:LookupBone("head")
    if headBone then
        local headPos = pred:GetBonePosition(headBone)
        if headPos then
            local startPos = headPos + pred:GetForward() * 25 + pred:GetUp() * 5
            prey:SetPos(startPos)
            prey:SetAngles(Angle(35, (headPos - startPos):Angle().y, 0))
        end
    end

    -- Gently open sleeping predator's mouth
    if pred.SetFacialExpression then
        pcall(pred.SetFacialExpression, pred, 1)
    end

    table.insert(activeSleepCrawls, {
        pred = pred,
        prey = prey,
        belly = belly,
        startTime = CurTime(),
        duration = duration,
        stage = 0
    })

    return true
end

hook.Add("Think", "VNPCS_SleepCrawlAnimation_Loop", function()
    local enabled = GetConVar("vnpcs_sleep_crawl_enabled")
    if enabled and not enabled:GetBool() then return end

    local now = CurTime()

    for i = #activeSleepCrawls, 1, -1 do
        local anim = activeSleepCrawls[i]
        local pred = anim.pred
        local prey = anim.prey
        local belly = anim.belly

        if not IsValid(pred) or not IsValid(prey) or not IsValid(belly) or not pred.VNPC_IsSleeping then
            if IsValid(prey) then
                resetAllBoneManipulations(prey)
                prey:SetNoDraw(true)
                prey.VNPC_IsCrawlingInBelly = false
            end
            table.remove(activeSleepCrawls, i)
            continue
        end

        local tNorm = math.Clamp((now - anim.startTime) / anim.duration, 0, 1)
        prey.VNPC_IngestionDepth = math.sin(tNorm * math.pi * 0.5)

        if IsValid(belly) and belly.SetBellySize then
            belly:SetBellySize()
        end

        -- Animate crawling descent along esophagus path from open mouth into belly
        local headBone = pred:LookupBone("ValveBiped.Bip01_Head1") or pred:LookupBone("Head") or pred:LookupBone("head")
        if headBone then
            local headPos = pred:GetBonePosition(headBone)
            if headPos then
                local mouthPos = headPos + pred:GetForward() * 8 + pred:GetUp() * 2
                local stomachPos = belly:WorldSpaceCenter()
                local esophPos = LerpVector(tNorm, mouthPos, stomachPos)
                prey:SetPos(esophPos)
                prey:SetAngles(Angle(45, pred:GetAngles().y + 180, 0))
            end
        end

        animateCrawlingPrey(prey, tNorm)

        -- STAGE 1 (tNorm >= 0.15): Head enters mouth -> deflate head
        if tNorm >= 0.15 and anim.stage < 1 then
            anim.stage = 1
            deflateBoneCategory(prey, "head", Vector(0.01, 0.01, 0.01))
        end

        -- STAGE 2 (tNorm >= 0.45): Torso & arms slide down throat -> deflate torso
        if tNorm >= 0.45 and anim.stage < 2 then
            anim.stage = 2
            deflateBoneCategory(prey, "torso", Vector(0.01, 0.01, 0.01))
        end

        -- STAGE 3 (tNorm >= 0.80): Legs crawl inside -> deflate legs
        if tNorm >= 0.80 and anim.stage < 3 then
            anim.stage = 3
            deflateBoneCategory(prey, "legs", Vector(0.01, 0.01, 0.01))
        end

        -- STAGE 4 (tNorm >= 1.00): Complete! Store prey inside belly without waking sleeping predator
        if tNorm >= 1.00 then
            resetAllBoneManipulations(prey)
            prey.VNPC_IsCrawlingInBelly = false
            pred.VNPC_IsSleepCrawled = false
            prey.VNPC_IngestionDepth = 1.0

            if belly.AddPrey then
                belly:AddPrey(prey)
            end

            if pred.SetFacialExpression then
                pcall(pred.SetFacialExpression, pred, 2) -- Peaceful sleeping full face
            end

            table.remove(activeSleepCrawls, i)
        end
    end
end)

concommand.Add("vnpcs_test_sleep_crawl", function(ply)
    local pred, prey = nil, nil
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(ent) and ent.VNPC_IsSleeping then
            pred = ent
            break
        end
    end
    if not IsValid(pred) then
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            if IsValid(ent) and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) then
                pred = ent
                pred.VNPC_IsSleeping = true
                break
            end
        end
    end

    if not IsValid(pred) then
        print("[V-NPCs] No valid predator found to test sleep-crawl.")
        return
    end

    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(ent) and ent ~= pred and not ent.Vored and not ent.VNPC_Vored then
            prey = ent
            break
        end
    end

    if not IsValid(prey) then
        print("[V-NPCs] No valid prey NPC found to test sleep-crawl.")
        return
    end

    print(string.format("[V-NPCs] Starting 7.5-second willing prey sleep-crawl test: [%s] crawling into sleeping [%s]'s belly!", prey.PrintName or prey:GetClass(), pred.PrintName or pred:GetClass()))
    VNPC_StartSleepingCrawlAnimation(pred, prey)
end)

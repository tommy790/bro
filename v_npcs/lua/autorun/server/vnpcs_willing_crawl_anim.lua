-- V-NPCs Willing Prey Sleeping-Predator Crawl-In Animation (vnpcs_willing_crawl_anim.lua)
-- Animates a willing prey model crawling into a sleeping predator's open mouth and slipping down the esophagus over 7.5 seconds.

CreateConVar("vnpcs_willing_crawl_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable 7.5-second willing prey crawling-in animation when a predator is sleeping")
CreateConVar("vnpcs_willing_crawl_duration", "7.5", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Duration in seconds of the willing prey crawling into a sleeping predator's mouth")

local activeWillingCrawls = {}

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

local function VNPC_AnimateWillingPreyCrawling(prey, stage, tNorm)
    if not IsValid(prey) then return end
    local now = CurTime()

    -- Crawling spine curve
    local spine = prey:LookupBone("ValveBiped.Bip01_Spine1") or prey:LookupBone("Spine1") or prey:LookupBone("ValveBiped.Bip01_Spine")
    if spine then
        prey:ManipulateBoneAngles(spine, Angle(math.sin(now * 8) * 10 + 10, math.sin(now * 6) * 10, 0))
    end

    if stage < 2 then
        local rArm = prey:LookupBone("ValveBiped.Bip01_R_UpperArm") or prey:LookupBone("R_UpperArm")
        local lArm = prey:LookupBone("ValveBiped.Bip01_L_UpperArm") or prey:LookupBone("L_UpperArm")
        local rFore = prey:LookupBone("ValveBiped.Bip01_R_Forearm") or prey:LookupBone("R_Forearm")
        local lFore = prey:LookupBone("ValveBiped.Bip01_L_Forearm") or prey:LookupBone("L_Forearm")

        if rArm then prey:ManipulateBoneAngles(rArm, Angle(math.sin(now * 10) * 25 + 40, -10, 15)) end
        if lArm then prey:ManipulateBoneAngles(lArm, Angle(-math.sin(now * 10) * 25 + 40, 10, -15)) end
        if rFore then prey:ManipulateBoneAngles(rFore, Angle(-60, 0, 0)) end
        if lFore then prey:ManipulateBoneAngles(lFore, Angle(-60, 0, 0)) end
    end

    if stage < 3 then
        local rThigh = prey:LookupBone("ValveBiped.Bip01_R_Thigh") or prey:LookupBone("R_Thigh")
        local lThigh = prey:LookupBone("ValveBiped.Bip01_L_Thigh") or prey:LookupBone("L_Thigh")
        local rCalf = prey:LookupBone("ValveBiped.Bip01_R_Calf") or prey:LookupBone("R_Calf")
        local lCalf = prey:LookupBone("ValveBiped.Bip01_L_Calf") or prey:LookupBone("L_Calf")

        local crawlA = math.sin(now * 12) * 35 - 10
        local crawlB = -math.sin(now * 12) * 35 - 10

        if rThigh then prey:ManipulateBoneAngles(rThigh, Angle(0, crawlA, 0)) end
        if lThigh then prey:ManipulateBoneAngles(lThigh, Angle(0, crawlB, 0)) end
        if rCalf then prey:ManipulateBoneAngles(rCalf, Angle(0, 30, 0)) end
        if lCalf then prey:ManipulateBoneAngles(lCalf, Angle(0, 30, 0)) end
    end
end

function VNPC_StartWillingCrawlAnimation(pred, prey, belly)
    if not IsValid(pred) or not IsValid(prey) or not IsValid(belly) then return false end
    local enabled = GetConVar("vnpcs_willing_crawl_enabled")
    if enabled and not enabled:GetBool() then return false end

    local dur_cv = GetConVar("vnpcs_willing_crawl_duration")
    local duration = dur_cv and dur_cv:GetFloat() or 7.5
    if duration <= 0.1 then return false end

    prey:SetNoDraw(false)
    prey.VNPC_IsBeingSwallowed = true
    prey.VNPC_IsWillingCrawl = true
    prey:SetSolid(SOLID_NONE)
    prey:SetMoveType(MOVETYPE_NONE)

    -- Softly open the sleeping predator's mouth to receive the willing prey without waking her
    if pred.SetFacialExpression then
        pcall(pred.SetFacialExpression, pred, 1)
    end

    table.insert(activeWillingCrawls, {
        pred = pred,
        prey = prey,
        belly = belly,
        startTime = CurTime(),
        duration = duration,
        stage = 0
    })

    return true
end

hook.Add("Think", "VNPCS_WillingCrawlAnimation_Loop", function()
    local enabled = GetConVar("vnpcs_willing_crawl_enabled")
    if enabled and not enabled:GetBool() then return end

    local now = CurTime()

    for i = #activeWillingCrawls, 1, -1 do
        local anim = activeWillingCrawls[i]
        local pred = anim.pred
        local prey = anim.prey
        local belly = anim.belly

        if not IsValid(pred) or not IsValid(prey) or not IsValid(belly) then
            if IsValid(prey) then
                resetAllBoneManipulations(prey)
                prey:SetNoDraw(true)
                prey.VNPC_IsBeingSwallowed = false
                prey.VNPC_IsWillingCrawl = nil
            end
            table.remove(activeWillingCrawls, i)
            continue
        end

        local tNorm = math.Clamp((now - anim.startTime) / anim.duration, 0, 1)
        prey.VNPC_IngestionDepth = math.sin(tNorm * math.pi * 0.5)

        if IsValid(belly) and belly.SetBellySize then
            belly:SetBellySize()
        end

        local headBone = pred:LookupBone("ValveBiped.Bip01_Head1") or pred:LookupBone("Head") or pred:LookupBone("head")
        if headBone then
            local headPos = pred:GetBonePosition(headBone)
            if headPos then
                local mouthWorld = headPos + pred:GetForward() * 5 + pred:GetUp() * 1
                local stomachWorld = belly:WorldSpaceCenter() + pred:GetUp() * 20

                if tNorm < 0.25 then
                    -- STAGE 1 (0.0 to 0.25): Crawl up from chest/lap to open mouth
                    local climbStart = headPos + pred:GetForward() * 25 - pred:GetUp() * 15
                    local climbPos = LerpVector(tNorm / 0.25, climbStart, mouthWorld)
                    prey:SetPos(climbPos)
                    prey:SetAngles(Angle(180, pred:GetAngles().y, 0))
                else
                    -- STAGE 2-4 (0.25 to 1.0): Slip down the esophagus into the stomach
                    local esophNorm = (tNorm - 0.25) / 0.75
                    local esophWorld = LerpVector(esophNorm, mouthWorld, stomachWorld)
                    prey:SetPos(esophWorld)
                    prey:SetAngles(Angle(180, pred:GetAngles().y, 0))
                end
            end
        end

        VNPC_AnimateWillingPreyCrawling(prey, anim.stage, tNorm)

        if tNorm >= 0.30 and anim.stage < 1 then
            anim.stage = 1
            deflateBoneCategory(prey, "head", Vector(0.01, 0.01, 0.01))
        end

        if tNorm >= 0.45 and anim.stage < 2 then
            anim.stage = 2
            deflateBoneCategory(prey, "torso", Vector(0.01, 0.01, 0.01))
        end

        if tNorm >= 0.70 and anim.stage < 3 then
            anim.stage = 3
            deflateBoneCategory(prey, "legs", Vector(0.01, 0.01, 0.01))
        end

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
            prey.VNPC_IsWillingCrawl = nil
            prey.VNPC_IngestionDepth = 1.0

            if belly.AddPrey then
                belly:AddPrey(prey)
            end

            if pred.SetFacialExpression then
                pcall(pred.SetFacialExpression, pred, 2)
            end

            table.remove(activeWillingCrawls, i)
        end
    end
end)

concommand.Add("vnpcs_willing_crawl_status", function(ply)
    print("===============================================================")
    print("      V-NPCs WILLING PREY SLEEPING-CRAWL ANIMATION STATUS      ")
    print("===============================================================")
    print(" - Willing Crawl Enabled: " .. tostring(GetConVar("vnpcs_willing_crawl_enabled"):GetBool()))
    print(" - Crawl-In Duration: " .. tostring(GetConVar("vnpcs_willing_crawl_duration"):GetFloat()) .. " sec")
    print(" - Active Willing Crawls Count: " .. #activeWillingCrawls)
    for index, anim in ipairs(activeWillingCrawls) do
        if IsValid(anim.pred) and IsValid(anim.prey) then
            local pct = math.Clamp((CurTime() - anim.startTime) / anim.duration * 100, 0, 100)
            print(string.format("   #%d: Willing Prey [%s] crawling into sleeping Predator [%s] -> Stage %d (%.1f%% complete)", index, anim.prey.PrintName or anim.prey:GetClass(), anim.pred.PrintName or anim.pred:GetClass(), anim.stage, pct))
        end
    end
    print("===============================================================")
end)

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

function VNPC_StartUnbirthWillingCrawlAnimation(pred, prey, belly)
    if not IsValid(pred) or not IsValid(prey) or not IsValid(belly) then return false end
    local enabled = GetConVar("vnpcs_willing_crawl_enabled")
    if enabled and not enabled:GetBool() then return false end

    local duration = 6.5

    prey:SetNoDraw(false)
    prey.VNPC_IsBeingSwallowed = true
    prey.VNPC_IsWillingCrawl = true
    prey.VNPC_IsWillingUnbirthCrawl = true
    pred.VNPC_IsWillingUnbirthCrawl = true
    if pred.SetNWBool then pred:SetNWBool("VNPC_IsWillingUnbirthCrawl", true) end

    prey:SetSolid(SOLID_NONE)
    prey:SetMoveType(MOVETYPE_NONE)

    table.insert(activeWillingCrawls, {
        pred = pred,
        prey = prey,
        belly = belly,
        startTime = CurTime(),
        duration = duration,
        stage = 0,
        isUnbirthWilling = true
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
        local tEase = tNorm * tNorm * (3 - 2 * tNorm)
        prey.VNPC_IngestionDepth = math.sin(tEase * math.pi * 0.5)

        if IsValid(belly) and belly.SetBellySize then
            belly:SetBellySize()
        end

        if anim.isUnbirthWilling then
            -- WILLING UNBIRTH CRAWL: prey crawls from behind directly into backwards-facing predator's womb (pelvis)!
            local wombBone = pred:LookupBone("ValveBiped.Bip01_Pelvis") or pred:LookupBone("Pelvis") or pred:LookupBone("pelvis")
            local wombPos = wombBone and pred:GetBonePosition(wombBone) or (pred:GetPos() + Vector(0, 0, 32))
            local entrancePos = wombPos - pred:GetForward() * 22 - pred:GetUp() * 4

            local curPos = LerpVector(tEase, entrancePos, wombPos + pred:GetForward() * 4)
            prey:SetPos(curPos)
            prey:SetAngles(Angle(0, pred:GetAngles().y, 0))
        else
            -- NORMAL WILLING CRAWL: prey crawls into mouth
            local headBone = pred:LookupBone("ValveBiped.Bip01_Head1") or pred:LookupBone("Head") or pred:LookupBone("head")
            if headBone then
                local headPos = pred:GetBonePosition(headBone)
                if headPos then
                    local mouthWorld = headPos + pred:GetForward() * 5 + pred:GetUp() * 1
                    local stomachWorld = belly:WorldSpaceCenter() + pred:GetUp() * 20

                    if tEase < 0.25 then
                        -- STAGE 1 (0.0 to 0.25): Crawl up from chest/lap to open mouth
                        local climbStart = headPos + pred:GetForward() * 25 - pred:GetUp() * 15
                        local climbPos = LerpVector(tEase / 0.25, climbStart, mouthWorld)
                        prey:SetPos(climbPos)
                        prey:SetAngles(Angle(180, pred:GetAngles().y, 0))
                    else
                        -- STAGE 2-4 (0.25 to 1.0): Slip down the esophagus into the stomach
                        local esophNorm = (tEase - 0.25) / 0.75
                        local esophWorld = LerpVector(esophNorm, mouthWorld, stomachWorld)
                        prey:SetPos(esophWorld)
                        prey:SetAngles(Angle(180, pred:GetAngles().y, 0))
                    end
                end
            end
        end

        VNPC_AnimateWillingPreyCrawling(prey, anim.stage, tEase)

        if tEase >= 0.30 and anim.stage < 1 then
            anim.stage = 1
            deflateBoneCategory(prey, "head", Vector(0.01, 0.01, 0.01))
            if prey.EmitSound then prey:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 75, math.random(95, 105)) end
        end

        if tEase >= 0.45 and anim.stage < 2 then
            anim.stage = 2
            deflateBoneCategory(prey, "torso", Vector(0.01, 0.01, 0.01))
            if prey.EmitSound then prey:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 75, math.random(95, 105)) end
        end

        if tEase >= 0.70 and anim.stage < 3 then
            anim.stage = 3
            deflateBoneCategory(prey, "legs", Vector(0.01, 0.01, 0.01))
            if prey.EmitSound then prey:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 75, math.random(95, 105)) end
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
            prey.VNPC_IsWillingUnbirthCrawl = nil
            pred.VNPC_IsWillingUnbirthCrawl = nil
            if pred.SetNWBool then pred:SetNWBool("VNPC_IsWillingUnbirthCrawl", false) end
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

function VNPC_IsWillingPrey(ent)
    if not IsValid(ent) or ent:Health() <= 0 or ent.Vored or ent.VNPC_Vored then return false end
    if ent.VNPC_IsPermanentFortPredator then return false end
    if ent.VNPC_IsWillingMate or ent.VNPC_PreyPersonality == "willing" or ent.PreyPersonality == "willing" then
        return true
    end
    if VNPC_GetPreyPersonality and VNPC_GetPreyPersonality(ent) == "willing" then
        return true
    end
    return false
end

function VNPC_WillingPreyCampfire_AI(now)
    for _, camp in ipairs(VNPC_ActivePredatorCamps or {}) do
        if not IsValid(camp.campfire) and not camp.pos then continue end
        local targetPos = IsValid(camp.campfire) and camp.campfire:GetPos() or camp.pos

        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            if not VNPC_IsWillingPrey(ent) then continue end
            if ent.Vored or ent.VNPC_Vored or ent.VNPC_IsWillingCrawl or ent.VNPC_IsBeingSwallowed then continue end
            if (ent.VNPC_NextCampInvestigateTime or 0) > now then continue end

            local dSqr = ent:GetPos():DistToSqr(targetPos)
            if dSqr <= (2200 * 2200) then
                if not ent.VNPC_InvestigatingCamp then
                    ent.VNPC_InvestigatingCamp = camp
                    if ent.SetLastPosition then pcall(ent.SetLastPosition, ent, targetPos) end
                    if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_FORCED_GO) end
                else
                    if dSqr <= (350 * 350) then
                        -- Arrived at the Predator Camp! Look for an awake predator present at camp.
                        local awakePred = nil
                        for _, pred in ipairs(camp.members or {}) do
                            if IsValid(pred) and pred:Health() > 0 and not pred.Vored and not pred.VNPC_Vored then
                                local pDist = pred:GetPos():DistToSqr(targetPos)
                                if pDist <= (600 * 600) and not pred.VNPC_IsSleeping and not pred.VNPC_IsReturningToCampToSleep then
                                    awakePred = pred
                                    break
                                end
                            end
                        end

                        if IsValid(awakePred) then
                            local belly = awakePred.VNPC_Belly or awakePred.Belly
                            if not IsValid(belly) and VNPC_AttachFemaleModelVore then
                                VNPC_AttachFemaleModelVore(awakePred)
                                belly = awakePred.VNPC_Belly or awakePred.Belly
                            end
                            if IsValid(belly) then
                                if awakePred.VNPC_AssignedMoveset == "unbirth" then
                                    VNPC_StartUnbirthWillingCrawlAnimation(awakePred, ent, belly)
                                    print("[V-NPCs] Willing prey " .. tostring(ent) .. " investigated Predator Camp #" .. camp.id .. " and crawled into backwards-facing unbirth predator " .. tostring(awakePred) .. "'s womb!")
                                else
                                    VNPC_StartWillingCrawlAnimation(awakePred, ent, belly)
                                    print("[V-NPCs] Willing prey " .. tostring(ent) .. " investigated Predator Camp #" .. camp.id .. " and crawled into awake predator " .. tostring(awakePred) .. "'s stomach through the mouth!")
                                end
                                ent.VNPC_InvestigatingCamp = nil
                            end
                        else
                            -- Predators are sleeping/resting OR out hunting; prey just leaves!
                            ent.VNPC_InvestigatingCamp = nil
                            ent.VNPC_NextCampInvestigateTime = now + 45.0
                            local leavePos = ent:GetPos() + Vector(math.random(-800, 800), math.random(-800, 800), 0)
                            if ent.SetLastPosition then pcall(ent.SetLastPosition, ent, leavePos) end
                            if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_FORCED_GO) end
                            print("[V-NPCs] Willing prey " .. tostring(ent) .. " visited Predator Camp #" .. camp.id .. " but predators were sleeping/resting or out hunting; prey left the camp.")
                        end
                    elseif (ent.VNPC_NextInvestigateMoveTime or 0) <= now then
                        ent.VNPC_NextInvestigateMoveTime = now + 2.0
                        if ent.SetLastPosition then pcall(ent.SetLastPosition, ent, targetPos) end
                        if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_FORCED_GO_RUN) end
                    end
                end
            end
        end
    end
end

function VNPC_UnbirthWillingCrawl_AI(now)
    local enabled = GetConVar("vnpcs_willing_crawl_enabled")
    if enabled and not enabled:GetBool() then return end

    for _, pred in ipairs(ents.FindByClass("npc_*")) do
        if not IsValid(pred) or pred:Health() <= 0 or pred.Vored or pred.VNPC_Vored then continue end
        if pred.VNPC_AssignedMoveset ~= "unbirth" then continue end
        if IsValid(VNPC_GetEntityEnemy and VNPC_GetEntityEnemy(pred) or nil) or pred.VNPC_IsWillingUnbirthCrawl or pred.Swallowing then continue end

        local predPos = pred:GetPos()
        local predBack = -pred:GetForward()

        for _, prey in ipairs(ents.FindByClass("npc_*")) do
            if not VNPC_IsWillingPrey(prey) or prey == pred or prey.Vored or prey.VNPC_Vored or prey.VNPC_IsWillingCrawl then continue end
            if prey:GetPos():DistToSqr(predPos) <= (140 * 140) then
                local toPrey = (prey:GetPos() - predPos):GetNormalized()
                toPrey.z = 0
                if predBack:Dot(toPrey) > 0.45 then
                    local belly = pred.VNPC_Belly or pred.Belly
                    if not IsValid(belly) and VNPC_AttachFemaleModelVore then
                        VNPC_AttachFemaleModelVore(pred)
                        belly = pred.VNPC_Belly or pred.Belly
                    end
                    if IsValid(belly) then
                        VNPC_StartUnbirthWillingCrawlAnimation(pred, prey, belly)
                        print("[V-NPCs] Willing Unbirth Crawl: Predator " .. tostring(pred) .. " facing backwards against willing prey " .. tostring(prey) .. "; willing prey is crawling into her womb!")
                        break
                    end
                end
            end
        end
    end
end

hook.Add("Think", "VNPCS_WillingPreyCampfire_Loop", function()
    local now = CurTime()
    if (VNPC_NextWillingCampfireThink or 0) > now then return end
    VNPC_NextWillingCampfireThink = now + 1.0
    VNPC_WillingPreyCampfire_AI(now)
    VNPC_UnbirthWillingCrawl_AI(now)
end)

concommand.Add("vnpcs_test_willing_campfire", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at a willing prey NPC to test campfire investigation!")
        return
    end

    local bestCamp = nil
    for _, camp in ipairs(VNPC_ActivePredatorCamps or {}) do
        bestCamp = camp
        break
    end
    if not bestCamp then
        ply:ChatPrint("[V-NPCs] No active Predator Camp found to investigate!")
        return
    end

    target.VNPC_PreyPersonality = "willing"
    target.VNPC_InvestigatingCamp = bestCamp
    local targetPos = IsValid(bestCamp.campfire) and bestCamp.campfire:GetPos() or bestCamp.pos
    if target.SetLastPosition then pcall(target.SetLastPosition, target, targetPos) end
    if target.SetSchedule then pcall(target.SetSchedule, target, SCHED_FORCED_GO_RUN) end

    ply:ChatPrint("[V-NPCs] Set willing prey " .. tostring(target) .. " to investigate Predator Camp #" .. bestCamp.id .. "'s campfire!")
end)

concommand.Add("vnpcs_test_willing_unbirth", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at an NPC to test willing unbirth womb crawling!")
        return
    end

    local pred = nil
    local prey = nil
    local isPredTarget = (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator)

    if isPredTarget then
        pred = target
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            if IsValid(ent) and ent ~= pred and VNPC_IsWillingPrey(ent) then
                prey = ent
                break
            end
        end
    else
        prey = target
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            if IsValid(ent) and ent ~= prey and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) then
                pred = ent
                break
            end
        end
    end

    if not IsValid(pred) or not IsValid(prey) then
        ply:ChatPrint("[V-NPCs] Could not find both a predator and a willing prey nearby!")
        return
    end

    pred.VNPC_AssignedMoveset = "unbirth"
    prey.VNPC_PreyPersonality = "willing"

    -- Position predator facing backwards against willing prey!
    pred:SetPos(prey:GetPos() + prey:GetForward() * 38)
    pred:SetAngles(Angle(0, prey:GetAngles().y, 0))

    local belly = pred.VNPC_Belly or pred.Belly
    if not IsValid(belly) and VNPC_AttachFemaleModelVore then
        VNPC_AttachFemaleModelVore(pred)
        belly = pred.VNPC_Belly or pred.Belly
    end

    if IsValid(belly) then
        VNPC_StartUnbirthWillingCrawlAnimation(pred, prey, belly)
        ply:ChatPrint("[V-NPCs] Tested Willing Unbirth: Predator " .. tostring(pred) .. " facing backwards against willing prey " .. tostring(prey) .. " crawling into her womb!")
    end
end)

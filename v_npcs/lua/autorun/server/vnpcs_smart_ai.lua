-- V-NPCs Smarter Predator AI Engine (vnpcs_smart_ai.lua)
-- Implements smart multi-factor target selection, squad/pack coordination, ambush/stalking awareness, and defensive full-belly tactics.

CreateConVar("vnpcs_smart_ai_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable smarter tactical predator AI (smart target selection, ambush/stalking, squad coordination, and defensive full-belly behavior)")

local claimedTargets = {}

function VNPC_SelectSmartPreyTarget(pred, search_radius)
    if not IsValid(pred) then return nil end
    local enabled = GetConVar("vnpcs_smart_ai_enabled")
    if enabled and not enabled:GetBool() then return nil end
    if pred.VNPC_IsCarryingPreyForCamp then return nil end

    local bestTarget = nil
    local bestScore = -1e9
    local predPos = pred:GetPos()
    local hunger = VNPC_GetHunger and VNPC_GetHunger(pred) or 50

    for _, ent in ipairs(ents.FindInSphere(predPos, search_radius or 700)) do
        if not IsValid(ent) or ent == pred or ent.Vored or ent.VNPC_Vored or ent.VNPC_Surrendered then continue end
        if VNPC_IsProtectedChildPrey and VNPC_IsProtectedChildPrey(ent) then continue end
        if VNPC_IsPreyEmissary and VNPC_IsPreyEmissary(ent) then continue end
        if ent.VNPC_DigestedBone or ent.VNPC_BoneOwner or ent.VNPC_NoVore then continue end
        if ent.VNPC_PreyCampID and pred.VNPC_PreyCampID and ent.VNPC_PreyCampID == pred.VNPC_PreyCampID then continue end
        if not (ent:IsPlayer() or ent:IsNPC() or ent.IsDrGNextbot or ent:GetClass() == "prop_ragdoll" or ent.VNPC_IsCorpse) then continue end

        -- Skip targets that are already being engaged by a closer pack-mate predator
        local claimant = claimedTargets[ent]
        if IsValid(claimant) and claimant ~= pred and claimant:GetPos():DistToSqr(ent:GetPos()) < predPos:DistToSqr(ent:GetPos()) * 0.7 then
            continue
        end

        -- Check relationship / hostility
        local isHostile = false
        if ent:IsPlayer() or ent:IsNPC() or ent.IsDrGNextbot then
            if pred.GetRelationship and pred:GetRelationship(ent) == D_HT then
                isHostile = true
            elseif pred.GetEnemy and pred:GetEnemy() == ent then
                isHostile = true
            end
        elseif ent:GetClass() == "prop_ragdoll" or ent.VNPC_IsCorpse then
            if pred.CanEatCorpse and pred:CanEatCorpse(ent) then
                isHostile = true
            end
        end
        if not isHostile then continue end
        if pred.EatCondition and not pred:EatCondition(ent) then continue end

        local dist = predPos:Distance(ent:GetPos())
        local val = VNPC_CalculatePreyValue and VNPC_CalculatePreyValue(ent) or 75
        local score = (val * (1.0 + hunger * 0.02)) / (dist + 50) * 100

        -- Tactical bonuses
        if ent:IsPlayer() then
            score = score + 60 -- Prioritize players
        end
        if ent.VNPC_PreyCampID then
            score = score + 75 -- Prioritize prey camp members!
        end
        if ent:Health() > 0 and ent:Health() <= 40 then
            score = score + 45 -- Prioritize wounded targets
        end

        -- Check if target has their back turned (ambush opportunity)
        if ent.GetAimVector then
            local aim = ent:GetAimVector()
            local toPred = (predPos - ent:GetPos()):GetNormalized()
            if aim:Dot(toPred) < -0.3 then
                score = score + 50 -- Back turned bonus
            end
        end

        if score > bestScore then
            bestScore = score
            bestTarget = ent
        end
    end

    if IsValid(bestTarget) then
        claimedTargets[bestTarget] = pred
    end

    return bestTarget
end

hook.Add("Think", "VNPCS_SmartAI_TacticalLoop", function()
    local enabled = GetConVar("vnpcs_smart_ai_enabled")
    if enabled and not enabled:GetBool() then return end

    local now = CurTime()

    -- Clean up invalid claims
    for target, claimant in pairs(claimedTargets) do
        if not IsValid(target) or not IsValid(claimant) or target.Vored or target.VNPC_Vored then
            claimedTargets[target] = nil
        end
    end

    for _, pred in ipairs(ents.FindByClass("npc_*")) do
        if not IsValid(pred) or pred.Vored or pred.VNPC_Vored then continue end
        if not (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) then continue end
        if (pred.VNPC_NextSmartThink or 0) > now then continue end
        pred.VNPC_NextSmartThink = now + 0.4

        local belly = pred.VNPC_Belly or pred.Belly
        local preyCount = IsValid(belly) and (belly.Prey and #belly.Prey or 0) or 0
        local isHeavilyStuffed = preyCount >= 3

        -- DEFENSIVE TACTIC: If heavily full and low HP, retreat/seek safe distance while digesting
        if isHeavilyStuffed and pred:Health() < pred:GetMaxHealth() * 0.35 then
            if pred.SetEnemy then pcall(pred.SetEnemy, pred, nil) end
            if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_TAKE_COVER_FROM_ENEMY) end
            continue
        end

        -- OBSTACLE CLEARING: If stuck in or blocked by a prop, swallow the prop to clear the path!
        for _, prop in ipairs(ents.FindInSphere(pred:GetPos(), 95)) do
            if not IsValid(prop) or prop == pred or prop.Vored or prop.VNPC_Vored then continue end
            if prop.VNPC_DigestedBone or prop.VNPC_BoneOwner or prop.VNPC_NoVore then continue end
            if prop.VNPC_IsPreyCampWall or prop.VNPC_IsPreyCampHutPiece or prop.VNPC_IsPredatorTent then continue end
            local cls = prop:GetClass()
            if cls == "prop_physics" or cls == "prop_dynamic" or cls == "prop_ragdoll" or cls == "func_breakable" then
                local dist = pred:GetPos():Distance(prop:GetPos())
                if dist <= 70 or (pred.GetVelocity and pred:GetVelocity():Length2DSqr() < 16 and IsValid(pred:GetEnemy())) then
                    if pred.EatEntity then
                        pred:EatEntity(prop)
                    elseif IsValid(belly) and belly.AddPrey then
                        belly:AddPrey(prop)
                    end
                    break
                end
            end
        end

        -- SMART TARGET SELECTION: Choose optimal target
        local smartTarget = VNPC_SelectSmartPreyTarget(pred, pred.SightRange or 700)
        if IsValid(smartTarget) then
            local dist = pred:GetPos():Distance(smartTarget:GetPos())
            if dist <= 130 then
                if pred.EatEntity then
                    pred:EatEntity(smartTarget)
                elseif IsValid(belly) and belly.AddPrey then
                    belly:AddPrey(smartTarget)
                end
            else
                if pred.SetEnemy then pcall(pred.SetEnemy, pred, smartTarget) end
                if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_CHASE_ENEMY) end

                -- TACTICAL AMBUSH: Sprint faster when target is not looking at us
                if smartTarget.GetAimVector then
                    local aim = smartTarget:GetAimVector()
                    local toPred = (pred:GetPos() - smartTarget:GetPos()):GetNormalized()
                    if aim:Dot(toPred) < -0.3 and pred.SetRunSpeed then
                        if not pred.VNPC_BaseRunSpeed then pred.VNPC_BaseRunSpeed = pred.RunSpeed or 300 end
                        pcall(pred.SetRunSpeed, pred, pred.VNPC_BaseRunSpeed * 1.35)
                    elseif pred.VNPC_BaseRunSpeed and pred.SetRunSpeed then
                        pcall(pred.SetRunSpeed, pred, pred.VNPC_BaseRunSpeed)
                    end
                end
            end
        end
    end
end)

concommand.Add("vnpcs_smart_ai_status", function(ply)
    print("===============================================================")
    print("            V-NPCs SMARTER TACTICAL AI STATUS                  ")
    print("===============================================================")
    print(" - Smart Tactical AI Enabled: " .. tostring(GetConVar("vnpcs_smart_ai_enabled"):GetBool()))
    local count = 0
    for target, claimant in pairs(claimedTargets) do
        if IsValid(target) and IsValid(claimant) then
            count = count + 1
            local dist = math.floor(claimant:GetPos():Distance(target:GetPos()))
            print(string.format(" - Target Claim #%d: Predator [%s #%d] -> Engaging [%s #%d] (Dist: %d)", count, claimant.PrintName or claimant:GetClass(), claimant:EntIndex(), target.PrintName or target:GetClass(), target:EntIndex(), dist))
        end
    end
    if count == 0 then
        print(" - Active Target Claims: NONE currently engaged")
    end
    print("===============================================================")
end)

-- V-NPCs Predator Camp Population Regeneration & Consensual Male Mate Adoption Engine (vnpcs_predator_mating.lua)
-- Underpopulated predator camps dispatch foragers to capture Willing Male Citizens alive to bring back as mates for pregnancy and population growth

local pred_mating_enabled = CreateConVar("vnpcs_pred_mating_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable underpopulated predator camps seeking willing male mates for pregnancy")
local pred_mating_thresh = CreateConVar("vnpcs_pred_mating_thresh", "2", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Member count threshold below which a predator camp seeks a willing male mate")
local pred_pregnancy_time = CreateConVar("vnpcs_pred_pregnancy_time", "120.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Duration in seconds for a pregnant predator to bear a baby sister")

function VNPC_DeliverWillingMateToCamp(pred, camp, belly)
    if not IsValid(pred) or not IsValid(belly) or not camp then return false end
    if not belly.Prey or #belly.Prey == 0 then return false end

    belly:Regurgitate(1)
    pred.VNPC_IsCarryingMateForCamp = false
    belly.VNPC_NoDigestion = false
    belly.DigestionStrength = pred.VoreSettings and pred.VoreSettings.DigestionStrength or 2

    local male = nil
    for _, ent in ipairs(ents.GetAll()) do
        if ent.VNPC_IsWillingMate and ent:GetPos():DistToSqr(camp.pos) < (400 * 400) then
            male = ent
            break
        end
    end

    if IsValid(male) then
        pred.VNPC_LovedMate = male
        male.VNPC_LovedPredator = pred
        male.VNPC_CampID = camp.id
        camp.mates = camp.mates or {}
        if not table.HasValue(camp.mates, male) then
            table.insert(camp.mates, male)
        end

        if male.SetSchedule then pcall(male.SetSchedule, male, SCHED_TARGET_FACE) end
        if male.SetEnemy then pcall(male.SetEnemy, male, nil) end

        if VNPC_InitiatePrivateMating then
            VNPC_InitiatePrivateMating(pred, male, camp)
        else
            pred.VNPC_IsPregnantWithSister = CurTime() + pred_pregnancy_time:GetFloat()
        end
        if pred.EmitSound then
            pred:EmitSound("npc/citizen/vo/nice.wav", 80, 115)
        end
        return true
    end
    return false
end

function VNPC_ForagerSeekWillingMate(pred, camp)
    if not IsValid(pred) or not camp then return end

    local myPos = pred:GetPos()
    local bestMale = nil
    local bestDistSqr = 1600 * 1600

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) or ent:Health() <= 0 or ent.Vored or ent.VNPC_Vored then continue end
        if not VNPC_IsMalePreyCitizen or not VNPC_IsMalePreyCitizen(ent) then continue end
        if VNPC_IsAdultPreyCitizen and not VNPC_IsAdultPreyCitizen(ent) then continue end

        -- Check personality: must be "willing" (or "desire"/"desirous")
        local pers, _ = VNPC_GetPreyPersonality(ent)
        if string.lower(tostring(pers or "")) == "willing" or string.lower(tostring(pers or "")) == "desire" or string.lower(tostring(pers or "")) == "desirous" then
            local dSqr = myPos:DistToSqr(ent:GetPos())
            if dSqr <= bestDistSqr then
                bestMale = ent
                bestDistSqr = dSqr
            end
        end
    end

    if IsValid(bestMale) then
        local dist = pred:GetPos():Distance(bestMale:GetPos())
        if dist <= 140 then
            -- Capture willing male mate alive without digestion!
            local belly = pred.VNPC_Belly or pred.Belly
            if IsValid(belly) and belly.AddPrey then
                if belly:AddPrey(bestMale) then
                    pred.VNPC_IsCarryingMateForCamp = true
                    bestMale.VNPC_IsWillingMate = true
                    belly.VNPC_NoDigestion = true
                    belly.DigestionStrength = 0
                end
            end
        else
            if pred.SetEnemy then pcall(pred.SetEnemy, pred, bestMale) end
            if pred.SetLastPosition then pcall(pred.SetLastPosition, pred, bestMale:GetPos()) end
            if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_FORCED_GO_RUN) end
        end
    end
end

hook.Add("Think", "VNPC_PredatorMating_AI_Loop", function()
    if not pred_mating_enabled:GetBool() then return end
    local now = CurTime()
    if (VNPC_NextPredMatingThink or 0) > now then return end
    VNPC_NextPredMatingThink = now + 1.0

    local camps = VNPC_ActivePredatorCamps or {}
    local thresh = pred_mating_thresh:GetInt() or 2

    for _, camp in ipairs(camps) do
        -- Ensure camp needs mate if underpopulated
        camp.needsMate = (#camp.members <= thresh)

        for _, pred in ipairs(camp.members) do
            if not IsValid(pred) or pred:Health() <= 0 then continue end

            -- 1. Check existing pregnancy with a new sister
            if pred.VNPC_IsPregnantWithSister and now >= pred.VNPC_IsPregnantWithSister then
                pred.VNPC_IsPregnantWithSister = nil
                local child = ents.Create("npc_citizen")
                if IsValid(child) then
                    child:SetPos(pred:GetPos() + pred:GetForward() * 24 + Vector(0, 0, 5))
                    child:SetAngles(Angle(0, pred:GetAngles().y, 0))
                    child:Spawn()
                    child:Activate()
                    child.VNPC_ChildGender = "female"
                    child:SetModel("models/Humans/Group01/Female_01.mdl")
                    child.VNPC_BornSister = true

                    if VNPC_StartChildbirthAnimation then
                        VNPC_StartChildbirthAnimation(pred, child, camp)
                    end
                end
            end

            -- 2. If camp needs mate, Foragers seek willing male prey to carry home
            if camp.needsMate and (pred.VNPC_CampRole == "forager" or pred.VNPC_IsCampFounder or (VNPC_HasTownRole and VNPC_HasTownRole(pred, "mate"))) then
                local belly = pred.VNPC_Belly or pred.Belly
                if pred.VNPC_IsCarryingMateForCamp and IsValid(belly) and #belly.Prey > 0 then
                    if pred.SetEnemy then pcall(pred.SetEnemy, pred, nil) end
                    if pred.SetLastPosition then pcall(pred.SetLastPosition, pred, camp.pos) end
                    if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_FORCED_GO_RUN) end

                    if pred:GetPos():DistToSqr(camp.pos) <= (250 * 250) then
                        VNPC_DeliverWillingMateToCamp(pred, camp, belly)
                    end
                elseif not pred.VNPC_IsCarryingMateForCamp then
                    VNPC_ForagerSeekWillingMate(pred, camp)
                end
            end
        end
    end
end)

concommand.Add("vnpcs_pred_mating_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Predator Camp Mating & Population Regeneration Status")
    print("Enabled: " .. tostring(pred_mating_enabled:GetBool()))
    print("Underpopulated Member Threshold: <=" .. tostring(pred_mating_thresh:GetInt()))
    print("Pregnancy Duration: " .. tostring(pred_pregnancy_time:GetFloat()) .. "s")
    print("-----------------------------------------")
    local pregCount = 0
    for _, camp in ipairs(VNPC_ActivePredatorCamps or {}) do
        print(string.format(" -> Pred Camp [#%d] | Members: %d | Needs Mate: %s | Mates at camp: %d",
            camp.id, #camp.members, tostring(camp.needsMate or false), #(camp.mates or {})))
        for _, m in ipairs(camp.members) do
            if IsValid(m) and m.VNPC_IsPregnantWithSister then
                pregCount = pregCount + 1
                local rem = math.max(0, m.VNPC_IsPregnantWithSister - CurTime())
                print(string.format("      -> Pregnant Predator [%d] %s | Birth in: %.1fs", m:EntIndex(), m:GetClass(), rem))
            end
        end
    end
    print("Total pregnant predators expecting sisters: " .. pregCount)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Predator mating status printed to console. Pregnant preds: " .. pregCount)
    end
end)

concommand.Add("vnpcs_test_pred_mate", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a female V-NPC predator to test pregnancy with a sister-in-training!")
        return
    end
    target.VNPC_IsPregnantWithSister = CurTime() + 5.0 -- 5 second test pregnancy!
    ply:ChatPrint("[V-NPCs] Triggered pregnancy on " .. tostring(target) .. "! Baby sister-in-training in 5 seconds!")
end)

concommand.Add("vnpcs_test_spawn_willing_male", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local male = ents.Create("npc_citizen")
    if IsValid(male) then
        male:SetModel("models/Humans/Group01/Male_01.mdl")
        male:SetPos(tr.HitPos + Vector(0, 0, 10))
        male:SetAngles(Angle(0, math.random(0, 360), 0))
        male:Spawn()
        male:Activate()
        male.VNPC_PreyPersonality = "willing"
        male.PreyPersonality = "willing"
        ply:ChatPrint("[V-NPCs] Spawned Male Citizen with WILLING personality: " .. tostring(male) .. "!")
    end
end)

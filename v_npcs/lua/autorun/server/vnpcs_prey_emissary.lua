-- V-NPCs Prey Camp Emissary & Predator-Prey Cross-Camp Mating Engine (vnpcs_prey_emissary.lua)
-- Prey camps with zero females send a protected Male Emissary to invite bored predators to visit their fort to mate and bear a citizen baby

local emissary_enabled = CreateConVar("vnpcs_prey_emissary_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable prey camps sending male emissaries to ask bored predators to mate")
local boredom_time = CreateConVar("vnpcs_emissary_boredom_time", "25.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Seconds without combat/hunting required for a predator to be bored enough to agree")
local emissary_preg_time = CreateConVar("vnpcs_emissary_pregnancy_time", "45.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Duration in seconds for a visiting predator to bear a citizen baby at a prey camp")

function VNPC_IsPreyEmissary(ent)
    if not IsValid(ent) then return false end
    if ent.VNPC_IsPreyEmissary or ent.VNPC_PreyRole == "emissary" then return true end
    return false
end

function VNPC_IsPredatorBoredForMating(pred, predCamp)
    if not IsValid(pred) or pred:Health() <= 0 or pred.Vored or pred.VNPC_Vored then return false end
    if pred.VNPC_IsVisitingPreyCamp or pred.VNPC_IsPregnantWithSister or pred.VNPC_IsPregnantWithCitizen then return false end

    -- Must be calm (not in combat, not recently damaged)
    if IsValid(pred:GetEnemy()) or (CurTime() - (pred.VNPC_LastDamagedTime or 0)) < 15.0 then return false end

    -- Predator camp must not be at war
    if predCamp and predCamp.state == "war" then return false end

    if VNPC_GetPredatorPersonality then
        local pers, _ = VNPC_GetPredatorPersonality(pred)
        if string.lower(tostring(pers or "")) == "loving" then
            return true -- Loving predators always agree to visit and mate with male citizens without needing boredom!
        end
    end

    -- Belly must not be full of active undigested prey
    local belly = pred.VNPC_Belly or pred.Belly
    if IsValid(belly) and ((belly.Prey and #belly.Prey > 0) or (belly.DigestionPhase or 0) > 0) then
        return false
    end

    -- Must have been idle/without hunting for >= boredom_time (default 25s)
    local now = CurTime()
    if (now - (pred.VNPC_LastHuntTime or pred.VNPC_SpawnTime or now)) >= boredom_time:GetFloat() then
        return true
    end
    return true -- if calm and empty, she is bored enough!
end

function VNPC_PredatorShyEmissaryHesitation(pred, emissary, camp, predCamp)
    if not IsValid(pred) or not IsValid(emissary) or not camp then return false end
    if pred.VNPC_IsHesitatingToMate then return true end

    pred.VNPC_IsHesitatingToMate = true
    pred.VNPC_IsEmbarrassed = CurTime() + 6.0

    if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_NPC_FREEZE) end
    if emissary.SetSchedule then pcall(emissary.SetSchedule, emissary, SCHED_NPC_FREEZE) end

    if pred.EmitSound then
        local snd = math.random() < 0.5 and "npc/alyx/gasp03.wav" or "npc/citizen/sigh01.wav"
        pred:EmitSound(snd, 75, math.random(108, 115))
    end
    if pred.SetFacialExpression then
        pcall(pred.SetFacialExpression, pred, 4) -- Blushing / flustered face
    end

    for _, p in ipairs(player.GetAll()) do
        p:ChatPrint("[V-NPCs] SHY HESITATION! Emissary " .. (emissary.PrintName or emissary:GetClass()) .. " asked shy predator " .. (pred.PrintName or pred:GetClass()) .. " to visit his fort to mate; she blushes deeply and struggles to answer!")
    end

    timer.Simple(4.0, function()
        if IsValid(pred) and IsValid(emissary) and IsValid(camp) then
            pred.VNPC_IsHesitatingToMate = nil
            if pred.SetFacialExpression then
                pcall(pred.SetFacialExpression, pred, 2)
            end
            VNPC_PredatorAgreeToEmissary(pred, emissary, camp, predCamp)
            for _, p in ipairs(player.GetAll()) do
                p:ChatPrint("[V-NPCs] SHY AGREEMENT! After blushing and struggling to answer, shy predator " .. pred:GetClass() .. " softly agreed to follow Emissary " .. emissary:GetClass() .. " to his Prey Camp to mate!")
            end
        end
    end)
    return true
end

function VNPC_PredatorAgreeToEmissary(pred, emissary, camp, predCamp)
    if not IsValid(pred) or not IsValid(emissary) or not camp then return false end

    pred.VNPC_IsVisitingPreyCamp = true
    pred.VNPC_VisitedPreyCamp = camp
    pred.VNPC_OriginalCampID = pred.VNPC_CampID
    pred.VNPC_OriginalCampPos = predCamp and predCamp.pos or pred:GetPos()
    emissary.VNPC_EscortingPredator = pred

    if VNPC_RecordRecognizedMate then
        VNPC_RecordRecognizedMate(predCamp, pred, emissary)
    end

    if pred.SetEnemy then pcall(pred.SetEnemy, pred, nil) end
    if pred.SetLastPosition then pcall(pred.SetLastPosition, pred, camp.pos) end
    if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_FORCED_GO_RUN) end
    if emissary.SetLastPosition then pcall(emissary.SetLastPosition, emissary, camp.pos) end
    if emissary.SetSchedule then pcall(emissary.SetSchedule, emissary, SCHED_FORCED_GO_RUN) end

    if pred.EmitSound then pred:EmitSound("npc/citizen/vo/nice.wav", 80, 108) end
    for _, p in ipairs(player.GetAll()) do
        p:ChatPrint("[V-NPCs] PREY EMISSARY SUCCESS! Prey Camp #" .. camp.id .. " sent an Emissary; bored predator " .. pred:GetClass() .. " agreed to visit their fort to mate!")
    end
    return true
end

function VNPC_EmissarySeekPredatorCamp(emissary, camp)
    if not IsValid(emissary) or not camp then return end

    local myPos = emissary:GetPos()
    local bestCamp = nil
    local bestDistSqr = 3000 * 3000

    for _, predCamp in ipairs(VNPC_ActivePredatorCamps or {}) do
        if predCamp.pos and predCamp.state ~= "war" then
            local dSqr = myPos:DistToSqr(predCamp.pos)
            if dSqr <= bestDistSqr then
                bestCamp = predCamp
                bestDistSqr = dSqr
            end
        end
    end

    if bestCamp then
        if emissary:GetPos():DistToSqr(bestCamp.pos) <= (400 * 400) then
            if VNPC_CheckRecognizedMateWelcome and VNPC_CheckRecognizedMateWelcome(bestCamp, emissary, camp) then
                return
            end
            for _, mem in ipairs(bestCamp.members) do
                if VNPC_IsPredatorBoredForMating(mem, bestCamp) then
                    local pers = (VNPC_GetPredatorPersonality and select(1, VNPC_GetPredatorPersonality(mem))) or "opportunistic"
                    if string.lower(tostring(pers)) == "shy" or (VNPC_IsShyPredator and VNPC_IsShyPredator(mem)) then
                        VNPC_PredatorShyEmissaryHesitation(mem, emissary, camp, bestCamp)
                    else
                        VNPC_PredatorAgreeToEmissary(mem, emissary, camp, bestCamp)
                    end
                    break
                end
            end
        else
            if emissary.SetLastPosition then pcall(emissary.SetLastPosition, emissary, bestCamp.pos) end
            if emissary.SetSchedule then pcall(emissary.SetSchedule, emissary, SCHED_FORCED_GO_RUN) end
        end
    end
end

hook.Add("Think", "VNPC_PreyEmissary_AI_Loop", function()
    if not emissary_enabled:GetBool() then return end
    local now = CurTime()
    if (VNPC_NextPreyEmissaryThink or 0) > now then return end
    VNPC_NextPreyEmissaryThink = now + 1.0

    -- 1. Check Prey Camps without females and dispatch an emissary
    for _, camp in ipairs(VNPC_ActivePreyCamps or {}) do
        if camp.fortified or #(camp.huts or {}) > 0 then
            local femaleCount = 0
            local activeEmissaries = 0
            for _, mem in ipairs(camp.members) do
                if IsValid(mem) and mem:Health() > 0 then
                    if VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(mem) then
                        femaleCount = femaleCount + 1
                    end
                    if mem.VNPC_PreyRole == "emissary" or mem.VNPC_IsPreyEmissary then
                        activeEmissaries = activeEmissaries + 1
                    end
                end
            end

            if femaleCount == 0 and #camp.members >= 2 and activeEmissaries == 0 then
                for _, mem in ipairs(camp.members) do
                    if IsValid(mem) and VNPC_IsMalePreyCitizen and VNPC_IsMalePreyCitizen(mem) then
                        mem.VNPC_PreyRole = "emissary"
                        mem.VNPC_IsPreyEmissary = true
                        VNPC_EmissarySeekPredatorCamp(mem, camp)
                        break
                    end
                end
            elseif activeEmissaries > 0 then
                for _, mem in ipairs(camp.members) do
                    if IsValid(mem) and (mem.VNPC_PreyRole == "emissary" or mem.VNPC_IsPreyEmissary) then
                        if not mem.VNPC_EscortingPredator then
                            VNPC_EmissarySeekPredatorCamp(mem, camp)
                        end
                    end
                end
            end
        end
    end

    -- 2. Coordinate visiting predators pregnant with citizen babies at Prey Camps
    for _, pred in ipairs(ents.GetAll()) do
        if not IsValid(pred) or pred:Health() <= 0 then continue end
        if not pred.VNPC_IsVisitingPreyCamp or not pred.VNPC_VisitedPreyCamp then continue end
        local camp = pred.VNPC_VisitedPreyCamp

        if pred.VNPC_IsPregnantWithCitizen and now >= pred.VNPC_IsPregnantWithCitizen then
            pred.VNPC_IsPregnantWithCitizen = nil
            local child = ents.Create("npc_citizen")
            if IsValid(child) then
                child:SetPos(pred:GetPos() + pred:GetForward() * 24 + Vector(0, 0, 5))
                child:SetAngles(Angle(0, pred:GetAngles().y, 0))
                child:Spawn()
                child:Activate()
                child.VNPC_ChildGender = math.random() < 0.5 and "female" or "male"
                if child.VNPC_ChildGender == "female" then
                    child:SetModel("models/Humans/Group01/Female_01.mdl")
                else
                    child:SetModel("models/Humans/Group01/Male_01.mdl")
                end

                if VNPC_StartChildbirthAnimation then
                    VNPC_StartChildbirthAnimation(pred, child, camp)
                end
            end

            -- Return home to original Predator Camp after childbirth completes
            timer.Simple(4.5, function()
                if IsValid(pred) then
                    pred.VNPC_IsVisitingPreyCamp = false
                    pred.VNPC_VisitedPreyCamp = nil
                    pred.VNPC_PreyCampBabyMother = nil
                    if pred.SetLastPosition and pred.VNPC_OriginalCampPos then
                        pcall(pred.SetLastPosition, pred, pred.VNPC_OriginalCampPos)
                    end
                    if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_FORCED_GO_RUN) end
                    for _, p in ipairs(player.GetAll()) do
                        p:ChatPrint("[V-NPCs] CHILDBIRTH COMPLETE! Visiting predator " .. pred:GetClass() .. " gave birth to a new citizen for Prey Camp #" .. tostring(camp and camp.id or "N/A") .. " and has returned home to Predator Camp #" .. tostring(pred.VNPC_OriginalCampID or "N/A") .. "!")
                    end
                end
            end)
        elseif not pred.VNPC_IsPregnantWithCitizen then
            local distSqr = pred:GetPos():DistToSqr(camp.pos)
            if distSqr <= (300 * 300) then
                pred.VNPC_IsPregnantWithCitizen = now + emissary_preg_time:GetFloat()
                pred.VNPC_PreyCampBabyMother = true

                for _, mem in ipairs(camp.members) do
                    if IsValid(mem) and (mem.VNPC_PreyRole == "emissary" or mem.VNPC_IsPreyEmissary) then
                        mem.VNPC_PreyRole = "citizen"
                        mem.VNPC_IsPreyEmissary = nil
                        mem.VNPC_EscortingPredator = nil
                        break
                    end
                end

                if pred.EmitSound then pred:EmitSound("npc/citizen/vo/nice.wav", 80, 108) end
                for _, p in ipairs(player.GetAll()) do
                    p:ChatPrint("[V-NPCs] CROSS-CAMP MATING! Predator " .. pred:GetClass() .. " arrives at Prey Camp #" .. camp.id .. " and is now pregnant with a new citizen baby for their fort!")
                end
            else
                if pred.SetLastPosition then pcall(pred.SetLastPosition, pred, camp.pos) end
                if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_FORCED_GO_RUN) end
            end
        end
    end
end)

concommand.Add("vnpcs_emissary_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Prey Camp Emissary & Visiting Predator Mating Status")
    print("Enabled: " .. tostring(emissary_enabled:GetBool()))
    print("Predator Boredom Time: " .. tostring(boredom_time:GetFloat()) .. "s")
    print("Visiting Pregnancy Duration: " .. tostring(emissary_preg_time:GetFloat()) .. "s")
    print("-----------------------------------------")
    local emissaryCount, visitCount = 0, 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) then
            if VNPC_IsPreyEmissary(ent) then
                emissaryCount = emissaryCount + 1
                print(string.format(" -> Active Emissary [%d] %s | Camp: #%s", ent:EntIndex(), ent:GetClass(), tostring(ent.VNPC_PreyCampID or "N/A")))
            end
            if ent.VNPC_IsVisitingPreyCamp then
                visitCount = visitCount + 1
                local rem = ent.VNPC_IsPregnantWithCitizen and math.max(0, ent.VNPC_IsPregnantWithCitizen - CurTime()) or 0
                print(string.format(" -> Visiting Predator [%d] %s | Visiting Camp: #%s | Birth in: %.1fs",
                    ent:EntIndex(), ent:GetClass(), tostring(ent.VNPC_VisitedPreyCamp and ent.VNPC_VisitedPreyCamp.id or "N/A"), rem))
            end
        end
    end
    print("Total active emissaries: " .. emissaryCount .. " | Visiting pregnant predators: " .. visitCount)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Emissary status printed to console. Emissaries: " .. emissaryCount .. " | Visiting preds: " .. visitCount)
    end
end)

concommand.Add("vnpcs_test_prey_emissary", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at a Male Citizen in a Prey Camp to assign as an Emissary!")
        return
    end
    local camp = VNPC_GetPreyCamp and VNPC_GetPreyCamp(target)
    if not camp then
        camp = VNPC_AssignPreyToCamp and VNPC_AssignPreyToCamp(target)
    end
    if camp then
        target.VNPC_PreyRole = "emissary"
        target.VNPC_IsPreyEmissary = true
        VNPC_EmissarySeekPredatorCamp(target, camp)
        ply:ChatPrint("[V-NPCs] Assigned " .. tostring(target) .. " as an Emissary for Prey Camp #" .. camp.id .. " and dispatched to seek a bored predator!")
    end
end)

concommand.Add("vnpcs_test_visiting_mate", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a female V-NPC predator to test cross-camp visiting pregnancy!")
        return
    end
    local bestCamp = nil
    for _, camp in ipairs(VNPC_ActivePreyCamps or {}) do
        bestCamp = camp
        break
    end
    if not bestCamp then
        ply:ChatPrint("[V-NPCs] No active Prey Camp found to visit!")
        return
    end
    target.VNPC_IsVisitingPreyCamp = true
    target.VNPC_VisitedPreyCamp = bestCamp
    target.VNPC_OriginalCampID = target.VNPC_CampID
    target.VNPC_IsPregnantWithCitizen = CurTime() + 5.0 -- 5 second test pregnancy!
    target.VNPC_PreyCampBabyMother = true
    ply:ChatPrint("[V-NPCs] Set " .. tostring(target) .. " as a visiting predator pregnant with a citizen baby for Prey Camp #" .. bestCamp.id .. " (birth in 5 seconds)!")
end)

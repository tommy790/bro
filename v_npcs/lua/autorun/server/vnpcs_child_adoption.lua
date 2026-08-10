-- V-NPCs Predator Adoption & Sister-In-Training AI Engine (vnpcs_child_adoption.lua)
-- Predators who conquer a prey camp adopt surviving female children; when grown, they transform into full V-NPC predators to join the pack

local adoption_enabled = CreateConVar("vnpcs_child_adoption_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable predator adoption of surviving female children from conquered prey camps")
local adopted_role = CreateConVar("vnpcs_adopted_sister_role", "forager", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Default camp role assigned to an adopted sister once grown (forager or stayer)")

function VNPC_AdoptFemaleChild(pred, child, camp)
    if not adoption_enabled:GetBool() then return false end
    if not IsValid(pred) or not IsValid(child) then return false end

    -- Unenroll from the conquered prey camp
    child.VNPC_PreyCampID = nil
    if camp and camp.members then
        for idx, mem in ipairs(camp.members) do
            if mem == child then
                table.remove(camp.members, idx)
                break
            end
        end
    end

    -- Assign adoption references
    child.VNPC_AdoptedByPredator = pred
    if pred.VNPC_CampID then
        child.VNPC_CampID = pred.VNPC_CampID
    end

    -- Instruct child to follow her new adoptive predator mother
    if child.SetSchedule then
        pcall(child.SetSchedule, child, SCHED_TARGET_FACE)
    end
    if child.SetEnemy then
        pcall(child.SetEnemy, child, nil)
    end

    if child.EmitSound then
        child:EmitSound("npc/citizen/vo/nice.wav", 80, 115)
    end

    for _, p in ipairs(player.GetAll()) do
        p:ChatPrint("[V-NPCs] CAMP CONQUERED! Predator " .. (pred.PrintName or pred:GetClass()) .. " adopted a surviving female child from Prey Camp #" .. tostring(camp and camp.id or "N/A") .. " to raise as a sister!")
    end

    return true
end

function VNPC_TransformToPredator(child, motherPred)
    if not IsValid(child) then return false end

    -- 1. Ensure full adult scale and model
    child:SetModelScale(1.0, 0)
    if not child:GetModel() or not string.find(string.lower(child:GetModel()), "female") then
        child:SetModel("models/Humans/Group01/Female_01.mdl")
    end

    -- 2. Give her a full V-NPC Vore Belly and movesets
    if VNPC_GiveFemaleModelVore then
        VNPC_GiveFemaleModelVore(child)
    end

    child.VNPC_FemaleModelVore = true
    child.Predator = true
    child.VNPC_IsAdoptedSister = true
    child.VNPC_ProtectedChild = nil
    child.VNPC_IsGrowingBaby = nil
    child.VNPC_AdoptedByPredator = nil

    -- 3. Enroll her in her adoptive mother's Predator Camp
    local predCamp = nil
    if IsValid(motherPred) and VNPC_GetPredatorCamp then
        predCamp = VNPC_GetPredatorCamp(motherPred)
    end

    if predCamp then
        table.insert(predCamp.members, child)
        child.VNPC_CampID = predCamp.id
        child.VNPC_CampRole = adopted_role:GetString() or "forager"
    elseif VNPC_AssignPredatorToCamp then
        VNPC_AssignPredatorToCamp(child)
    end

    if child.EmitSound then
        child:EmitSound("belly/snd_digeststart.wav", 80, 105)
    end

    for _, p in ipairs(player.GetAll()) do
        p:ChatPrint("[V-NPCs] SISTER-IN-TRAINING GROWN! An adopted female child has reached adulthood and joined " .. (IsValid(motherPred) and (motherPred.PrintName or motherPred:GetClass()) or "the pack") .. "'s camp as a full V-NPC Predator!")
    end

    return true
end

function VNPC_CheckPreyCampConquest(camp)
    if not adoption_enabled:GetBool() or not camp then return end

    local livingAdults = 0
    local survivingChildren = {}
    for _, mem in ipairs(camp.members) do
        if IsValid(mem) and mem:Health() > 0 and not mem.Vored and not mem.VNPC_Vored then
            if VNPC_IsProtectedChildPrey and VNPC_IsProtectedChildPrey(mem) then
                table.insert(survivingChildren, mem)
            else
                livingAdults = livingAdults + 1
            end
        end
    end

    -- Track that camp once had adult members so conquest is meaningful
    if livingAdults > 0 then
        camp.hadAdultMembers = true
        return
    end

    -- When 0 living adults remain and children survive, the camp is conquered!
    if camp.hadAdultMembers and livingAdults == 0 and #survivingChildren > 0 then
        local conquerorPred = nil
        local bestDistSqr = 1600 * 1600
        for _, pred in ipairs(ents.GetAll()) do
            if IsValid(pred) and pred:Health() > 0 and (pred.IsDrGNextbot or pred.VNPC_FemaleModelVore or pred.Predator) then
                local dSqr = pred:GetPos():DistToSqr(camp.pos)
                if dSqr <= bestDistSqr then
                    conquerorPred = pred
                    bestDistSqr = dSqr
                end
            end
        end

        if IsValid(conquerorPred) then
            for _, child in ipairs(survivingChildren) do
                local isFemale = (child.VNPC_ChildGender == "female") or (VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(child))
                if isFemale then
                    VNPC_AdoptFemaleChild(conquerorPred, child, camp)
                end
            end
        end
        camp.hadAdultMembers = false
    end
end

concommand.Add("vnpcs_adoption_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Predator Child Adoption & Sister-In-Training Status")
    print("Enabled: " .. tostring(adoption_enabled:GetBool()))
    print("Default Grown Role: " .. tostring(adopted_role:GetString()))
    print("-----------------------------------------")
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent.VNPC_AdoptedByPredator then
            count = count + 1
            local pct = math.Clamp((CurTime() - (ent.VNPC_BabyBirthTime or 0)) / (ent.VNPC_BabyGrowDuration or 60) * 100, 0, 100)
            print(string.format(" -> Adopted Female Child [%d] %s | Adoptive Mother: %s | Growth: %.1f%%",
                ent:EntIndex(), ent:GetClass(), tostring(ent.VNPC_AdoptedByPredator), pct))
        end
    end
    print("Total active adopted female children: " .. count)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Adoption status printed to console. Adopted children: " .. count)
    end
end)

concommand.Add("vnpcs_test_adopt_child", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at a female citizen/child to trigger adoption!")
        return
    end
    local pred = nil
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent ~= target and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) then
            pred = ent
            break
        end
    end
    if not IsValid(pred) then
        ply:ChatPrint("[V-NPCs] No active female V-NPC predator found on the map to adopt!")
        return
    end
    target.VNPC_ChildGender = "female"
    target.VNPC_IsGrowingBaby = true
    target.VNPC_BabyBirthTime = CurTime()
    target.VNPC_BabyGrowDuration = 60.0
    VNPC_AdoptFemaleChild(pred, target, nil)
end)

concommand.Add("vnpcs_test_grow_sister", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not target.VNPC_AdoptedByPredator then
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and ent.VNPC_AdoptedByPredator then
                target = ent
                break
            end
        end
    end
    if not IsValid(target) or not target.VNPC_AdoptedByPredator then
        ply:ChatPrint("[V-NPCs] No adopted female child found! Use vnpcs_test_adopt_child first.")
        return
    end
    VNPC_TransformToPredator(target, target.VNPC_AdoptedByPredator)
end)

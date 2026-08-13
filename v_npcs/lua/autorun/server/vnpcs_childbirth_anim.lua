-- V-NPCs Pregnant Citizen Womb Growth & Childbirth Bone Pose Engine (vnpcs_childbirth_anim.lua)
-- Spawns unborn baby citizens inside pregnant mothers; grows from value 10 to 50; mother sits with legs separated to give birth; baby grows to full size 1.0 in 60s

local growth_rate = CreateConVar("vnpcs_prey_camp_baby_growth_rate", "1.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Growth value gained per second for unborn babies inside the womb (value 10 to 50)")
local child_grow_time = CreateConVar("vnpcs_prey_camp_child_grow_time", "60.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Duration in seconds for a born baby citizen to grow from 0.35 to full size 1.0")
local childbirth_enabled = CreateConVar("vnpcs_childbirth_anim_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable sitting childbirth bone pose animation and pregnancy belly bulge")
local mate_love_max = CreateConVar("vnpcs_mate_love_max", "100", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum mate love score (higher love lengthens mating and grows larger litters)")
local mate_love_max_litter = CreateConVar("vnpcs_mate_love_max_litter", "4", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum number of babies a high-love mother can carry at once")

function VNPC_IsProtectedChildPrey(ent)
    if not IsValid(ent) then return false end
    if ent.VNPC_IsUnbornBaby or ent.VNPC_IsGrowingBaby or ent.VNPC_ProtectedChild then return true end
    if ent.VNPC_PreyCampID and (ent:GetModelScale() or 1) < 0.95 then return true end
    return false
end

function VNPC_IsAdultPreyCitizen(ent)
    if not IsValid(ent) or ent:Health() <= 0 then return false end
    if ent.VNPC_IsUnbornBaby or ent.VNPC_IsGrowingBaby or ent.VNPC_ProtectedChild then return false end
    if (ent:GetModelScale() or 1) < 0.95 then return false end
    return true
end

function VNPC_GetMateLove(a, b)
    local love = 0
    if IsValid(a) then love = math.max(love, tonumber(a.VNPC_MateLove) or 0) end
    if IsValid(b) then love = math.max(love, tonumber(b.VNPC_MateLove) or 0) end
    local maxLove = mate_love_max:GetFloat()
    if maxLove < 1 then maxLove = 100 end
    return math.Clamp(love, 0, maxLove)
end

function VNPC_AddMateLove(a, b, amount)
    amount = tonumber(amount) or 0
    local maxLove = mate_love_max:GetFloat()
    if maxLove < 1 then maxLove = 100 end
    local current = VNPC_GetMateLove(a, b)
    local nextLove = math.Clamp(current + amount, 0, maxLove)
    if IsValid(a) then a.VNPC_MateLove = nextLove end
    if IsValid(b) then b.VNPC_MateLove = nextLove end
    return nextLove
end

function VNPC_TickCoupleLove(a, b, dt)
    dt = tonumber(dt) or 0
    if dt <= 0 or not IsValid(a) or not IsValid(b) then
        return VNPC_GetMateLove(a, b)
    end
    local gain = 0
    if a.VNPC_IsMatingBonePose or b.VNPC_IsMatingBonePose or (a.GetNWBool and a:GetNWBool("VNPC_IsMatingBonePose")) or (b.GetNWBool and b:GetNWBool("VNPC_IsMatingBonePose")) then
        gain = 1.15
    else
        local dist = a:GetPos():Distance(b:GetPos())
        if dist <= 160 then
            gain = 0.55
        elseif dist <= 420 then
            gain = 0.18
        end
    end
    if a.VNPC_IsPregnant or b.VNPC_IsPregnant then
        gain = gain + 0.12
    end
    if gain <= 0 then
        return VNPC_GetMateLove(a, b)
    end
    return VNPC_AddMateLove(a, b, gain * dt)
end

function VNPC_GetMatingDuration(love)
    love = math.Clamp(tonumber(love) or 0, 0, 100)
    return 8.0 + (love / 100.0) * 22.0
end

function VNPC_GetLitterSize(love)
    love = math.Clamp(tonumber(love) or 0, 0, 100)
    local size = 1
    if love >= 88 then
        size = 4
    elseif love >= 68 then
        size = 3
    elseif love >= 38 then
        size = 2
    end
    local maxLitter = mate_love_max_litter:GetInt()
    if maxLitter < 1 then maxLitter = 1 end
    return math.Clamp(size, 1, maxLitter)
end

function VNPC_IsWombPrey(ent, info)
    if info and (info.WombPrey or info.NoDigest) then return true end
    if IsValid(ent) and (ent.VNPC_IsWombPrey or ent.VNPC_IsUnbornBaby) then return true end
    return false
end

function VNPC_BellyHasSwallowedPrey(belly)
    if not IsValid(belly) or not istable(belly.Prey) then return false end
    for _, info in ipairs(belly.Prey) do
        if info and not VNPC_IsWombPrey(info.Entity, info) then
            return true
        end
    end
    return false
end

function VNPC_EnsureMotherBelly(mother)
    if not IsValid(mother) then return nil end
    local belly = mother.VNPC_Belly or mother.Belly or mother.belly
    if IsValid(belly) then return belly end
    if mother.GetBelly and isfunction(mother.GetBelly) then
        local ok, found = pcall(mother.GetBelly, mother)
        if ok and IsValid(found) then return found end
    end
    if mother.GetNWEntity then
        local nw = mother:GetNWEntity("Belly")
        if IsValid(nw) then return nw end
    end
    -- Existing preds keep their vore belly. Regular pregnant citizens get a
    -- belly without being turned into hunters.
    if mother.Predator or mother.VNPC_FemaleModelVore or mother.IsDrGNextbot or mother.EatEntity then
        if VNPC_GiveFemaleModelVore then
            pcall(VNPC_GiveFemaleModelVore, mother)
            belly = mother.VNPC_Belly or mother.Belly
            if IsValid(belly) then return belly end
        end
    end
    if VNPC_EnsureFemalePreyBelly then
        return VNPC_EnsureFemalePreyBelly(mother)
    end
    return nil
end

function VNPC_GetWombPreyValue(mother, baby)
    local growth = 10
    if IsValid(mother) then
        growth = tonumber(mother.VNPC_BabyGrowthValue) or 10
    end
    local t = math.Clamp((growth - 10) / 40, 0, 1)
    return 16 + t * 52
end

function VNPC_PutUnbornInBelly(mother, baby)
    if not IsValid(mother) or not IsValid(baby) then return false end
    local belly = VNPC_EnsureMotherBelly(mother)
    if not IsValid(belly) then return false end
    belly.Prey = belly.Prey or {}
    for _, info in ipairs(belly.Prey) do
        if info and info.Entity == baby then
            info.WombPrey = true
            info.NoDigest = true
            info.Absorbing = false
            baby.VNPC_IsWombPrey = true
            baby.VNPC_IsUnbornBaby = true
            baby.VNPC_MotherRef = mother
            return true
        end
    end

    baby.VNPC_IsUnbornBaby = true
    baby.VNPC_IsWombPrey = true
    baby.VNPC_MotherRef = mother
    baby.Vored = true
    baby.VNPC_Vored = true
    baby.VNPC_IsBeingSwallowed = nil
    baby.VNPC_IngestionDepth = nil
    if baby.SetHealth then baby:SetHealth(math.max(baby:Health() or 0, 100)) end

    if baby.SetParent then baby:SetParent(nil) end
    if VNPC_HideSwallowedPrey then
        VNPC_HideSwallowedPrey(baby, belly)
    else
        baby:SetNoDraw(true)
        if baby.AddEffects then baby:AddEffects(EF_NODRAW) end
        baby:SetSolid(SOLID_NONE)
        baby:SetMoveType(MOVETYPE_NONE)
        baby:SetParent(belly)
        baby:SetPos(belly:GetPos())
    end

    local value = VNPC_GetWombPreyValue(mother, baby)
    table.insert(belly.Prey, {
        Value = value,
        TrueValue = value,
        Alive = true,
        Entity = baby,
        Absorbing = false,
        WombPrey = true,
        NoDigest = true,
        OldFlags = { Solid = SOLID_BBOX, MoveType = MOVETYPE_STEP, Flags = 0 }
    })
    if belly.SetBellySize then belly:SetBellySize() end
    if belly.SetNWInt and belly.GetAliveFactor then
        belly:SetNWInt("AliveFactor", belly:GetAliveFactor())
    end
    return true
end

function VNPC_UpdateWombPreyInBelly(mother)
    if not IsValid(mother) then return end
    local belly = mother.VNPC_Belly or mother.Belly or mother.belly
    if not IsValid(belly) or not istable(belly.Prey) then return end
    local growth = tonumber(mother.VNPC_BabyGrowthValue) or 10
    local t = math.Clamp((growth - 10) / 40, 0, 1)
    local scale = 0.15 + t * 0.17
    local changed = false
    for _, info in ipairs(belly.Prey) do
        if not info or not VNPC_IsWombPrey(info.Entity, info) then continue end
        local val = VNPC_GetWombPreyValue(mother, info.Entity)
        info.Value = val
        info.TrueValue = val
        info.WombPrey = true
        info.NoDigest = true
        info.Absorbing = false
        if IsValid(info.Entity) then
            info.Entity.VNPC_IsWombPrey = true
            if info.Entity.SetModelScale then
                info.Entity:SetModelScale(scale, 0)
            end
        end
        changed = true
    end
    if changed and belly.SetBellySize then
        belly:SetBellySize()
    end
end

function VNPC_ReleaseWombPrey(mother, baby)
    if not IsValid(baby) then return false end
    local belly = IsValid(mother) and (mother.VNPC_Belly or mother.Belly or mother.belly) or nil
    if not IsValid(belly) then
        belly = baby:GetParent()
        if not (IsValid(belly) and belly.Prey) then
            belly = nil
        end
    end
    if IsValid(belly) and istable(belly.Prey) then
        for i = #belly.Prey, 1, -1 do
            local info = belly.Prey[i]
            if info and info.Entity == baby then
                table.remove(belly.Prey, i)
                break
            end
        end
        if belly.SetBellySize then belly:SetBellySize() end
        if #belly.Prey == 0 or not VNPC_BellyHasSwallowedPrey(belly) then
            if belly.ChangeDigestionPhase and not VNPC_BellyHasSwallowedPrey(belly) then
                if #belly.Prey == 0 then
                    belly:ChangeDigestionPhase(0)
                end
            end
        end
    end
    baby:SetParent(nil)
    if VNPC_UnhideRegurgitatedPrey then
        VNPC_UnhideRegurgitatedPrey(baby)
    else
        baby:SetNoDraw(false)
        if baby.RemoveEffects then baby:RemoveEffects(EF_NODRAW) end
        if baby.SetRenderMode then baby:SetRenderMode(RENDERMODE_NORMAL) end
        baby:SetColor(Color(255, 255, 255, 255))
        if baby.DrawShadow then baby:DrawShadow(true) end
    end
    baby.Vored = false
    baby.VNPC_Vored = false
    baby.VNPC_IsDeadAndAbsorbed = nil
    baby.VNPC_IsWombPrey = nil
    baby.VNPC_IsBeingSwallowed = nil
    baby.VNPC_IngestionDepth = nil
    if baby.NextThink then pcall(baby.NextThink, baby, CurTime()) end
    return true
end

function VNPC_RemoveWombPrey(mother, baby)
    VNPC_ReleaseWombPrey(mother, baby)
    if IsValid(baby) then
        baby:Remove()
    end
end

function VNPC_GetBabyNPCClass(mother)
    if not IsValid(mother) or mother:IsPlayer() then return "npc_citizen" end
    local cls = mother:GetClass()
    if not isstring(cls) or cls == "" or cls == "player" or cls:find("func_") then
        return "npc_citizen"
    end
    return cls
end

function VNPC_IsHL2GenderedHumanModel(mdl)
    mdl = string.lower(mdl or "")
    if mdl == "" then return false end
    if mdl:find("alyx") or mdl:find("mossman") then return false end
    return mdl:find("humans/group0") or mdl:find("humans/female") or mdl:find("humans/male")
        or mdl:find("/group01/") or mdl:find("/group02/") or mdl:find("/group03")
        or mdl:find("citizen_female") or mdl:find("citizen_male")
end

function VNPC_GetBabyModel(mother, gender)
    gender = gender or "female"
    local fallback = (gender == "male") and "models/Humans/Group01/Male_01.mdl" or "models/Humans/Group01/Female_01.mdl"
    if not IsValid(mother) then return fallback end
    local momMdl = mother:GetModel() or ""
    if momMdl == "" then return fallback end
    -- Unique / custom NPCs always look like the mother.
    if not VNPC_IsHL2GenderedHumanModel(momMdl) then
        return momMdl
    end
    if gender == "male" then
        local male = momMdl
        male = string.gsub(male, "[Ff]emale_", "Male_")
        male = string.gsub(male, "/[Ff]emale", "/Male")
        male = string.gsub(male, "female", "male")
        if male ~= momMdl and util.IsValidModel and util.IsValidModel(male) then
            return male
        end
        if male ~= momMdl then
            return male
        end
    end
    return momMdl
end

function VNPC_CopyMotherAppearance(mother, child)
    if not IsValid(mother) or not IsValid(child) then return end
    if mother.GetSkin and child.SetSkin then
        pcall(child.SetSkin, child, mother:GetSkin() or 0)
    end
    if mother.GetColor and child.SetColor then
        pcall(child.SetColor, child, mother:GetColor())
    end
    if mother.GetNumBodyGroups and child.SetBodygroup and mother.GetBodygroup then
        local n = mother:GetNumBodyGroups() or 0
        for i = 0, n - 1 do
            pcall(child.SetBodygroup, child, i, mother:GetBodygroup(i) or 0)
        end
    end
    if mother.GetMaterial and child.SetMaterial then
        local mat = mother:GetMaterial()
        if isstring(mat) and mat ~= "" then
            pcall(child.SetMaterial, child, mat)
        end
    end
end

function VNPC_HideBabyOwnBelly(child)
    if not IsValid(child) then return end
    local belly = child.VNPC_Belly or child.Belly or child.belly
    if IsValid(belly) then
        child.VNPC_BabyOwnBelly = belly
        belly:SetNoDraw(true)
        if belly.SetSolid then belly:SetSolid(SOLID_NONE) end
    end
end

function VNPC_SpawnMotherChild(mother, gender)
    gender = gender or (math.random() < 0.5 and "female" or "male")
    local cls = VNPC_GetBabyNPCClass(mother)
    local child = ents.Create(cls)
    if not IsValid(child) then
        child = ents.Create("npc_citizen")
    end
    if not IsValid(child) then return nil end
    child.VNPC_IsUnbornBaby = true
    child.VNPC_IsWombPrey = true
    child.VNPC_ProtectedChild = true
    child.VNPC_ChildGender = gender
    child.VNPC_MotherClass = cls
    if IsValid(mother) then
        child.VNPC_MotherModel = mother:GetModel()
        child:SetPos(mother:GetPos() + Vector(0, 0, 32))
        child:SetAngles(Angle(0, mother:GetAngles().y, 0))
    end
    child:Spawn()
    child:Activate()
    local mdl = VNPC_GetBabyModel(mother, gender)
    if mdl and child.SetModel then
        pcall(child.SetModel, child, mdl)
    end
    VNPC_CopyMotherAppearance(mother, child)
    VNPC_HideBabyOwnBelly(child)
    return child
end

function VNPC_CreateUnbornBaby(mother)
    if not IsValid(mother) then return nil end
    local gender = math.random() < 0.5 and "female" or "male"
    local child = VNPC_SpawnMotherChild(mother, gender)
    if not IsValid(child) then return nil end
    child:SetModelScale(0.15, 0)
    child:SetNoDraw(true)
    child:SetSolid(0)
    child:SetMoveType(MOVETYPE_NONE)
    child.VNPC_IsUnbornBaby = true
    child.VNPC_IsWombPrey = true
    child.VNPC_MotherRef = mother
    child:SetHealth(100)
    if not VNPC_PutUnbornInBelly(mother, child) then
        child:SetParent(mother)
    end
    return child
end

function VNPC_GetUnbornLitter(mother)
    local kids = {}
    local seen = {}
    if not IsValid(mother) then return kids end
    local function addKid(c)
        if IsValid(c) and not seen[c] then
            seen[c] = true
            table.insert(kids, c)
        end
    end
    if istable(mother.VNPC_UnbornChildren) then
        for _, c in ipairs(mother.VNPC_UnbornChildren) do
            addKid(c)
        end
    end
    addKid(mother.VNPC_UnbornChild)
    local belly = mother.VNPC_Belly or mother.Belly or mother.belly
    if IsValid(belly) and istable(belly.Prey) then
        for _, info in ipairs(belly.Prey) do
            local ent = info and info.Entity
            if info and (info.WombPrey or info.NoDigest or (IsValid(ent) and (ent.VNPC_IsWombPrey or ent.VNPC_IsUnbornBaby))) then
                addKid(ent)
            end
        end
    end
    mother.VNPC_UnbornChildren = kids
    if #kids > 0 then
        mother.VNPC_UnbornChild = kids[1]
    end
    return kids
end

function VNPC_EnsureUnbornLitter(mother, count)
    if not IsValid(mother) then return {} end
    local maxLitter = mate_love_max_litter:GetInt()
    if maxLitter < 1 then maxLitter = 1 end
    count = math.max(1, math.floor(tonumber(count) or mother.VNPC_LitterSize or 1))
    count = math.Clamp(count, 1, maxLitter)
    local kids = VNPC_GetUnbornLitter(mother)
    while #kids < count do
        local baby = VNPC_CreateUnbornBaby(mother)
        if not IsValid(baby) then break end
        table.insert(kids, baby)
    end
    mother.VNPC_UnbornChildren = kids
    mother.VNPC_UnbornChild = kids[1]
    mother.VNPC_LitterSize = math.max(tonumber(mother.VNPC_LitterSize) or 0, #kids)
    for _, baby in ipairs(kids) do
        if IsValid(baby) then
            VNPC_PutUnbornInBelly(mother, baby)
        end
    end
    VNPC_UpdateWombPreyInBelly(mother)
    return kids
end

function VNPC_EnsureUnbornChild(mother, count)
    local kids = VNPC_EnsureUnbornLitter(mother, count)
    return kids[1]
end

function VNPC_FinalizeBornBaby(mother, child, camp, slot, litterSize)
    if not IsValid(child) then return nil end
    slot = slot or 1
    litterSize = math.max(1, tonumber(litterSize) or 1)
    local origin = IsValid(mother) and mother:GetPos() or child:GetPos()
    local fwd = IsValid(mother) and mother:GetForward() * (26 + (slot - 1) * 4) or Vector(26, 0, 0)
    local spread = (slot - 1) - ((litterSize - 1) * 0.5)
    local side = IsValid(mother) and mother:GetRight() * (spread * 14) or Vector(0, 0, 0)

    child:SetParent(nil)
    child:SetNoDraw(false)
    child:SetSolid(SOLID_BBOX)
    child:SetMoveType(MOVETYPE_STEP)
    child:SetPos(origin + fwd + side + Vector(0, 0, 6))
    if IsValid(mother) then
        child:SetAngles(Angle(0, mother:GetAngles().y, 0))
    end
    child:SetModelScale(0.35, 0)

    child.VNPC_ChildGender = child.VNPC_ChildGender or (math.random() < 0.5 and "female" or "male")
    local babyMdl = VNPC_GetBabyModel(mother, child.VNPC_ChildGender)
    if babyMdl and child.SetModel then
        pcall(child.SetModel, child, babyMdl)
    end
    VNPC_CopyMotherAppearance(mother, child)
    VNPC_HideBabyOwnBelly(child)

    child.VNPC_IsUnbornBaby = nil
    child.VNPC_IsGrowingBaby = true
    child.VNPC_ProtectedChild = true
    child.VNPC_BabyBirthTime = CurTime()
    child.VNPC_BabyGrowDuration = child_grow_time:GetFloat()
    child.VNPC_LitterSlot = slot
    child.VNPC_LitterSize = litterSize
    if IsValid(mother) then
        child.VNPC_MotherRef = mother
        if IsValid(mother.VNPC_WildMate) then
            child.VNPC_FatherRef = mother.VNPC_WildMate
        elseif IsValid(mother.VNPC_LovedPartner) then
            child.VNPC_FatherRef = mother.VNPC_LovedPartner
        elseif IsValid(mother.VNPC_MatingPartner) then
            child.VNPC_FatherRef = mother.VNPC_MatingPartner
        end
    end

    if camp and camp.members then
        if not table.HasValue(camp.members, child) then
            table.insert(camp.members, child)
        end
        child.VNPC_PreyCampID = camp.id
        camp.townDevPoints = (camp.townDevPoints or 0) + 50.0
    end
    if IsValid(mother) and (mother.VNPC_PreyCampBabyMother or mother.VNPC_IsPermanentFortPredator) then
        child.VNPC_BornSister = nil
        child.VNPC_AdoptedByPredator = nil
    end

    if IsValid(mother) and (mother.VNPC_IsWildWanderer or mother.VNPC_WildType) then
        mother.VNPC_WildChild = child
        if IsValid(child.VNPC_FatherRef) then
            child.VNPC_FatherRef.VNPC_WildChild = child
        end
        if VNPC_MakeWildWanderer then
            VNPC_MakeWildWanderer(child)
        end
        if mother.VNPC_WildType == "predator" and (child.VNPC_ChildGender == "female" or string.find(string.lower(child:GetModel() or ""), "female")) then
            child.VNPC_WildType = "predator"
            if VNPC_ForceGiveWildPredatorVore then
                VNPC_ForceGiveWildPredatorVore(child)
            end
        else
            child.VNPC_WildType = child.VNPC_WildType or "prey"
        end
    end

    if child.EmitSound then
        child:EmitSound("npc/citizen/vo/nice.wav", 80, 135)
    end
    return child
end

VNPC_ChildbirthSittingPoseKeyframe = {
    ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(15, 0, 0) },
    ["ValveBiped.Bip01_Spine"] = { pos = Vector(0, 0, 0), ang = Angle(-12, 0, 0) },
    ["ValveBiped.Bip01_Spine1"] = { pos = Vector(0, 0, 0), ang = Angle(-10, 0, 0) },
    ["ValveBiped.Bip01_Spine2"] = { pos = Vector(0, 0, 0), ang = Angle(-8, 0, 0) },
    ["ValveBiped.Bip01_Pelvis"] = { pos = Vector(0, 0, -22), ang = Angle(-15, 0, 0) },
    ["ValveBiped.Bip01_R_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(-75, -45, 0) },
    ["ValveBiped.Bip01_L_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(-75, 45, 0) },
    ["ValveBiped.Bip01_R_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(110, 0, 0) },
    ["ValveBiped.Bip01_L_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(110, 0, 0) },
    ["ValveBiped.Bip01_R_Foot"] = { pos = Vector(0, 0, 0), ang = Angle(-20, 0, 0) },
    ["ValveBiped.Bip01_L_Foot"] = { pos = Vector(0, 0, 0), ang = Angle(-20, 0, 0) },
    ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(35, -25, 15) },
    ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(35, 25, -15) },
    ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-60, 20, -10) },
    ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-60, -20, 10) }
}

function VNPC_ApplyPregnancyBellyBulge(mother, val)
    if not IsValid(mother) or not mother.LookupBone or not mother.ManipulateBoneScale then return end
    local spineBone = mother:LookupBone("ValveBiped.Bip01_Spine") or mother:LookupBone("Spine")
    local pelvisBone = mother:LookupBone("ValveBiped.Bip01_Pelvis") or mother:LookupBone("Pelvis")
    local factor = math.Clamp((val - 10) / 40, 0, 1)
    local litter = math.max(1, tonumber(mother.VNPC_LitterSize) or 1)
    if istable(mother.VNPC_UnbornChildren) then
        local living = 0
        for _, c in ipairs(mother.VNPC_UnbornChildren) do
            if IsValid(c) then living = living + 1 end
        end
        if living > 0 then litter = math.max(litter, living) end
    end
    local litterMult = 1.0 + (litter - 1) * 0.28
    local scaleVec = Vector(1.0 + factor * 0.45 * litterMult, 1.0 + factor * 0.40 * litterMult, 1.0 + factor * 0.35 * litterMult)

    if spineBone then
        mother:ManipulateBoneScale(spineBone, scaleVec)
    end
    if pelvisBone then
        mother:ManipulateBoneScale(pelvisBone, Vector(1.0 + factor * 0.25 * litterMult, 1.0 + factor * 0.25 * litterMult, 1.0 + factor * 0.20 * litterMult))
    end
    VNPC_UpdateWombPreyInBelly(mother)
end

function VNPC_ResetPregnancyBellyBulge(mother)
    if not IsValid(mother) or not mother.LookupBone or not mother.ManipulateBoneScale then return end
    local spineBone = mother:LookupBone("ValveBiped.Bip01_Spine") or mother:LookupBone("Spine")
    local pelvisBone = mother:LookupBone("ValveBiped.Bip01_Pelvis") or mother:LookupBone("Pelvis")
    if spineBone then
        mother:ManipulateBoneScale(spineBone, Vector(1, 1, 1))
    end
    if pelvisBone then
        mother:ManipulateBoneScale(pelvisBone, Vector(1, 1, 1))
    end
end

function VNPC_ApplyChildbirthBonePose(mother, apply)
    if not IsValid(mother) or not mother.LookupBone then return end
    for boneName, data in pairs(VNPC_ChildbirthSittingPoseKeyframe) do
        local boneID = mother:LookupBone(boneName)
        if boneID then
            if apply then
                if data.ang then mother:ManipulateBoneAngles(boneID, data.ang) end
                if data.pos then mother:ManipulateBonePosition(boneID, data.pos) end
            else
                mother:ManipulateBoneAngles(boneID, angle_zero)
                mother:ManipulateBonePosition(boneID, vector_origin)
            end
        end
    end
end

function VNPC_StartChildbirthAnimation(mother, child, camp)
    if not IsValid(mother) then return end

    local kids = VNPC_GetUnbornLitter(mother)
    if IsValid(child) and not table.HasValue(kids, child) then
        table.insert(kids, 1, child)
    end
    local litterSize = math.max(#kids, tonumber(mother.VNPC_LitterSize) or 1, 1)
    if #kids < litterSize then
        kids = VNPC_EnsureUnbornLitter(mother, litterSize)
        litterSize = math.max(#kids, 1)
    end
    if #kids == 0 then
        kids = VNPC_EnsureUnbornLitter(mother, 1)
        litterSize = math.max(#kids, 1)
    end

    mother.VNPC_IsPregnant = nil
    mother.VNPC_UnbornChild = nil
    mother.VNPC_UnbornChildren = nil
    mother.VNPC_BabyGrowthValue = nil
    local sitTime = 4.5 + (litterSize - 1) * 1.6

    -- 1. Apply Sitting Childbirth Pose with legs separated
    if childbirth_enabled:GetBool() then
        if mother.SetSchedule then pcall(mother.SetSchedule, mother, SCHED_NPC_FREEZE) end
        mother.VNPC_InChildbirthPose = CurTime() + sitTime
        VNPC_ApplyChildbirthBonePose(mother, true)
        if mother.EmitSound then
            local snd = math.random() < 0.5 and "npc/alyx/sigh01.wav" or "npc/citizen/vo/citizen_we_are_safe.wav"
            mother:EmitSound(snd, 80, math.random(105, 115))
        end
    end

    -- 2. Deliver the whole litter, staggered between the separated knees
    for i, baby in ipairs(kids) do
        local delay = (i - 1) * 0.85
        timer.Simple(delay, function()
            if not IsValid(mother) then return end
            local born = baby
            if not IsValid(born) then
                born = VNPC_SpawnMotherChild(mother, math.random() < 0.5 and "female" or "male")
                if IsValid(born) then
                    born:SetPos(mother:GetPos() + mother:GetForward() * 24 + Vector(0, 0, 5))
                    born:SetAngles(Angle(0, mother:GetAngles().y, 0))
                end
            end
            if IsValid(born) then
                VNPC_ReleaseWombPrey(mother, born)
                VNPC_FinalizeBornBaby(mother, born, camp, i, litterSize)
            end
        end)
    end
    print(string.format("[V-NPCs] Childbirth: %s gave birth to a litter of %d!", tostring(mother), litterSize))

    -- 3. Restore mother after the litter delivery sit
    timer.Simple(sitTime, function()
        if IsValid(mother) then
            VNPC_ApplyChildbirthBonePose(mother, false)
            VNPC_ResetPregnancyBellyBulge(mother)
            mother.VNPC_LitterSize = nil
            if mother.SetSchedule then pcall(mother.SetSchedule, mother, SCHED_IDLE_STAND) end
        end
    end)
end

-- 1-Minute Baby Citizen Growth Loop
hook.Add("Think", "VNPC_BabyCitizenGrowth_Loop", function()
    local now = CurTime()

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) or ent:Health() <= 0 then continue end

        -- 1. Unborn Baby inside Womb: keep them hidden in the mother's belly
        if ent.VNPC_IsUnbornBaby and IsValid(ent.VNPC_MotherRef) then
            local mother = ent.VNPC_MotherRef
            local belly = mother.VNPC_Belly or mother.Belly or mother.belly
            if IsValid(belly) then
                if ent:GetParent() ~= belly or not ent.VNPC_IsWombPrey then
                    VNPC_PutUnbornInBelly(mother, ent)
                end
            elseif ent:GetParent() ~= mother then
                ent:SetParent(mother)
                ent:SetPos(mother:GetPos() + Vector(0, 0, 32))
            end
            continue
        end

        -- 2. Born Baby Citizen: female babies eat small prey (headcrabs) & drink water to grow; males use natural timer
        if ent.VNPC_IsGrowingBaby then
            local isFemale = (ent.VNPC_ChildGender == "female" or string.find(string.lower(ent:GetModel() or ""), "female"))
            if isFemale then
                local progress = math.Clamp(ent.VNPC_GrowthProgress or 0.0, 0.0, 100.0)
                local scale = 0.35 + (progress / 100.0) * 0.65
                ent:SetModelScale(scale, 0)

                if progress >= 100.0 then
                    ent:SetModelScale(1.0, 0)
                    ent.VNPC_IsGrowingBaby = nil
                    ent.VNPC_ProtectedChild = nil
                    ent.VNPC_GrowthProgress = nil

                    if (ent.VNPC_AdoptedByPredator or ent.VNPC_BornSister) and VNPC_TransformToPredator then
                        VNPC_TransformToPredator(ent, ent.VNPC_AdoptedByPredator or ent.VNPC_MotherRef)
                        return
                    end
                    local mom = ent.VNPC_MotherRef
                    if IsValid(mom) and (mom.Predator or mom.VNPC_FemaleModelVore or mom.IsDrGNextbot or mom.EatEntity) then
                        if VNPC_GiveFemaleModelVore then
                            VNPC_GiveFemaleModelVore(ent)
                        end
                        if IsValid(ent.VNPC_BabyOwnBelly) then
                            ent.VNPC_BabyOwnBelly:SetNoDraw(false)
                        end
                    end

                    if ent.EmitSound then
                        ent:EmitSound("npc/citizen/vo/readytohelp.wav", 80, 105)
                    end
                    print("[V-NPCs] Female Baby Growth Complete: Baby " .. tostring(ent) .. " reached 100% growth by eating small prey & drinking water!")
                    hook.Run("VNPC_OnBabyGrowthComplete", ent)
                else
                    -- Add a growth tick every 30 seconds
                    if (now - (ent.VNPC_LastGrowthTickTime or ent.VNPC_BabyBirthTime or now)) >= 30.0 then
                        ent.VNPC_LastGrowthTickTime = now
                        ent.VNPC_GrowthProgress = math.Clamp((ent.VNPC_GrowthProgress or 0.0) + 15.0, 0, 100)
                        print("[V-NPCs] 30-Second Growth Tick: Baby female " .. tostring(ent) .. " gained +15 Growth Progress (" .. ent.VNPC_GrowthProgress .. "/100)!")
                    end

                    -- Hunt small prey (Headcrabs, grubs, small NPCs <= 60 HP) to swallow & digest for growth
                    if (ent.VNPC_NextBabyHuntTime or 0) <= now then
                        ent.VNPC_NextBabyHuntTime = now + 3.0
                        local bestSmall = nil
                        local bestDistSqr = 600 * 600
                        for _, prey in ipairs(ents.FindInSphere(ent:GetPos(), 600)) do
                            if IsValid(prey) and prey ~= ent and prey:Health() > 0 and not prey.Vored and not prey.VNPC_Vored then
                                local species = VNPC_GetPreySpecies and VNPC_GetPreySpecies(prey) or ""
                                if species == "headcrab" or (prey:GetMaxHealth() or 100) <= 60 then
                                    local dSqr = prey:GetPos():DistToSqr(ent:GetPos())
                                    if dSqr <= bestDistSqr then
                                        bestSmall = prey
                                        bestDistSqr = dSqr
                                    end
                                end
                            end
                        end
                        if IsValid(bestSmall) then
                            if bestDistSqr <= (90 * 90) then
                                if ent.EmitSound then ent:EmitSound("gulps/g" .. math.random(1, 10) .. ".wav", 80, 105) end
                                print("[V-NPCs] Baby Female Swallowed Small Prey: Baby " .. tostring(ent) .. " swallowed small prey " .. tostring(bestSmall) .. "! (Will grow once digestion is finished)")
                                if not ent.EatEntity and VNPC_AttachFemaleModelVore then
                                    VNPC_AttachFemaleModelVore(ent)
                                end
                                if ent.EatEntity then
                                    ent:EatEntity(bestSmall)
                                elseif ent.VNPC_Belly and ent.VNPC_Belly.AddPrey then
                                    ent.VNPC_Belly:AddPrey(bestSmall)
                                else
                                    bestSmall:Remove()
                                    ent.VNPC_GrowthProgress = math.Clamp((ent.VNPC_GrowthProgress or 0.0) + 35.0, 0, 100)
                                end
                            else
                                if ent.SetLastPosition then pcall(ent.SetLastPosition, ent, bestSmall:GetPos()) end
                                if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_FORCED_GO_RUN) end
                            end
                        end
                    end
                end
            else
                -- Male babies grow on the natural timer
                local duration = ent.VNPC_BabyGrowDuration or 60.0
                local tNorm = math.Clamp((now - (ent.VNPC_BabyBirthTime or now)) / duration, 0, 1)
                local scale = 0.35 + (tNorm * 0.65)
                ent:SetModelScale(scale, 0)

                if tNorm >= 1.00 then
                    ent:SetModelScale(1.0, 0)
                    ent.VNPC_IsGrowingBaby = nil
                    ent.VNPC_ProtectedChild = nil

                    if (ent.VNPC_AdoptedByPredator or ent.VNPC_BornSister) and VNPC_TransformToPredator then
                        VNPC_TransformToPredator(ent, ent.VNPC_AdoptedByPredator or ent.VNPC_MotherRef)
                        return
                    end

                    if ent.EmitSound then
                        ent:EmitSound("npc/citizen/vo/readytohelp.wav", 80, 105)
                    end
                end
            end
        end
    end
end)

concommand.Add("vnpcs_childbirth_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Pregnant Citizen Womb Growth & Childbirth Status")
    print("Enabled: " .. tostring(childbirth_enabled:GetBool()))
    print("Womb Growth Rate: " .. tostring(growth_rate:GetFloat()) .. " / sec")
    print("Child Grow Time: " .. tostring(child_grow_time:GetFloat()) .. "s")
    print("Mate Love Max: " .. tostring(mate_love_max:GetFloat()) .. " | Max Litter: " .. tostring(mate_love_max_litter:GetInt()))
    print("-----------------------------------------")
    local pregCount, growCount, wombBabies, lovePairs = 0, 0, 0, 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) then
            if IsValid(ent.VNPC_LovedPartner) and ent:EntIndex() < ent.VNPC_LovedPartner:EntIndex() then
                lovePairs = lovePairs + 1
            end
            if ent.VNPC_IsPregnant and ent.VNPC_BabyGrowthValue then
                pregCount = pregCount + 1
                local kids = VNPC_GetUnbornLitter(ent)
                local litter = math.max(#kids, tonumber(ent.VNPC_LitterSize) or 1)
                wombBabies = wombBabies + litter
                local belly = ent.VNPC_Belly or ent.Belly
                local inBelly = 0
                if IsValid(belly) and istable(belly.Prey) then
                    for _, info in ipairs(belly.Prey) do
                        if info and (info.WombPrey or (IsValid(info.Entity) and (info.Entity.VNPC_IsWombPrey or info.Entity.VNPC_IsUnbornBaby))) then
                            inBelly = inBelly + 1
                        end
                    end
                end
                print(string.format(" -> Pregnant Citizen [%d] | Growth Value: %.1f / 50.0 | Love: %.0f | Litter: %d | In Belly: %d | Mating lasts %.1fs",
                    ent:EntIndex(), ent.VNPC_BabyGrowthValue, VNPC_GetMateLove(ent, ent.VNPC_LovedPartner or ent.VNPC_WildMate), litter, inBelly, VNPC_GetMatingDuration(VNPC_GetMateLove(ent, ent.VNPC_LovedPartner or ent.VNPC_WildMate))))
            end
            if ent.VNPC_IsGrowingBaby then
                growCount = growCount + 1
                local pct = math.Clamp((CurTime() - (ent.VNPC_BabyBirthTime or 0)) / (ent.VNPC_BabyGrowDuration or 60) * 100, 0, 100)
                local litterStr = (ent.VNPC_LitterSize and ent.VNPC_LitterSize > 1) and string.format(" | Litter %d/%d", ent.VNPC_LitterSlot or 1, ent.VNPC_LitterSize) or ""
                print(string.format(" -> Growing Baby [%d] %s | Scale: %.2f (%.1f%% grown)%s", ent:EntIndex(), ent:GetClass(), ent:GetModelScale() or 0.35, pct, litterStr))
            end
        end
    end
    print("Total pregnant mothers: " .. pregCount .. " | Womb babies: " .. wombBabies .. " | Love pairs: " .. lovePairs .. " | Active growing babies: " .. growCount)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Childbirth status printed to console. Pregnant: " .. pregCount .. " | Womb babies: " .. wombBabies .. " | Babies: " .. growCount)
    end
end)

concommand.Add("vnpcs_test_childbirth", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot()) then
        ply:ChatPrint("[V-NPCs] Please aim at a female citizen to test childbirth!")
        return
    end
    local camp = VNPC_GetPreyCamp and VNPC_GetPreyCamp(target) or nil
    local litter = math.max(1, tonumber(target.VNPC_LitterSize) or #VNPC_GetUnbornLitter(target), VNPC_GetLitterSize(VNPC_GetMateLove(target, target.VNPC_LovedPartner or target.VNPC_WildMate)))
    target.VNPC_LitterSize = litter
    VNPC_EnsureUnbornLitter(target, litter)
    VNPC_StartChildbirthAnimation(target, target.VNPC_UnbornChild, camp)
    ply:ChatPrint("[V-NPCs] Triggered sitting childbirth bone pose animation and litter birth (" .. litter .. ") on " .. tostring(target) .. "!")
end)

concommand.Add("vnpcs_test_baby_grow", function(ply)
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent.VNPC_IsGrowingBaby then
            ent.VNPC_GrowthProgress = (ent.VNPC_GrowthProgress or 0) + 35.0
            count = count + 1
        end
    end
    local msg = "[V-NPCs] Added +35 Growth Progress to all " .. count .. " growing female babies!"
    print(msg)
    if IsValid(ply) then ply:ChatPrint(msg) end
end)

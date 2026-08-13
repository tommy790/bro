--[[
    Give Female Model NPCs Vore (Server Implementation)
    Includes robust belly attachment to spine or fallback bones,
    proper positioning, and continuous belly think/visual updates.
]]

if not SERVER then return end

local function GetBellyAnchorBone(ent)
    local names = {
        ent.SpineBone or "000000000",
        "ValveBiped.Bip01_Spine2",
        "Spine2",
        "ValveBiped.Bip01_Spine1",
        "Spine1",
        "ValveBiped.Bip01_Spine4",
        "Spine4",
        "ValveBiped.Bip01_Spine",
        "Spine",
        "ValveBiped.Bip01_Pelvis",
        "Pelvis",
        "ValveBiped.spine2",
        "Bip01_Spine2",
        "Bip01_Spine1",
        "Bip01_Spine",
        "Bip01_Pelvis",
        "bip_spine_2",
        "bip_spine_1",
        "bip_spine_0",
        "bip_pelvis",
        "spine2",
        "spine1",
        "spine",
        "pelvis",
        "root",
        "Root",
        "ValveBiped.Bip01"
    }
    for _, name in ipairs(names) do
        local bone = ent:LookupBone(name)
        if bone and bone >= 0 then
            return bone
        end
    end
    return 0 -- fallback to bone 0 (root/pelvis bone)
end

function VNPC_GiveFemaleModelVore(ent)
    if not IsValid(ent) then return false end
    if IsValid(ent.VNPC_Belly or ent.Belly) then return true end
    if not ent.VNPC_ForceFemaleVore and not VNPC_IsFemaleModelNPC(ent) then return false end
    
    ent.VNPC_FemaleModelVore = true
    ent.Predator = true
    ent.Belly_Angles = ent.Belly_Angles or Angle(0, 90, 90)
    ent.Belly_Offset = VNPC_GetFixedFemaleBellyOffset(ent)
    
    ent.VoreSettings = ent.VoreSettings or {
        EatsPlayers = true,
        OnlyEatsEnemies = false,
        BurpsEnabled = true,
        DigestionStrength = 3,
        AbsorptionSpeed = 2,
        StruggleMultiplier = 1.5,
        HasWeightGain = true,
        FatFoldsMaxSize = 0.3
    }
    ent.BellyProperties = ent.BellyProperties or {
        BellyColor = Color(195,145,122), 
        DigestionStrength = 2,
        AbsorptionPower = 1.5,
        StruggleMultiplier = 1.25,
        MaxBaseSize = 0.5,
        BaseSize = 0,
        FatFoldsMaxSize = 1
    }
    ent.VoreSounds = ent.VoreSounds or {
        ["big_burp"] = {
            "burps/burp1.wav", "burps/burp2.wav", "burps/burp3.wav",
            "burps/burp4.wav", "burps/burp6.wav", "burps/burp12.wav"
        },
        ["small_burp"] = {
            "burps/burp7.wav", "burps/burp8.wav", "burps/burp9.wav",
            "burps/burp10.wav", "burps/burp11.wav", "burps/burp14.wav"
        },
        ["swallow"] = {
            "gulps/g1.wav", "gulps/g2.wav", "gulps/g3.wav",
            "gulps/g4.wav", "gulps/g5.wav", "gulps/g6.wav"
        }
    }
    ent.VoreSoundPitch = ent.VoreSoundPitch or 1
    ent.TriggerBone = ent.TriggerBone or "ValveBiped.Bip01_Pelvis"
    ent.TriggerThreshold = ent.TriggerThreshold or Vector(1.0, 1.0, 1.0)
    ent.OffsetFullFactor = ent.OffsetFullFactor or 1.5
    ent.BoneBlendState = ent.BoneBlendState or {}
    ent.LastFacialPhase = ent.LastFacialPhase or 0
    ent.FacialPhaseStartTime = ent.FacialPhaseStartTime or CurTime()
    
    -- Create and attach belly entity with spine or fallback bone
    if not IsValid(ent.VNPC_Belly) then
        local belly = ents.Create("ent_vore_belly")
        if IsValid(belly) then
            belly:SetPos(ent:GetPos())
            belly:SetParent(ent)
            belly:SetProperties(ent.BellyProperties, ent)
            belly:SetNPC(ent)
            
            belly:Spawn()
            belly:Activate()
            
            local spineBone = GetBellyAnchorBone(ent)
            ent.VNPC_BellyBone = spineBone
            belly:FollowBone(ent, spineBone)
            if not belly:GetParent() or belly:GetParent() ~= ent then
                belly:SetParent(ent)
            end
            belly:SetLocalAngles(ent.Belly_Angles or Angle(0, 90, 90))
            belly:SetLocalPos(ent.Belly_Offset or Vector(0, 3.5, 0))
            if belly.SetBellySize then
                belly:SetBellySize()
            end
            
            ent.VNPC_Belly = belly
            ent.Belly = belly
            ent:SetNWEntity("Belly", belly)
        end
    end

    function ent:EatGroup(targets)
        if not istable(targets) then return self:EatEntity(targets) end
        local count = 0
        for _, e in ipairs(targets) do
            if IsValid(e) and not e.Vored and not e.VNPC_Vored then
                if self:EatEntity(e) then
                    count = count + 1
                end
            end
        end
        return count > 0, count
    end

    -- Add EatEntity method
    function ent:EatEntity(target)
        if not IsValid(target) or (self.Swallowing and not self._InClumpVore) or target.Vored or self.Vored then return false end
        if target.VNPC_DigestedBone or target.VNPC_BoneOwner or target.VNPC_NoVore then return false end
        if target.VNPC_IsPreyCampWall or target.VNPC_IsPreyCampHutPiece or target.VNPC_IsCourtyardDefense then
            if self.VNPC_PreyCampID and target.VNPC_PreyCampID == self.VNPC_PreyCampID then return false end
        end
        if VNPC_IsFamilyOrMate and VNPC_IsFamilyOrMate(self, target) then return false end
        if target.VNPC_IsSleeping and target.VNPC_CampID and VNPC_GetPredatorCamp then
            local c = VNPC_GetPredatorCamp(target)
            if c and #(c.barricades or {}) > 0 and self.VNPC_CampID ~= target.VNPC_CampID then return false end
        end
        if not (self.VNPC_IsWildWanderer and self.VNPC_WildType == "predator") and VNPC_IsProtectedChildPrey and VNPC_IsProtectedChildPrey(target) then return false end
        if VNPC_IsPreyEmissary and VNPC_IsPreyEmissary(target) then return false end
        if target.VNPC_PreyCampID and self.VNPC_PreyCampID and target.VNPC_PreyCampID == self.VNPC_PreyCampID then return false end
        if VNPC_CanSwallowOwnSpecies and not VNPC_CanSwallowOwnSpecies(self, target) then return false end
        if not target:GetModel() or target:GetClass():find("func") then return false end
        
        self.Swallowing = true
        local belly = self.VNPC_Belly or self.Belly
        if not IsValid(belly) then return false end
        
        if belly:AddPrey(target) then
            local snd_list = self.VoreSounds and self.VoreSounds["swallow"]
            if snd_list and #snd_list > 0 then
                local snd = snd_list[math.random(1, #snd_list)]
                self:EmitSound(snd, 100, 100)
            end
            if VNPC_PlayNativeVoreGesture then
                VNPC_PlayNativeVoreGesture(self, "swallow")
            end
            if VNPC_AddPredatorXP then
                local bonus = math.floor((target:GetMaxHealth() or 100) * 0.5)
                if VNPC_IsDangerousPrey and VNPC_IsDangerousPrey(target) then
                    bonus = bonus + 100
                end
                VNPC_AddPredatorXP(self, 50 + bonus, "Swallowed prey alive")
            end
            if not self._InClumpVore and VNPC_GetClumpedPreyGroup then
                self._InClumpVore = true
                local group = VNPC_GetClumpedPreyGroup(self, target)
                if #group > 1 then
                    for i = 2, #group do
                        local extraPrey = group[i]
                        if IsValid(extraPrey) and not extraPrey.Vored and not extraPrey.VNPC_Vored then
                            pcall(self.EatEntity, self, extraPrey)
                        end
                    end
                end
                self._InClumpVore = nil
            end

            local animList = nil
            if VNPC_GetAnimatedBoneList then
                animList = VNPC_GetAnimatedBoneList(self)
            end
            local tSwallow = (animList and animList[1] and animList[1].length) or 1.0
            local tGulp = (animList and animList[4] and animList[4].length) or 1.0
            local calm_swallow_cv = GetConVar("vnpcs_calm_swallow_animation")
            if calm_swallow_cv and calm_swallow_cv:GetBool() and not IsValid(self:GetEnemy()) then
                tSwallow = 5.0
                tGulp = 1.0
            end
            local tFull = tSwallow + tGulp

            timer.Simple(tSwallow, function()
                if IsValid(self) and IsValid(belly) and belly.DigestionPhase == 1 then
                    self:SetFacialExpression(4)
                end
            end)

            timer.Simple(tFull, function()
                if IsValid(self) then
                    if IsValid(belly) and (belly.DigestionPhase ~= 0 or (belly.Prey and #belly.Prey > 0)) then
                        self:SetFacialExpression(2)
                    else
                        self:SetFacialExpression(0)
                    end
                end
            end)

            if not GetConVar("vnpcs_patrol_full"):GetBool() then
                if self.ClearPatrols then pcall(self.ClearPatrols, self) end
                if self.ClearSchedule then pcall(self.ClearSchedule, self) end
                if self.SetSchedule then pcall(self.SetSchedule, self, SCHED_IDLE_STAND) end
                if self.SetEnemy then pcall(self.SetEnemy, self, nil) end
                if self.SetTarget then pcall(self.SetTarget, self, nil) end
            end

            self.Swallowing = false
            return true
        end
        self.Swallowing = false
        return false
    end

    function ent:Burp(big)
        if not self.VoreSounds then return end
        local snd_list = big and self.VoreSounds["big_burp"] or self.VoreSounds["small_burp"]
        if snd_list and #snd_list > 0 then
            local snd = snd_list[math.random(1, #snd_list)]
            self:EmitSound(snd, 80, (self.VoreSoundPitch or 1) * 100, 1.4)
        end
        if VNPC_PlayNativeVoreGesture then
            VNPC_PlayNativeVoreGesture(self, "burp")
        end
    end

    function ent:PlayVoreGesture(gesture_type)
        if VNPC_PlayNativeVoreGesture then
            return VNPC_PlayNativeVoreGesture(self, gesture_type)
        end
        return false
    end

    function ent:PlayBonePoseAnimation(anim_type)
        if VNPC_PlayBonePoseAnimation then
            return VNPC_PlayBonePoseAnimation(self, anim_type)
        end
        return false
    end

    function ent:AnimatedBoneOffsets()
        if VNPC_AnimatedBoneOffsets then
            VNPC_AnimatedBoneOffsets(self)
        end
    end

    -- Belly methods matching VNPCs
    function ent:GetBellyAnchor()
        return GetBellyAnchorBone(self)
    end

    function ent:SetupBelly(spineBone)
        local belly = self.VNPC_Belly or self.Belly
        if not IsValid(belly) then
            belly = ents.Create("ent_vore_belly")
            self.VNPC_Belly = belly
            self.Belly = belly
            self:SetNWEntity("Belly", belly)
        end
        if IsValid(belly) then
            belly:SetPos(self:GetPos())
            belly:SetParent(self)
            belly:SetProperties(self.BellyProperties, self)
            belly:SetNPC(self)
            belly:Spawn()
            belly:Activate()
            belly:FollowBone(self, spineBone or 0)
            if not belly:GetParent() or belly:GetParent() ~= self then
                belly:SetParent(self)
            end
            belly:SetLocalAngles(self.Belly_Angles or Angle(0, 90, 90))
            local offset = self.Belly_Offset
            if VNPC_GetFixedFemaleBellyOffset and (not offset or offset == Vector(0, 1, 0) or offset == Vector(0, 0, 0)) then
                offset = VNPC_GetFixedFemaleBellyOffset(self)
            end
            belly:SetLocalPos(offset or Vector(0, 3.5, 0))
            if belly.SetBellySize then belly:SetBellySize() end
            if self.OnBellyCreated then self:OnBellyCreated(belly) end
        end
        return belly
    end

    function ent:SetBellyPosition()
        local belly = self.VNPC_Belly or self.Belly
        if not IsValid(belly) then return end
        belly:SetLocalAngles(self.Belly_Angles or Angle(0, 90, 90))
        local offset = self.Belly_Offset
        if VNPC_GetFixedFemaleBellyOffset and (not offset or offset == Vector(0, 1, 0) or offset == Vector(0, 0, 0)) then
            offset = VNPC_GetFixedFemaleBellyOffset(self)
        end
        belly:SetLocalPos(offset or Vector(0, 3.5, 0))
    end

    function ent:GetBelly()
        return self.VNPC_Belly or self.Belly or self:GetNWEntity("Belly")
    end

    -- Weight gain methods matching VNPCs
    ent.BoneScale = ent.BoneScale or 1
    ent.VoreSettings = ent.VoreSettings or {}
    ent.VoreSettings.HasWeightGain = true
    ent.VoreSettings.WeightGainBones = ent.VoreSettings.WeightGainBones or VNPC_FEMALE_WEIGHT_GAIN_BONES
    ent.VoreSettings.WeightGainSettings = ent.VoreSettings.WeightGainSettings or VNPC_FEMALE_WEIGHT_GAIN_SETTINGS

    function ent:GainWeight(amount)
        if not amount or amount == 0 then return end
        self.BoneScale = math.max((self.BoneScale or 1) + amount, 1)
        self:SetNWFloat("Bonescale", self.BoneScale)
        if VNPC_DoVisualBonescale then VNPC_DoVisualBonescale(self, self.BoneScale) end
        if self.OnWeightGain then self:OnWeightGain(self.BoneScale) end
    end

    function ent:LoseWeight(amount)
        if not amount or amount == 0 then return end
        self:GainWeight(-amount)
    end

    function ent:GetWeight()
        return self.BoneScale or 1
    end

    function ent:SetWeight(num)
        self.BoneScale = math.max(num or 1, 1)
        self:SetNWFloat("Bonescale", self.BoneScale)
        if VNPC_DoVisualBonescale then VNPC_DoVisualBonescale(self, self.BoneScale) end
        if self.OnWeightGain then self:OnWeightGain(self.BoneScale) end
    end

    function ent:OnWeightGain(scale) end

    -- Facial expression methods matching VNPCs
    function ent:SetFacialExpression(phase)
        self.CurrentFacialPhase = phase
        self:SetNWInt("FacialPhase", phase)
    end

    function ent:GetCurrentFacialPhase()
        return self:GetNWInt("FacialPhase", self.CurrentFacialPhase or 0)
    end

    function ent:UpdateFacialExpressions() end

    -- Predation / VNPC model classification methods
    function ent:IsFemaleModel(mdl)
        return true
    end

    function ent:IsFemaleNPC()
        return true
    end

    function ent:IsCitizenVore()
        local mdl = string.lower(self:GetModel() or "")
        local cls = string.lower(self:GetClass() or "")
        return (mdl:find("group01") or mdl:find("group02") or mdl:find("group03") or cls:find("citizen") or cls:find("rebel") or cls:find("refugee") or cls:find("medic")) ~= nil
    end

    function ent:IsUnnoticedVore()
        if self.UnnoticedVore ~= nil then return self.UnnoticedVore end
        if self.VoreSettings and self.VoreSettings.UnnoticedVore ~= nil then return self.VoreSettings.UnnoticedVore end
        local mdl = string.lower(self:GetModel() or "")
        return (mdl:find("group01") or mdl:find("group02") or mdl:find("group03") or mdl:find("female") or mdl:find("alyx") or mdl:find("mossman")) ~= nil
    end

    function ent:ApplyUnnoticedVore(prey)
        if not IsValid(prey) then return end
        prey.UnnoticedVored = true
        if prey.SetSquad then pcall(prey.SetSquad, prey, "") end
        if prey.SetEnemy then pcall(prey.SetEnemy, prey, nil) end
        if prey.SetTarget then pcall(prey.SetTarget, prey, nil) end
        for _, npc in ipairs(ents.FindByClass("npc_*")) do
            if IsValid(npc) and npc ~= self and npc ~= prey then
                if npc:GetEnemy() == self or npc:GetEnemy() == prey then
                    npc:SetEnemy(nil)
                end
                if npc.SetEntityRelationship then
                    npc:SetEntityRelationship(self, D_NU, 99)
                end
            end
        end
    end

    function ent:EatCondition(prey)
        if not IsValid(prey) or prey.VNPC_DigestedBone or prey.VNPC_BoneOwner or prey.VNPC_NoVore then return false end
        if prey.VNPC_IsPreyCampWall or prey.VNPC_IsPreyCampHutPiece or prey.VNPC_IsCourtyardDefense then
            if self.VNPC_PreyCampID and prey.VNPC_PreyCampID == self.VNPC_PreyCampID then return false end
        end
        if VNPC_CanSwallowOwnSpecies and not VNPC_CanSwallowOwnSpecies(self, prey) then return false end
        return true
    end

    function ent:CanEat(prey)
        if not IsValid(prey) or prey.VNPC_DigestedBone or prey.VNPC_BoneOwner or prey.VNPC_NoVore then return false end
        if prey.VNPC_IsPreyCampWall or prey.VNPC_IsPreyCampHutPiece or prey.VNPC_IsCourtyardDefense then
            if self.VNPC_PreyCampID and prey.VNPC_PreyCampID == self.VNPC_PreyCampID then return false end
        end
        if VNPC_CanSwallowOwnSpecies and not VNPC_CanSwallowOwnSpecies(self, prey) then return false end
        return true
    end

    -- Event hooks matching VNPCs
    function ent:PostEntityEaten(ent) end
    function ent:OnBellyCreated(belly) end

    function ent:OnDigestionPhaseChanged(new, old)
        if new == 0 then
            self:SetFacialExpression(0)
        elseif new == 2 and old == 1 then
            self:SetFacialExpression(2)
        elseif new == 1 and old == 0 then
            self:SetFacialExpression(1)
        end
    end

    function ent:OnPreyAbsorbing(power, old_value, new_value)
        self:GainWeight((power or 1) * 0.006)
    end

    function ent:OnPreyAbsorbed()
        if IsValid(self.VNPC_Belly) and self.VNPC_Belly.PlayFinalAbsorbSound then
            self.VNPC_Belly:PlayFinalAbsorbSound()
        end
        if VNPC_ScheduleDigestedBoneSpit then
            VNPC_ScheduleDigestedBoneSpit(self, self.VNPC_Belly)
        end
    end
    function ent:OnPreyKilled()
        if IsValid(self.VNPC_Belly) and self.VNPC_Belly.PlayFinalDigestSound then
            self.VNPC_Belly:PlayFinalDigestSound()
        end
        if VNPC_ScheduleDigestedBoneSpit then
            VNPC_ScheduleDigestedBoneSpit(self, self.VNPC_Belly)
        end
    end

    function ent:Regurgitate(prey)
        local belly = self.VNPC_Belly or self.Belly
        if IsValid(belly) and belly.Regurgitate then
            return pcall(belly.Regurgitate, belly, prey)
        end
        if IsValid(prey) then
            prey.Vored = false
            prey.VNPC_Vored = false
            prey:SetNoDraw(false)
            prey:SetSolid(SOLID_BBOX)
            prey:SetMoveType(MOVETYPE_WALK)
            prey:SetParent(nil)
            prey:SetPos(self:GetPos() + self:GetForward() * 50 + Vector(0, 0, 10))
            if prey:IsPlayer() and prey.UnLock then
                pcall(prey.UnLock, prey)
            end
            return true
        end
        return false
    end

    function ent:ReleaseAllPrey()
        local belly = self.VNPC_Belly or self.Belly
        if IsValid(belly) and belly.Prey and istable(belly.Prey) then
            for _, p_tbl in ipairs(belly.Prey) do
                if p_tbl and IsValid(p_tbl.Entity) and not (p_tbl.WombPrey or p_tbl.NoDigest or p_tbl.Entity.VNPC_IsWombPrey or p_tbl.Entity.VNPC_IsUnbornBaby) then
                    self:Regurgitate(p_tbl.Entity)
                end
            end
        end
    end

    function ent:PlayRandomGurgle()
        local belly = self.VNPC_Belly or self.Belly
        if IsValid(belly) and belly.PlayRandomGurgle then
            pcall(belly.PlayRandomGurgle, belly)
        end
    end

    function ent:PlayRandomStruggle()
        local belly = self.VNPC_Belly or self.Belly
        if IsValid(belly) and belly.PlayRandomStruggle then
            pcall(belly.PlayRandomStruggle, belly)
        end
    end

    function ent:CanEatCorpse(ragdoll)
        local allow_corpses = GetConVar("vnpcs_female_model_vore_eat_corpses")
        if allow_corpses and not allow_corpses:GetBool() then return false end
        if not IsValid(ragdoll) then return false end
        if ragdoll:GetClass() ~= "prop_ragdoll" and not ragdoll.VNPC_IsCorpse then return false end
        if ragdoll.Vored or ragdoll.VNPC_Vored then return false end
        return true
    end

    -- Speed & AI methods matching VNPCs
    function ent:GetAdjustedSpeeds()
        return 200, 300
    end

    function ent:UpdateRelations() end
    function ent:ShouldIgnore(target)
        return false
    end
    function ent:ClearPatrols()
        if self.ClearSchedule then pcall(self.ClearSchedule, self) end
    end
    function ent:AddPatrolPos(pos)
        if self.SetLastPosition then pcall(self.SetLastPosition, self, pos) end
    end

    return true
end

-- Hook OnEntityCreated to automatically give female model NPCs vore
hook.Add("OnEntityCreated", "VNPC_AutoGiveFemaleModelVore", function(ent)
    timer.Simple(0.1, function()
        if not IsValid(ent) then return end
        local enabled = GetConVar("vnpcs_female_model_vore")
        if enabled and not enabled:GetBool() then return end
        if VNPC_IsFemaleModelNPC(ent) then
            VNPC_GiveFemaleModelVore(ent)
        end
    end)
end)

-- Continuous Belly Think and Attachment Loop for Female Model Vore NPCs
hook.Add("Think", "VNPC_FemaleModelVore_Think", function()
    local enabled = GetConVar("vnpcs_female_model_vore")
    if enabled and not enabled:GetBool() then return end
    
    local now = CurTime()
    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if not IsValid(npc) then continue end
        if not IsValid(npc.VNPC_Belly or npc.Belly) and (npc.VNPC_NextVoreCheckTime or 0) <= now then
            npc.VNPC_NextVoreCheckTime = now + 2.0
            if npc.VNPC_ForceFemaleVore or VNPC_IsFemaleModelNPC(npc) then
                VNPC_GiveFemaleModelVore(npc)
            end
        end
        if not npc.VNPC_FemaleModelVore then continue end
        
        -- Maintain belly attachment, positioning, and think
        local belly = npc.VNPC_Belly or npc.Belly
        if IsValid(belly) then
            if (npc.VNPC_NextBellyThink or 0) <= now then
                npc.VNPC_NextBellyThink = now + 0.5
                if belly.NPCThink then
                    pcall(belly.NPCThink, belly)
                end
            end
            if not belly:GetParent() or belly:GetParent() ~= npc then
                local spineBone = GetBellyAnchorBone(npc)
                belly:FollowBone(npc, spineBone)
                if not belly:GetParent() or belly:GetParent() ~= npc then
                    belly:SetParent(npc)
                end
            end
            belly:SetLocalAngles(npc.Belly_Angles or Angle(0, 90, 90))
            belly:SetLocalPos(npc.Belly_Offset or VNPC_GetFixedFemaleBellyOffset(npc))

            local hasSwallowed = VNPC_BellyHasSwallowedPrey and VNPC_BellyHasSwallowedPrey(belly) or ((not VNPC_BellyHasSwallowedPrey) and (belly.DigestionPhase ~= 0 or (belly.Prey and #belly.Prey > 0)))
            if (not hasSwallowed) and not npc.Swallowing then
                local current_phase = npc:GetCurrentFacialPhase()
                if current_phase == 1 or current_phase == 2 or current_phase == 4 then
                    npc:SetFacialExpression(0)
                end
            end

            if not GetConVar("vnpcs_patrol_full"):GetBool() and (VNPC_BellyHasSwallowedPrey and VNPC_BellyHasSwallowedPrey(belly) or ((not VNPC_BellyHasSwallowedPrey) and (belly.DigestionPhase ~= 0 or (belly.Prey and #belly.Prey > 0)))) then
                if not IsValid(npc:GetEnemy()) then
                    local isMovingOrWandering = false
                    if npc.IsMoving and npc:IsMoving() then isMovingOrWandering = true end
                    if npc.GetVelocity and npc:GetVelocity():Length2DSqr() > 4 then isMovingOrWandering = true end
                    if npc.GetCurrentSchedule then
                        local sched = npc:GetCurrentSchedule()
                        if sched ~= SCHED_IDLE_STAND and sched ~= SCHED_NPC_FREEZE and sched ~= SCHED_WAIT_FOR_SCRIPT then
                            isMovingOrWandering = true
                        end
                    end
                    if isMovingOrWandering then
                        if npc.ClearSchedule then pcall(npc.ClearSchedule, npc) end
                        if npc.ClearPatrols then pcall(npc.ClearPatrols, npc) end
                        if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_IDLE_STAND) end
                        if npc.StopMoving then pcall(npc.StopMoving, npc) end
                        if npc.SetVelocity then pcall(npc.SetVelocity, npc, Vector(0, 0, 0)) end
                    end
                end
            end
        end
        if VNPC_AnimatedBoneOffsets then
            VNPC_AnimatedBoneOffsets(npc)
        end
    end
end)

-- AI Think loop for female model vore NPCs to grab nearby targets/enemies
hook.Add("Think", "VNPC_FemaleModelVore_AI", function()
    local enabled = GetConVar("vnpcs_female_model_vore")
    if enabled and not enabled:GetBool() then return end
    
    local now = CurTime()
    local grab_dist = GetConVar("vnpcs_female_model_vore_grab_range"):GetFloat() or 75
    local detect_dist = GetConVar("vnpcs_female_model_vore_range"):GetFloat() or 600
    
    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if not IsValid(npc) or not npc.VNPC_FemaleModelVore then continue end
        if (npc.VNPC_NextAIThink or 0) > now then continue end
        npc.VNPC_NextAIThink = now + 0.5
        
        local belly = npc.VNPC_Belly or npc.Belly
        if IsValid(belly) and (VNPC_BellyHasSwallowedPrey and VNPC_BellyHasSwallowedPrey(belly) or ((not VNPC_BellyHasSwallowedPrey) and (belly.DigestionPhase ~= 0 or (belly.Prey and #belly.Prey > 0)))) then
            if VNPC_IsPredatorCalm and VNPC_IsPredatorCalm(npc) then
                if npc.ClearSchedule then pcall(npc.ClearSchedule, npc) end
                if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_IDLE_STAND) end
                continue
            end
        end
        
        local pers, pers_data = "opportunistic", nil
        if VNPC_GetPredatorPersonality then
            pers, pers_data = VNPC_GetPredatorPersonality(npc)
        end
        local levelBonus = (VNPC_GetPredatorLevel and (VNPC_GetPredatorLevel(npc) - 1) * 3.0) or 0
        if npc.GetMaxHealth and npc:GetMaxHealth() > 0 and (npc:Health() / npc:GetMaxHealth()) < 0.35 then
            npc.VNPC_DesperateSurvival = true
            levelBonus = levelBonus + 25.0
        else
            npc.VNPC_DesperateSurvival = nil
        end
        local eff_grab = grab_dist * (pers_data and pers_data.grab_multiplier or 1.0)
        local eff_detect = detect_dist * (pers_data and pers_data.range_multiplier or 1.0)

        -- Target enemy if present
        local enemy = npc:GetEnemy()
        local prefer_swallow = GetConVar("vnpcs_ai_prefer_swallowing")
        if IsValid(enemy) and enemy ~= npc and not enemy.Vored then
            if VNPC_CanSwallowOwnSpecies and not VNPC_CanSwallowOwnSpecies(npc, enemy) then
                continue
            end
            local targetRad = (enemy.OBBMaxs and enemy:OBBMaxs():Length2D() or 30)
            local dist = npc:GetPos():Distance(enemy:GetPos())
            local battle_grab = math.max(140, eff_grab * 1.5) + targetRad + levelBonus
            if dist <= battle_grab then
                if npc.CapabilitiesAdd and npc.VNPC_RemovedRangeAttack then
                    pcall(npc.CapabilitiesAdd, npc, CAP_WEAPON_RANGE_ATTACK1)
                    npc.VNPC_RemovedRangeAttack = nil
                end
                npc:EatEntity(enemy)
            elseif dist <= eff_detect then
                if prefer_swallow and prefer_swallow:GetBool() and npc.CapabilitiesRemove then
                    pcall(npc.CapabilitiesRemove, npc, CAP_WEAPON_RANGE_ATTACK1)
                    npc.VNPC_RemovedRangeAttack = true
                end
                if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_CHASE_ENEMY) end
            end
        else
            if npc.CapabilitiesAdd and npc.VNPC_RemovedRangeAttack then
                pcall(npc.CapabilitiesAdd, npc, CAP_WEAPON_RANGE_ATTACK1)
                npc.VNPC_RemovedRangeAttack = nil
            end
            if pers_data and pers_data.only_enemies then continue end
            -- Search for nearby hostile target or corpses
            for _, ent in ipairs(ents.FindInSphere(npc:GetPos(), eff_detect)) do
                if IsValid(ent) and ent ~= npc and not ent.Vored and (ent:IsPlayer() or ent:IsNPC()) then
                    if ent.VNPC_DigestedBone or ent.VNPC_BoneOwner or ent.VNPC_NoVore then continue end
                    if VNPC_IsFamilyOrMate and VNPC_IsFamilyOrMate(npc, ent) then continue end
                    if not (npc.VNPC_IsWildWanderer and npc.VNPC_WildType == "predator") and VNPC_IsProtectedChildPrey and VNPC_IsProtectedChildPrey(ent) then continue end
                    if VNPC_IsPreyEmissary and VNPC_IsPreyEmissary(ent) then continue end
                    if VNPC_CanSwallowOwnSpecies and not VNPC_CanSwallowOwnSpecies(npc, ent) then continue end
                    if npc.GetRelationship and npc:GetRelationship(ent) == D_HT then
                        local targetRad = (ent.OBBMaxs and ent:OBBMaxs():Length2D() or 30)
                        local levelBonus = (VNPC_GetPredatorLevel and (VNPC_GetPredatorLevel(npc) - 1) * 3) or 0
                        local grab_reach = math.max(110, eff_grab) + targetRad + levelBonus
                        if npc:GetPos():Distance(ent:GetPos()) <= grab_reach then
                            npc:EatEntity(ent)
                            break
                        elseif npc.SetEnemy then
                            pcall(npc.SetEnemy, npc, ent)
                            if prefer_swallow and prefer_swallow:GetBool() and npc.CapabilitiesRemove then
                                pcall(npc.CapabilitiesRemove, npc, CAP_WEAPON_RANGE_ATTACK1)
                                npc.VNPC_RemovedRangeAttack = true
                            end
                            if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_CHASE_ENEMY) end
                            break
                        end
                    end
                elseif IsValid(ent) and (ent:GetClass() == "prop_ragdoll" or ent.VNPC_IsCorpse) and npc.CanEatCorpse and npc:CanEatCorpse(ent) then
                    if ent.VNPC_DigestedBone or ent.VNPC_BoneOwner or ent.VNPC_NoVore then continue end
                    local rag_dist = GetConVar("vnpcs_female_model_vore_ragdoll_range"):GetFloat() or 150
                    if npc:GetPos():Distance(ent:GetPos()) <= math.min(eff_grab, rag_dist) then
                        npc:EatEntity(ent)
                        break
                    end
                end
            end
        end
    end
end)

CreateConVar("vnpcs_ai_prefer_swallowing", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Make predator NPCs prefer rushing to swallow enemies over standing and shooting ranged weapons")
CreateConVar("vnpcs_battle_prefer_vore", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Make predators prefer swallowing over shooting to kill in battles")

hook.Add("EntityTakeDamage", "VNPC_Battle_PreferVore", function(target, dmginfo)
    local enabled = GetConVar("vnpcs_battle_prefer_vore")
    if enabled and not enabled:GetBool() then return end

    local attacker = dmginfo:GetAttacker()
    if not IsValid(attacker) or not IsValid(target) then return end
    if not (target:IsPlayer() or target:IsNPC() or target:IsNextBot()) then return end
    if target.Vored or target.VNPC_Vored then return end

    if attacker.IsDrGNextbot or attacker.VNPC_FemaleModelVore or attacker.Predator or attacker.EatEntity then
        local dmg = dmginfo:GetDamage()
        local curHP = target:Health()
        local surr_hp = GetConVar("vnpcs_surrender_hp_threshold"):GetInt() or 35
        if target:IsNPC() and (curHP - dmg <= surr_hp) and not target.VNPC_Surrendered then
            if VNPC_MakeSurrender then
                VNPC_MakeSurrender(target, attacker)
            end
        end
        if curHP - dmg <= 15 or target.VNPC_Surrendered then
            dmginfo:SetDamage(math.max(0, curHP - 15))
        end
    end
end)

-- AI Think loop for willing/desire prey NPCs to seek out predators and present themselves to be eaten
hook.Add("Think", "VNPC_WillingPrey_AI", function()
    local enabled = GetConVar("vnpcs_personalities_enabled")
    if enabled and not enabled:GetBool() then return end

    local now = CurTime()
    local grab_dist = GetConVar("vnpcs_female_model_vore_grab_range"):GetFloat() or 75

    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if not IsValid(npc) or npc.Vored or npc.VNPC_Vored then continue end
        if (npc.VNPC_NextWillingThink or 0) > now then continue end
        npc.VNPC_NextWillingThink = now + 0.6

        local pers, pers_data = "fighter", nil
        if VNPC_GetPreyPersonality then
            pers, pers_data = VNPC_GetPreyPersonality(npc)
        end

        if pers_data and (pers_data.seek_predator or pers_data.willing) then
            -- Search for nearby female model vore predator
            for _, pred in ipairs(ents.FindInSphere(npc:GetPos(), 600)) do
                if IsValid(pred) and pred ~= npc and (pred.Predator or pred.VNPC_FemaleModelVore or VNPC_IsFemaleModelNPC(pred)) and not pred.Vored then
                    if npc.VNPC_PreyCampID and pred.VNPC_PreyCampID and npc.VNPC_PreyCampID == pred.VNPC_PreyCampID then
                        continue
                    end
                    if npc.VNPC_PreyCampID and VNPC_IsFemalePreyCitizen and VNPC_IsFemalePreyCitizen(pred) then
                        continue
                    end
                    local dist = npc:GetPos():Distance(pred:GetPos())
                    local grabDist = (VNPC_IsAnyoneListeningToBelly and VNPC_IsAnyoneListeningToBelly(pred)) and 200 or 140
                    if dist <= grabDist then
                        if pred.VNPC_IsSleeping and VNPC_StartSleepingCrawlAnimation then
                            VNPC_StartSleepingCrawlAnimation(pred, npc)
                        elseif pred.EatEntity then
                            pcall(pred.EatEntity, pred, npc)
                        end
                        break
                    elseif dist <= 220 then
                        if npc.SetTarget then pcall(npc.SetTarget, npc, pred) end
                        if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_TARGET_FACE) end
                        if pred.SetEnemy then pcall(pred.SetEnemy, pred, npc) end
                        if pred.SetSchedule then pcall(pred.SetSchedule, pred, SCHED_CHASE_ENEMY) end
                        break
                    elseif npc.SetSchedule then
                        if npc.SetTarget then pcall(npc.SetTarget, npc, pred) end
                        pcall(npc.SetSchedule, npc, SCHED_TARGET_CHASE)
                        break
                    end
                end
            end
        end
    end
end)

hook.Add("EntityTakeDamage", "VNPC_FemaleModelVore_MeleeSwallow", function(target, dmginfo)
    if not IsValid(target) or not target.VNPC_FemaleModelVore then return end
    if target.Swallowing then return end

    local attacker = dmginfo:GetAttacker()
    if not IsValid(attacker) or attacker == target or attacker.Vored or attacker.VNPC_Vored then return end
    if VNPC_IsFamilyOrMate and VNPC_IsFamilyOrMate(target, attacker) then return end
    if not (target.VNPC_IsWildWanderer and target.VNPC_WildType == "predator") and VNPC_IsProtectedChildPrey and VNPC_IsProtectedChildPrey(attacker) then return end
    if VNPC_IsPreyEmissary and VNPC_IsPreyEmissary(attacker) then return end
    if VNPC_CanSwallowOwnSpecies and not VNPC_CanSwallowOwnSpecies(target, attacker) then return end

    local dist = target:GetPos():Distance(attacker:GetPos())
    local targetRad = (attacker.OBBMaxs and attacker:OBBMaxs():Length2D() or 30)
    if dist <= (150 + targetRad) then
        if target.EatEntity and target:EatEntity(attacker) then
            dmginfo:SetDamage(0)
        end
    end
end)

-- Damage threshold regurgitation / cleanup hooks
hook.Add("EntityTakeDamage", "VNPC_FemaleModelVore_DamageRegurgitate", function(ent, dmg)
    if IsValid(ent) and ent.VNPC_FemaleModelVore and IsValid(ent.VNPC_Belly) then
        if dmg:GetDamage() >= (ent:GetMaxHealth() * 0.3) or (ent:Health() - dmg:GetDamage() <= 0) then
            if ent.VNPC_Belly.Prey and istable(ent.VNPC_Belly.Prey) then
                for i = #ent.VNPC_Belly.Prey, 1, -1 do
                    local info = ent.VNPC_Belly.Prey[i]
                    local prey = (istable(info) and info.Entity) or info
                    if istable(info) and (info.WombPrey or info.NoDigest) then continue end
                    if IsValid(prey) and (prey.VNPC_IsWombPrey or prey.VNPC_IsUnbornBaby) then continue end
                    if IsValid(prey) and ent.VNPC_Belly.RegurgitateENT then
                        pcall(ent.VNPC_Belly.RegurgitateENT, ent.VNPC_Belly, prey)
                    elseif IsValid(prey) and ent.VNPC_Belly.Regurgitate then
                        pcall(ent.VNPC_Belly.Regurgitate, ent.VNPC_Belly, i)
                    end
                end
            end
        end
    end
end)

hook.Add("EntityRemoved", "VNPC_FemaleModelVore_Cleanup", function(ent)
    if IsValid(ent) and ent.VNPC_FemaleModelVore and IsValid(ent.VNPC_Belly) then
        if ent.VNPC_Belly.Prey and istable(ent.VNPC_Belly.Prey) then
            for i = #ent.VNPC_Belly.Prey, 1, -1 do
                local info = ent.VNPC_Belly.Prey[i]
                local prey = (istable(info) and info.Entity) or info
                if istable(info) and (info.WombPrey or info.NoDigest) then continue end
                if IsValid(prey) and (prey.VNPC_IsWombPrey or prey.VNPC_IsUnbornBaby) then continue end
                if IsValid(prey) and ent.VNPC_Belly.RegurgitateENT then
                    pcall(ent.VNPC_Belly.RegurgitateENT, ent.VNPC_Belly, prey)
                elseif IsValid(prey) and ent.VNPC_Belly.Regurgitate then
                    pcall(ent.VNPC_Belly.Regurgitate, ent.VNPC_Belly, i)
                end
            end
        end
        if IsValid(ent.VNPC_Belly) then
            ent.VNPC_Belly:Remove()
        end
    end
end)

concommand.Add("vnpcs_test_citizen_swallow", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not target:IsNPC() then
        return
    end
    if VNPC_IsFemaleModelNPC and VNPC_IsFemaleModelNPC(target) then
        if not target.VNPC_FemaleModelVore then
            VNPC_GiveFemaleModelVore(target)
        end
        local bestEnemy = nil
        for _, ent in ipairs(ents.FindInSphere(target:GetPos(), 300)) do
            if IsValid(ent) and ent ~= target and not ent.Vored and (ent:IsNPC() or ent:IsPlayer()) then
                bestEnemy = ent
                break
            end
        end
        if IsValid(bestEnemy) and target.EatEntity then
            target:EatEntity(bestEnemy)
        end
    end
end)

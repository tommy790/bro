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
    if ent.VNPC_FemaleModelVore then return true end
    if not VNPC_IsFemaleModelNPC(ent) then return false end
    
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
        if not IsValid(target) or self.Swallowing or target.Vored or self.Vored then return false end
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
        return true
    end

    function ent:CanEat(prey)
        return true
    end

    -- Event hooks matching VNPCs
    function ent:PostEntityEaten(ent) end
    function ent:OnBellyCreated(belly) end

    function ent:OnDigestionPhaseChanged(new, old)
        if new == 0 and old == 2 then
            self:Burp(true)
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
    end
    function ent:OnPreyKilled()
        if IsValid(self.VNPC_Belly) and self.VNPC_Belly.PlayFinalDigestSound then
            self.VNPC_Belly:PlayFinalDigestSound()
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
                if p_tbl and IsValid(p_tbl.Entity) then
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
        if not IsValid(npc) or not npc.VNPC_FemaleModelVore then continue end
        
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
        
        local pers, pers_data = "opportunistic", nil
        if VNPC_GetPredatorPersonality then
            pers, pers_data = VNPC_GetPredatorPersonality(npc)
        end
        local eff_grab = grab_dist * (pers_data and pers_data.grab_multiplier or 1.0)
        local eff_detect = detect_dist * (pers_data and pers_data.range_multiplier or 1.0)

        -- Target enemy if present
        local enemy = npc:GetEnemy()
        if IsValid(enemy) and enemy ~= npc and not enemy.Vored then
            local dist = npc:GetPos():Distance(enemy:GetPos())
            if dist <= eff_grab then
                npc:EatEntity(enemy)
            elseif dist <= eff_detect then
                if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_CHASE_ENEMY) end
            end
        else
            if pers_data and pers_data.only_enemies then continue end
            -- Search for nearby hostile target or corpses
            for _, ent in ipairs(ents.FindInSphere(npc:GetPos(), eff_detect)) do
                if IsValid(ent) and ent ~= npc and not ent.Vored and (ent:IsPlayer() or ent:IsNPC()) then
                    if npc.GetRelationship and npc:GetRelationship(ent) == D_HT then
                        if npc:GetPos():Distance(ent:GetPos()) <= eff_grab then
                            npc:EatEntity(ent)
                            break
                        elseif npc.SetEnemy then
                            pcall(npc.SetEnemy, npc, ent)
                            if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_CHASE_ENEMY) end
                            break
                        end
                    end
                elseif IsValid(ent) and (ent:GetClass() == "prop_ragdoll" or ent.VNPC_IsCorpse) and npc.CanEatCorpse and npc:CanEatCorpse(ent) then
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
                    local dist = npc:GetPos():Distance(pred:GetPos())
                    if dist <= grab_dist then
                        if pred.EatEntity then
                            pcall(pred.EatEntity, pred, npc)
                        end
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

-- Damage threshold regurgitation / cleanup hooks
hook.Add("EntityTakeDamage", "VNPC_FemaleModelVore_DamageRegurgitate", function(ent, dmg)
    if IsValid(ent) and ent.VNPC_FemaleModelVore and IsValid(ent.VNPC_Belly) then
        if dmg:GetDamage() >= (ent:GetMaxHealth() * 0.3) or (ent:Health() - dmg:GetDamage() <= 0) then
            if ent.VNPC_Belly.Prey and istable(ent.VNPC_Belly.Prey) then
                for _, prey in ipairs(ent.VNPC_Belly.Prey) do
                    if IsValid(prey) and ent.VNPC_Belly.Regurgitate then
                        pcall(ent.VNPC_Belly.Regurgitate, ent.VNPC_Belly, prey)
                    end
                end
            end
        end
    end
end)

hook.Add("EntityRemoved", "VNPC_FemaleModelVore_Cleanup", function(ent)
    if IsValid(ent) and ent.VNPC_FemaleModelVore and IsValid(ent.VNPC_Belly) then
        if ent.VNPC_Belly.Prey and istable(ent.VNPC_Belly.Prey) then
            for _, prey in ipairs(ent.VNPC_Belly.Prey) do
                if IsValid(prey) and ent.VNPC_Belly.Regurgitate then
                    pcall(ent.VNPC_Belly.Regurgitate, ent.VNPC_Belly, prey)
                end
            end
        end
        if IsValid(ent.VNPC_Belly) then
            ent.VNPC_Belly:Remove()
        end
    end
end)

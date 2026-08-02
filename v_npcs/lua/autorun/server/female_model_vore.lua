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
    ent.Belly_Offset = ent.Belly_Offset or Vector(0, 3.5, 0)
    
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
            belly:SetLocalPos(npc.Belly_Offset or Vector(0, 3.5, 0))
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
        
        -- Target enemy if present
        local enemy = npc:GetEnemy()
        if IsValid(enemy) and enemy ~= npc and not enemy.Vored then
            local dist = npc:GetPos():Distance(enemy:GetPos())
            if dist <= grab_dist then
                npc:EatEntity(enemy)
            elseif dist <= detect_dist then
                if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_CHASE_ENEMY) end
            end
        else
            -- Search for nearby hostile target
            for _, ent in ipairs(ents.FindInSphere(npc:GetPos(), detect_dist)) do
                if IsValid(ent) and ent ~= npc and not ent.Vored and (ent:IsPlayer() or ent:IsNPC()) then
                    if npc.GetRelationship and npc:GetRelationship(ent) == D_HT then
                        if npc:GetPos():Distance(ent:GetPos()) <= grab_dist then
                            npc:EatEntity(ent)
                            break
                        elseif npc.SetEnemy then
                            pcall(npc.SetEnemy, npc, ent)
                            if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_CHASE_ENEMY) end
                            break
                        end
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

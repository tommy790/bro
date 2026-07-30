local function GetBoneID(ent, names)
    if type(names) == "string" then 
		names = {names} 
	end
		
    for _, name in ipairs(names) do
        local bone = ent:LookupBone(name)

        if bone then return bone end
    end
    return nil
end

function ENT:GetBellyAnchor() --: number?
	local spineBone = GetBoneID(self, {
		self.SpineBone or "000000000",
        "ValveBiped.Bip01_Spine2",
        "Spine2",
        "ValveBiped.Bip01_Spine1",
        "Spine1",
		"ValveBiped.spine2",
		"Bip01_Spine2",
		"Bip01_Spine1",
		"bip_spine_2",
		"bip_spine_1",
    })
	
    if not spineBone then
        print("[V-NPCs] Couldn't find required spine bones\n")
        print("Available bones:\n")
        for i=0, self:GetBoneCount()-1 do
            print(i..": "..(self:GetBoneName(i) or "unknown").."\n")
        end
		self:Remove()

		net.Start("VoreNoModNotif")
		net.WriteString(self.ModNeeded)
		net.WriteString(self.PrintName)
		net.Broadcast() --probably replace this to the npc owner if that even works
		
        return
    end

	return spineBone
end

function ENT:SetupBelly(spineBone)
	local belly = ents.Create(self.BellyObject or "ent_vore_belly")
	belly:SetProperties(self.BellyProperties, self)
	belly:SetNPC(self)

	belly:Spawn()
	belly:Activate()

	self.Belly = belly
    belly:FollowBone(self, spineBone)
	self:SetNWEntity("Belly", belly)
	self:OnBellyCreated(belly)
end

function ENT:SetBellyPosition() 
	if not self.Belly then return end

	self.Belly:SetLocalAngles(self.Belly_Angles)
	self.Belly:SetLocalPos(self.Belly_Offset)
end

function ENT:GetBelly()
    return self:GetNWEntity("Belly")
end
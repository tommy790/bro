local function getLerpTime(dt, sped)
   	return 1 - math.exp(-sped * dt) --i love this formula
end

function ENT:DoBoneOffsets()
    if not self.VoreSettings.BoneOffsets then return end
    local potential_headbone_add = nil 

	for name, info in pairs(self.VoreSettings.BoneOffsets) do
		if not info.BoneID then
			info.BoneID = self:LookupBone(name) or -1
		end
		if info.BoneID == -1 then continue end

		if info.BoneID == self._headbone then
			if info.Custom then
				local angle = info.Custom(info, self.VisualBonescale, self)
				potential_headbone_add = angle
				continue 
			end

			local offset = math.min(info.Start + (self.VisualBonescale - 1) * info.Multi, info.Max)
			potential_headbone_add = info.Angle * offset
			continue 
		end

		if info.Custom then
			local spring = self.Belly and self.Belly.BellySpring
			local angle = info.Custom(info, self.VisualBonescale, self)
			self:ManipulateBoneAngles(info.BoneID, angle)
			continue 
		end

		local offset = math.min(info.Start + (self.VisualBonescale - 1) * info.Multi, info.Max)
		self:ManipulateBoneAngles(info.BoneID, info.Angle * offset)
	end

    return potential_headbone_add
end 

function ENT:VNPCLook(_dt)
    local headBone = self._headbone
    if not headBone or headBone < 0 then return end
	local bonePos, boneAng = self:GetBonePosition(headBone)

	local ownEyePos = self:EyePos()
	if not self.EyeTarget then
		self.EyeTarget = ownEyePos
	end

	local target = ownEyePos + self:GetAngles():Forward() * 100

	if ownEyePos then
		local phase = self:GetNWInt("DigestionPhase")
		if phase and phase ~= 0 then
			target = self:GetPos() + self:GetAngles():Forward() * 50
		end 
	end

	local forward = self:GetAngles():Forward()
	local max_dist = 80 * self.LookDistMulti * self:GetModelScale()
		
	local chasing = self:GetNW2Entity("DrGBaseEnemy") or self:GetNW2Entity("DrGBasePossessionLockedOn")
	if chasing and chasing:IsValid() then
		target = chasing:EyePos()
	else
		for _, ent in ents.Iterator() do
			if ent:GetNoDraw() or not ent:Alive() then
				continue
			end

			if ent:IsNPC() or ent:IsNextBot() or ent:IsPlayer() then
				local eyePos = ent:EyePos()
				local toTarget = (eyePos - ownEyePos):GetNormalized()
				local dot = forward:Dot(toTarget)
				if eyePos:Distance(ownEyePos) <= max_dist and dot > 0.2 then
					target = ent:EyePos()
					break
				end
			end
		end
	end

	local lerpSpeed = getLerpTime(_dt, 10)
	local headlerpSpeed = getLerpTime(_dt, 6)

	local new = LerpVector(lerpSpeed, self.EyeTarget, target)
	self.EyeTarget = new
	self:SetEyeTarget(new)

	local dir = (self.EyeTarget - bonePos):GetNormalized()
	local targetAng = dir:Angle()

	local localAng = self:WorldToLocalAngles(targetAng)

	local pitch = math.Clamp(localAng.y, -45, 45)
	local yaw = math.Clamp(localAng.x, -40, 30)		
	local dogRoll = pitch * yaw/90

	if self.CustomHeadTurn then
		targetAng = self:CustomHeadTurn(yaw, pitch, dogRoll)
	else
		targetAng = Angle(dogRoll, -yaw, pitch)
	end

	if potential_headbone_add then
		targetAng:Add(potential_headbone_add)
	end

	self.HeadLerpAng = self.HeadLerpAng or Angle(0, 0, 0)
	self.HeadLerpAng = LerpAngle(headlerpSpeed, self.HeadLerpAng, targetAng)
			
	self:ManipulateBoneAngles(headBone, self.HeadLerpAng)
end

function ENT:CustomThink()
	local _dt = FrameTime()
	self.Belly = self:GetNWEntity("Belly")

	--BONESCALE SHIT
	local current_scale = self:GetNWFloat("Bonescale", 1)
	local oldVisual = self.VisualBonescale

	local bonescale_lerp = getLerpTime(_dt, 3)
	self.VisualBonescale = Lerp(bonescale_lerp, self.VisualBonescale or current_scale, current_scale)
	if oldVisual ~= self.VisualBonescale then
		self:DoVisualBonescale(self.VisualBonescale)
	end

	local potential_headbone_add = self:DoBoneOffsets()

	if self._headbone == nil then
		self._headbone = self:LookupBone(self.EyeBone)
	end
	self:VNPCLook(_dt)
end

function ENT:OnPossessed(plr)
	if plr ~= LocalPlayer() then return end
	self.ZMulti = 1
		
	hook.Add("CreateMove", "possesing_vore_npc_zmulti_bullshit", function(cmd)
		if not IsValid(self) or not IsValid(plr) then
			hook.Remove("CreateMove", "possesing_vore_npc_zmulti_bullshit")
			return 
		end

		if cmd:GetMouseWheel() ~= 0 then
			self.ZMulti = self.ZMulti - cmd:GetMouseWheel() * 0.08
			if self.ZMulti < 0.3 then
				self.ZMulti = 0.3
			end
			if self.ZMulti > 5 then
				self.ZMulti = 5
			end
		end
	end)
end

function ENT:OnDispossessed(plr)
	if plr ~= LocalPlayer() then return end
	hook.Remove("CreateMove", "possesing_vore_npc_zmulti_bullshit")
end
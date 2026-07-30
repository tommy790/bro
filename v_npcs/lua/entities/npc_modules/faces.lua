
function ENT:SetFacialExpression(phase)
	if phase == self.CurrentFacialPhase then return end
	self.CurrentFacialPhase = phase

    local flexTargets = self.VoreSettings.FlexFaces
    self.VoreFlexLerpStart = CurTime()
    self.VoreFlexTargets = flexTargets[phase] or flexTargets[0]

	self.CurrentFlexes = self.CurrentFlexes or {}
	if self.FaceWipers then --very assuming
		for _,term in ipairs(self.FaceWipers) do
			term()
		end
		self.FaceWipers = nil
	end

	for flexName, targetWeight in pairs(self.VoreFlexTargets) do
		if type(targetWeight) == "function" then --CUSTOM CODE FOR FACIAL PHASE
			local return_function = targetWeight()
			if return_function and type(return_function) == "function" then
				if not self.FaceWipers then self.FaceWipers = {} end
				table.insert(self.FaceWipers, return_function)
			end

			continue 
		elseif type(flexName) == "number" then --if you actually just inserted the real thing
			self.CurrentFlexes[flexName] = true 
			self.VoreFlexTargets[flexName] = targetWeight
			continue 
		end

		local flexId = self:GetFlexIDByName(flexName) --FLEX, AKA THE ACTUAL FACE
        if flexId and flexId >= 0 then
			self.CurrentFlexes[flexId] = true
			self.VoreFlexTargets[flexId] = targetWeight
			continue
        end
		 
		local is_bodygroup, _end = string.find(flexName, "_bg_") --EXAMPLE IS "_bg_Smile4"
		if is_bodygroup and is_bodygroup == 1 then --BODYGROUPS
			local actual_bodygroupName = string.sub(flexName, _end + 1, -1)
			local actual_bodygroup = self:FindBodygroupByName(actual_bodygroupName)
			if actual_bodygroup >= 0 then
				self:SetBodygroup(actual_bodygroup, targetWeight)
			end

			continue 
		end

		local is_skin = flexName == "_set_skin_" --SKIN
		if is_skin then
			self:SetSkin(targetWeight)
			continue 
		end
    end

	self:SetNWInt("FacialPhase", phase)
end

function ENT:GetCurrentFacialPhase()
	return self:GetNWInt("FacialPhase", -1)
end

function ENT:UpdateFacialExpressions()
	if not self.VoreFlexTargets then return end 
	local targets = self.VoreFlexTargets

    local duration = self.VoreFlexLerpDuration
    local lerp = math.Clamp((CurTime() - (self.VoreFlexLerpStart or 0)) / duration, 0, 1)
    local easedLerp = math.ease.InOutSine(lerp)

	for flexId, _ in pairs(self.CurrentFlexes or {}) do
		local reseting = targets[flexId] == nil
		local flex_target = targets[flexId] or 0

		local current = self:GetFlexWeight(flexId) or 0
		local new = Lerp(easedLerp, current, flex_target)

		self:SetFlexWeight(flexId, new)

		if reseting and new == flex_target then
			self.CurrentFlexes[flexId] = nil
		end
	end
            
    if lerp == 1 then
        self.VoreFlexTargets = nil
    end
end
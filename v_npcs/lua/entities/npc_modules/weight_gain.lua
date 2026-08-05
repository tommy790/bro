local gain_global = CreateConVar("vnpcs_gain", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
local gain_force = CreateConVar("vnpcs_global_gain", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
local gain_multi = CreateConVar("vnpcs_gain_multi", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED})

local function whatIsBone(boneName, definers) 
	boneName = string.lower(boneName)

	if definers then
		for ident, _ in pairs(definers) do
			if boneName:find(string.lower(ident)) then
				return ident
			end
		end
	end

	if boneName:find("breast") or boneName:find("boob") or boneName:find("pectoral") or boneName:find("pec") or boneName:find("lpectoral") or boneName:find("rpectoral") then
		return "Boob"
	elseif boneName:find("thigh") or boneName:find("leg_bone1") then
		return "Thigh"
	elseif boneName:find("calf") or boneName:find("leg_bone3") then
		return "Calf"
	elseif boneName:find("arm") then
		return "Arm"
	elseif boneName:find("pelvis") or boneName:find("hips") or boneName:find("butt") then
		return "Waist"
	elseif boneName:find("spine") then
		return "Spine"
	end

	return "Unknown"
end

function ENT:UpdateBoneScale(_bonescale)
	if not gain_global:GetBool() then return end
	if not gain_force:GetBool() then
		if not self.VoreSettings.HasWeightGain then return end
	end

	self:SetNWFloat("Bonescale", _bonescale)
	self:OnWeightGain(_bonescale)
end

function ENT:GainWeight(amountGained)
	self.BoneScale = self.BoneScale + amountGained * gain_multi:GetFloat() * self:GetModelScale()
	self:UpdateBoneScale(self.BoneScale)
end

function ENT:SetWeight(new)
	self.BoneScale = new
	self:UpdateBoneScale(self.BoneScale)
end

local pectoral_bone_names = {
    "ValveBiped.Bip01_L_Pectoral",
    "ValveBiped.Bip01_R_Pectoral",
    "ValveBiped.Bip01_L_Pectoral0",
    "ValveBiped.Bip01_R_Pectoral0",
    "Bip01_L_Pectoral",
    "Bip01_R_Pectoral",
    "L_Pectoral",
    "R_Pectoral",
    "l_pectoral",
    "r_pectoral",
    "pectoral0",
    "pectoral1",
    "pec_l",
    "pec_r",
    "ValveBiped.Bip01_lpectoral",
    "ValveBiped.Bip01_rpectoral",
    "ValveBiped.Bip01_Lpectoral",
    "ValveBiped.Bip01_Rpectoral",
    "Bip01_lpectoral",
    "Bip01_rpectoral",
    "lpectoral",
    "rpectoral",
    "Lpectoral",
    "Rpectoral"
}

function ENT:EnsurePectoralBonesInWeightGain()
    if not self.VoreSettings or not self.VoreSettings.WeightGainBones then return end
    if self._CheckedPectoralBones then return end
    self._CheckedPectoralBones = true

    local existing = {}
    for _, name in ipairs(self.VoreSettings.WeightGainBones) do
        existing[string.lower(name)] = true
    end

    for _, name in ipairs(pectoral_bone_names) do
        local boneID = self:LookupBone(name)
        if boneID and not existing[string.lower(name)] then
            table.insert(self.VoreSettings.WeightGainBones, name)
            existing[string.lower(name)] = true
        end
    end

    local count = self:GetBoneCount() or 0
    for i = 0, count - 1 do
        local name = self:GetBoneName(i)
        if name then
            local lower_name = string.lower(name)
            if (lower_name:find("pectoral") or lower_name:find("pec_") or lower_name:find("_pec") or lower_name:find("lpectoral") or lower_name:find("rpectoral")) and not existing[lower_name] then
                table.insert(self.VoreSettings.WeightGainBones, name)
                existing[lower_name] = true
            end
        end
    end
end

function ENT:DoVisualBonescale(_bonescale)
	self:EnsurePectoralBonesInWeightGain()
	local setting = self.VoreSettings.WeightGainSettings
	local definers = self.VoreSettings.WeightGainDefiners

	for _, boneName in ipairs(self.VoreSettings.WeightGainBones) do
		local boneID = self:LookupBone(boneName)
		if not boneID then continue end

		local is = whatIsBone(boneName, definers) ----this isn't smart and runs multiple times, rewrite to only run once and cache that info.
		--print(is)
		local multiplier = 0.5
		local max  = 1.5
		if setting[is.."Multiplier"] then
			multiplier = tonumber(setting[is.."Multiplier"]) or 0.5
		end
		if setting["Max"..is] then
			max = tonumber(setting["Max"..is]) or 1.5
		end

		local actual_scale = _bonescale + (multiplier - 1) * (_bonescale - 1)

		local scaleVec, posAdjust
		if definers and definers[is] then
			scaleVec, posAdjust = definers[is](actual_scale, max) 
		elseif is == "Boob" then
			scaleVec = Vector(
				math.min(actual_scale, 1.65 * max),
				math.min(actual_scale, 1.7 * max),
				math.min(actual_scale, 2.2 * max)
			)
		elseif is == "Waist" then
			scaleVec = Vector(
				math.min(actual_scale, 1.3 * max),  -- Width
				math.min(actual_scale, 1.4 * max),  -- Depth
				math.min(actual_scale, 1.6 * max)   -- Height
			)
		elseif is == "Spine" then
			scaleVec = Vector(
				math.min(actual_scale, 1.6 * max),  -- Width
				math.min(actual_scale, 1),  -- Depth
				math.min(actual_scale, 1.6 * max)   -- Height
			)
		else
			scaleVec = Vector(
				math.min(actual_scale, 1),  -- Width
				math.min(actual_scale, 1.6 * max),  -- Depth
				math.min(actual_scale, 1.6 * max)   -- Height
			)
		end
				
		self:ManipulateBoneScale(boneID, scaleVec)
		if posAdjust then
			self:ManipulateBonePosition(boneID, posAdjust, true)
		end
	end
end
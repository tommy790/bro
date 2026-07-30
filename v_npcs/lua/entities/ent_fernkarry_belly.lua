--[[
    belly model swap test, use this for your model swap 
]]

AddCSLuaFile()
AddCSLuaFile("belly_modules/mechanics.lua")
AddCSLuaFile("belly_modules/sounds.lua")
AddCSLuaFile("belly_modules/basic_visual.lua")
AddCSLuaFile("belly_modules/npc.lua")

include("belly_modules/mechanics.lua")
include("belly_modules/sounds.lua")
include("belly_modules/basic_visual.lua")
include("belly_modules/npc.lua")

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false

local force_fatcap = CreateConVar("vnpcs_global_fatcap", "0", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})

local belly_fat_multi = CreateConVar("vnpcs_fat_multi", 1, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})
local belly_fatcap_multi = CreateConVar("vnpcs_fatcap_multi", 1, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})

ENT.PreyStruggleMultiplier = 1.2

function ENT:Initialize()
	if SERVER then
        self:SetModel("models/fernkarry/belly/belly.mdl")
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetModelScale(1)
        self.NextVoreThink = CurTime()
    end
    self:CreateSounds()
end

function ENT:GainBellyFat(power)
    local newBase = self.BaseScale + (power * 0.007 * belly_fat_multi:GetFloat()) --magic number

    local max_scale = self.MaxBaseScale 
    if force_fatcap:GetBool() then
        max_scale = belly_fatcap_multi:GetFloat()
    else
        max_scale = max_scale * belly_fatcap_multi:GetFloat()
    end

    if newBase > max_scale then
        self:SetBaseScale(max_scale)
    else
        self:SetBaseScale(newBase)
    end
end

function ENT:OnPreyAdded() 
    self:PlaySwallowedSound()
end

function ENT:OnPreyDigesting(prey_index, dmg) 
    if math.random() < 0.4 then
		self:PlayRandomGurgle()
    end
end 

--SET FUNCTIONS
function ENT:SetStruggleMultipler(num)
    self.PreyStruggleMultiplier = num
end

function ENT:OnRemove()
    self:WipeAllPrey()
    self:StopAllSounds()
end

function ENT:SetProperties(props, npc) --alot of support for legacy, not very readable or automatic
    self:SetBaseScale(npc.BaseBellySize or props.BaseSize or 0)
	self:SetColor(npc._BellyColor or npc.BellyColor or props.BellyColor or Color(255,0,255))

	self:SetDigestionPower(npc.VoreSettings.DigestionStrength or props.DigestionStrength or 3)
	self:SetAbsorbPower(npc.VoreSettings.AbsorptionSpeed or props.AbsorptionPower or 2)
	self:SetStruggleMultipler(npc.VoreSettings.StruggleMultiplier or props.StruggleMultiplier or 1.5)
	self:SetMaxScale(npc.VoreSettings.MaxBaseSize or props.MaxBaseSize or 0.5)

    if npc.BellyMaterial or props.BellyMaterial then
		self:SetMaterial(npc.BellyMaterial or props.BellyMaterial)
	elseif npc._BellyColor then --THIS IS FOR OLD NPCS
		self:SetMaterial("models/wormonlooker/belly/oldbelly")
	end

    self.WeightGainAmount = props.WeightGainAmount or 0.5
end

if not CLIENT then return end

function ENT:Draw()
    self:DrawModel() 
end

local force_struggle = CreateConVar("vnpcs_global_struggle", "0", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})
local global_struggle_multi = CreateConVar("vnpcs_struggle_multi", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})
local camera_sway = CreateClientConVar("vnpcs_camerasway", "1", true)
local belly_clipping = CreateClientConVar("vnpcs_bellyclipping", "1", true)

local vector_one = Vector(1,1,1)

ENT.FlexNames = {
    "Wrinkle 01",
    "Wrinkle 02",
    "Prey Push 01 L",
    "Prey Push 01 R",
    "Prey Push 02 L",
    "Prey Push 02 R",
    "Prey Push 03 L",
    "Prey Push 03 R",
    "Prey Push 04 L",
    "Prey Push 04 R",
    "Prey Push 05 L",
    "Prey Push 05 R",
    "Prey Outline",

    "Thigh Left",
    "Thigh Right",
    "Lift Left",
    "Lift Right",
    "Lower Left",
    "Lower Right",
    "Squish Left",
    "Squish Right",
    "Sides Slim",
    "Sides Widen",
    "Cleavage Extend",
    "Cleavage Top",
    "Cleavage Bottom",
    "Extrude Lower",
    "Extrude Upper",
    "Extrude Bottom",
    "Extrude Top",
    "Extrude Front",
    "Crease Middle",
    "Press Waist Left",
    "Press Waist Right",
    "Press Side Left",
    "Press Side Right",
    "Press Front Left",
    "Press Front Right",
    "Needle Left",
    "Needle Right",
    "Pelvis Expand",
    "Pelvis Puffed",
    "Fatten Top",
    "Fatten Bottom 01",
    "Fatten Bottom 02",

}

local function getLerpTime(dt, sped)
    return 1 - math.exp(-sped * dt) --i love this formula
end

local function do_spring(spring, target) --adjusted spring code :)
    local currentPosition = spring.pos
	local currentVelocity = spring.velocity
	local targetPosition = target
	local dampingFactor = spring.damping
	local speed = spring.speed

    if speed == 0 then
        return spring
    end

	local deltaTime = speed * (CurTime() - spring.time)
	local dampingSquared = dampingFactor * dampingFactor

	local angFreq, sinTheta, cosTheta
	if dampingSquared < 1 then
		angFreq = math.sqrt(1 - dampingSquared)
		local exponential = math.exp(-dampingFactor * deltaTime) / angFreq
		cosTheta = exponential * math.cos(angFreq * deltaTime)
		sinTheta = exponential * math.sin(angFreq * deltaTime)
	elseif dampingSquared == 1 then
		angFreq = 1
		local exponential = math.exp(-dampingFactor * deltaTime) / angFreq
		cosTheta, sinTheta = exponential, exponential * deltaTime
	else
		angFreq = math.sqrt(dampingSquared - 1)
		local angFreq2 = 2 * angFreq
		local u = math.exp((-dampingFactor + angFreq) * deltaTime) / angFreq2
		local v = math.exp((-dampingFactor - angFreq) * deltaTime) / angFreq2
		cosTheta, sinTheta = u + v, u - v
	end

	local pullToTarget = 1 - (angFreq * cosTheta + dampingFactor * sinTheta)
	local velPosPush = sinTheta / speed
	local velPushRate = speed * sinTheta
	local velocityDecay = angFreq * cosTheta - dampingFactor * sinTheta

	local positionDifference = targetPosition - currentPosition

	local newPosition =  currentPosition + positionDifference * pullToTarget + currentVelocity * velPosPush
	
	if newPosition ~= newPosition then
		return targetPosition * 0, currentVelocity * 0 --thanks blev for having a shitty computer
	end

	local newVelocity = positionDifference * velPushRate + currentVelocity * velocityDecay

    spring.pos = newPosition
	spring.velocity = newVelocity
    spring.time = CurTime()
    
	return spring
end

function ENT:client_init()
    self.BellySpring = {pos = baseScale or 0, velocity = 0, damping = 0.7, speed = 2, time = CurTime()}
    self.RotationSpring = {pos = 0, velocity = 0, damping = 1, speed = 2, time = CurTime()}
    self.ParentAttachment = self:GetParentAttachment()

    for i=0, self:GetFlexNum() - 1 do
		print([["]]..self:GetFlexName(i)..[[",]])
	end
end

function ENT:StruggleAnimation(aliveFactor)
    --[[
        type flex = {
            target : number;
            spring : Spring;
        }
    ]]

    local alive_struggle_speed = math.pow(aliveFactor,0.4)
    local spring_speed = alive_struggle_speed
    
    if not self.RandomFlexes or table.IsEmpty(self.RandomFlexes) then
        local struggleMulti = self.PreyStruggleMultiplier * 0.6
        if force_struggle:GetBool() then
            struggleMulti = global_struggle_multi:GetFloat()
        else
            struggleMulti = struggleMulti * global_struggle_multi:GetFloat()
        end

        self.RandomFlexes = {}
        for _, flex in ipairs(self.FlexNames) do
            local flexId = self:GetFlexIDByName(flex)
            if flexId and flexId >= 0 then
                self.RandomFlexes[flexId] = {
                    target = math.Rand(-0.5 * struggleMulti, 1 * struggleMulti) * 0.8;
                    spring = {pos = 0, velocity = 0, damping = 0.7, speed = spring_speed, time = CurTime()}
                }
            end
        end
    end

    for flexId, info in pairs(self.RandomFlexes) do
        info.spring.speed = spring_speed
        local springResult = do_spring(info.spring, info.target)
        self:SetFlexWeight(flexId, springResult.pos) 
        self.RandomFlexes[flexId].spring = springResult
    end
    
    -- Occasionally set new random targets
        
    if not self.PreyStruggleTimer then
        self.PreyStruggleTimer = 0
    end
    self.PreyStruggleTimer = self.PreyStruggleTimer + FrameTime()

    local struggleMulti = self.PreyStruggleMultiplier
    if force_struggle:GetBool() then
        struggleMulti = global_struggle_multi:GetFloat()
    else
        struggleMulti = struggleMulti * global_struggle_multi:GetFloat()
    end

    local freq = alive_struggle_speed == 0 and 10 or 0.3/alive_struggle_speed
    if self.PreyStruggleTimer > freq then 
        for flex, _ in pairs(self.RandomFlexes) do
            if math.random() < 0.3 then
                self.RandomFlexes[flex].target = math.Rand(-0.5 * struggleMulti, 1 * struggleMulti) * 0.8
            end
        end
        self.PreyStruggleTimer = 0
    end
end

function ENT:DigestAnimation()
    if not self.RandomFlexes then return end

    self.PreyStruggleTimer = nil 
    if table.IsEmpty(self.RandomFlexes) then
        self.RandomFlexes = nil
        return
    end

    for flex,_ in pairs(self.RandomFlexes) do
        self.RandomFlexes[flex].target = 0 --no more prey!
    end

    local lerpSpeed = getLerpTime(FrameTime(), 0.15)
    for flexId, target in pairs(self.RandomFlexes) do
        local result = Lerp(lerpSpeed, self:GetFlexWeight(flexId), 0)
        self:SetFlexWeight(flexId, result)  -- Improved smoothing
        if result == 0 then
            self.RandomFlexes[flexId] = nil
        end
    end
end

function ENT:Think() --this code is realllyyyyy stupid
    if not self.BellySpring then
        self:client_init()
    end
    local currentPhase = self:GetNWInt("DigestionPhase")
    local wantedSize = self:GetNWFloat("BellySize")
    local baseScale = self:GetNWFloat("BaseScale")
    local aliveFactor = self:GetNWInt("AliveFactor") or 1
    self.NPC = self.NPC or self:GetNWEntity("NPCParent")
    --
    local main_bone = 1
    local targetSize = wantedSize

    self.BellySpring = do_spring(self.BellySpring, wantedSize)
    local newSize = self.BellySpring.pos * 1.8 --ik this will be nAn sometimes but it doesnt error

    if newSize <= 0 then
        self:ManipulateBoneScale(0, vector_origin) --fatrolls bone
        self:ManipulateBoneScale(main_bone, vector_origin)
        return 
    end

    local clipMax = -500
    do 
        if belly_clipping:GetBool() then
            local bone_matrix = self:GetBoneMatrix(0)
            local pos = bone_matrix:GetTranslation()

            local tr = util.TraceLine({
                start = pos,
                endpos = pos + (-vector_up * 200),
                filter = {self, self.NPC}
            })

            if tr.Hit then
                clipMax = tr.HitPos:Distance(pos)
            end
        end
    end

    do
        local modelSize = math.Clamp(newSize, 0, 1)

        self:ManipulateBoneScale(main_bone, vector_one * newSize)
        local test = (newSize - 1) * 9
        self:ManipulateBonePosition(main_bone, Vector(test * 0.6    , 0, math.max(-test * 1, -clipMax)))
        self:ManipulateBoneScale(0, vector_one * modelSize) --fatrolls bone
    end
    --[[animations]]
    if currentPhase == 1 then
        self:StruggleAnimation(aliveFactor)
    else
        self:DigestAnimation()
    end
end

function ENT:InteralCameraPos(entPos, ang)
    local bone_matrix = self:GetBoneMatrix(1)
    local bone_pos = bone_matrix:GetTranslation()
    local bone_ang = bone_matrix:GetAngles()
    local bone_scale = bone_matrix:GetScale()

    entPos = bone_pos - Vector(0,0,5) + bone_ang:Right() * bone_scale * -15

    if camera_sway:GetBool() == true then
        ang = ang - bone_ang 
    end
    ang = Angle(ang.x, ang.y, 0) --whatever

    return entPos, ang
end
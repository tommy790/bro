if not CLIENT then return end

local force_struggle = CreateConVar("vnpcs_global_struggle", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
local global_struggle_multi = CreateConVar("vnpcs_struggle_multi", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
local camera_sway = CreateClientConVar("vnpcs_camerasway", "1", true)
local belly_clipping = CreateClientConVar("vnpcs_bellyclipping", "1", true)

local vector_one = Vector(1,1,1)

ENT.FlexNames = ENT.FlexNames or { --this is hardcoded rn
    "MiddleTop",
    "MiddleLeft",
    "MiddleRight",
    "MiddleBottom",
    "MiddleLeftTop",
    "MiddleRightTop",
    "TopLeft",
    "TopRight",
    "BottomLeft",
    "BottomRight",
    "PreyOutline",
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
    self.RotationSpring = {pos = 0, velocity = 0, damping = 1, speed = 3.5, time = CurTime()}
    self.ParentAttachment = self:GetParentAttachment()
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
        local struggleMulti = self.PreyStruggleMultiplier
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
        local target_changed = false 
        for flex, _ in pairs(self.RandomFlexes) do
            if math.random() < 0.3 then
                target_changed = true 
                self.RandomFlexes[flex].target = math.Rand(-0.5 * struggleMulti, 1 * struggleMulti) * 0.8
            end
        end
        self.PreyStruggleTimer = 0
        if target_changed then
            timer.Simple(0.2/alive_struggle_speed, function()
                if self and IsValid(self) then
                    self:PlayRandomStruggle()
                end
            end)
        end
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
    local currentPhase = self:GetNWInt("DigestionPhase", 0)
    local wantedSize = self:GetNWFloat("BellySize", 0)
    local baseScale = self:GetNWFloat("BaseScale", 0)
    local aliveFactor = self:GetNWInt("AliveFactor", 1)
    self.MaxFolds = self:GetNWFloat("Fatfolds", 1)
    self.FoldMulti = self:GetNWFloat("FatfoldsMulti", 1)
    self.NPC = self:GetNWEntity("NPCParent")
    --
    local main_bone = 1
    local targetSize = wantedSize

    self.BellySpring = do_spring(self.BellySpring, wantedSize)
    local newSize = self.BellySpring.pos --ik this will be nAn sometimes but it doesnt error

    if newSize <= 0 then
        self:ManipulateBoneScale(0, vector_origin) --fatrolls bone
        self:ManipulateBoneScale(main_bone, vector_origin)
        return 
    end

    do 
        local wantedAngleOffset = 0
        if belly_clipping:GetBool() and not self:GetNWBool("NoClipFix", false) then
            local bone_matrix = self:GetBoneMatrix(1)
            local pos = bone_matrix:GetTranslation()
            local offset = 4

            local box = vector_one * newSize * 5

            local tr = util.TraceHull({
                start = pos + vector_up * offset,
                endpos = pos + (-vector_up * 200),
                maxs = box,
		        mins = -box,
                filter = {self, self.NPC}
            })

            if tr.Hit then
                local dist = tr.HitPos:Distance(pos) + (newSize * 5) + offset  
                local belly_size_messurement_aprox = 36 * newSize
                local clipCalc = dist - belly_size_messurement_aprox 

                if clipCalc < 0 then
                 wantedAngleOffset = 50 * math.exp((5 * clipCalc)/math.pow(dist, 1.2)) - 50
                end
            end
        end
        self.RotationSpring = do_spring(self.RotationSpring, wantedAngleOffset)
    end

    do
        local modelSize = math.Clamp(newSize * (self.FoldMulti or 1), 0, self.MaxFolds)
        self:ManipulateBoneAngles(main_bone, Angle(0, 0, self.RotationSpring.pos))

        self:ManipulateBoneScale(main_bone, vector_one * newSize)
        
        local ughhhhhh = math.min(-(1 - newSize) * 3.5, 0)
        self:ManipulateBonePosition(main_bone, Vector(0, ughhhhhh * 1.2, ughhhhhh * 0.9))
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

    entPos = bone_pos - vector_up + bone_ang:Right() * bone_scale * -15

    if camera_sway:GetBool() == true then
        ang = ang - bone_ang 
    end
    ang = Angle(ang.x, ang.y, 0) --whatever

    return entPos, ang
end
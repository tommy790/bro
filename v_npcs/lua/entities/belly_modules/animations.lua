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

        --[[ MULTI-OCCUPANT SHAPE ]]
        --2+ prey of the same species rock the belly back and forth between
        --the two of them instead of settling on one steady lean, hinting
        --that there's more than one body shifting around in there.
        local occupants = self:GetNWInt("BellyOccupants", 0)
        if occupants >= 2 then
            local wobbleAmount = math.min(occupants - 1, 3) * 4
            wantedAngleOffset = wantedAngleOffset + math.sin(CurTime() * 2.1) * wobbleAmount
        end

        self.RotationSpring = do_spring(self.RotationSpring, wantedAngleOffset)
    end

    do
        local modelSize = math.Clamp(newSize * (self.FoldMulti or 1), 0, self.MaxFolds)
        self:ManipulateBoneAngles(main_bone, Angle(0, 0, self.RotationSpring.pos))

        --[[ DYNAMIC WEIGHT PAINTING & MESH DEFORM ]]
        --blends towards the actual shape of whatever's inside (wide vs tall
        --vs long) instead of always inflating uniformly, so the belly reads
        --like it's actually holding that specific prey.
        local wantedShape = self:GetNWVector("BellyShape", vector_one)
        self.ShapeBlend = self.ShapeBlend or vector_one
        self.ShapeBlend = LerpVector(getLerpTime(FrameTime(), 2), self.ShapeBlend, wantedShape)

        --[[ RAGDOLL MATRIX ]]
        --live simulated struggle offset/force, shifts the bulge position and
        --adds a bit of extra "jostle" so the belly visibly bounces around
        --wherever the prey currently is. When 2+ prey of the same species
        --are inside, this alternates its focus between both of them instead
        --of averaging them into one static point, which reads as two
        --separate bodies taking turns pressing outward rather than one
        --bigger blob.
        local occupants = self:GetNWInt("BellyOccupants", 0)
        local ragOffset = self:GetNWVector("RagOffset", vector_origin)
        local ragOffset2 = self:GetNWVector("RagOffset2", vector_origin)
        local ragForce = self:GetNWFloat("RagForce", 0)
        local ragForce2 = self:GetNWFloat("RagForce2", 0)

        local targetOffset, targetForce = ragOffset, ragForce
        if occupants >= 2 then
            local phase = (math.sin(CurTime() * 1.3) + 1) * 0.5
            targetOffset = LerpVector(phase, ragOffset, ragOffset2)
            targetForce = Lerp(phase, ragForce, ragForce2)
        end

        self.RagBlend = self.RagBlend or vector_origin
        self.RagBlend = LerpVector(getLerpTime(FrameTime(), 9), self.RagBlend, targetOffset)

        --a real second bulge bone (if a belly model ever ships with one)
        --always wins over the illusion above
        local secondBone = self.SecondBellyBone
        if secondBone == nil then
            secondBone = self:LookupBone("main2") or false
            self.SecondBellyBone = secondBone
        end

        local widenExtra = 1
        if occupants >= 2 and not secondBone then
            widenExtra = 1 + math.min(occupants - 1, 3) * 0.08
        end

        local scaleVec = Vector(
            newSize * self.ShapeBlend.x * widenExtra,
            newSize * self.ShapeBlend.y * widenExtra,
            newSize * self.ShapeBlend.z
        ) * (1 + targetForce * 0.12)

        self:ManipulateBoneScale(main_bone, scaleVec)
        
        local ughhhhhh = math.min(-(1 - newSize) * 3.5, 0)
        local jostle = self.RagBlend * 0.06
        self:ManipulateBonePosition(main_bone, Vector(jostle.x, ughhhhhh * 1.2 + jostle.y, ughhhhhh * 0.9 + jostle.z))
        self:ManipulateBoneScale(0, vector_one * modelSize) --fatrolls bone

        if secondBone then
            if occupants >= 2 then
                self:ManipulateBoneScale(secondBone, Vector(newSize, newSize, newSize) * (1 + ragForce2 * 0.12))
                self:ManipulateBonePosition(secondBone, ragOffset2 * 0.06)
            else
                self:ManipulateBoneScale(secondBone, vector_origin)
            end
        end
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
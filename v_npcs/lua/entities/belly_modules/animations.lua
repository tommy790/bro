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

--[[
    Belly deformation driven by the prey's actual body.

    The belly model ships a directional grid of push-out flexes (MiddleTop,
    TopLeft, BottomRight, ...) plus a PreyOutline. When active ragdolls are on we
    read the prey ragdoll's limb bones -- it is a networked entity, so this needs
    no extra networking at all -- work out which direction each limb is pressing
    against the stomach wall, and drive the matching flex. A hand shoving at the
    upper left genuinely reads as a hand shoving at the upper left.

    Falls back to the original random-target struggle when no ragdoll is present.

    NOTE: these direction vectors are in belly-bone local space. Belly_Angles is
    Angle(0, 90, 90), so the model's local axes are rotated relative to world and
    this table is the one thing here that may need correcting against the actual
    model. It is deliberately a plain table so that is a ten second edit.
]]
local FLEX_DIRECTIONS = {
    MiddleTop      = Vector( 0,  0,  1),
    MiddleBottom   = Vector( 0,  0, -1),
    MiddleLeft     = Vector( 0,  1,  0),
    MiddleRight    = Vector( 0, -1,  0),
    MiddleLeftTop  = Vector( 0,  0.7,  0.7),
    MiddleRightTop = Vector( 0, -0.7,  0.7),
    TopLeft        = Vector( 0.7,  0.7,  0.4),
    TopRight       = Vector( 0.7, -0.7,  0.4),
    BottomLeft     = Vector(-0.7,  0.7, -0.4),
    BottomRight    = Vector(-0.7, -0.7, -0.4)
}

for _, dir in pairs(FLEX_DIRECTIONS) do dir:Normalize() end

-- the parts of a body that actually press outwards
local LIMB_BONES = {
    "ValveBiped.Bip01_L_Hand", "ValveBiped.Bip01_R_Hand",
    "ValveBiped.Bip01_L_Foot", "ValveBiped.Bip01_R_Foot",
    "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_R_Forearm",
    "ValveBiped.Bip01_Head1",
    "Hand_L", "Hand_R", "Foot_L", "Foot_R", "Head",
    "hand_l", "hand_r", "foot_l", "foot_r"
}

local function cacheLimbBones(ragdoll)
    local cached = ragdoll.VNPCS_LimbBones
    if cached then return cached end

    cached = {}
    for _, name in ipairs(LIMB_BONES) do
        local bone = ragdoll:LookupBone(name)
        if bone then cached[#cached + 1] = bone end
    end

    -- unknown skeleton: fall back to a sparse sample of whatever it does have
    if #cached == 0 then
        local count = ragdoll:GetBoneCount() or 0
        for bone = 0, count - 1, math.max(math.floor(count / 8), 1) do
            cached[#cached + 1] = bone
        end
    end

    ragdoll.VNPCS_LimbBones = cached
    return cached
end

--[[
    Returns a flexName -> 0..1 pressure table, or nil when there is no ragdoll
    to read (in which case the caller uses the random struggle instead).
]]
function ENT:GatherRagdollPressure()
    local slots = VNPCS_RAGDOLL_SLOTS or 4
    if self:GetNWInt("PreyRagdollCount", 0) <= 0 then return nil end

    local matrix = self:GetBoneMatrix(1)
    if not matrix then return nil end

    local center = matrix:GetTranslation()
    local angles = matrix:GetAngles()
    local radius = math.max(self:GetNWFloat("BellySize", 0), 0.2) * 22 + 14

    local pressure, found = {}, false

    for slot = 1, slots do
        local ragdoll = self:GetNWEntity("PreyRagdoll" .. slot)
        if IsValid(ragdoll) then
            for _, bone in ipairs(cacheLimbBones(ragdoll)) do
                local worldPos = ragdoll:GetBonePosition(bone)
                if worldPos then
                    local localPos = WorldToLocal(worldPos, angle_zero, center, angles)
                    local reach = localPos:Length() / radius

                    -- only limbs actually near the wall deform it
                    if reach > 0.45 then
                        found = true

                        local dir = localPos:GetNormalized()
                        local push = math.Clamp((reach - 0.45) / 0.55, 0, 1)

                        for name, flexDir in pairs(FLEX_DIRECTIONS) do
                            local alignment = dir:Dot(flexDir)
                            if alignment > 0 then
                                -- ^3 keeps a limb from smearing across every flex
                                local amount = alignment * alignment * alignment * push
                                if amount > (pressure[name] or 0) then
                                    pressure[name] = amount
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if not found then return nil end

    return pressure
end

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

    --[[
        Real struggling from prey (belly_modules/struggle.lua) drives the springs
        harder and more often, so a player fighting to get out visibly thrashes
        the belly rather than the animation being purely on a random timer.
    ]]
    local intensity = math.Clamp(self:GetNWFloat("StruggleIntensity", 0), 0, 1)
    self.StruggleIntensity = intensity

    local spring_speed = alive_struggle_speed * (1 + intensity * 1.6)

    local struggleMulti = self.PreyStruggleMultiplier
    if force_struggle:GetBool() then
        struggleMulti = global_struggle_multi:GetFloat()
    else
        struggleMulti = struggleMulti * global_struggle_multi:GetFloat()
    end
    struggleMulti = struggleMulti * (1 + intensity * 0.85)
    
    if not self.RandomFlexes or table.IsEmpty(self.RandomFlexes) then
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

    --[[
        Real body pressure overrides the random targets when a prey ragdoll is
        present. The springs still smooth the result, so the wall gives and
        recovers rather than snapping to the limb position.
    ]]
    local pressure = self:GatherRagdollPressure()
    self.HasRagdollPressure = pressure ~= nil

    if pressure then
        for name, amount in pairs(pressure) do
            local flexId = self:GetFlexIDByName(name)
            if flexId and flexId >= 0 and self.RandomFlexes[flexId] then
                self.RandomFlexes[flexId].target = amount * struggleMulti
            end
        end

        local outline = self:GetFlexIDByName("PreyOutline")
        if outline and outline >= 0 then
            local peak = 0
            for _, amount in pairs(pressure) do
                if amount > peak then peak = amount end
            end
            self:SetFlexWeight(outline, Lerp(getLerpTime(FrameTime(), 6), self:GetFlexWeight(outline) or 0, peak))
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

    local freq = alive_struggle_speed == 0 and 10 or 0.3/alive_struggle_speed
    freq = freq / (1 + (self.StruggleIntensity or 0) * 2) --thrash faster when fought

    if self.PreyStruggleTimer > freq then 
        local target_changed = false 

        --[[
            When a real body is driving the flexes the random targets would just
            fight it for one frame each cycle. Keep the sound cue, drop the
            randomisation.
        ]]
        if not self.HasRagdollPressure then
            for flex, _ in pairs(self.RandomFlexes) do
                if math.random() < 0.3 then
                    target_changed = true 
                    self.RandomFlexes[flex].target = math.Rand(-0.5 * struggleMulti, 1 * struggleMulti) * 0.8
                end
            end
        else
            target_changed = true
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
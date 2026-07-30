--[[

    this replaces and handles most npc ai stuff 
    mostly replacing drgbase functions

]]

local patrolling = CreateConVar("vnpcs_patrol_full", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
local instaVore = CreateConVar("vnpcs_instavore", "0", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})

local hungryPlayers = CreateConVar("vnpcspersonality_players", "0", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})
local hungryNPCs = CreateConVar("vnpcspersonality_npcs", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})

local fatSpeedMutli = CreateConVar("vnpcs_speeddiff", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED})

function ENT:PossessionFaceForward() --this is so the player can actually look at themselves while possessing
	if not self:IsPossessed() then return end
	local lockedOn = self:PossessionGetLockedOn()
	local isMoving = self:IsMoving()
	local current, view = self:CurrentViewPreset()

	if isMoving or view.eyepos then
		self:FaceTowards(self:GetPos() + self:PossessorNormal())
	elseif IsValid(lockedOn) then
		self:FaceTowards(lockedOn) 
	end
end

function ENT:PossessorView() --this code is just so that the traceline filters out the belly, be scared and be weary.
	if not self:IsPossessed() then return end
	local current, view = self:CurrentViewPreset()

	local origin
	local distance

	if not self.ZMulti then
		self.ZMulti = 0
	end
	if current == -1 or view.auto then
		origin = self:WorldSpaceCenter() +
			Vector(0, 0, self:Height() / 3)
		distance = self:Length() * 3
	else
		local offset = view.offset or Vector(0, 0, 0)
		if view.eyepos then
			origin = self:EyePos()
		elseif isstring(view.bone) then
			local boneid = self:LookupBone(view.bone)
			if boneid ~= nil then
				origin = self:GetBonePosition(boneid)
			end
		else origin = self:WorldSpaceCenter() end

		local tr = self:TraceLine(
			self:PossessorForward() * offset.x * self:GetModelScale() +
			self:PossessorRight() * offset.y * self:GetModelScale() +
			self:PossessorUp() * offset.z * self:GetModelScale(), {
			start = origin,
			filter = {self, self.Belly},
		})

		origin = tr.HitPos
		distance = view.distance or 0
	end

	local tr = self:TraceLine(-self:PossessorNormal() * distance * self.ZMulti * self:GetModelScale(), {start = origin, filter = {self, self.Belly}})
	return tr.HitPos, self:GetPossessor():EyeAngles()
end

function ENT:GetAdjustedSpeeds() --weight speed mechanics are here
	if not self.Belly then
		return self.WalkSpeed, self.RunSpeed
	end
	
	local WEIGHT_VALUE = self.Belly:GetCollectivePreyValue()
	if WEIGHT_VALUE <= 0 then
		return self.WalkSpeed, self.RunSpeed
	end

	local ogWalk, ogRun = self.WalkSpeed, self.RunSpeed
	local multi = fatSpeedMutli:GetFloat() or 1

	local newRun = math.max(ogWalk, ogRun - WEIGHT_VALUE * 0.7 * multi)
	local newWalk = math.max(ogWalk/2, ogWalk - WEIGHT_VALUE * 0.1 * multi)
	
	return newWalk, newRun
end

function ENT:OnUpdateSpeed()
	local walkspeed, runspeed = self:GetAdjustedSpeeds() 
	if self:IsCrouching() then return walkspeed * 0.8 end
	if self:IsRunning() then return runspeed end
	return walkspeed 
end

function ENT:OnUpdateAnimation()
		if self:IsDown() or self:IsDead() then return end
		if not self:IsOnGround() then 
			return self.JumpAnimation, self.JumpAnimRate
		elseif self:IsCrouching() then
			if self:IsMoving() then
				return self.CrouchWalkAnimation, self.WalkAnimRate * 0.7
			end
			return self.CrouchAnimation, self.WalkAnimRate * 0.7
		elseif self:IsRunning() then 
			return self.RunAnimation, self.RunAnimRate
		elseif self:IsMoving() then 
			return self.WalkAnimation, self.WalkAnimRate
		end
		return self.IdleAnimation, self.IdleAnimRate
end

function ENT:OpenDoor(door)
	if IsValid(door) and door:DrG_IsDoor() then
		door = door:DrG_Wrap()
		door:Open(self)
	end
end

function ENT:OnClimbing(ladder, left, down)
	if IsValid(ladder) then
		self:EmitSlotSound("DrGBaseLadderClimbing", 0.3, "player/footsteps/ladder"..math.random(4)..".wav")
	end
	return not down and left < 112.5
end

function ENT:OnStopClimbing(ladder, height, down)
	if down then return end
	local footstep = false
	self:PlayActivityAndMoveAbsolute(ACT_ZOMBIE_CLIMB_END, self.ClimbAnimRate, function(self, cycle)
		if cycle >= 0.875 and not footstep then
			footstep = true
			self:EmitFootstep()
		end
		if cycle > 0.5 or not IsValid(ladder) then return end
		self:EmitSlotSound("DrGBaseLadderClimbing", 0.3, "player/footsteps/ladder"..math.random(4)..".wav")
	end)
end

function ENT:CheckOpenDoors() --THIS IS SCARY!!!! doing this every think is probably a bad idea but IDC
	local ents = ents.FindInSphere( self:GetPos(), 35 )
	for i,v in ipairs(ents) do
		self:OpenDoor(v)
	end
end

function ENT:UpdateRelations()
	self:SetSelfClassRelationship(D_LI)

	if hungryNPCs:GetBool() then
		self:SetDefaultRelationship(D_HT, 2)
	else
		self:SetDefaultRelationship(D_NU, 2)
	end

	if hungryPlayers:GetBool() then
		self:SetPlayersRelationship(D_HT, 2)
	else
		self:SetPlayersRelationship(D_NU, 3)
	end
end

function ENT:IsCrouching()
	return self:GetNW2Bool("DrGBaseCrouching")
end

function ENT:SetCrouching(bool)
	self:SetNW2Bool("DrGBaseCrouching", bool)
end

function ENT:ShouldIgnore(ent) 
	if self:GetEnemy() ~= ent then
		return ent.Predator --change this later? maybe?
	end
	return false 
end

function ENT:OnMeleeAttack(enemy) 
	if instaVore:GetBool() then
		self:Attack({
			damage = function(ent, orgin)
				self:EatEntity(ent)
				return -3
			end,
			type = DMG_SLASH,
			viewpunch = Angle(20, math.random(-10, 10), 0),
			angle = 180,
		})
        return
	end

	self:PlaySequenceAndMove(self.AttackAnimation, {rate = 1.5, collisions = false}, function(_, cycle)
		if cycle > 0.25 and cycle < 0.4 then
			--print(self.Speeds.LungeSpeed)
			self.WalkSpeed = self.Speeds.LungeSpeed
			self.RunSpeed = self.Speeds.LungeSpeed
			--self.loco:SetVelocity(self:GetForward() * 1000) --buffed
			self:MoveTowards(self:GetPos() + self:GetForward())
		end
		if cycle == 1 then
			self.WalkSpeed = self.Speeds.WalkSpeed
			self.RunSpeed = self.Speeds.RunSpeed
		end
		self:FaceEnemy()
	end)
end

function ENT:OnAnimEvent()
	if not self.IsPlayingSequence then return end --idk what the fuck this error is, just wave and nod
	if self:IsPlayingSequence(self.AttackAnimation) then
		self:Attack({
			damage = function(ent, orgin)
				self:EatEntity(ent)
				return -3
			end,
			type = DMG_SLASH,
			viewpunch = Angle(20, math.random(-10, 10), 0),
			angle = 180,
		})
	end
end

function ENT:OnTakeDamage(dmg, hitgroup) --will eat anything that attacks them
	self:AddEntityRelationship(dmg:GetAttacker(), D_HT, 15)
	self:SpotEntity(dmg:GetAttacker())
end

function ENT:OnReachedPatrol()
	self:Wait(math.random(10, 15))
end

function ENT:OnIdle()
	if (self.Belly and self.Belly.DigestionPhase ~= 0) and not patrolling:GetBool() then return end
	self:AddPatrolPos(self:RandomPos(1000))
end

function ENT:OnLandOnGround()
    self:EmitFootstep()
end
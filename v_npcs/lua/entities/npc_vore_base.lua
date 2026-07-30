if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "drgbase_nextbot" -- DO NOT TOUCH (obviously)
ENT.PrintName = "Base Vore NPC"
ENT.Category = "Vore"

AddCSLuaFile("npc_modules/belly.lua")
AddCSLuaFile("npc_modules/weight_gain.lua")
AddCSLuaFile("npc_modules/faces.lua")
AddCSLuaFile("npc_modules/client.lua")
AddCSLuaFile("npc_modules/drgbase.lua")
include("npc_modules/belly.lua")
include("npc_modules/weight_gain.lua")
include("npc_modules/faces.lua")
include("npc_modules/drgbase.lua")

local global_burps = CreateConVar("vnpcs_burps", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})
local force_burps = CreateConVar("vnpcs_global_burps", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
local patrolling = CreateConVar("vnpcs_patrol_full", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED})

ENT.Models = {"models/player/Group01/female_01.mdl"} --all entries are model paths
ENT.SpawnHealth = 100
ENT.ModelScale = 1
ENT.ModelColor = Color(255,255,255)

--------[[VORE SETTINGS]]

ENT.ModNeeded = [["hello, set this to the workshop addon where you found the mod, if youre seeing this even if you have the addon, either your model doesnt have bones or your directory isn't correct. : ) "]]

ENT.Belly_Offset = Vector(0, 1, 0)
ENT.Belly_Angles = Angle(0, 90, 90)

ENT.BellyProperties = {
	BellyColor = Color(195,145,122), 
	DigestionStrength = 2,
	AbsorptionPower = 1.5,
	StruggleMultiplier = 1.25,
	MaxBaseSize = 0.5,
	BaseSize = 0,
	FatFoldsMaxSize = 1 --you can set this to zero to not have fat folds
}

ENT.VoreSounds = { --this is only 'human' sounds, belly sounds are different
	["big_burp"] = {
		"burps/burp1.wav",
		"burps/burp2.wav",
		"burps/burp3.wav",
		"burps/burp4.wav",
		"burps/burp6.wav",
		"burps/burp12.wav",
	},
	["small_burp"] = {
		"burps/burp7.wav",
		"burps/burp8.wav",
		"burps/burp9.wav",
		"burps/burp10.wav",
		"burps/burp11.wav",
		"burps/burp14.wav",
		"burps/burp15.wav",
		"burps/burp16.wav",
		"burps/burp17.wav",
		"burps/burp18.wav",
		"burps/burp19.wav",
		"burps/burp20.wav",
		"burps/burp21.wav",
		"burps/burp22.wav",
		"burps/burp23.wav",
	},
	["swallow"] = {
		"gulps/g1.wav",
		"gulps/g2.wav",
		"gulps/g3.wav",
		"gulps/g4.wav",
		"gulps/g5.wav",
		"gulps/g6.wav",
		"gulps/g7.wav",
		"gulps/g8.wav",
		"gulps/g9.wav",
		"gulps/g10.wav",
	}
}
ENT.VoreSoundPitch = 1
----------[[MECHANIC SETTINGS]]----------
ENT.VoreSettings = {}

ENT.VoreSettings.BurpsEnabled = true
ENT.VoreSettings.HasWeightGain = true
ENT.VoreSettings.WeightGainBones = {}
ENT.VoreSettings.WeightGainSettings = {}
ENT.VoreSettings.FlexFaces = { --default, based on hl2 flexes
    [0] = { -- Neutral (rest)
        ["right_puckerer"] = 0,
        ["left_puckerer"] = 0,
        ["right_stretcher"] = 0,
        ["left_stretcher"] = 0,
        ["right_mouth_drop"] = 0,
        ["left_mouth_drop"] = 0,
        ["right_corner_puller"] = 0,
        ["left_corner_puller"] = 0,
        ["jaw_drop"] = 0,
        ["jaw_sideways"] = 0.5,
        ["left_lid_closer"] = 0,
        ["mouth_sideways"] = 0.5,
		["blink"] = 0,

		["right_lid_tightener"] = 0,
		["right_lid_droop"] = 0,
		["left_lid_droop"] = 0,
		["right_inner_raiser"] = 0,
		["right_lowerer"] = 0,
		["left_inner_raiser"] = 0,
    },
    [1] = { -- Swallowing
        ["right_puckerer"] = 0,
        ["left_puckerer"] = 0,
        ["right_stretcher"] = 1,
        ["left_stretcher"] = 1,
        ["right_mouth_drop"] = 0.7,
        ["left_mouth_drop"] = 0.7,
        ["right_corner_puller"] = 0.7,
        ["left_corner_puller"] = 0.7,
        ["jaw_drop"] = 1.5,
        ["jaw_sideways"] = 0.5,
        ["left_lid_closer"] = 0,
        ["mouth_sideways"] = 0.5,
		["blink"] = 1,
    },
    [2] = { -- Digesting (reset most flexes)
        ["right_puckerer"] = 0,
        ["left_puckerer"] = 0,
        ["right_stretcher"] = 0,
        ["left_stretcher"] = 0,
        ["right_mouth_drop"] = 0,
        ["left_mouth_drop"] = 0,
        ["right_corner_puller"] = 0,
        ["left_corner_puller"] = 0,
        ["jaw_drop"] = 0,
        ["jaw_sideways"] = 0.5,
        ["mouth_sideways"] = 0.5,
        ["left_lid_closer"] = 0,
		["blink"] = 0,
		["right_inner_raiser"] = 0.5,
		["left_inner_raiser"] = 0.5,
		["right_lowerer"] = 0,
		["right_lid_droop"] = 0.8,
		["left_lid_droop"] = 0.8,
    },
    [3] = { -- Burping
        ["jaw_drop"] = 1.7,
        ["right_mouth_drop"] = 0.9,
    	["left_mouth_drop"] = 0.9,
		["jaw_sideways"] = 0.5,
		["left_lid_closer"] = 0.5,
        ["mouth_sideways"] = 0.5,
		["blink"] = 0,

		["right_lid_tightener"] = 1,
		["right_lid_droop"] = 1,
		["left_lid_droop"] = 1,
		["right_inner_raiser"] = 1,
		["right_lowerer"] = 1,
		["left_inner_raiser"] = 0,
    },
	[4] = { -- Glupping
		["mouth_sideways"] = 0.5,
		["blink"] = 1,
		["jaw_drop"] = 0,
	}
}

ENT.BoneScale = 1 --this is for weight gain
ENT.LookDistMulti = 1
ENT.VoreFlexLerpDuration = 1
ENT.CurrentFlexes = {}
ENT.CurrentFacialPhase = -1

ENT.PrintAnimations = false
ENT.Predator = true --dont change this
--ENT.SpineBone = "" --(REPLACE IF SPINE BONE IS DIFFERENT)

------------------------------------
-- AI --
ENT.SpotDuration = 20

ENT.RangeAttackRange = 0
ENT.MeleeAttackRange = 35
ENT.ReachEnemyRange = 10
ENT.AvoidEnemyRange = 0

ENT.UseWalkframes = true

ENT.IdleAnimation = ACT_HL2MP_IDLE
ENT.WalkAnimation = ACT_HL2MP_WALK
ENT.RunAnimation = ACT_HL2MP_RUN_FAST
ENT.JumpAnimation = ACT_HL2MP_JUMP_KNIFE
ENT.CrouchAnimation = ACT_HL2MP_IDLE_CROUCH
ENT.CrouchWalkAnimation = ACT_HL2MP_WALK_CROUCH


ENT.AttackAnimation = "seq_baton_swing"

ENT.WalkSpeed = 80
ENT.RunSpeed = 390

ENT.Speeds = {
	WalkSpeed = ENT.WalkSpeed,
	RunSpeed = ENT.RunSpeed,
	LungeSpeed = 600,
}

ENT.RunAnimRate = 1.5

ENT.Acceleration = 800
ENT.Deceleration = 800
ENT.JumpHeight = 100

ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.EyeOffset = Vector(0, 0, 0)
ENT.EyeAngle = Angle(0, 0, 0)

ENT.SightFOV = 260
ENT.SightRange = 400
ENT.StepHeight = 40
ENT.DeathDropHeight = 1000
ENT.MaxYawRate = 400

-- Climbing --
--[[
ENT.ClimbLedges = false 
ENT.ClimbProps = false 
ENT.ClimbLedgesMaxHeight = 400
ENT.ClimbLadders = true
ENT.ClimbSpeed = 100
ENT.ClimbUpAnimation = ACT_ZOMBIE_CLIMB_UP
ENT.ClimbOffset = Vector(-14, 0, 0)
]]

-----------[[POSSESION]]
ENT.PossessionEnabled = true
ENT.PossessionPrompt = true
ENT.PossessionMovement = POSSESSION_MOVE_8DIR
ENT.PossessionViews = {
	{
		offset = Vector(0, 0, 10),
		distance = 80
	},
	{
		offset = Vector(7.5, 0, 0),
		distance = 0,
		eyepos = true
	}
}

ENT.PossessionBinds = {
	[IN_JUMP] = {{
		coroutine = false,
		onkeydown = function(self)
			if not self:IsOnGround() then return end
			--self:EmitFootstep()
			self:Jump()
		end
	}},
	[IN_ATTACK] = {{
		coroutine = true,
		onkeydown = function(self)
			self:OnMeleeAttack()
		end
	}},
	[IN_DUCK] = {{
		coroutine = false,
		onkeypressed = function(self)
			self:SetCrouching(not self:IsCrouching())
		end
	}},
}

--[[HELPERS]]

local function GetRandomFromTable(tbl) --:string?
	if not tbl then return end
	if #tbl == 0 then return end --has to be an array not a dict

	return tbl[math.random(1, #tbl)]
end

--[[FUNCTIONS]]

function ENT:EatEntity(ent)
	if not IsValid(ent) or self.Swallowing or ent.Vored or self.Vored then return end
	if not ent:GetModel() or ent:GetClass():find("func") then return end

	local result = false

	self.Swallowing = true
	self:SetFacialExpression(1)

	print(ent, ent:GetClass()) --get rid of this one day
	
	if self.Belly:AddPrey(ent) then
		local swallow_sound = GetRandomFromTable(self.VoreSounds["swallow"])
		self:EmitSound(swallow_sound, 100, 100)

		timer.Simple(1, function()
			if self and IsValid(self) then
				self:SetFacialExpression(4)
			end
		end)

		timer.Simple(2, function()
			if self and IsValid(self) then
				self:SetFacialExpression(2)
			end
		end)

		if not patrolling:GetBool() then
			self:ClearPatrols()
		end

		self:PostEntityEaten(ent)
		result = true 
	end
	self.Swallowing = false
	self:SetEntityRelationship(ent, D_NU, 2)

	return result
end

function ENT:Burp(big)
	local enabled = global_burps:GetBool()
	if not enabled then return end

	if not force_burps:GetBool() then
		if not self.VoreSettings.BurpsEnabled then return end
	end

	local burp = ""
	if not big then				
		burp = GetRandomFromTable(self.VoreSounds["small_burp"])
		self:EmitSound(burp, 80, self.VoreSoundPitch * 100, 1.4)
	else
		burp = GetRandomFromTable(self.VoreSounds["big_burp"])
		self:EmitSound(burp, 80, self.VoreSoundPitch * 100, 1.4)
	end

	self:SetFacialExpression(3) -- Burp face
	local length = (big and 1.5 or 1.2)/self.VoreSoundPitch
    timer.Simple(length, function()
        if self and IsValid(self) then
			if self.Belly.DigestionPhase == 0 then
				self:SetFacialExpression(0) -- Normal face
			else
				self:SetFacialExpression(2) -- Digestion face
			end
        end
    end)
end

--HOOKS FOR CUSTOM NPCS--

function ENT:PostEntityEaten(ent) end
function ENT:PostInitalize() end
function ENT:PostThink() end
function ENT:OnWeightGain(scale) end
function ENT:OnBellyCreated(belly) end

------------

if SERVER then --setup functions
	function ENT:CustomInitialize()
		local anchor = self:GetBellyAnchor()
		if not anchor then return end

		self.Speeds.WalkSpeed = self.WalkSpeed 
		self.Speeds.RunSpeed = self.RunSpeed

		if self.PrintAnimations then
			for i,v in ipairs(self:GetSequenceList()) do
				print(v, self:GetSequenceActivityName(i), self:GetSequenceActivity(i))
			end
		end
		if self.GoPrintBodygroups then
			self:PrintBodygroups()
		end
		if self.PrintFlexes then
			for i=0, self:GetFlexNum() - 1 do
				print(self:GetFlexName(i))
			end
		end
		self:SetColor(self.ModelColor)
		self:UpdateRelations()

		if self.BodyGroups then
			for bodyGroup, value in pairs(self.BodyGroups) do
				local groupIndex = self:FindBodygroupByName(bodyGroup)
				self:SetBodygroup(groupIndex, value) --if you write bad code this will error
			end
		end
		
		self:SetupBelly(anchor)

		for i, walk in ipairs({
			self.RunAnimation,
			self.WalkAnimation
		}) do
			if type(walk) == "string" then 
				self:SequenceEvent(walk, {0.28, 0.78}, function(self) --this fucks up footsteps for possessing. fix it one day
					self:EmitFootstep()
				end)
				continue 
			end
			self:SequenceEvent(self:SelectRandomSequence(walk), {0.28, 0.78}, function(self) --this fucks up footsteps for possessing. fix it one day
				self:EmitFootstep()
			end)
		end

		self:AddAnimEvent(self.AttackAnimation, {15}, "_attack")
		self:SetFacialExpression(0)
		self:SetWeight(self.BoneScale)

		self:PostInitalize()
	end

	function ENT:CustomThink()
		self:SetBellyPosition() 
		if self.Belly then
			self.Belly:NPCThink()
		end
		self:UpdateFacialExpressions()
		self:CheckOpenDoors()

		self:PostThink() --hook
	end

	--[[
	downloading a model from the workshop without restarting the game will make precaching the model fuck it up and never load until you reset your game. so i just disabled it
	]]
	if ConVarExists("drgbase_precache_models") then
		local var = GetConVar("drgbase_precache_models")
		var:SetBool(false)
	end	
else
	include("npc_modules/client.lua")
end

-- DO NOT TOUCH --
AddCSLuaFile()
--DrGBase.AddNextbot(ENT)
if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Exoworo"
ENT.Category = "Vore"
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3458760980" -- <<<<<<<<<

--THIS IS THE MODEL!
ENT.Models = {"models/labirhin/pm_exoworo.mdl"}
ENT.SpawnHealth = 100

--BELLY VISUALS

ENT.Belly_Offset = Vector(4, 5, 0) 
ENT.Belly_Angles = Angle(0, 90, 90)

ENT.BellyProperties = {
	BellyColor = Color(255,255,255), --its a custom texture :P
	DigestionStrength = 2, --how fast digestion happens (dmg)
	AbsorptionPower = 1.5, --how fast absorption happens
	StruggleMultiplier = 1.25, --struggle animation size
	MaxBaseSize = 0.8, --max size for belly fat
	BaseSize = 0, --inital size when spawned in
	FatFoldsMaxSize = 2, --you can set this to zero to not have fat folds
	FatFoldsMulti = 2,

	BellyMaterial = "models/wormonlooker/belly/belly_exo", --can set own material
}
ENT.BellyObject = "ent_vore_belly" --can change belly mechanics, have to write own

ENT.WalkSpeed = 80
ENT.RunSpeed = 320

ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.EyeOffset = Vector(3, 0, 7)
ENT.EyeAngle = Angle(0, 0, 0)

ENT.SightFOV = 260
ENT.SightRange = 400

--PROBABLY CHANGE THESE! 
ENT.IdleAnimation = ACT_HL2MP_IDLE
ENT.WalkAnimation = ACT_HL2MP_WALK
ENT.RunAnimation = ACT_HL2MP_RUN
ENT.AttackAnimation = "seq_baton_swing"

--MECHANICS--
ENT.VoreSettings = {}
ENT.VoreSettings.BurpsEnabled = true
ENT.VoreSettings.HasWeightGain = true
ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 20,
		Multi = 12,
		Start = 5,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 20,
		Multi = 12,
		Start = 5,
		["Angle"] = Angle(0,1,0),
	} 
}

--ENT.PrintAnimations = true --debug
--[[
	USE THE DISPLAY INFO TOOL TO GET FACE FLEXES AND BODYGROUP CODENAMES
]]

ENT.VoreSettings.WeightGainBones = {
    "ValveBiped.Bip01_L_Thigh",
    "ValveBiped.Bip01_R_Thigh",

	"ValveBiped.Bip01_L_Calf",
	"ValveBiped.Bip01_R_Calf",

	"ValveBiped.Bip01_L_Forearm",
	"ValveBiped.Bip01_R_Forearm",

    "ValveBiped.Bip01_Pelvis",
    "ValveBiped.Bip01_Spine",
    "ValveBiped.Bip01_Spine1",

	"glut_l",
	"glut_r",
	
	"belly",

	"breast_l",
	"breast_r",
}

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxBoob = 0.95;
	MaxThigh = 1.1;
	MaxCalf = 1.1;
	MaxArm = 0.8;
    MaxWaist = 0.9;
    MaxSpine = 0.7;

	MaxBelly = 1.6;
	MaxGlut = 1.2;

	BoobMultiplier = 0.6;
	ThighMultiplier = 0.5;
	CalfMultiplier = 0.3;
	ArmMultiplier = 0.1;
    WaistMultiplier = 0.3;
    SpineMultiplier = 0.15;

	BellyMultiplier = 0.7;
	GlutMultiplier = 1;
}

ENT.VoreSettings.WeightGainDefiners = {
	["Belly"] = function(scale, max)
		return Vector(
			math.min(scale, 1.3),
			math.min(scale, max),
			math.min(scale, max * 1.1)
		)
	end,
	["Glut"] = function(scale, max)
		return Vector(
			math.min(scale, max),
			math.min(scale, max),
			math.min(scale, max)
		)
	end,
}

ENT.VoreSettings.FlexFaces = {
	[0] = { --rest
		["_bg_mouth"] = 0,
		["_bg_eye_l"] = 0,
		["_bg_eye_r"] = 0,
	},
	[1] = { --swallow
		["_bg_mouth"] = 11,
		["_bg_eye_l"] = 6,
		["_bg_eye_r"] = 6,
	},
	[2] = { --full
		["_bg_mouth"] = 3,
		["_bg_eye_l"] = 7,
		["_bg_eye_r"] = 7,
	},
	[3] = { --burp
		["_bg_mouth"] = 1,
		["_bg_eye_l"] = 4,
		["_bg_eye_r"] = 4,
	},
	[4] = { --final gulp
		["_bg_mouth"] = 4,
		["_bg_eye_l"] = 5,
		["_bg_eye_r"] = 5,
	},
}

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
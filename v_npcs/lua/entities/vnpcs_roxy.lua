if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Roxanne"
ENT.Category = "Vore"
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3134220059" -- <<<<<<<<<

--THIS IS THE MODEL!
ENT.Models = {"models/alvaroports/vrcroxy_pm.mdl"}
ENT.SpawnHealth = 100

ENT.BellyColor = Color(247,245,239)
ENT.Belly_Offset = Vector(-1, 2.5, 0)

ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.EyeOffset = Vector(0, 0, 3)
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

ENT.VoreSettings.DigestionStrength = 2
ENT.VoreSettings.AbsorptionSpeed = 1.5
ENT.VoreSettings.StruggleMultiplier = 1.2
ENT.VoreSettings.MaxBaseSize = 0.5

ENT.VoreSettings.BellyFloorModifier = 0.4
ENT.VoreSettings.HasWeightGain = true
ENT.BellyMaterial = "models/wormonlooker/belly/belly_painting"
ENT.VoreSettings.FatFoldsMaxSize = 0.5

ENT.Skins = 0

--ENT.GoPrintBodygroups = true --debug
--ENT.PrintAnimations = true --debug
--ENT.PrintFlexes = true --debug
--ENT.GoPrintBodygroups = true -- debug

ENT.BodyGroups = {
	Wings = 0,
}

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
	
	"Breast_L",
	"Breast_L.001",
	"Breast_L.002",

	"Breast_R",
	"Breast_R.001",
	"Breast_R.002",

	"Breast_L",
	"Breast_L.001",
	"Breast_L.002",

	"ButtProxy_L",
	"ButtProxy_L.001",

	"ButtProxy_R",
	"ButtProxy_R.001",
}

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxBreast = 1.0; --boobs are SUPER jacked up in this model
	MaxThigh = 1.2;
	MaxCalf = 1.1;
	MaxArm = 0.8;
    MaxWaist = 1.3;
    MaxSpine = 0.5;
	MaxButt = 1.5;

	BreastMultiplier = 0.6;
	ThighMultiplier = 0.5;
	CalfMultiplier = 0.3;
	ArmMultiplier = 0.1;
    WaistMultiplier = 0.3;
	ButtMultiplier = 0.4;
    SpineMultiplier = 0.15;
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 17,
		Multi = 7,
		Start = 7,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 17,
		Multi = 7,
		Start = 7,
		["Angle"] = Angle(0,1,0),
	} 
}

ENT.VoreSettings.WeightGainDefiners = {
	["Butt"] = function(value, max)
		return Vector(
			math.min(value, max),
			math.min(value * 1.3, max * 1.3),
			math.min(value, max * 1.2)
		)
	end,
	["Breast"] = function(value, max)
		return Vector(
			math.min(value, max),
			math.min(value, max * 2),
			math.min(value, max * 1.2)
		)
	end,
}

ENT.VoreSettings.FlexFaces = {
	[0] = { --rest
	
	},
	[1] = { --swallow
		Emote_Angry = 1,
	},
	[2] = { --full
		Emote_Intimate = 1,
	},
	[3] = { --burp
		Emote_Crazy = 1,
	},
	[4] = { --final gulp
		Emote_Happy = 1,
	},
}

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
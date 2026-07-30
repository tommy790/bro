if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Loona"
ENT.Category = "Vore"
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3423874004" -- <<<<<<<<<

--THIS IS THE MODEL!
ENT.Models = {"models/alvaroports/DogzeelaLoonaPM.mdl"}
ENT.SpawnHealth = 100

ENT._BellyColor = Color(195,190,190)
ENT.Belly_Offset = Vector(1.8, 1.1, 0)

ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.EyeOffset = Vector(0, 0, 2.5)
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

ENT.VoreSettings.BurpsEnabled = false

ENT.VoreSettings.DigestionStrength = 2
ENT.VoreSettings.AbsorptionSpeed = 1.5
ENT.VoreSettings.StruggleMultiplier = 1.2
ENT.VoreSettings.MaxBaseSize = 0.5

ENT.VoreSettings.BellyFloorModifier = 0.4
ENT.VoreSettings.HasWeightGain = true

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
	
	"DEF_BUTT.L",
	"DEF_BUTT.R",
	
	--"DEF_BREAST_A.L",
	"DEF_BREAST_B.L",

	--"DEF_BREAST_A.R",
	"DEF_BREAST_B.R",
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 18,
		Multi = 7,
		Start = 7,
		["Angle"] = Angle(0.5,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 18,
		Multi = 7,
		Start = 7,
		["Angle"] = Angle(-0.5,1,0),
	} 
}


ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxBreast = 1.9;
	MaxThigh = 1.2;
	MaxCalf = 1.1;
	MaxArm = 0.8;
    MaxWaist = 1.3;
    MaxSpine = 0.7;
	MaxButt = 2;

	BreastMultiplier = 0.6;
	ThighMultiplier = 0.5;
	CalfMultiplier = 0.3;
	ArmMultiplier = 0.1;
    WaistMultiplier = 0.3;
	ButtMultiplier = 0.4;
    SpineMultiplier = 0.15;
}

ENT.VoreSettings.WeightGainDefiners = {
	["Butt"] = function(value, max)
		return Vector(
			math.min(value, max),
			math.min(value * 1.1, max * 1.3),
			math.min(value, max * 1.2)
		)
	end,
	["Breast"] = function(value, max)
		return Vector(
			math.min(value, max),
			math.min(value, max * 1.3),
			math.min(value, max * 1.2)
		)
	end,
}


-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
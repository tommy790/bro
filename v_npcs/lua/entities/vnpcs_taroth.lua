if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Taroth"
ENT.Category = "Vore"
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3651261570" -- <<<<<<<<<

--THIS IS THE MODEL!
ENT.Models = {"models/ltusamodels_inc/kt_bom39/kt_player.mdl"}
ENT.SpawnHealth = 100
ENT.ModelScale = 1.1

ENT.BellyColor = Color(35,27,26)
ENT.Belly_Offset = Vector(1, 2.4, 0)

ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.EyeOffset = Vector(0, 0, 4)
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

--ENT.GoPrintBodygroups = true --debug
--ENT.PrintAnimations = true --debug
ENT.PrintFlexes = true --debug
--ENT.GoPrintBodygroups = true -- debug
ENT.VoreSettings.FatFoldsMaxSize = 1.3

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
	
	"Breast.L.001",
	"Breast.L.002",
	"Breast.L.003",
	"Breast.L.004",
	
	"Breast.R.001",
	"Breast.R.002",
	"Breast.R.003",
	"Breast.R.004",
	
	"Butt.L.001",
	"Butt.L.002",
	
	"Butt.R.001",
	"Butt.R.002",
}

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxBreast = 1.6;
	MaxThigh = 1.3;
	MaxCalf = 1.3;
	MaxArm = 0.8;
    MaxWaist = 1.3;
    MaxSpine = 0.7;

	BreastMultiplier = 0.5;
	ThighMultiplier = 0.5;
	CalfMultiplier = 0.3;
	ArmMultiplier = 0.1;
    WaistMultiplier = 0.3;
    SpineMultiplier = 0.15;
}

ENT.VoreSettings.WeightGainDefiners = {
	["Breast"] = function(value, max)
		return Vector(
			math.min(value,max),
			math.min(value * 1.3,max * 1.3),
			math.min(value,max)
		)
	end,
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 25,
		Multi = 8,
		Start = 9,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 25,
		Multi = 8,
		Start = 9,
		["Angle"] = Angle(0,1,0),
	} 
}

ENT.VoreSettings.FlexFaces = {
	[0] = { --rest
		FX_Smile = 0,
		FX_Ahe = 0,
		Blink = 0,
		FX_Happy = 0,
		FX_Worry = 0,
		FX_RollEye = 0,
	},
	[1] = { --swallow
		FX_Ahe = 1,
		Blink = 1.2,
		FX_Happy = 1,
		FX_Worry = 0,
		FX_Smile = 0,
		FX_RollEye = 0,
	},
	[2] = { --full
		FX_Smile = 1,
		FX_Happy = 0,
		FX_Ahe = 0,
		Blink = 0,
		FX_Worry = 0,
		FX_RollEye = 0,
	},
	[3] = { --burp
		FX_Smile = 0,
		FX_Worry = 1,
		FX_Ahe = 1,
		FX_Happy = 1,
		Blink = 0,
		FX_RollEye = 1,
	},
	[4] = { --final gulp
		FX_Smile = 0,
		FX_Ahe = 0,
		Blink = 1,
		FX_Happy = 0,
		FX_Worry = 0,
		FX_RollEye = 0,
	},
}

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
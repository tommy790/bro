if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "DW Noelle (DT Pack)"
ENT.Category = "Vore"

--THIS IS THE MODEL!
ENT.Models = {"models/CryptiaCurves/Deltarune/Stylized_Noelle_Holiday_Dark_World_PM.mdl"}
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3651268172"
ENT.SpawnHealth = 100

ENT.BellyColor = Color(176,123,137)
ENT.Belly_Offset = Vector(0, 1.6, 0)
ENT.EyeOffset = Vector(0, 0, 5)

ENT.SightFOV = 260
ENT.SightRange = 400


--PROBABLY CHANGE THESE! 
ENT.IdleAnimation = ACT_HL2MP_IDLE
ENT.WalkAnimation = ACT_HL2MP_WALK
ENT.RunAnimation = ACT_HL2MP_RUN
ENT.AttackAnimation = "seq_baton_swing"

ENT.VoreSettings = {}
ENT.VoreSettings.OnlyEatsEnemies = false
ENT.VoreSettings.EatsPlayers = true

ENT.VoreSettings.BurpsEnabled = true

ENT.VoreSettings.DigestionStrength = 3
ENT.VoreSettings.AbsorptionSpeed = 1.5
ENT.VoreSettings.StruggleMultiplier = 1.2
ENT.VoreSettings.BellyFloorModifier = 0.2

ENT.VoreSettings.HasWeightGain = true
ENT.BellyMaterial = "models/wormonlooker/belly/belly_painting" --celshaded belly hi
ENT.VoreSoundPitch = 1.1

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
	
	"Butt_R",
	"Butt1_R",

	"Butt_L",
	"Butt1_L",

	"Breast_R",
	"Breast1_R",

	"Breast_L",
	"Breast1_L",
}

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxBreast = 1.7;
	MaxThigh = 1.4;
	MaxCalf = 1.4;
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
			math.min(value, max * 1.4),
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

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 25,
		Multi = 7,
		Start = 9,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 25,
		Multi = 7,
		Start = 9,
		["Angle"] = Angle(0,1,0),
	} 
}


ENT.VoreSettings.FlexFaces = {
	[0] = { --rest
		
	},
	[1] = { --swallow
		blink = 1,
		mouthconfused = 1,
		eyebrowsangry = 1,
	},
	[2] = { --full
		eyeshalfclosed = 1,
		happy = 1,
	},
	[3] = { --burp
		pupilssmall = 1,
		mouthopen = 1,
		mouthoh = 0.6,
		eyessurprised = 1,
	},
	[4] = { --final gulp
		surprised = 1,
		surprised1 = 0.2
	},
}
-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
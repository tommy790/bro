if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Lovander"
ENT.Category = "Vore"
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3651262583"

--THIS IS THE MODEL!
ENT.Models = {"models/LTUSAMODELS_inc/lovander_bom39/lovander_player.mdl"}
ENT.SpawnHealth = 100

ENT.BellyColor = Color(248,247,243)
ENT.Belly_Offset = Vector(0, 1, 0)

--[[]]

ENT.SightFOV = 260
ENT.SightRange = 400


--PROBABLY CHANGE THESE! 
ENT.IdleAnimation = ACT_HL2MP_IDLE
ENT.WalkAnimation = ACT_HL2MP_WALK
ENT.RunAnimation = ACT_HL2MP_RUN
ENT.AttackAnimation = "seq_baton_swing"

ENT.VoreSettings = {}
ENT.BodyGroups = {
	["Clothes"] = 1
}
ENT.ModelScale = 1.2
ENT.VoreSettings.EatsPlayers = true

ENT.VoreSettings.BurpsEnabled = true

ENT.VoreSettings.DigestionStrength = 2
ENT.VoreSettings.AbsorptionSpeed = 1.5
ENT.VoreSettings.StruggleMultiplier = 1.2

ENT.VoreSettings.HasWeightGain = true
ENT.BellyMaterial = "models/wormonlooker/belly/belly_lovander"

ENT.EyeOffset = Vector(0, 0, 5)

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

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 29,
		Multi = 7,
		Start = 14,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 29,
		Multi = 7,
		Start = 14,
		["Angle"] = Angle(0,1,0),
	} 
}


ENT.VoreSettings.WeightGainBones = {
    "ValveBiped.Bip01_L_Thigh",
    "ValveBiped.Bip01_R_Thigh",

	"ValveBiped.Bip01_L_Calf",
	"ValveBiped.Bip01_R_Calf",

	"ValveBiped.Bip01_L_Forearm",
	"ValveBiped.Bip01_R_Forearm",
	"ValveBiped.Bip01_Spinebut",

    "ValveBiped.Bip01_Pelvis",
    "ValveBiped.Bip01_Spine",
    "ValveBiped.Bip01_Spine1",
	
	"Breast.L",
	"Breast.L.001",
	"Breast.L.002",

	"Breast.R",
	"Breast.R.001",
	"Breast.R.002",
	
	"Butt.L",
	"Butt.R",
}

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxBreast = 1.8;
	MaxThigh = 1.4;
	MaxCalf = 1.2;
	MaxArm = 0.8;
    MaxWaist = 1.2;
    MaxSpine = 0.7;

	BreastMultiplier = 0.6;
	ThighMultiplier = 0.5;
	CalfMultiplier = 0.3;
	ArmMultiplier = 0.1;
    WaistMultiplier = 0.3;
    SpineMultiplier = 0.15;
}

ENT.VoreSettings.WeightGainDefiners = {
	["Breast"] = function(value, max)
		return Vector(
			math.min(value, max),
			math.min(value * 1.2, max * 1.2),
			math.min(value, max)
		)
	end,
}

ENT.VoreSettings.FlexFaces = {
	[0] = {
		Nipple_ClothOn = 1;
		fx_naughty1 = 0,
		Blink = 0,
		fx_smile = 0,
		fx_happy = 0,
	},
	[1] = { -- first
		Nipple_ClothOn = 1;
		fx_naughty1 = 0,
		Blink = 1,
		fx_smile = 1,
		fx_happy = 0,
	},
	[2] = { --third
		Nipple_ClothOn = 1;
		fx_naughty1 = 0,
		Blink = 0.2,
		fx_smile = 0.7,
		fx_happy = 0,
	},
	[3] = { -- burp
		Nipple_ClothOn = 1;
		fx_naughty1 = 0,
		Blink = 1,
		fx_smile = 0,
		fx_happy = 1.5,
	},
	[4] = { -- second
		Nipple_ClothOn = 1;
		fx_naughty1 = 1,
		Blink = 0.2,
		fx_smile = 0,
		fx_happy = 0,
	},
}

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
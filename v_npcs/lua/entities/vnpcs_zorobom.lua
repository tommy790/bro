if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Zorobom"
ENT.Category = "Vore"

--THIS IS THE MODEL!
ENT.Models = {"models/ltusamodels_inc/zorobom_bom39/zoroark.mdl"}
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3651267620"
ENT.SpawnHealth = 100

ENT.BellyColor = Color(49,49,49)
ENT.Belly_Offset = Vector(1.5, 2, 0)
ENT.EyeOffset = Vector(0, 0, 5)

--[[]]

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
ENT.ModelScale = 1.25 -- i didnt realize this was on lol

ENT.VoreSettings.HasWeightGain = true
ENT.VoreSettings.FatFoldsMaxSize = 0.9

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

	"Butt.L.001",
	"Butt.R.001",
	"Breast.L.001",
	"Breast.R.001",
	"Breast.L.002",
	"Breast.R.002",
	"Breast.L.003",
	"Breast.R.003",
}

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxBreast = 2;
	MaxThigh = 0.9;
	MaxCalf = 1;
	MaxArm = 0.5;
    MaxWaist = 0.8;
    MaxSpine = 1.2;
	MaxButt = 6;

	ThighMultiplier = 0.5;
	CalfMultiplier = 0.5;
	ArmMultiplier = 0.1;
    WaistMultiplier = 0.3;
    SpineMultiplier = 0.15;
	ButtMultiplier = 1.2;
	BreastMultiplier = 0.5;
}

ENT.VoreSettings.WeightGainDefiners = { --If you want to define a bone that isn't apart of the base npc. Soft coding :)
	Butt = function(actual_scale, max)
		return Vector(
			math.min(actual_scale , max),
			math.min(actual_scale , max),
			math.min(actual_scale, max)
		)
	end,
	Breast = function(actual_scale, max)
		return Vector(
			math.min(actual_scale, max * 0.8),
			math.min(actual_scale, max * 1.2),
			math.min(actual_scale, max * 0.8)
		)
	end,
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 17,
		Multi = 8,
		Start = 11,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 17,
		Multi = 8,
		Start = 11,
		["Angle"] = Angle(0,1,0),
	} 
}

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Mr. Lycaon"
ENT.Category = "Vore"

--THIS IS THE MODEL!
ENT.Models = {"models/kapuyas/zenless_zone_zero/von_lycaon/zzz_von_lycaon_e_pm.mdl"}
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3459027575"
ENT.SpawnHealth = 100

ENT.BellyColor = Color(236,240,242)
ENT.Belly_Offset = Vector(4.7, 1, 0)
ENT.EyeOffset = Vector(0, 0, 4)


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

ENT.VoreSettings.DigestionStrength = 8
ENT.VoreSettings.AbsorptionSpeed = 2
ENT.VoreSettings.StruggleMultiplier = 1.4
ENT.VoreSettings.BellyFloorModifier = 0.5
ENT.ModelScale = 1.1

ENT.VoreSettings.HasWeightGain = true
ENT.BellyMaterial = "models/wormonlooker/belly/belly_celpainting"

ENT.VoreSettings.WeightGainBones = {
    "ValveBiped.Bip01_L_Thigh",
    "ValveBiped.Bip01_R_Thigh",

	"ValveBiped.Bip01_L_Calf",
	"ValveBiped.Bip01_R_Calf",

	"ValveBiped.Bip01_L_Forearm",
	"ValveBiped.Bip01_R_Forearm",

	"ValveBiped.Bip01_R_UpperArm",
	"ValveBiped.Bip01_L_UpperArm",

    "ValveBiped.Bip01_Pelvis",
    "ValveBiped.Bip01_Spine",
    "ValveBiped.Bip01_Spine1",
	"ValveBiped.Bip01_Spine4",
}


ENT.VoreSettings.WeightGainSettings = {
	MaxThigh = 1.2;
	MaxCalf = 1;
	MaxArm = 1.1;
	MaxSpine = 1.1;
    MaxWaist = 1.2;

	ThighMultiplier = 1;
	CalfMultiplier = 0.7;
	ArmMultiplier = 0.5;
	SpineMultiplier = 0.15;
	WaistMultiplier = 0.4;
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 11,
		Multi = 7,
		Start = 0,
		["Angle"] = Angle(0.5,1,-0.5),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 11,
		Multi = 7,
		Start = 0,
		["Angle"] = Angle(0,1,0),
	} 
}

ENT.VoreSettings.WeightGainDefiners = { --If you want to define a bone that isn't apart of the base npc. Soft coding :)
	Spine4 = function(actual_scale, max)
		return Vector(
			math.min(actual_scale, 1.2),
			math.min(actual_scale, max * 0.7),
			math.min(actual_scale, max * 0.8)
		)
	end,
}


-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
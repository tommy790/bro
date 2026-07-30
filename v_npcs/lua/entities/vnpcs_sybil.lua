if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Sybil"
ENT.Category = "Vore"

--THIS IS THE MODEL!
ENT.Models = {"models/alvaroports/sybilsunpriest.mdl"}
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3386980901"
ENT.SpawnHealth = 100

ENT._BellyColor = Color(150,150,150)
ENT.Belly_Offset = Vector(1.5, 2, 0)
ENT.EyeOffset = Vector(0, 0, 3)

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

ENT.VoreSettings.BurpsEnabled = false 

ENT.VoreSettings.DigestionStrength = 2
ENT.VoreSettings.AbsorptionSpeed = 1.5
ENT.VoreSettings.StruggleMultiplier = 1.2

ENT.VoreSettings.HasWeightGain = true
ENT.VoreSettings.FatFoldsMaxSize = 0.5

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
	
	"bip_butt_r",
	"bip_butt_l",
	
	"bip_breast_02_r",
	"bip_breast_02_l",
	"bip_breast_03_r",
	"bip_breast_03_l",
}

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxBoob = 0.7;
	MaxThigh = 1.2;
	MaxCalf = 0.95;
	MaxArm = 0.8;
    MaxWaist = 1.5;
    MaxSpine = 0.7;

	BoobMultiplier = 0.7;
	ThighMultiplier = 0.4;
	CalfMultiplier = 0.25;
	ArmMultiplier = 0.1;
    WaistMultiplier = 0.5;
    SpineMultiplier = 0.15;
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 21,
		Multi = 7,
		Start = 9,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 21,
		Multi = 7,
		Start = 9,
		["Angle"] = Angle(0,1,0),
	} 
}


-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
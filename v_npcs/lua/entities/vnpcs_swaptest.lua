if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "different belly test"
ENT.Category = "Vore"

ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3661383115"
ENT.Models = {"models/alyx.mdl"}

ENT.SpawnHealth = 100

ENT.Belly_Offset = Vector(-5, 3, 0)
ENT.BellyProperties = {
	BellyColor = Color(184,141,92), 
	DigestionStrength = 2,
	AbsorptionPower = 1.5,
	StruggleMultiplier = 1.0,
	MaxBaseSize = 0.5,
	BaseSize = 0,
	FatFoldsMaxSize = 1 --you can set this to zero to not have fat folds
}
ENT.BellyObject = "ent_fernkarry_belly" --this is the actual belly

ENT.IdleAnimation = ACT_IDLE
ENT.WalkAnimation = ACT_WALK
ENT.RunAnimation = ACT_RUN
ENT.JumpAnimation = ACT_JUMP
ENT.AttackAnimation = "swing"

ENT.VoreSettings = {}

ENT.VoreSettings.WeightGainBones = {
    "ValveBiped.Bip01_L_Breast0",
    "ValveBiped.Bip01_L_Breast1",
    "ValveBiped.Bip01_R_Breast0",
    "ValveBiped.Bip01_R_Breast1",

    "ValveBiped.Bip01_L_Thigh",
    "ValveBiped.Bip01_R_Thigh",

	"ValveBiped.Bip01_L_Calf",
	"ValveBiped.Bip01_R_Calf",

	"ValveBiped.Bip01_L_Forearm",
	"ValveBiped.Bip01_R_Forearm",
	"ValveBiped.Bip01_Spinebut",

    "ValveBiped.Bip01_Pelvis",
}

ENT.VoreSettings.WeightGainSettings = {
	MaxBoob = 1.5;
	MaxThigh = 2;
	MaxCalf = 1.7;
	MaxArm = 0.8;
    MaxWaist = 2;
    MaxSpine = 0.7;

	BoobMultiplier = 0.7;
	ThighMultiplier = 0.7;
	CalfMultiplier = 0.6;
	ArmMultiplier = 0.4;
    WaistMultiplier = 0.6;
    SpineMultiplier = 0.2;
}

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
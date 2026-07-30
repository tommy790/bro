if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)
ENT.PrintName = "Dr. Mossman"
ENT.Category = "Vore"

ENT.Models = {"models/mossman.mdl"}

ENT.Belly_Offset = Vector(-0.5, 3.6, 0)
ENT.BellyProperties = {
	BellyColor = Color(214,163,140), 
	DigestionStrength = 2,
	AbsorptionPower = 1.5,
	StruggleMultiplier = 1.25,
	MaxBaseSize = 0.5,
	BaseSize = 0,
	FatFoldsMaxSize = 0.6 --you can set this to zero to not have fat folds
}

ENT.IdleAnimation = ACT_IDLE
ENT.WalkAnimation = ACT_WALK
ENT.RunAnimation = ACT_RUN
ENT.JumpAnimation = ACT_JUMP
ENT.AttackAnimation = "swing"

ENT.VoreSettings = {}
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

	"ValveBiped.Bip01_Spine4",
}

ENT.VoreSettings.WeightGainSettings = {
	MaxThigh = 1.5;
	MaxCalf = 1.3;
	MaxArm = 1.1;
	MaxSpine = 1.1;
    MaxWaist = 1.3;
	MaxSpine4 = 2;

	ThighMultiplier = 1;
	CalfMultiplier = 0.7;
	ArmMultiplier = 0.5;
	SpineMultiplier = 0.2;
	WaistMultiplier = 0.4;
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 8,
		Multi = 5,
		Start = 0,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 8,
		Multi = 5,
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
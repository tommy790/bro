if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Alyx"
ENT.Category = "Vore"

ENT.Models = {"models/alyx.mdl"}
ENT.SpawnHealth = 100

ENT.BellyColor = Color(169,131,90)
ENT.Belly_Offset = Vector(0, 3.4, 0)
ENT.EyeOffset = Vector(0, 0, 4)


--[[]]

ENT.SightFOV = 260
ENT.SightRange = 400

ENT.IdleAnimation = ACT_IDLE
ENT.WalkAnimation = ACT_WALK
ENT.RunAnimation = ACT_RUN
ENT.JumpAnimation = ACT_JUMP
ENT.AttackAnimation = "swing"

ENT.VoreSettings = {}
ENT.VoreSettings.OnlyEatsEnemies = false
ENT.VoreSettings.EatsPlayers = true

ENT.VoreSettings.BurpsEnabled = true

ENT.VoreSettings.DigestionStrength = 3
ENT.VoreSettings.AbsorptionSpeed = 2
ENT.VoreSettings.StruggleMultiplier = 1.5

ENT.VoreSettings.HasWeightGain = true
ENT.VoreSettings.FatFoldsMaxSize = 0.3
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


ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.VoreSettings.FlexFaces = VNPC_FEMALE_FLEX_FACES

if CLIENT then
    function ENT:CustomHeadTurn(yaw, pitch, roll)
        return Angle(pitch * 0.8, -yaw * 0.9, roll * 0.5)
    end
end

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
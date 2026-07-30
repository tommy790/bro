if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Ben Bigger"
ENT.Category = "Vore"
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3294789154" -- <<<<<<<<<

--THIS IS THE MODEL!
ENT.Models = {"models/cyanblue/zzz/ben/ben_bigger.mdl"}
ENT.SpawnHealth = 200

ENT.BellyColor = Color(119,104,93)
ENT.Belly_Offset = Vector(13, 4, 0)

ENT.WalkSpeed = 80
ENT.RunSpeed = 270

ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.EyeOffset = Vector(1, 0, 7)
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
ENT.VoreSettings.MaxBaseSize = .67

ENT.VoreSettings.BellyFloorModifier = 0.3
ENT.VoreSettings.HasWeightGain = true
ENT.BellyMaterial = "models/wormonlooker/belly/belly_celpainting"
ENT.VoreSoundPitch = 0.9

ENT.VoreSettings.WeightGainBones = {
    "ValveBiped.Bip01_L_Thigh",
    "ValveBiped.Bip01_R_Thigh",

	"ValveBiped.Bip01_L_Calf",
	"ValveBiped.Bip01_R_Calf",

	"ValveBiped.Bip01_L_Forearm",
	"ValveBiped.Bip01_R_Forearm",

	"ValveBiped.Bip01_R_UpperArm",
	"ValveBiped.Bip01_L_UpperArm",

	"ValveBiped.Bip01_R_Clavicle",
	"ValveBiped.Bip01_L_Clavicle",

    "ValveBiped.Bip01_Pelvis",
    "ValveBiped.Bip01_Spine",
    "ValveBiped.Bip01_Spine1",
	"ValveBiped.Bip01_Spine2",
	"ValveBiped.Bip01_Spine4",
}


ENT.VoreSettings.WeightGainSettings = {
	MaxThigh = 1;
	MaxCalf = 1.1;
	MaxArm = 1.1;
	MaxSpine = 1.3;
    MaxPelvis = 1.5;
	MaxSpine = 1.5;
	MaxClavicle = 1.2,

	ThighMultiplier = 0.5;
	CalfMultiplier = 0.4;
	ArmMultiplier = 0.4;
	SpineMultiplier = 0.4;
	SpineMultiplier = 0.4;
	PelvisMultiplier = 0.4;
	ClavicleMultiplier = 0.4;
}

ENT.VoreSettings.WeightGainDefiners = { --If you want to define a bone that isn't apart of the base npc. Soft coding :)
	Spine = function(actual_scale, max)
		return Vector(
			math.min(actual_scale, 1),
			math.min(actual_scale, max * 1),
			math.min(actual_scale, max * 0.8)
		)
	end,
	Clavicle = function(actual_scale, max)
		return Vector(
			math.min(actual_scale, max * 1.2),
			math.min(actual_scale, 1.5),
			math.min(actual_scale, max * 1.1)
		)
	end,
	Pelvis = function(actual_scale, max)
		return Vector(
			math.min(actual_scale, 1.1),
			math.min(actual_scale, max),
			math.min(actual_scale, max * 1.1)
		)
	end,
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 15,
		Multi = 8,
		Start = 8,
		["Angle"] = Angle(0.5,1,-0.5),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 15,
		Multi = 8,
		Start = 8,
		["Angle"] = Angle(0,1,0),
	} 
}

ENT.VoreSettings.FlexFaces = {
        [0] = { -- Neutral (reset all flexes)

        },
        [1] = { -- Swallowing
			["Eye Close2"] = 1,
			["Mouth ↙↘ Ben"] = 1,
			
        },
        [2] = { -- Digesting (reset most flexes)
			["Eye Ball ↓"] = 1,
			["Eye Open↓"] = 1,
        },
        [3] = { -- Burping
			["Eye Ball No"] = 1,
        	["Mouth Aa3Shout"] = 1,
			["Mouth Laugh2 Ben"] = 0.8,
			["Mouth ↙↘ Ben"] = 1, --however did the flexes for this model im going to kill you IRL
        },
		[4] = { -- Glupping
			["Mouth Oo"] = 1,
			["Eye Ball ↑"] = 1,
		}
	}
-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
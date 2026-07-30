if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Amicus"
ENT.Category = "Vore"
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3593572453" -- <<<<<<<<<

--THIS IS THE MODEL!
ENT.Models = {"models/characters/adastra/amicus/Amicus.mdl"}
ENT.SpawnHealth = 100

ENT.BellyColor = Color(162,164,176)
ENT.Belly_Offset = Vector(-2.6, -0.2, 0)

ENT.WalkSpeed = 80
ENT.RunSpeed = 320

ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.EyeOffset = Vector(5, 0, 6)
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

ENT.VoreSettings.BellyFloorModifier = 0.3
ENT.VoreSettings.HasWeightGain = true

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
}


ENT.VoreSettings.WeightGainSettings = {
	MaxThigh = 1.2;
	MaxCalf = 1.1;
	MaxArm = 1.5;
	MaxSpine = 1.1;
    MaxWaist = 1.4;
	MaxSpine2 = 1.7;
	MaxClavicle = 1.5,

	ThighMultiplier = 0.7;
	CalfMultiplier = 0.6;
	ArmMultiplier = 0.5;
	SpineMultiplier = 0.15;
	Spine2Multiplier = 0.5;
	WaistMultiplier = 0.4;
	ClavicleMultiplier = 0.3;
}

ENT.VoreSettings.WeightGainDefiners = { --If you want to define a bone that isn't apart of the base npc. Soft coding :)
	Spine2 = function(actual_scale, max)
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
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 15,
		Multi = 6,
		Start = 3,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 15,
		Multi = 6,
		Start = 3,
		["Angle"] = Angle(0,1,0),
	} 
}

ENT.VoreSettings.FlexFaces = {
         [0] = { -- Neutral (reset all flexes)
          	
        },
        [1] = { -- Swallowing

        },
        [2] = { -- Digesting (reset most flexes)

        },
        [3] = { -- Burping
        	["Pupils Small"] = 1,
        },
		[4] = { -- Glupping
			
		}
	}
-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
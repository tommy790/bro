if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Hybrid"
ENT.Category = "Vore"

ENT.Models = {"models/n7legion/fortnite/hybrid_player_alt.mdl"}
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=1710765110"
ENT.SpawnHealth = 100

ENT._BellyColor = Color(20,23,24)
ENT.Belly_Offset = Vector(1, 5, 0)
ENT.EyeOffset = Vector(2, 0, 1)

--[[]]

ENT.SightFOV = 260
ENT.SightRange = 400


--PROBABLY CHANGE THESE! 
ENT.IdleAnimation = ACT_HL2MP_IDLE
ENT.WalkAnimation = ACT_HL2MP_WALK
ENT.RunAnimation = ACT_HL2MP_RUN_FAST
ENT.AttackAnimation = "seq_baton_swing"

ENT.VoreSettings = {}
ENT.VoreSettings.OnlyEatsEnemies = false
ENT.VoreSettings.EatsPlayers = true

ENT.VoreSettings.BurpsEnabled = true

ENT.VoreSettings.DigestionStrength = 8
ENT.VoreSettings.AbsorptionSpeed = 2
ENT.VoreSettings.StruggleMultiplier = 1.4
ENT.VoreSettings.BellyFloorModifier = 0.5

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
	"ValveBiped.Bip01_Spine4",
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 11,
		Multi = 9,
		Start = 0,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 11,
		Multi = 9,
		Start = 0,
		["Angle"] = Angle(0,1,0),
	} 
}

ENT.VoreSettings.WeightGainSettings = {
	MaxThigh = 1.4;
	MaxCalf = 1.3;
	MaxArm = 1.5;
	MaxSpine = 1.1;
    MaxWaist = 1.4;
	MaxSpine4 = 2.5;
	MaxClavicle = 2,

	ThighMultiplier = 1;
	CalfMultiplier = 0.7;
	ArmMultiplier = 0.5;
	SpineMultiplier = 0.15;
	WaistMultiplier = 0.4;
	ClavicleMultiplier = 0.3;
}

ENT.VoreSettings.WeightGainDefiners = { --If you want to define a bone that isn't apart of the base npc. Soft coding :)
	Spine4 = function(actual_scale, max)
		return Vector(
			math.min(actual_scale, 1),
			math.min(actual_scale, max * 0.7),
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

ENT.VoreSettings.FlexFaces = {
         [0] = { -- Neutral (reset all flexes)
          	["Lewd"] = 0;
			["Ou"] = 0;
			["Happy"] = 0;
			["Th"] = 0;
			["Kk"] = 0;
			["Aa"] = 0;
			["Pp"] = 0;
        },
        [1] = { -- Swallowing
          	["Lewd"] = 0;
			["Ou"] = 0;
			["Happy"] = 0;
			["Th"] = 0;
			["Kk"] = 0;
			["Aa"] = 0;
			["Pp"] = 1;
        },
        [2] = { -- Digesting (reset most flexes)
        	["Th"] = 1;
			["Ou"] = 0;
			["Happy"] = 0.25;
			["Kk"] = 0;
			["Aa"] = 0;
			["Pp"] = 0;
        },
        [3] = { -- Burping
        	["Lewd"] = 1;
			["Ou"] = 1;
			["Happy"] = 1;
			["Th"] = 0;
			["Kk"] = 0;
			["Aa"] = 3;
			["Pp"] = 0;
        },
		[4] = { -- Glupping
			["Lewd"] = 0;
			["Ou"] = 0;
			["Happy"] = 1;
			["Th"] = 0;
			["Kk"] = 0;
			["Aa"] = 0;
			["Pp"] = 0;
		}
	}

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
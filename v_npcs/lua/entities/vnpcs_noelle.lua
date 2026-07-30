if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Noelle"
ENT.Category = "Vore"

--THIS IS THE MODEL!
ENT.Models = {"models/deltarune/noelle/noelle.mdl"}
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=1776194467"
ENT.SpawnHealth = 100

ENT.BellyColor = Color(243,145,96)
ENT.Belly_Offset = Vector(4, 1, 0)
ENT.EyeOffset = Vector(5, 0, 10)

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

ENT.VoreSettings.DigestionStrength = 4
ENT.VoreSettings.AbsorptionSpeed = 2
ENT.VoreSettings.StruggleMultiplier = 1.4
ENT.VoreSettings.BellyFloorModifier = 3
ENT.ModelScale = 1.3
ENT.VoreSoundPitch = 1.1

ENT.VoreSettings.HasWeightGain = true
--ENT.PrintFlexes = true 

ENT.VoreSettings.WeightGainBones = {
    "ValveBiped.Bip01_L_Thigh",
    "ValveBiped.Bip01_R_Thigh",

	"ValveBiped.Bip01_L_Calf",
	"ValveBiped.Bip01_R_Calf",

	--"ValveBiped.Bip01_L_Forearm",
	--"ValveBiped.Bip01_R_Forearm",
	"ValveBiped.Bip01_Spinebut",

    "ValveBiped.Bip01_Pelvis",
    "ValveBiped.Bip01_Spine",
    "ValveBiped.Bip01_Spine1",

	"ValveBiped.Bip01_Spine4", --these are the boobs
	"Skirt3.L",
	"Skirt2.L",
	"Skirt1.L",
	"Skirt3.R",
	"Skirt2.R",
	"Skirt1.R",
}

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxThigh = 1.25;
	MaxCalf = 1.2;
	MaxArm = 0.5;
    MaxWaist = 1;
    MaxSpine = 1.7;
	MaxSkirt = 3.5;
	["MaxValveBiped.Bip01_Spine4"] = 1.7;

	ThighMultiplier = 0.5;
	CalfMultiplier = 0.3;
	ArmMultiplier = 0.1;
    WaistMultiplier = 0.3;
    SpineMultiplier = 0.15;
	SkirtMultiplier = 1;
	["ValveBiped.Bip01_Spine4Multiplier"] = 0.3;

}

ENT.VoreSettings.WeightGainDefiners = { --If you want to define a bone that isn't apart of the base npc. Soft coding :)
	Skirt = function(actual_scale, max)
		return Vector(
			math.min(actual_scale, max),
			math.min(1),
			math.min(actual_scale, max)
		)
	end,
	["ValveBiped.Bip01_Spine4"] = function(actual_scale, max) --you can also overwrite the bones with your own vector manipulation!
		return Vector(
			math.min(1 + actual_scale/4, max),
			math.min(actual_scale, max),
			math.min(1 + actual_scale/4, max)
		)
	end,
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 19,
		Multi = 6,
		Start = 7,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 19,
		Multi = 6,
		Start = 7,
		["Angle"] = Angle(1,1,0),
	} 
}


ENT.VoreSettings.FlexFaces = {
	 [0] = { -- Neutral (reset all flexes)
            ["mouthclose"] = 0,
			["mouthopen"] = 0,
			["eyesclosehappy"] = 0,
			["mouthsmall"] = 0,
			["eyesclose"] = 0,
			["pupilsdown"] = 0,
			["eyebrowsworried"] = 0,
			["pupilsup"] = 0,
        },
        [1] = { -- Swallowing
            ["mouthclose"] = 1,
			["mouthopen"] = 0,
            ["mouthopen"] = 0,
			["eyesclose"] = 1,
			["pupilsup"] = 0,
        },
        [2] = { -- Digesting (reset most flexes)
			["mouthopen"] = 0,
			["eyesclosehappy"] = 0,
			["mouthsmall"] = 0,
			["eyesclose"] = 0,
			["pupilsdown"] = 0.5,
			["mouthclose"] = 0.5,
			["eyebrowsworried"] = 0,
			["pupilsup"] = 0,
        },
        [3] = { -- Burping
            ["mouthopen"] = 1.1,
			["eyesclosehappy"] = 1,
			["mouthsmall"] = 1,
			["pupilsdown"] = 0,
			["eyesclose"] = 0,
			["pupilsup"] = 0,
        },
		[4] = { -- Glupping
			["mouthclose"] = 1,
			["mouthopen"] = 0,
            ["mouthopen"] = 0,
			["eyesclose"] = 0.7,
			["eyebrowsworried"] = 0.6,
			["pupilsup"] = 0.4,
		}
}


-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
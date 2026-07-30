if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Ralsei"
ENT.Category = "Vore"

--THIS IS THE MODEL!
ENT.Models = {"models/kapuyas/deltarune/ralsei/bluegua/dr_ralsei_e_pm.mdl"}
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3467128951"
ENT.SpawnHealth = 100

ENT.BellyColor = Color(231,214,214)
ENT.Belly_Offset = Vector(8, 2.5, 0)
ENT.EyeOffset = Vector(0.5, 0, 8)

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
ENT.VoreSettings.BellyFloorModifier = 1

ENT.VoreSettings.HasWeightGain = true
ENT.BellyMaterial = "models/wormonlooker/belly/belly_celshaded" --celshaded belly hi
ENT.VoreSoundPitch = 1.2

ENT.BodyGroups = {
	["uppergarments"] =  1,
}
ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 25,
		Multi = 8,
		Start = 7,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 25,
		Multi = 8,
		Start = 7,
		["Angle"] = Angle(0,1,0),
	} 
}

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

	"Skirt3.L",
	"Skirt2.L",
	"Skirt1.L",
	"Skirt3.R",
	"Skirt2.R",
	"Skirt1.R",
}

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxThigh = 1.5;
	MaxCalf = 1.1;
	MaxArm = 0.5;
    MaxWaist = 1.5;
    MaxSpine = 1.7;
	MaxSkirt = 3.5;
	["MaxValveBiped.Bip01_Spine4"] = 1.7;

	ThighMultiplier = 0.5;
	CalfMultiplier = 0.3;
	ArmMultiplier = 0.5;
    WaistMultiplier = 0.3;
    SpineMultiplier = 0.15;
	SkirtMultiplier = 1;

}

ENT.VoreSettings.WeightGainDefiners = { --If you want to define a bone that isn't apart of the base npc. Soft coding :)
	Skirt = function(actual_scale, max)
		return Vector(
			math.min(actual_scale, max),
			math.min(1),
			math.min(actual_scale, max)
		)
	end,
	Pelvis = function(actual_scale, max)
		return Vector(
			math.min(actual_scale, max),
			math.min(actual_scale, max * 0.7),
			math.min(actual_scale, max * 1.2)
		)
	end,
}

ENT.VoreSettings.FlexFaces = {
         [0] = { -- Neutral (reset all flexes)
            ["right_puckerer"] = 0,
            ["left_puckerer"] = 0,
            ["right_stretcher"] = 0,
            ["left_stretcher"] = 0,
            ["right_mouth_drop"] = 0,
            ["left_mouth_drop"] = 0,
            ["right_corner_puller"] = 0,
            ["left_corner_puller"] = 0,
            ["jaw_drop"] = 0,
            ["jaw_sideways"] = 0.5,
            ["left_lid_closer"] = 0,
            ["mouth_sideways"] = 0.5,
			["Blush"] = 0,
			["MouthSmile"] = 0,
        },
        [1] = { -- Swallowing
            ["right_puckerer"] = 0,
            ["left_puckerer"] = 0,
            ["right_stretcher"] = 1,
            ["left_stretcher"] = 1,
            ["right_mouth_drop"] = 0.7,
            ["left_mouth_drop"] = 0.7,
            ["right_corner_puller"] = 0.7,
            ["left_corner_puller"] = 0.7,
            ["jaw_drop"] = 1,
            ["jaw_sideways"] = 0.5,
            ["left_lid_closer"] = 0,
            ["mouth_sideways"] = 0.5,
			["Blush"] = 1,
        },
        [2] = { -- Digesting (reset most flexes)
            ["right_puckerer"] = 0,
            ["left_puckerer"] = 0,
            ["right_stretcher"] = 0,
            ["left_stretcher"] = 0,
            ["right_mouth_drop"] = 0,
            ["left_mouth_drop"] = 0,
            ["right_corner_puller"] = 0,
            ["left_corner_puller"] = 0,
            ["jaw_drop"] = 0,
            ["jaw_sideways"] = 0.5,
            ["mouth_sideways"] = 0.5,
            ["left_lid_closer"] = 0,
			["Blush"] = 1,
			["MouthSmile"] = 1,
        },
        [3] = { -- Burping
            ["jaw_drop"] = 1.1,
            ["right_mouth_drop"] = 0.7,
            ["left_mouth_drop"] = 0.7,
            ["jaw_sideways"] = 0.5,
            ["left_lid_closer"] = 0.5,
            ["mouth_sideways"] = 0.5,
			["Blush"] = 1,
			["MouthSmile"] = 0,
        },
		[4] = { -- Glupping
			["mouth_sideways"] = 0.5,
			["Blush"] = 1,
		}
	}


-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
if not DrGBase then return end -- return if DrGBase isn't installed

ENT.Base = "npc_vore_base" -- DO NOT TOUCH

ENT.PrintName = "Template" --< Name of NPC
ENT.Category = "Vore" --< Where it's placed in the spawnlist
ENT.ModNeeded = "PUT THE WORKSHOP MODEL LINK HERE!" --< Copy and paste the workshop link into here, make sure it still has quotation marks

--MODEL STUFF

ENT.Models = {"models/player/Group01/female_06.mdl"} --< Replace with path of model
ENT.SpawnHealth = 100

ENT.Skins = {0} --< Can change 0 to be a different skin
ENT.BodyGroups = {} 
--[[
	Dictionary of Bodygroup names, index is the name and the value is which

	EXAMPLE ===

	ENT.BodyGroups = {
		["Jacket"] = 1,
		["Sweater"] = 4,
		["Socks"] = 1,
	}

	===
]]
ENT.VoreSounds = { --this is only 'human' sounds, belly sounds are different
	["big_burp"] = {
		"burps/burp1.wav",
		"burps/burp2.wav",
		"burps/burp3.wav",
		"burps/burp4.wav",
		"burps/burp6.wav",
		"burps/burp12.wav",
	},
	["small_burp"] = {
		"burps/burp7.wav",
		"burps/burp8.wav",
		"burps/burp9.wav",
		"burps/burp10.wav",
		"burps/burp11.wav",
		"burps/burp14.wav",
		"burps/burp15.wav",
		"burps/burp16.wav",
		"burps/burp17.wav",
		"burps/burp18.wav",
		"burps/burp19.wav",
		"burps/burp20.wav",
		"burps/burp21.wav",
		"burps/burp22.wav",
		"burps/burp23.wav",
	},
	["swallow"] = {
		"gulps/g1.wav",
		"gulps/g2.wav",
		"gulps/g3.wav",
		"gulps/g4.wav",
		"gulps/g5.wav",
		"gulps/g6.wav",
		"gulps/g7.wav",
		"gulps/g8.wav",
		"gulps/g9.wav",
		"gulps/g10.wav",
	}
}
ENT.VoreSoundPitch = 1 --This affects the pitch of all sounds listed above. 
-- 1 > is lower pitched, < 1 is higher pitched. 

ENT.EyeBone = "ValveBiped.Bip01_Head1" --< Change if not a basic ValveBiped model
ENT.EyeOffset = Vector(0, 0, 0) --< Adjust to fit more with eyes, check this value via possession.
ENT.EyeAngle = Angle(0, 0, 0)
--ENT.SpineBone = "" --< Replace and uncomment with a bone name if the NPC couldn't find a proper anchor for the belly.

--BELLY VISUALS

ENT.Belly_Offset = Vector(-1, 1, 0) --< How the belly is placed on the model, updates in real time when file is saved.
ENT.Belly_Angles = Angle(0, 90, 90) --< How the belly is rotated on the model, updates in real time when file is saved.

ENT.BellyProperties = {
	BellyColor = Color(255,255,255), --< Replaces color of belly, uses RGB 
	DigestionStrength = 2, --< Digestion damage
	AbsorptionPower = 1.5, --< Absorption damage/strength
	MaxBaseSize = 0.5, --< Max size for Belly fat
	BaseSize = 0, --< Inital belly size when spawned in
	FatFoldsMaxSize = 1, --< Fat folds max size (Fat folds are at the origin of the belly model)
	StopClipFix = false, --< Stops the clipping prevention.
	--BellyMaterial = "models/wormonlooker/belly/belly_celshaded", --< Put specific Material path
}
--ENT.BellyObject = "ent_vore_belly" --< Put name of belly object

ENT.WalkSpeed = 80
ENT.RunSpeed = 320

ENT.SightFOV = 260
ENT.SightRange = 400

--PROBABLY CHANGE THESE! 
ENT.IdleAnimation = ACT_HL2MP_IDLE 
ENT.WalkAnimation = ACT_HL2MP_WALK
ENT.RunAnimation = ACT_HL2MP_RUN
ENT.AttackAnimation = "seq_baton_swing"

--ENT.PrintAnimations = true --< Uncomment and look at the console to see all animations

--< USE THE DISPLAY INFO TOOL TO GET FACE FLEXES AND BODYGROUP CODENAMES

--MECHANICS--
ENT.VoreSettings = {}
ENT.VoreSettings.BurpsEnabled = true
ENT.VoreSettings.HasWeightGain = true

ENT.VoreSettings.WeightGainBones = {
    "ValveBiped.Bip01_L_Thigh",
    "ValveBiped.Bip01_R_Thigh",

	"ValveBiped.Bip01_L_Calf",
	"ValveBiped.Bip01_R_Calf",

	"ValveBiped.Bip01_L_Forearm",
	"ValveBiped.Bip01_R_Forearm",

    "ValveBiped.Bip01_Pelvis",
    "ValveBiped.Bip01_Spine",
    "ValveBiped.Bip01_Spine1",
} --< Put the name of the bones that you want to be affected by weight gain

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxBoob = 1.7;
	MaxThigh = 1.2;
	MaxCalf = 1.1;
	MaxArm = 0.8;
    MaxWaist = 1.3;
    MaxSpine = 0.7;

	BoobMultiplier = 0.6;
	ThighMultiplier = 0.5;
	CalfMultiplier = 0.3;
	ArmMultiplier = 0.1;
    WaistMultiplier = 0.3;
    SpineMultiplier = 0.15;
} 
--[[
	Default indenities are "Boob", "Thigh", "Calf", "Arm", "Waist", "Spine", and "Unknown"
	Each identity has a Max(Identity) and a (Identity)Multiplier
	
	Max(Identity) is the maximum amount of weight before the bone stops being affected
	(Identity)Multiplier is the slope of how quickly the bone is affected by weight
]]

ENT.VoreSettings.WeightGainDefiners = {} 
--[[ 
	Can create an identity for weight gain.
	Identity name will have to be in the names of the bones that you want to adjust.
	The value of the key will be a function, the arguments are the 'current scale' and the 'max' from weight gain settings; both numbers.
	That function has to return a Vector that will adjust the scale of the bone.

	EXAMPLE ===

	ENT.VoreSettings.WeightGainDefiners = {
		["Breast"] = function(actual_scale, max)
			return Vector(
				math.min(actual_scale, max * 0.8),
				math.min(actual_scale, max * 1.2),
				math.min(actual_scale, max * 0.8)
			)
		end,
	}

	====

	This identity can be used in WeightGainSettings
]]

ENT.VoreSettings.FlexFaces = {
	[0] = { --Rest (0) Default face
	
	},
	[1] = { --Swallow (1) Inital swallowing face when eating
	
	},
	[2] = { --Full (3) Rest face when digesting and absorbing 
	
	},
	[3] = { --Burp (4) Used when burping
	
	},
	[4] = { --Gulp (2) 2nd part of swallowing face
	
	},
}
--[[
	Make faces using the Face Poser.
	Names from the Face Poser aren't correct, so use the Display Info tool to get the proper codenames for the flexes.

	EXAMPLE ===

	ENT.VoreSettings.FlexFaces = {
		[0] = {
		
		},
		[1] = {
			["Emote_Angry"] = 1,
		},
		[2] = {
			["Emote_Intimate"] = 1,
		},
		[3] = {
			["Emote_Crazy"] = 1,
		},
		[4] = {
			["Emote_Happy"] = 1,
		},
	}

	===

	If a bone is in a phase but isn't in another, the flex will automatically go back to zero.
	
	If the index starts with "_bg_", than it will try to set a bodygroup with that name to that value. EXAMPLE -> (["_bg_mouth"] = 1) the bodygroup itself is called "mouth".
	If the index is "_set_skin_", the model skin will be set to the value specified.
	Advanced only. A function can also be used, the function will be called and if that function returns another function, whenever the facial phase is changed, that function will be called.

	EXAMPLE ===

	["test"] = function()
		print("Hello!")
		return function()
			print("Goodbye!")
		end
	end,

	===
]]
ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 8, --< Max Angle
		Multi = 5, --< The slope of the angle changing
		Start = 0, --< Inital Angle
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 8,
		Multi = 5,
		Start = 0,
		["Angle"] = Angle(0,1,0),
	} 
}
--[[
	BoneOffsets is to help with arms clipping into the model initially and during weight gain
	If no weight gain is implemented, set "Multi" to zero or just delete it.

	A custom function can be set.
	EXAMPLE ===

	["bone_name"] = {
		Max = 8,
		Multi = 5,
		Start = 0,
		["Angle"] = Angle(0,1,0),
		Custom = function(offset_info, _bonescale, self)
			local offset = math.min(offset_info.Start + (_bonescale - 1) * offset_info.Multi, offset_info.Max)
			return offset_info.Angle * offset
		end,
	}

	===
]]

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Shadow Ralesi (DT Pack)"
ENT.Category = "Vore"

--THIS IS THE MODEL!
ENT.Models = {"models/ltusamodels_inc/ralsei_cryptia/ralseishd_player.mdl"}
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3651268649"
ENT.SpawnHealth = 100

ENT._BellyColor = Color(23,1,23)
ENT.Belly_Offset = Vector(-0.5, 1.5, 0)
ENT.EyeOffset = Vector(2, 0, 5)

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
ENT.VoreSettings.BellyFloorModifier = 0.4
ENT.BellyMaterial = "models/wormonlooker/belly/belly_celshaded2" --celshaded belly hi
ENT.VoreSoundPitch = 1.2

ENT.Skins = 1

ENT.BodyGroups = {
	["Socks"] = 1,
	["Hat"] = 1,
	["Flares"] = 1,
	["Shorts"] = 3,
	["Scarf"] = 1,
	["Sweater"] = 1,
}

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
	
	"Butt.R",
	"Butt1.R",

	"Butt.L",
	"Butt1.L",
}

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxThigh = 1;
	MaxCalf = 1.2;
	MaxArm = 0.8;
    MaxWaist = 1.2;
    MaxSpine = 1;
	MaxButt = 1.5;

	ThighMultiplier = 0.4;
	CalfMultiplier = 0.3;
	ArmMultiplier = 0.1;
    WaistMultiplier = 0.3;
	ButtMultiplier = 0.3;
    SpineMultiplier = 0.15;
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 24,
		Multi = 8,
		Start = 13,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 24,
		Multi = 8,
		Start = 13,
		["Angle"] = Angle(0,1,0),
	} 
}

ENT.VoreSettings.WeightGainDefiners = {
	["Butt"] = function(value, max)
		return Vector(
			math.min(value, max),
			math.min(value, max * 1.3),
			math.min(value, max * 1.2)
		)
	end,
}

ENT.VoreSettings.FlexFaces = {
	[0] = { --rest
		JacketON = 1,
		SweaterON = 1,
		SocksON = 1,
	},
	[1] = { --swallow
		JacketON = 1,
		SweaterON = 1,
		SocksON = 1,
		--
		Eyes_Surprised = 1,
		Tears_ON = 1,
		Pupils_Tiny = 0.5,
		Eyebrows_Surprised = 1,
		Mouth_Oh = 0.7,
		Tongue = 0.7,
		Blush_ON = 1,
	},
	[2] = { --full
		JacketON = 1,
		SweaterON = 1,
		SocksON = 1,
		--
		Tongue1 = 1,
		Blush_ON = 1,
	},
	[3] = { --burp
		JacketON = 1,
		SweaterON = 1,
		SocksON = 1,
		--
		Eyes_Surprised = 1,
		Tears_ON = 1,
		Pupils_Tiny = 0.5,
		Eyebrows_Surprised = 1,
		Mouth_Oh = 0.7,
		Tongue = 0.7,
		Blush_ON = 1,
	},
	[4] = { --final gulp
		JacketON = 1,
		SweaterON = 1,
		SocksON = 1,
		--	
		Blush_ON = 1,
		Happy1 = 1,
	},
}

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
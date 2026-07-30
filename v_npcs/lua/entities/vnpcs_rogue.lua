if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Rogue The Bat"
ENT.Category = "Vore"
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3651576695" -- <<<<<<<<<

--THIS IS THE MODEL!
ENT.Models = {"models/ltusamodels_inc/Valz_Rouge/rouge_player.mdl"}
ENT.SpawnHealth = 100

ENT.BellyColor = Color(227,158,102)
ENT.Belly_Offset = Vector(-1, 1, 0)

ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.EyeOffset = Vector(0, 0, 0)
ENT.EyeAngle = Angle(0, 0, 0)
ENT.EyeOffset = Vector(0, 0, 5)

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


ENT.WalkSpeed = 60
ENT.RunSpeed = 1000
ENT.Acceleration = 200
ENT.Deceleration = 200


ENT.VoreSettings.BellyFloorModifier = 0.4
ENT.VoreSettings.HasWeightGain = true

ENT.Skins = 0

--ENT.GoPrintBodygroups = true --debug
--ENT.PrintAnimations = true --debug
--ENT.PrintFlexes = true --debug
--ENT.GoPrintBodygroups = true -- debug

ENT.BodyGroups = {
	Wings = 0,
}

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
	
	"c_breast_01.l",
	"c_breast_02.l",
	"c_breast_03.l",
	"c_breast_04.l",
	"c_breast_05.l",
	"c_breast_06.l",
	
	"c_breast_01.r",
	"c_breast_02.r",
	"c_breast_03.r",
	"c_breast_04.r",
	"c_breast_05.r",
	"c_breast_06.r",
	
	"c_butt_01_dupli_001.l",
	"c_butt_02_dupli_001.l",
	"c_butt_03_dupli_001.l",
	
	"c_butt_01_dupli_001.r",
	"c_butt_02_dupli_001.r",
	"c_butt_03_dupli_001.r",
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 20,
		Multi = 7,
		Start = 10,
		["Angle"] = Angle(-0.5,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 20,
		Multi = 7,
		Start = 10,
		["Angle"] = Angle(-0.5,1,0),
	} 
}

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxBreast = 1.7;
	MaxThigh = 1.2;
	MaxCalf = 1.1;
	MaxArm = 0.8;
    MaxWaist = 1.3;
    MaxSpine = 0.7;
	MaxButt = 1.5;

	BreastMultiplier = 0.6;
	ThighMultiplier = 0.5;
	CalfMultiplier = 0.3;
	ArmMultiplier = 0.1;
    WaistMultiplier = 0.3;
	ButtMultiplier = 0.4;
    SpineMultiplier = 0.15;
}

ENT.VoreSettings.WeightGainDefiners = {
	["Butt"] = function(value, max)
		return Vector(
			math.min(value, max),
			math.min(value * 1.3, max * 1.3),
			math.min(value, max * 1.2)
		)
	end,
	["Breast"] = function(value, max)
		return Vector(
			math.min(value, max),
			math.min(value * 1.3, max * 1.3),
			math.min(value, max * 1.2)
		)
	end,
}

ENT.VoreSettings.FlexFaces = {
	[0] = { --rest
		EyeWoa = 0,
		MouthOh = 0,
		TongueOut = 0,
		MouthSmile = 0,
		Ahegao = 0,
		Blink = 0,
		SmileOpen = 0,
		EyeSmug = 0,
		GrinSmile = 0,
	},
	[1] = { --swallow
		EyeWoa = 0.7,
		MouthOh = 1.2,
		TongueOut = 0.2,
		MouthSmile = 1,
		Ahegao = 0,
		Blink = 0,
		SmileOpen = 0,
		EyeSmug = 0,
		GrinSmile = 0,
	},
	[2] = { --full
		EyeSmug = 1,
		GrinSmile = 0.5,
		Ahegao = 0,
		Blink = 0,
		MouthSmile = 0,
		SmileOpen = 0,
		EyeWoa = 0,
		MouthOh = 0,
		TongueOut = 0,
	},
	[3] = { --burp
		EyeWoa = 0.7,
		MouthOh = 1.2,
		TongueOut = 0.2,
		MouthSmile = 1,
		Ahegao = 0,
		Blink = 0,
		SmileOpen = 0,
		EyeSmug = 0,
		GrinSmile = 0,
	},
	[4] = { --final gulp
		Blink = 1,
		Ahegao = 0,
		MouthSmile = 0,
		SmileOpen = 0,
		EyeSmug = 0,
		GrinSmile = 0,
		EyeWoa = 0,
		MouthOh = 0,
		TongueOut = 0,
	},
}

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Pur Slime"
ENT.Category = "Vore"

--THIS IS THE MODEL!
ENT.Models = {"models/alvaroports/purslimepm.mdl"}
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3651587202"
ENT.SpawnHealth = 100
ENT.ModelScale = .5

ENT.Belly_Offset = Vector(0, 2.5, 0)
ENT.BellyProperties = {
	BellyColor = Color(165, 4, 189, 225), 
	DigestionStrength = 10,
	AbsorptionPower = 2,
	StruggleMultiplier = 1.25,
	MaxBaseSize = 0.5,
	FloorModifier = 0.2,
	BaseSize = 0,
	FatFoldsMaxSize = 1, --you can set this to zero to not have fat folds
	--BellyMaterial = "models/wormonlooker/belly/belly_celshaded",
}

ENT.EyeOffset = Vector(2, 0, 2)
ENT.BellyObject = "ent_grower_vore"

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
ENT.BellyObject = "ent_grower_vore"

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


    "Butt.L.001",
    "Butt.L.002",
    "Butt.L.003",
    "Butt.L.004",

    "Butt.R.001",
    "Butt.R.002",
    "Butt.R.003",
    "Butt.R.004",

    "Breast.L.001",
    "Breast.L.002",
    "Breast.L.003",
    "Breast.L.004",

    "Breast.R.001",
    "Breast.R.002",
    "Breast.R.003",
    "Breast.R.004",
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 18,
		Multi = 7,
		Start = 7,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 18,
		Multi = 7,
		Start = 7,
		["Angle"] = Angle(0,1,0),
	} 
}

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxBreast = 1;
	MaxThigh = 1.2;
	MaxCalf = 1.1;
	MaxArm = 0.8;
    MaxWaist = 1.1;
    MaxSpine = 0.7;
	MaxButt = 2;

	BreastMultiplier = 0.6;
	ThighMultiplier = 0.5;
	CalfMultiplier = 0.3;
	ArmMultiplier = 0.1;
    WaistMultiplier = 0.3;
	ButtMultiplier = 0.5;
    SpineMultiplier = 0.15;
}

ENT.VoreSettings.WeightGainDefiners = {
	["Butt"] = function(value, max)
		return Vector(
			math.min(value, max),
			math.min(value, max * 1.3),
			math.min(value, max * 1.2)
		)
	end,
	["Breast"] = function(value, max)
		return Vector(
			math.min(value, max * 1.6),
			math.min(value, max * 1.6),
			math.min(value, max * 1.6)
		)
	end,
}

ENT.VoreSettings.FlexFaces = {
	[0] = { --rest
	
	},
	[1] = { --swallow
        ["Cool"] = 1,
        ["Half_ClosedEyes"] = 0.75,
        ["Blink"] = 0.5,
	},
	[2] = { --full
        ["Hehe2"] = 0.7
	},
	[3] = { --burp
        ["e"] = 1,
        ["Blink_R"] = 0.4,
        ["Wow"] = 1,
        ["ou"] = 1,
        ["sil"] = 1,
	},
	[4] = { --final gulp
        ["Blink_Smile"] = 1
	},
}

function ENT:PostInitalize() 
    self.Belly.NPCScale = self.ModelScale
end

function ENT:OnBellyCreated(belly)
	belly:SetRenderMode(RENDERMODE_TRANSCOLOR)
end

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
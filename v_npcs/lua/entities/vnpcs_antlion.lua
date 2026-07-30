if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Antlion Guard"
ENT.Category = "Vore"
ENT.ModNeeded = "PUT THE MODEL LINK HERE!" -- <<<<<<<<<

--THIS IS THE MODEL!
ENT.Models = {"models/antlion_guard.mdl"}
ENT.SpawnHealth = 100

ENT.BellyColor = Color(85,79,56)
ENT.Belly_Offset = Vector(-3, 15, 0)

ENT.WalkSpeed = 120
ENT.RunSpeed = 400

ENT.EyeBone = "Antlion_Guard.spine3"
ENT.EyeOffset = Vector(10, 0, 0)
ENT.EyeAngle = Angle(0, 0, 0)

ENT.SightFOV = 260
ENT.SightRange = 400

--PROBABLY CHANGE THESE! 
ENT.IdleAnimation = ACT_IDLE
ENT.WalkAnimation = ACT_WALK
ENT.RunAnimation = "charge_loop"
ENT.AttackAnimation = "shove"

--MECHANICS--
ENT.VoreSettings = {}

ENT.VoreSettings.BurpsEnabled = true

ENT.VoreSettings.DigestionStrength = 2
ENT.VoreSettings.AbsorptionSpeed = 1.5
ENT.VoreSettings.StruggleMultiplier = 1.2
ENT.VoreSettings.MaxBaseSize = 0.5

ENT.VoreSettings.BellyFloorModifier = 0.4	
ENT.VoreSettings.HasWeightGain = true
ENT.VoreSettings.FatFoldsMaxSize = 1 --you can set this to zero to not have fat folds
--ENT.BellyMaterial = "models/wormonlooker/belly/belly_celshaded"
ENT.SpineBone = "Antlion_Guard.spine1"

ENT.PrintAnimations = true --debug
--[[USE DISPLAY INFO TO GET FACE FLEXES AND BODYGROUP CODENAMES]]
ENT.LookDistMulti = 2

ENT.VoreSettings.WeightGainBones = {
    "Antlion_Guard.leg1_R",
    "Antlion_Guard.leg2_R",

	"Antlion_Guard.leg1_L",
    "Antlion_Guard.leg2_L",

	"Antlion_Guard.pelvis",

	"Antlion_Guard.arm1_R",
	"Antlion_Guard.arm1_L",

	"Antlion_Guard.claw1_R",
	"Antlion_Guard.claw1_L",
	"Antlion_Guard.claw2_R",
	"Antlion_Guard.claw2_L",

	"Antlion_Guard.spine1"
}

ENT.VoreSettings.WeightGainSettings = { --Change this!
	MaxBoob = 1.7;
	MaxThigh = 1.2;
	MaxCalf = 1.1;
	MaxArm = 1;
    MaxWaist = 1.3;
    MaxSpine = 0.7;
	MaxUnknown = 1;

	BoobMultiplier = 0.6;
	ThighMultiplier = 0.5;
	CalfMultiplier = 0.3;
	ArmMultiplier = 0.2;
    WaistMultiplier = 0.3;
    SpineMultiplier = 0.15;
	UnknownMultiplier = 0.2;
}

ENT.VoreSettings.FatFoldsMaxSize = 1 --you can set this to zero to not have fat folds, or more to have the fat folds to be larger!

ENT.VoreSettings.WeightGainDefiners = {}
ENT.ModelScale = 0.9

ENT.VoreSettings.FlexFaces = {
	[0] = { --rest
	
	},
	[1] = { --swallow
	
	},
	[2] = { --full
	
	},
	[3] = { --burp
	
	},
	[4] = { --final gulp
	
	},
}

if CLIENT then
	function ENT:CustomHeadTurn(yaw, pitch, roll)
		return Angle(-pitch, yaw * 0.5, -roll)
	end
end

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
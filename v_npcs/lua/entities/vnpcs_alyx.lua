if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Classic Alyx"
ENT.Category = "Vore"

ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3661383115"
ENT.Models = {"models/tucket1/alyx.mdl"}
ENT.SpawnHealth = 100

ENT.BellyColor = Color(163,127,82)
ENT.Belly_Offset = Vector(0, 4.2, 0)

--[[]]

ENT.SightFOV = 260
ENT.SightRange = 400

ENT.WalkAnimation = ACT_HL2MP_WALK
ENT.AttackAnimation = "swing"

ENT.VoreSettings = {}
ENT.VoreSettings.OnlyEatsEnemies = false
ENT.VoreSettings.EatsPlayers = true

ENT.VoreSettings.BurpsEnabled = true

ENT.VoreSettings.DigestionStrength = 3
ENT.VoreSettings.AbsorptionSpeed = 1.5
ENT.VoreSettings.StruggleMultiplier = 1.5

ENT.VoreSettings.HasWeightGain = true
ENT.VoreSettings.FatFoldsMaxSize = 1

ENT.VoreSettings.WeightGainBones = {
    "ValveBiped.Bip01_L_Breast0",
    "ValveBiped.Bip01_L_Breast1",
    "ValveBiped.Bip01_R_Breast0",
    "ValveBiped.Bip01_R_Breast1",

    "ValveBiped.Bip01_L_Thigh",
    "ValveBiped.Bip01_R_Thigh",

	"ValveBiped.Bip01_L_Calf",
	"ValveBiped.Bip01_R_Calf",

	"ValveBiped.Bip01_L_Forearm",
	"ValveBiped.Bip01_R_Forearm",
	"ValveBiped.Bip01_Spinebut",

    "ValveBiped.Bip01_Pelvis",
}

ENT.VoreSettings.WeightGainSettings = {
	MaxBoob = 1.5;
	MaxThigh = 2;
	MaxCalf = 1.7;
	MaxArm = 0.8;
    MaxWaist = 2;
    MaxSpine = 0.7;

	BoobMultiplier = 0.7;
	ThighMultiplier = 0.7;
	CalfMultiplier = 0.6;
	ArmMultiplier = 0.4;
    WaistMultiplier = 0.6;
    SpineMultiplier = 0.2;
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 20,
		Multi = 7,
		Start = 2,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 20,
		Multi = 7,
		Start = 2,
		["Angle"] = Angle(0,1,0),
	} 
}

ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.VoreSettings.FlexFaces = VNPC_FEMALE_FLEX_FACES

if CLIENT then
    function ENT:CustomHeadTurn(yaw, pitch, roll)
        return Angle(pitch * 0.8, -yaw * 0.9, roll * 0.5)
    end
end

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
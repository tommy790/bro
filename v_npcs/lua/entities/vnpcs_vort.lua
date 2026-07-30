if not DrGBase then return end -- return if DrGBase isn't installed
ENT.Base = "npc_vore_base" -- DO NOT TOUCH (obviously)

ENT.PrintName = "Vortigaunt"
ENT.Category = "Vore"

ENT.Models = {"models/vortigaunt.mdl"}
ENT.SpawnHealth = 100

ENT.BellyColor = Color(96,86,65)
ENT.Belly_Offset = Vector(0, 2, 0)
ENT.EyeOffset = Vector(15, 0, -5)
	
--[[]]

ENT.SightFOV = 260
ENT.SightRange = 400

ENT.WalkAnimation = ACT_WALK
ENT.RunAnimation = ACT_RUN
ENT.IdleAnimation = ACT_IDLE
ENT.JumpAnimation = ACT_JUMP
ENT.AttackAnimation = "MeleeHigh1"

ENT.EyeBone = "ValveBiped.neck1"

ENT.VoreSettings = {}
ENT.VoreSettings.EatsPlayers = true

ENT.VoreSettings.BurpsEnabled = true

ENT.VoreSettings.DigestionStrength = 2
ENT.VoreSettings.AbsorptionSpeed = 1.5
ENT.VoreSettings.StruggleMultiplier = 1.3
ENT.VoreSettings.MaxBaseSize = 0.6
ENT.VoreSettings.BellyFloorModifier = 0.1

ENT.VoreSettings.HasWeightGain = true

ENT.VoreSettings.WeightGainBones = {
	"ValveBiped.leg_bone1_L",
	"ValveBiped.leg_bone1_R",

	"ValveBiped.leg_bone2_L",
	"ValveBiped.leg_bone2_R",

	"ValveBiped.leg_bone3_L",
	"ValveBiped.leg_bone3_R",

	"ValveBiped.hlp_ulna_R",
	"ValveBiped.hlp_ulna_L",

	"ValveBiped.arm1_L",
	"ValveBiped.arm1_R",
	"ValveBiped.arm2_L",
	"ValveBiped.arm2_R",

	"ValveBiped.spine1",
	"ValveBiped.hips",
}
ENT.VoreSettings.WeightGainSettings = {
	MaxBoob = 2;
	MaxThigh = 2;
	MaxCalf = 1.5;
	MaxArm = 0.8;

	BoobMultiplier = 1;
	ThighMultiplier = 1;
	CalfMultiplier = 0.7;
	ArmMultiplier = 0.5;
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.neck1"] = {
		Max = 65, --< Max Angle
		Multi = 1, --< The slope of the angle changing
		Start = 10, --< Inital Angle
		["Angle"] = Angle(0,-1,0),
		["Custom"] = function(info, _bonescale, self) --this is to just rotate the neck with the belly so no clipping happens, lots of hardcoded bullshit in npc_vore_base if you want to see why it doesnt overwrite the head turning
			local belly = self.Belly
			if not belly then return info.Angle * info.Start end
			local rotation = belly.RotationSpring and belly.RotationSpring.pos
			if not rotation then return info.Angle * info.Start end

			local offset = math.min(info.Start + (-rotation) * info.Multi, info.Max)
			return info.Angle * offset
		end
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


if not DrGBase then return end -- return if DrGBase isn't installed

ENT.Base = "npc_vore_base"
ENT.PrintName = "Bonfie"
ENT.Category = "Vore"
ENT.ModNeeded = "https://steamcommunity.com/sharedfiles/filedetails/?id=3518355325"

--MODEL STUFF
ENT.Models = {"models/pacagma/cryptiacurves/v2_playermodels/springbonnie_nsfw_player.mdl"}
ENT.SpawnHealth = 100
ENT.Belly_Offset = Vector(0, 5, 0)
ENT.Belly_Angles = Angle(0, 90, 90) 
ENT.BodyGroups = {
	["Blush"] = 1,
}

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

ENT.BellyProperties = {
	BellyColor = Color(191,150,15), --< Replaces color of belly, uses RGB 
	DigestionStrength = 2, --< Digestion damage
	AbsorptionPower = 1.5, --< Absorption damage/strength
	MaxBaseSize = 0.5, --< Max size for Belly fat
	BaseSize = 0, --< Inital belly size when spawned in
	FatFoldsMaxSize = 1, --< Fat folds max size (Fat folds are at the origin of the belly model)
	StopClipFix = false, --< Stops the clipping prevention.
	BellyMaterial = "models/wormonlooker/belly/belly_celpainted", --< Put specific Material path
}

ENT.WalkSpeed = 90
ENT.RunSpeed = 450
ENT.Acceleration = 1987
ENT.Deceleration = 1987
ENT.JumpHeight = 1000
ENT.StepHeight = 50
ENT.DeathDropHeight = 1000
ENT.ClimbLedges = true
ENT.ClimbProps = true
ENT.ClimbLedgesMaxHeight = 5000
ENT.ClimbLedgesMinHeight = 0
ENT.LedgeDetectionDistance = 40
ENT.ClimbLadders = true
ENT.ClimbLaddersUp = true
ENT.LaddersUpDistance = 20
ENT.ClimbLaddersUpMaxHeight = math.huge
ENT.ClimbLaddersUpMinHeight = 0
ENT.ClimbLaddersDown = true
ENT.LaddersDownDistance = 20
ENT.ClimbLaddersDownMaxHeight = math.huge
ENT.ClimbLaddersDownMinHeight = 0
ENT.ClimbSpeed = 250
ENT.ClimbUpAnimation = ACT_CLIMB_UP
ENT.ClimbDownAnimation = ACT_CLIMB_DOWN
ENT.ClimbAnimRate = 1
ENT.ClimbOffset = Vector(0, 0, 0)
ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.EyeOffset = Vector(0, 0, 0)
ENT.EyeAngle = Angle(0, 0, 0)
ENT.SightFOV = 260
ENT.SightRange = 700
ENT.HearingCoefficient = 3
ENT.SpotDuration = 8

ENT.IdleAnimation = ACT_HL2MP_IDLE
ENT.WalkAnimation = ACT_HL2MP_WALK
ENT.RunAnimation = ACT_HL2MP_RUN_FAST
ENT.AttackAnimation = "seq_baton_swing"

--MECHANICS--
ENT.VoreSettings = {}
ENT.VoreSettings.BurpsEnabled = true
ENT.VoreSettings.HasWeightGain = true
ENT.VoreSettings.WeightGainBones = {
    "ValveBiped.Bip01_L_Thigh.001",
    "ValveBiped.Bip01_R_Thigh.001",
	"ValveBiped.Bip01_L_Calf",
	"ValveBiped.Bip01_R_Calf",
	"ValveBiped.Bip01_L_Forearm",
	"ValveBiped.Bip01_R_Forearm",
    "ValveBiped.Bip01_Pelvis",
	"Breast.R",
	"Breast1.R",
	"Breast2.R",
	"Breast.L",
	"Breast1.L",
	"Breast2.L",
	"Butt.R",
	"Butt.L",
}

ENT.VoreSettings.WeightGainSettings = {
	MaxBoob = 1.1;
	MaxThigh = 0.8;
	MaxCalf = 0.8;
	MaxArm = 0.8;
    MaxWaist = 0.85;
    MaxSpine = 0.9;
	BoobMultiplier = 0.5;
	ThighMultiplier = 0.4;
	CalfMultiplier = 0.3;
	ArmMultiplier = 0.1;
    WaistMultiplier = 0.3;
    SpineMultiplier = 0.15;
}

ENT.VoreSettings.WeightGainDefiners = {
	["Butt"] = function(value, max)
		return Vector(
			math.min(value, max * 0.7),
			math.min(value, max * 0.6),
			math.min(value, max * 0.7)
		)
	end,
	["Breast"] = function(value, max)
		return Vector(
			math.min(value, max * 0.75),
			math.min(value, max * 0.7),
			math.min(value, max * 1)
		)
	end,
}

ENT.VoreSettings.FlexFaces = {
	[0] = {
		eyesangry = 1.2,
		eyeswide = 1,
		eyeshappy = 0.4,
		mouthsmirk = 1,
		eyebrowsdown = 0.11,
		eyebrowsangry = 0.5,
		eyebrowsstraight = 1,
	},
	[1] = { -- first
		eyesclosedhappy = 1.2,
		mouthopen = 0.56,
		mouthoh = 0.56,
		mouthsmile = 0.1,
		eyebrowsup = 0.2,
	},
	[2] = { --third
		eyesangry = 0.4,
		eyeswide = 1.3,
		eyeshappy = 0.5,
		mouthopen = 0.5,
		mouthstraight = -0.5,
		mouthsmile = 2,
		eyebrowsup = 0.3,
		eyebrowssurprised = 1,
		eyesangry = 1,
	},
	[3] = { -- burp
		eyesangry = 1.2,
		eyeswide = 1.5,
		mouthopen = 0.11,
		mouthoh = 1,
		eyebrowsup = 0.4,
		eyebrowssurprised = 1,
	},
	[4] = { -- second
		eyesclosedhappy = 0.55,
		mouthsmile = 1,
	},
}

ENT.VoreSettings.BoneOffsets = {
	["ValveBiped.Bip01_R_Clavicle"] = {
		Max = 8,
		Multi = 5,
		Start = 0,
		["Angle"] = Angle(0,1,0),
	},
	["ValveBiped.Bip01_L_Clavicle"] = {
		Max = 8,
		Multi = 5,
		Start = 0,
		["Angle"] = Angle(0,1,0),
	} 
}

ENT.DressList = {
	["HemSE01_L"] = {pos = Vector(0, 0, -6)},
	["HemSE02_L"] = {pos = Vector(0, 0, 0)},
	["HemSE03_L"] = {pos = Vector(0, 0, 0)},
	["HemBA21_L"] = {pos = Vector(0, 0, 0)},
	["HemBA11_L"] = {pos = Vector(0, 0, 0)},
	["Sweet_0_0"] = {pos = Vector(0, 0, 6.5)},
	["Sweet_5_0"] = {pos = Vector(0, 0, 0)},
	["Sweet_0_4"] = {pos = Vector(6, 0, 0)},
	["Sweet_5_4"] = {pos = Vector(0, 0, 0)},
	["Sweet_0_8"] = {pos = Vector(0, 0, -6)},
	["Sweet_4_8"] = {pos = Vector(0, 0, 0)},
	["Sweet_8_8"] = {pos = Vector(0, 0, 0)},
	["Sweet_0_11"] = {pos = Vector(-7, 0, 0)},
	["Sweet_4_11"] = {pos = Vector(0, 0, 0)},
	["Sweet_8_11"] = {pos = Vector(0, 0, 0)},
	["HemSD13_R"] = {pos = Vector(-6, 0, 0)},
	["HemSD14_R"] = {pos = Vector(0, 0, 0)}
}

ENT.TriggerBone = "ValveBiped.Bip01_Pelvis"
ENT.TriggerThreshold = Vector(1.0, 1.0, 1.0)
ENT.OffsetFullFactor = 1.5

local function LerpAngle(t, ang1, ang2)
	return Angle(
		Lerp(t, ang1.p, ang2.p),
		Lerp(t, ang1.y, ang2.y),
		Lerp(t, ang1.r, ang2.r)
	)
end

local AnimatedBoneList = {
	[0] = { -- rest
		["ValveBiped.Bip01_Head1"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
		},
		["ValveBiped.Bip01_R_UpperArm"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
		},
		["ValveBiped.Bip01_R_Forearm"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
		},
		["ValveBiped.Bip01_R_Hand"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
		},
		["ValveBiped.Bip01_L_UpperArm"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
		},
		["ValveBiped.Bip01_L_Forearm"] = {
 			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
		},
		["ValveBiped.Bip01_L_Hand"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
		},
		["EyesLeft"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
        },
		["EyesRight"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
        }
    },
	[1] = { -- swallow
		["ValveBiped.Bip01_Head1"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 10, 0)
		},
		["ValveBiped.Bip01_R_UpperArm"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(80, -10, 0)
		},
		["ValveBiped.Bip01_R_Forearm"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(25, -100, 50)
		},
		["ValveBiped.Bip01_R_Hand"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(30, -20, 20)
		},
		["ValveBiped.Bip01_L_UpperArm"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(-50, 20, 0)
		},
		["ValveBiped.Bip01_L_Forearm"] = {
 			pos = Vector(0, 0, 0),
			ang = Angle(-145, 40, -180)
		},
		["ValveBiped.Bip01_L_Hand"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(-15, -20, -30)
		},
		["EyesLeft"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
        },
		["EyesRight"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
        }
    },
	[2] = { -- full
		length = 1.0,
		keyframes = {
			[0.00] = {
                ["ValveBiped.Bip01_Head1"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(0, -20, 0)
                },
                ["ValveBiped.Bip01_R_UpperArm"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(10, -10, 0)
                },
                ["ValveBiped.Bip01_R_Forearm"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(155, 40, 150)
                },
                ["ValveBiped.Bip01_R_Hand"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(-10, -60, 20)
                },
                ["ValveBiped.Bip01_L_UpperArm"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(-10, -10, 0)
                },
                ["ValveBiped.Bip01_L_Forearm"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(-145, 40, -150)
                },
                ["ValveBiped.Bip01_L_Hand"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(5, -63, -15)
                },
                ["EyesLeft"] = {
                    pos = Vector(-0.7, 0, 0),
                    ang = Angle(0, 0, 0)
                },
                ["EyesRight"] = {
                    pos = Vector(-0.7, 0, 0),
                    ang = Angle(0, 0, 0)
                }
		    },
			[0.50] = {
                ["ValveBiped.Bip01_Head1"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(0, -20, 0)
                },
                ["ValveBiped.Bip01_R_UpperArm"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(10, -10, 0)
                },
                ["ValveBiped.Bip01_R_Forearm"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(155, 40, 150)
                },
                ["ValveBiped.Bip01_R_Hand"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(-10, -60, 20)
                },
                ["ValveBiped.Bip01_L_UpperArm"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(-10, -10, 0)
                },
                ["ValveBiped.Bip01_L_Forearm"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(-145, 40, -150)
                },
                ["ValveBiped.Bip01_L_Hand"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(5, -63, -15)
                },
                ["EyesLeft"] = {
                    pos = Vector(-0.7, 0, 0),
                    ang = Angle(0, 0, 0)
                },
                ["EyesRight"] = {
                    pos = Vector(-0.7, 0, 0),
                    ang = Angle(0, 0, 0)
                }
		    },
			[1.00] = {
                ["ValveBiped.Bip01_Head1"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(0, -20, 0)
                },
                ["ValveBiped.Bip01_R_UpperArm"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(10, -10, 0)
                },
                ["ValveBiped.Bip01_R_Forearm"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(155, 40, 150)
                },
                ["ValveBiped.Bip01_R_Hand"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(-10, -60, 20)
                },
                ["ValveBiped.Bip01_L_UpperArm"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(-10, -10, 0)
                },
                ["ValveBiped.Bip01_L_Forearm"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(-145, 40, -150)
                },
                ["ValveBiped.Bip01_L_Hand"] = {
                    pos = Vector(0, 0, 0),
                    ang = Angle(5, -63, -15)
                },
                ["EyesLeft"] = {
                    pos = Vector(-0.7, 0, 0),
                    ang = Angle(0, 0, 0)
                },
                ["EyesRight"] = {
                    pos = Vector(-0.7, 0, 0),
                    ang = Angle(0, 0, 0)
                }
	        }
        }
    },
	[3] = { -- burp
		["ValveBiped.Bip01_Head1"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 5, 0)
		},
		["ValveBiped.Bip01_R_UpperArm"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(10, -10, 0)
		},
		["ValveBiped.Bip01_R_Forearm"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(155, 30, 150)
		},
		["ValveBiped.Bip01_R_Hand"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(-10, 30, 0)
		},
		["ValveBiped.Bip01_L_UpperArm"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(-10, -10, 0)
		},
		["ValveBiped.Bip01_L_Forearm"] = {
 			pos = Vector(0, 0, 0),
			ang = Angle(-145, 30, -150)
		},
		["ValveBiped.Bip01_L_Hand"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(5, 30, 0)
		},
		["EyesLeft"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
        },
		["EyesRight"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
        }
    },
	[4] = { -- final gulp
		["ValveBiped.Bip01_Head1"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(-10, 0, 0)
		},
		["ValveBiped.Bip01_R_UpperArm"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(40, -50, 0)
		},
		["ValveBiped.Bip01_R_Forearm"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(5, -115, 0)
		},
		["ValveBiped.Bip01_R_Hand"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(35, 70, 30)
		},
		["ValveBiped.Bip01_L_UpperArm"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(-70, 20, 0)
		},
		["ValveBiped.Bip01_L_Forearm"] = {
 			pos = Vector(0, 0, 0),
			ang = Angle(-145, 40, -180)
		},
		["ValveBiped.Bip01_L_Hand"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, -40, 0)
		},
		["EyesLeft"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
        },
		["EyesRight"] = {
			pos = Vector(0, 0, 0),
			ang = Angle(0, 0, 0)
        }
	}
}

function ENT:CustomOnInitialize()
	self.BoneBlendState = {}
	self.LastFacialPhase = 0
	self.FacialPhaseStartTime = CurTime()
end

local function InterpolateKeyframes(keyframes, tNorm, boneName)
	local closestBefore, closestAfter = nil, nil
	for k,_ in pairs(keyframes) do
		if k <= tNorm then
			if (not closestBefore) or k > closestBefore then closestBefore = k end
        end
		if k >= tNorm then
			if (not closestAfter) or k < closestAfter then closestAfter = k end
		end
	end
	closestBefore = closestBefore or closestAfter
	closestAfter  = closestAfter  or closestBefore
	local frame1 = keyframes[closestBefore] or {}
	local frame2 = keyframes[closestAfter]  or {}
	local a = (closestAfter - closestBefore)
	local f = (a > 0) and ( (tNorm - closestBefore) / a ) or 0
	local b1 = frame1[boneName]
	local b2 = frame2[boneName]
	if not b1 and not b2 then
		return vector_origin, angle_zero
	end
	local pos1 = b1 and b1.pos or vector_origin
	local pos2 = b2 and b2.pos or pos1
	local ang1 = b1 and b1.ang or angle_zero
	local ang2 = b2 and b2.ang or ang1
	return LerpVector(f, pos1, pos2), LerpAngle(f, ang1, ang2)
end

function ENT:AnimatedBoneOffsets()
	if not self.BoneBlendState then
		self.BoneBlendState = {}
	end
	local phase = self:GetNWInt("FacialPhase", -1)
	local data = AnimatedBoneList[phase] or AnimatedBoneList[0]
	if phase ~= self.LastFacialPhase then
		self.FacialPhaseStartTime = CurTime()
		self.LastFacialPhase = phase
	end
	local boneCount = self:GetBoneCount()
	local speed = 5
	for i = 0, boneCount - 1 do
		local boneName = self:GetBoneName(i)
		if not boneName then continue end
		local tgtPos, tgtAng = vector_origin, angle_zero
		if data.keyframes and data.length then
			local elapsed = CurTime() - self.FacialPhaseStartTime
			local tNorm = elapsed / data.length
			tNorm = math.abs((tNorm % 2) - 1)
			tgtPos, tgtAng = InterpolateKeyframes(data.keyframes, tNorm, boneName)
		elseif data.pose or data[boneName] then
			local tgt = (data.pose and data.pose[boneName]) or data[boneName]
			if tgt then
				tgtPos = tgt.pos or vector_origin
				tgtAng = tgt.ang or angle_zero
			end
		end
		local cur = self.BoneBlendState[boneName]
		if not cur then
			cur = {pos = vector_origin, ang = angle_zero}
			self.BoneBlendState[boneName] = cur
		end
		cur.pos = LerpVector(FrameTime() * speed, cur.pos, tgtPos)
		cur.ang = LerpAngle(FrameTime() * speed, cur.ang, tgtAng)
		self:ManipulateBonePosition(i, cur.pos)
		self:ManipulateBoneAngles(i, cur.ang)
	end
end

function ENT:Think()
	if self.BaseClass.Think then
		self.BaseClass.Think(self)
	end
	self:AnimatedBoneOffsets()
end

AddCSLuaFile()
DrGBase.AddNextbot(ENT)

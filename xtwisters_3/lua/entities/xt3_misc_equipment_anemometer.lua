AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "XT3 Anemometer"

ENT.MaximumInteractDistance = 100
ENT.MaximumRenderingDistance = 400

ENT.CurrentlyExperiencedWindspeed = 0
ENT.MaximumExperiencedWindspeed = 0
ENT.LastDeployTime = 0

ENT.XT3DoNotApplyPhysics = false
ENT.XT3AnemometerDevice = true

ENT.Spawnable = true

function ENT:Initialize()
    self:SetModel("models/props_lab/powerbox02d.mdl")
    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
    self:DrawShadow(false)
    self:SetModelScale(1)
    self:SetMaterial("phoenix_storms/gear")
	self:SetColor(Color(255, 0, 0, 255))
    self:SetAngles(self:GetAngles() - Angle(90, 0, 0))
    
    local PhysicsObject = self:GetPhysicsObject()
    if PhysicsObject:IsValid() then PhysicsObject:Wake() end

    self:SetNW2Bool("XT3ProbeDeployed", false)
end

if SERVER then
    function ENT:Think()
        local MaximumWindVelocity, MaximumWindspeed = GetGlobalWindspeed(self:GetPos())
        
        self.CurrentlyExperiencedWindspeed = MaximumWindspeed
        self.MaximumExperiencedWindspeed = math.max(self.MaximumExperiencedWindspeed, MaximumWindspeed)

        self:SetNW2Float("CurrentlyExperiencedWindspeed", self.CurrentlyExperiencedWindspeed)
        self:SetNW2Float("MaximumExperiencedWindspeed", self.MaximumExperiencedWindspeed)

        self:NextThink(CurTime())
    end

    function ENT:Deploy()
        local DeployState = not self:GetNW2Bool("XT3ProbeDeployed", false)
        self:SetNW2Bool("XT3ProbeDeployed", DeployState)
        
        self.XT3DoNotApplyPhysics = DeployState

        local PhysicsObject = self:GetPhysicsObject()
        if PhysicsObject then  
            if DeployState then
                PhysicsObject:Sleep()
            else
                PhysicsObject:Wake()
            end
        end
    end
end

if CLIENT then
	function ENT:DrawTranslucent()
		self.CurrentlyExperiencedWindspeed = self:GetNW2Float("CurrentlyExperiencedWindspeed")
        self.MaximumExperiencedWindspeed = self:GetNW2Float("MaximumExperiencedWindspeed")

		self:DrawModel()

		local Player = LocalPlayer()
		if Player:IsValid() then 
            local PlayerPosition = Player:GetPos()
            local AnemometerPosition = self:GetPos()

            local DistanceFromPlayer = (AnemometerPosition - PlayerPosition):Length()
            if DistanceFromPlayer < self.MaximumRenderingDistance then  
                local CurrentExperiencedWindspeed = self.CurrentlyExperiencedWindspeed
                local MaximumExperiencedWindspeed = self.MaximumExperiencedWindspeed

                local TextPosition = AnemometerPosition + (VectorZAxis * 35)
                local EyeAngles = EyeAngles()
                EyeAngles:RotateAroundAxis(EyeAngles:Right(), 90)
                EyeAngles:RotateAroundAxis(EyeAngles:Up(), -90)

                local InstantaneousWindspeed = math.floor(CurrentExperiencedWindspeed * 1.333333333)
                local InstantaneousWindspeedMax = math.floor(MaximumExperiencedWindspeed * 1.333333333)

                CurrentExperiencedWindspeed = math.floor(CurrentExperiencedWindspeed)
                MaximumExperiencedWindspeed = math.floor(MaximumExperiencedWindspeed)

                cam.Start3D2D(TextPosition, EyeAngles, 0.25)
        
                    local TextColor = Color(189, 255, 255, 255)
                    local TextStrokeColor = Color(18, 26, 26, 300)

                    draw.SimpleTextOutlined("Current 3 Second Gust Windspeed : " .. CurrentExperiencedWindspeed .. " MPH", "XT3ProbeFont", 0, 0, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)
                    draw.SimpleTextOutlined("Maximum 3 Second Gust Windspeed : " .. MaximumExperiencedWindspeed .. " MPH", "XT3ProbeFont", 0, 64, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)

                    draw.SimpleTextOutlined("Current Instantaneous Windspeed : " .. InstantaneousWindspeed .. " MPH", "XT3ProbeFont", 0, 32, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)
                    draw.SimpleTextOutlined("Maximum Instantaneous Windspeed : " .. InstantaneousWindspeedMax .. " MPH", "XT3ProbeFont", 0, 96, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)
                    
                cam.End3D2D()

            end
        end
	end
end

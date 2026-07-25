AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "XT3 Barometer"

ENT.MaximumInteractDistance = 100
ENT.MaximumRenderingDistance = 400

ENT.LowestPressureDropped = 0
ENT.CurrentAtmosphericPressure = 0

ENT.LastDeployTime = 0

ENT.XT3DoNotApplyPhysics = false
ENT.XT3AnemometerDevice = true

ENT.Spawnable = true

function ENT:Initialize()
    self:SetModel("models/props_interiors/pot01a.mdl")
    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
    self:DrawShadow(false)
    self:SetModelScale(1)
    self:SetMaterial("phoenix_storms/dome")
	self:SetColor(Color(255, 0, 0, 255))

    local PhysicsObject = self:GetPhysicsObject()
    if PhysicsObject:IsValid() then PhysicsObject:Wake() end
   
   -- PhysicsObject:SetMass(250)
    self:SetNW2Bool("XT3ProbeDeployed", false)
end

if SERVER then
    function ENT:Think()
        local MaximumWindVelocity, MaximumWindspeed, LowestAtmosphericPressure, LowestPressureDropped = GetGlobalWindspeed(self:GetPos())

        self.CurrentAtmosphericPressure = LowestAtmosphericPressure
        self.LowestPressureDropped = math.max(self.LowestPressureDropped, LowestPressureDropped)

        self:SetNW2Float("CurrentAtmosphericPressure", self.CurrentAtmosphericPressure)
        self:SetNW2Float("LowestPressureDropped", self.LowestPressureDropped)

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
        self.LowestPressureDropped = self:GetNW2Float("LowestPressureDropped", self.LowestPressureDropped)
        self.CurrentAtmosphericPressure = self:GetNW2Float("CurrentAtmosphericPressure", self.CurrentAtmosphericPressure)
		self:DrawModel()

		local Player = LocalPlayer()
		if Player:IsValid() then 
            local PlayerPosition = Player:GetPos()
            local AnemometerPosition = self:GetPos()

            local DistanceFromPlayer = (AnemometerPosition - PlayerPosition):Length()
            if DistanceFromPlayer < self.MaximumRenderingDistance then  
                local CurrentAtmosphericPressure = math.floor(self.CurrentAtmosphericPressure)
                local LowestPressureDropped = self.LowestPressureDropped
                local LowestAtmosphericPressure = math.floor(XT3BaseAtmosphericPressure - LowestPressureDropped)
                LowestPressureDropped = math.ceil(LowestPressureDropped)

                local TextPosition = AnemometerPosition + (VectorZAxis * 35)
                local EyeAngles = EyeAngles()
                EyeAngles:RotateAroundAxis(EyeAngles:Right(), 90)
                EyeAngles:RotateAroundAxis(EyeAngles:Up(), -90)

                cam.Start3D2D(TextPosition, EyeAngles, 0.25)
                    local TextColor = Color(189, 255, 255, 255)
                    local TextStrokeColor = Color(18, 26, 26, 300)
                    local Offset = -100

                    draw.SimpleTextOutlined("Current Atmospheric Pressure : " .. CurrentAtmosphericPressure .. " hPa", "XT3ProbeFont", 0, Offset+128, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)
                    draw.SimpleTextOutlined("Lowest Atmospheric Pressure Drop : " .. LowestPressureDropped .. " hPa", "XT3ProbeFont", 0, Offset+160, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)
                    draw.SimpleTextOutlined("Lowest Atmospheric Pressure : " .. LowestAtmosphericPressure  .. " hPa", "XT3ProbeFont", 0, Offset+192, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)
                    
                cam.End3D2D()

            end
        end
	end
end

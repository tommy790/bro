AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "XT3 Probe"

ENT.MaximumInteractDistance = 100
ENT.MaximumRenderingDistance = 400

ENT.CurrentlyExperiencedWindspeed = 0
ENT.MaximumExperiencedWindspeed = 0

ENT.LowestPressureDropped = 0
ENT.CurrentAtmosphericPressure = 0

ENT.LastDeployTime = 0

ENT.XT3DoNotApplyPhysics = false
ENT.XT3AnemometerDevice = true

ENT.Spawnable = true

function ENT:Initialize()
    self:SetModel("models/props_c17/substation_transformer01d.mdl")
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
   
    PhysicsObject:SetMass(250)
    self:SetNW2Bool("XT3ProbeDeployed", false)
end

if SERVER then
    function ENT:Think()
        local MaximumWindVelocity, MaximumWindspeed, LowestAtmosphericPressure, LowestPressureDropped = GetGlobalWindspeed(self:GetPos())

        self.CurrentlyExperiencedWindspeed = MaximumWindspeed
        self.MaximumExperiencedWindspeed = math.max(self.MaximumExperiencedWindspeed, MaximumWindspeed)

        self.CurrentAtmosphericPressure = LowestAtmosphericPressure
        self.LowestPressureDropped = math.max(self.LowestPressureDropped, LowestPressureDropped)

        self:SetNW2Float("CurrentlyExperiencedWindspeed", self.CurrentlyExperiencedWindspeed)
        self:SetNW2Float("MaximumExperiencedWindspeed", self.MaximumExperiencedWindspeed)

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
                self:StopSound("npc/attack_helicopter/aheli_megabomb_siren1.wav")
                self:EmitSound("npc/attack_helicopter/aheli_megabomb_siren1.wav")
                PhysicsObject:Sleep()
            else
                self:StopSound("npc/attack_helicopter/aheli_megabomb_siren1.wav")
                PhysicsObject:Wake()
            end
        end
    end
end

if CLIENT then
	function ENT:DrawTranslucent()
        self.LowestPressureDropped = self:GetNW2Float("LowestPressureDropped", self.LowestPressureDropped)
        self.CurrentAtmosphericPressure = self:GetNW2Float("CurrentAtmosphericPressure", self.CurrentAtmosphericPressure)
   
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

                local CurrentAtmosphericPressure = math.floor(self.CurrentAtmosphericPressure)
                local LowestPressureDropped = self.LowestPressureDropped
                local LowestAtmosphericPressure = math.floor(XT3BaseAtmosphericPressure - LowestPressureDropped)
                LowestPressureDropped = math.ceil(LowestPressureDropped)

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
                    local Offset = -200

                    draw.SimpleTextOutlined("Current 3 Second Gust Windspeed : " .. CurrentExperiencedWindspeed .. " MPH", "XT3BigProbeFont", 0, Offset, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)
                    draw.SimpleTextOutlined("Maximum 3 Second Gust Windspeed : " .. MaximumExperiencedWindspeed .. " MPH", "XT3BigProbeFont", 0, Offset+64, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)

                    draw.SimpleTextOutlined("Current Instantaneous Windspeed : " .. InstantaneousWindspeed .. " MPH", "XT3BigProbeFont", 0, Offset+32, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)
                    draw.SimpleTextOutlined("Maximum Instantaneous Windspeed : " .. InstantaneousWindspeedMax .. " MPH", "XT3BigProbeFont", 0, Offset+96, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)
                    
                    draw.SimpleTextOutlined("Current Atmospheric Pressure : " .. CurrentAtmosphericPressure .. " hPa", "XT3BigProbeFont", 0, Offset+128, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)
                    draw.SimpleTextOutlined("Lowest Atmospheric Pressure Drop : " .. LowestPressureDropped .. " hPa", "XT3BigProbeFont", 0, Offset+160, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)
                    draw.SimpleTextOutlined("Lowest Atmospheric Pressure : " .. LowestAtmosphericPressure  .. " hPa", "XT3BigProbeFont", 0, Offset+192, TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, TextStrokeColor)
                    
                cam.End3D2D()

            end
        end
	end
end

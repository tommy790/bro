AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "xtwisters3vortexbase"

ENT.VortexWindspeed = 0
ENT.VortexCoreSize = 0
ENT.VortexSwirlRatio = 0
ENT.VortexWindfieldFallOff = 0
ENT.ParticleSystemName = " "

ENT.AntiCyclonic = false
ENT.CustomFunctionality = true

ENT.DisplayName = "Depression"
ENT.PrintName = "XTwisters3 Depression"

local Tornadoes = {{
    ParticleName = "depressuobnxt23",
    VortexSize = 500,
    VortexSwirlRatio = {
        Min = 0,
        Max = 10
    },
    VortexForceMultipliers = {
        Radial = 1,
        Tangential = 1,
        Axial = -1
    }
}}

function ENT:Initialize()
    self:OnStart()

    if SERVER then

        local Particle, Size, Swirl, StrengthenParams, WindfieldMultipliers = SelectTornadoParticle(Tornadoes)

        self.ParticleSystemName = tostring(Particle)
        self.VortexCoreSize = Size
        self.VortexSwirlRatio = Swirl
        self.VortexStrengthenParameters = StrengthenParams
        self.WindfieldMultipliers = WindfieldMultipliers

        self.VortexWindspeed = SuperRandom(201, 250)
        self.VortexWindfieldFallOff = math.max(SuperRandom(0.55, 1), math.min((Size / 1500) ^ 2, 0.95)) -- So technically, the ACTUAL windfield falloff should ALWAYS be 1, but I want varying / large windfields for small tornadoes.

        local PrintSize = math.Round(ReturnWindfieldRadius(self, 65) * 2 * 0.0000473484848485 * 100) / 100
        if PrintSize < 1 then
            PrintSize = math.Round(ReturnWindfieldRadius(self, 65) * 2 * 0.08333325) .. " Yards wide"
        else
            PrintSize = PrintSize .. " Miles wide"
        end

        print(Particle, math.Round(self.VortexWindspeed) .. " mph windspeed", math.Round(self.VortexCoreSize) .. " Vortex Size", PrintSize, math.Round(self.VortexWindfieldFallOff * 100) / 100 .. " Windfield Falloff", math.Round(self.VortexSwirlRatio * 100) / 100 .. " Swirl Ratio")
        
        XT3PrintHint("The chosen particle is ".. Particle .. " and it's vortex core size is ".. math.Round(self.VortexCoreSize).. " HU wide. ".. "This tornado's windspeed is ".. math.Round(self.VortexWindspeed) .." mph.", 8)
        XT3PrintHint("The overall tornado's width is "..PrintSize.. " with a swirl ratio of ".. (math.Round(self.VortexSwirlRatio * 100) / 100) .. " and with a windfield fall off of ".. (math.Round(self.VortexWindfieldFallOff * 100) / 100), 8)

        self:SetModel("models/props_junk/garbage_metalcan001a.mdl")
        self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
        self:SetColor(Color(0, 0, 0, 0))
        self:SetRenderMode(RENDERMODE_TRANSALPHA)
        self:SetMoveType(MOVETYPE_FLY)
        self:SetSolid(SOLID_NONE)
        self:SetCollisionGroup(1)

    elseif CLIENT then
        self.TornadoSound = CreateSound(self, "VortexRoars/sad.wav")

        language.Add("xt3_tornadoes_depression", "Depression")
        killicon.Add("xt3_tornadoes_depression", "materials/KillIcons/Depression.png", Color(255, 255, 255))
    end
end

function ENT:CustomFunction()
    local Entities = XT3RetrievePlayerEntities(true, false)
    for Index = 1, #Entities do
        local Entity = Entities[Index]
        local PhysObject = Entity:GetPhysicsObject()
        if Entity:IsPlayer() or Entity:IsNPC() then
            local Trace, WindTunnelMultiplier, LiftMultiplier = TraceCheckWalls(Entity, self)
            if PhysObject:IsValid() and Entity:GetMoveType() ~= MOVETYPE_NOCLIP and not (Entity:IsPlayer() and Entity:InVehicle()) and not Trace then
                local WindVelocity, Windspeed, WindfieldMultiplier = GetTornadoWindspeed(self, Entity:GetPos())
                Windspeed = Windspeed * WindTunnelMultiplier

                local Damage = 1 * math.max((Windspeed - 60) / 350, 0)
                XT3CauseDamage(self, self, Entity, Damage * GetConVar("xtwisters3_damagemultiplier"):GetFloat(), DMG_SLASH)
            end
        end
    end
end

function ENT:OnRemove()
    XT3RemoveSound(self.TornadoSound)
    self:OnRemoval()

end


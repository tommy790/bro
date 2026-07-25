AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "xtwisters3vortexbase"

ENT.VortexWindspeed = 0
ENT.VortexCoreSize = 0
ENT.VortexSwirlRatio = 0
ENT.VortexWindfieldFallOff = 0
ENT.ParticleSystemName = " "

ENT.AntiCyclonic = true
ENT.CustomFunctionality = true

ENT.DisplayName = "Smallnado"
ENT.PrintName = "XTwisters3 Smallnado"

local Tornadoes = {
    {ParticleName = "cal3", VortexSize = 70, VortexSwirlRatio = {Min = 0, Max = 10}, VortexForceMultipliers = {Radial = 1, Tangential = -1, Axial = 1}}
	
}

function ENT:Initialize()
    self:OnStart()

    if SERVER then

        local Particle, Size, Swirl, StrengthenParams, WindfieldMultipliers = SelectTornadoParticle(Tornadoes)

        self.ParticleSystemName = tostring(Particle)
        self.VortexCoreSize = Size
        self.VortexSwirlRatio = Swirl
        self.VortexStrengthenParameters = StrengthenParams
        self.WindfieldMultipliers = WindfieldMultipliers
        
        self.VortexWindspeed = SuperRandom(450, 500)
        self.VortexWindfieldFallOff = SuperRandom(0.55, 1)

        local PrintSize = math.Round(ReturnWindfieldRadius(self, 65) * 2 * 0.0000473484848485 * 100) / 100
        if PrintSize < 1 then
            PrintSize = math.Round(ReturnWindfieldRadius(self, 65) * 2 * 0.08333325) .. " Yards wide"
        else
            PrintSize = PrintSize .. " Miles wide"
        end

        local PrintSize = math.Round(ReturnWindfieldRadius(self, 65) * 2 * 0.0000473484848485 * 100) / 100
        if PrintSize < 1 then
            PrintSize = math.Round(ReturnWindfieldRadius(self, 65) * 2 * 0.08333325) .. " Yards wide"
        else
            PrintSize = PrintSize .. " Miles wide"
        end

        print(Particle, math.Round(self.VortexWindspeed) .. " mph windspeed", math.Round(self.VortexCoreSize) .. " Vortex Size", PrintSize, math.Round(self.VortexWindfieldFallOff * 100) / 100 .. " Windfield Falloff", math.Round(self.VortexSwirlRatio * 100) / 100 .. " Swirl Ratio")
        
        XT3PrintHint("The chosen particle is ".. Particle .. " and it's vortex core size is ".. math.Round(self.VortexCoreSize).. " HU wide. ", 8)
        XT3PrintHint("The overall tornado's width is "..PrintSize.. " with a swirl ratio of ".. (math.Round(self.VortexSwirlRatio * 100) / 100) .. " and with a windfield fall off of ".. (math.Round(self.VortexWindfieldFallOff * 100) / 100), 8)

        self:SetModel("models/props_junk/garbage_metalcan001a.mdl")
        self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
        self:SetColor(Color(0, 0, 0, 0))
        self:SetRenderMode(RENDERMODE_TRANSALPHA)
        self:SetMoveType(MOVETYPE_FLY)
        self:SetSolid(SOLID_NONE)
        self:SetCollisionGroup(1)

    elseif CLIENT then
        self.TornadoSound = CreateSound(self, "VortexRoars/TwisterRoar.wav")

        language.Add("xt3_tornadoes_smallnado", "Smallnado")
        killicon.Add("xt3_tornadoes_smallnado", "materials/KillIcons/johncenanudes.png", Color(255, 255, 255))
    end
end

function ENT:CustomFunction()
    if SERVER then
        if math.random(1, 300) == 1 then
            if GetConVar("xtwisters3_lightningintornadoes"):GetInt() == 1 then
                XT3SpawnLightning(self, self:GetPos(), math.max(self.VortexCoreSize * 2.5, 10000))
            end
        end
    end
end

function ENT:OnRemove()
    XT3RemoveSound(self.TornadoSound)
    self:OnRemoval()
end


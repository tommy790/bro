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
ENT.MovementSpeedMultiplier = 0.25

ENT.DisplayName = "Dust devil"
ENT.PrintName = "XTwisters3 Dust devil"

local Tornadoes = {
    {ParticleName = "astral_dustdevil01", VortexSize = 100, VortexSwirlRatio = {Min = 1, Max = 2}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 35, VortexStartSize = 150, SizeFadeStart = 5, SizeFadeEnd = 5}} ;
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

        self.VortexWindspeed = SuperRandom(25, 110)
        self.VortexWindfieldFallOff = math.max(SuperRandom(0.55, 1), math.min((Size / 1500) ^ 2, 0.85))
        
        local PrintSize = math.Round(ReturnWindfieldRadius(self, 65) * 2 * 0.0000473484848485 * 100) / 100
        if PrintSize < 1 then
            PrintSize = math.Round(ReturnWindfieldRadius(self, 65) * 2 * 0.08333325).. " Yards wide"
        else
            PrintSize = PrintSize.. " Miles wide"
        end

        print(Particle, math.Round(self.VortexWindspeed) .. " mph windspeed", math.Round(self.VortexCoreSize) .. " Vortex Size", PrintSize, math.Round(self.VortexWindfieldFallOff * 100) / 100 .. " Windfield Falloff", math.Round(self.VortexSwirlRatio * 100) / 100 .. " Swirl Ratio")
        
        XT3PrintHint("The chosen particle is ".. Particle .. " and it's vortex core size is ".. math.Round(self.VortexCoreSize).. " HU wide. ".. "This dust devil's windspeed is ".. math.Round(self.VortexWindspeed) .." mph.", 8)
        XT3PrintHint("The overall dust devil's width is "..PrintSize.. " with a swirl ratio of ".. (math.Round(self.VortexSwirlRatio * 100) / 100) .. " and with a windfield fall off of ".. (math.Round(self.VortexWindfieldFallOff * 100) / 100), 8)

        self:SetModel("models/props_junk/garbage_metalcan001a.mdl")
        self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
        self:SetColor(Color(0, 0, 0, 0))
        self:SetRenderMode(RENDERMODE_TRANSALPHA)
        self:SetMoveType(MOVETYPE_FLY)
        self:SetSolid(SOLID_NONE)
        self:SetCollisionGroup(1)

    elseif CLIENT then
        self.TornadoSound = CreateSound(self, "VortexRoars/TornadoRoar.wav")

        language.Add("xt3_tornadoes_ef0", "Dust devil")
        killicon.Add("xt3_tornadoes_ef0", "materials/KillIcons/EF0KillIcon.png", Color(255, 255, 255))
    end
end

function ENT:CustomFunction()
   
end

function ENT:OnRemove()
    XT3RemoveSound(self.TornadoSound)
    self:OnRemoval()
end


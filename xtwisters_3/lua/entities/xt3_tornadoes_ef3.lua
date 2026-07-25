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

ENT.DisplayName = "EF3 Tornado"
ENT.PrintName = "XTwisters3 EF3 Tornado"

local Tornadoes = {
    {ParticleName = "Ash6_Tornado6_6", VortexSize = 770, VortexSwirlRatio = {Min = 1.25, Max = 2.5}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 45, VortexStartSize = 770, SizeFadeStart = 1000, SizeFadeEnd = 0}};
    {ParticleName = "trt_drillbit_2", VortexSize = 300, VortexSwirlRatio = {Min = 0.75, Max = 2}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 70, VortexStartSize = 200, SizeFadeStart = 0, SizeFadeEnd = 5}},
    {ParticleName = "astralxt3_tor3", VortexSize = 6500, VortexSwirlRatio = {Min = 2, Max = 3}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 80, VortexStartSize = 2000, SizeFadeStart = 85, SizeFadeEnd = 110}},
    {ParticleName = "astralxt3_tor2", VortexSize = 1000, VortexSwirlRatio = {Min = 1.9, Max = 2.5}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 90, VortexStartSize = 200, SizeFadeStart = 0, SizeFadeEnd = 5}},
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
        
        self.VortexWindspeed = SuperRandom(136, 165)
        self.VortexWindfieldFallOff = math.max(SuperRandom(0.55, 1), math.min((Size / 1500) ^ 2, 0.85))
        
        local PrintSize = math.Round(ReturnWindfieldRadius(self, 65) * 2 * 0.0000473484848485 * 100) / 100
        if PrintSize < 1 then
            PrintSize = math.Round(ReturnWindfieldRadius(self, 65) * 2 * 0.08333325).. " Yards wide"
        else
            PrintSize = PrintSize.. " Miles wide"
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
        self.TornadoSound = CreateSound(self, "VortexRoars/TornadoRoar.wav")

        language.Add("xt3_tornadoes_ef3", "EF3 Tornado")
        killicon.Add("xt3_tornadoes_ef3", "materials/KillIcons/EF3KillIcon.png", Color(255, 255, 255))
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


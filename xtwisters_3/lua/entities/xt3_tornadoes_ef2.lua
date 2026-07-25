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

ENT.DisplayName = "EF2 Tornado"
ENT.PrintName = "XTwisters3 EF2 Tornado"

local Tornadoes = {
    {ParticleName = "Ash1_Tornado1_1", VortexSize = 1550, VortexSwirlRatio = {Min = 1.25, Max = 3}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 50, VortexStartSize = 1550, SizeFadeStart = 0, SizeFadeEnd = 0}};
    {ParticleName = "trt_tornado_5", VortexSize = 1200, VortexSwirlRatio = {Min = 1.25, Max = 3}, StrengthenParams = {WindspeedFadeStart = 1, WindspeedFadeEnd = 80, VortexStartSize = 1000, SizeFadeStart = 1, SizeFadeEnd = 1}};
    {ParticleName = "RDS_XT3_EF2_A1", VortexSize = 900, VortexSwirlRatio = {Min = 1.35, Max = 2.35}, StrengthenParams = {WindspeedFadeStart = 1, WindspeedFadeEnd = 40, VortexStartSize = 900, SizeFadeStart = 1, SizeFadeEnd = 1}}; 
    {ParticleName = "astralxt3_tor5", VortexSize = 700, VortexSwirlRatio = {Min = 1.85, Max = 2.35}, StrengthenParams = {WindspeedFadeStart = 1, WindspeedFadeEnd = 90, VortexStartSize = 700, SizeFadeStart = 1, SizeFadeEnd = 1}} 
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

        self.VortexWindspeed = SuperRandom(111, 135)
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

        language.Add("xt3_tornadoes_ef2", "EF2 Tornado")
        killicon.Add("xt3_tornadoes_ef2", "materials/KillIcons/EF2KillIcon.png", Color(255, 255, 255))
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


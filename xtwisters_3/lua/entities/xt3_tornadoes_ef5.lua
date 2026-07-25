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

ENT.DisplayName = "EF5 Tornado"
ENT.PrintName = "XTwisters3 EF5 Tornado"

local Tornadoes = {
    {ParticleName = "Ash9_Tornado9_9", VortexSize = 3200, VortexSwirlRatio = {Min = 3, Max = 4}, StrengthenParams = {WindspeedFadeStart = 15, WindspeedFadeEnd = 160, VortexStartSize = 1500, SizeFadeStart = 90, SizeFadeEnd = 160}};
    {ParticleName = "Ash2_Tornado2_2", VortexSize = 700, VortexSwirlRatio = {Min = 0.95, Max = 2.25}, StrengthenParams = {WindspeedFadeStart = 10, WindspeedFadeEnd = 50, VortexStartSize = 550, SizeFadeStart = 1, SizeFadeEnd = 0}};
    {ParticleName = "Ash3_Tornado3_3", VortexSize = 3000, VortexSwirlRatio = {Min = 3, Max = 4}, StrengthenParams = {WindspeedFadeStart = 20, WindspeedFadeEnd = 80, VortexStartSize = 1500, SizeFadeStart = 5, SizeFadeEnd = 180}},
    {ParticleName = "RDS_XT3_EF5_A1", VortexSize = 1320, VortexSwirlRatio = {Min = 2, Max = 4}, StrengthenParams = {WindspeedFadeStart = 5, WindspeedFadeEnd = 70, VortexStartSize = 800, SizeFadeStart = 5, SizeFadeEnd = 30}},
    {ParticleName = "trt_tornado_1", VortexSize = 2600, VortexSwirlRatio = {Min = 4, Max = 6}, StrengthenParams = {WindspeedFadeStart = 10, WindspeedFadeEnd = 130, VortexStartSize = 800, SizeFadeStart = 35, SizeFadeEnd = 230}},
    {ParticleName = "trt_drillbit_1", VortexSize = 430, VortexSwirlRatio = {Min = 0.95, Max = 2.25}, StrengthenParams = {WindspeedFadeStart = 5, WindspeedFadeEnd = 50, VortexStartSize = 430, SizeFadeStart = 1, SizeFadeEnd = 1}},
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

        self.VortexWindspeed = SuperRandom(201, 250)
        self.VortexWindfieldFallOff = math.max(SuperRandom(0.55, 1), math.min((Size / 1500) ^ 2, 0.85))

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
        self.TornadoSound = CreateSound(self, "VortexRoars/TornadoRoar.wav")

        language.Add("xt3_tornadoes_ef5", "EF5 Tornado")
        killicon.Add("xt3_tornadoes_ef5", "materials/KillIcons/EF5KillIcon.png", Color(255, 255, 255))
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


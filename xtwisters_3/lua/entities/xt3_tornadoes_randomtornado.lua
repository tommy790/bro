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

ENT.DisplayName = "Random Tornado"
ENT.PrintName = "XTwisters3 Random Tornado"

local Tornadoes = {
    {ParticleName = "PGYT_ef0-1", VortexSize = 150, VortexSwirlRatio = {Min = 0.75, Max = 1.25}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 35, VortexStartSize = 150, SizeFadeStart = 5, SizeFadeEnd = 5}} ;
    {ParticleName = "Ash5_Tornado5_5", VortexSize = 100, VortexSwirlRatio = {Min = 0.8, Max = 1.5}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 50, VortexStartSize = 50, SizeFadeStart = 5, SizeFadeEnd = 60}};
    {ParticleName = "Ash8_Tornado8_8", VortexSize = 2100, VortexSwirlRatio = {Min = 1.5, Max = 2.5}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 35, VortexStartSize = 50, SizeFadeStart = 5, SizeFadeEnd = 60}};
    {ParticleName = "RDS_XT1_EF1_A1", VortexSize = 300, VortexSwirlRatio = {Min = 1, Max = 3}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 55, VortexStartSize = 700, SizeFadeStart = 15, SizeFadeEnd = 110}};
    {ParticleName = "trt_tornado_2", VortexSize = 700, VortexSwirlRatio = {Min = 0.25, Max = 0.65}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 55, VortexStartSize = 700, SizeFadeStart = 15, SizeFadeEnd = 110}};
    {ParticleName = "astralxt3_tor6", VortexSize = 8000, VortexSwirlRatio = {Min = 4, Max = 6}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 50, VortexStartSize = 1500, SizeFadeStart = 70, SizeFadeEnd = 140}};
    {ParticleName = "Ash1_Tornado1_1", VortexSize = 1550, VortexSwirlRatio = {Min = 1.25, Max = 3}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 50, VortexStartSize = 1550, SizeFadeStart = 0, SizeFadeEnd = 0}};
    {ParticleName = "trt_tornado_5", VortexSize = 1200, VortexSwirlRatio = {Min = 1.25, Max = 3}, StrengthenParams = {WindspeedFadeStart = 1, WindspeedFadeEnd = 80, VortexStartSize = 1000, SizeFadeStart = 1, SizeFadeEnd = 1}};
    {ParticleName = "RDS_XT3_EF2_A1", VortexSize = 900, VortexSwirlRatio = {Min = 1.35, Max = 2.35}, StrengthenParams = {WindspeedFadeStart = 1, WindspeedFadeEnd = 40, VortexStartSize = 900, SizeFadeStart = 1, SizeFadeEnd = 1}}; 
    {ParticleName = "astralxt3_tor5", VortexSize = 700, VortexSwirlRatio = {Min = 1.85, Max = 2.35}, StrengthenParams = {WindspeedFadeStart = 1, WindspeedFadeEnd = 90, VortexStartSize = 700, SizeFadeStart = 1, SizeFadeEnd = 1}};
    {ParticleName = "Ash6_Tornado6_6", VortexSize = 770, VortexSwirlRatio = {Min = 1.25, Max = 2.5}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 45, VortexStartSize = 770, SizeFadeStart = 1000, SizeFadeEnd = 0}};
    {ParticleName = "trt_drillbit_2", VortexSize = 300, VortexSwirlRatio = {Min = 0.75, Max = 2}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 70, VortexStartSize = 200, SizeFadeStart = 0, SizeFadeEnd = 5}},
    {ParticleName = "astralxt3_tor3", VortexSize = 6500, VortexSwirlRatio = {Min = 2, Max = 3}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 80, VortexStartSize = 2000, SizeFadeStart = 85, SizeFadeEnd = 110}},
    {ParticleName = "astralxt3_tor2", VortexSize = 1000, VortexSwirlRatio = {Min = 1.9, Max = 2.5}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 90, VortexStartSize = 200, SizeFadeStart = 0, SizeFadeEnd = 5}},
    {ParticleName = "Ash4_Tornado4_4", VortexSize = 1250, VortexSwirlRatio = {Min = 2, Max = 3}, StrengthenParams = {WindspeedFadeStart = 15, WindspeedFadeEnd = 85, VortexStartSize = 1000, SizeFadeStart = 5, SizeFadeEnd = 30}};
    {ParticleName = "Ash7_Tornado7_7", VortexSize = 2550, VortexSwirlRatio = {Min = 2, Max = 2.5}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 95, VortexStartSize = 1000, SizeFadeStart = 5, SizeFadeEnd = 30}},
    {ParticleName = "trt_tornado_4", VortexSize = 1000, VortexSwirlRatio = {Min = 2, Max = 5}, StrengthenParams = {WindspeedFadeStart = 10, WindspeedFadeEnd = 90, VortexStartSize = 850, SizeFadeStart = 15, SizeFadeEnd = 110}},
    {ParticleName = "trt_tornado_3", VortexSize = 700, VortexSwirlRatio = {Min = 1.75, Max = 4.25}, StrengthenParams = {WindspeedFadeStart = 10, WindspeedFadeEnd = 90, VortexStartSize = 200, SizeFadeStart = 75, SizeFadeEnd = 110}},
    {ParticleName = "astralxt3_tor1", VortexSize = 700, VortexSwirlRatio = {Min = 1.8, Max = 2.5}, StrengthenParams = {WindspeedFadeStart = 0, WindspeedFadeEnd = 110, VortexStartSize = 700, SizeFadeStart = 0, SizeFadeEnd = 110}},
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

        self.VortexWindspeed = SuperRandom(50, 300)
        self.VortexWindfieldFallOff = math.max(SuperRandom(0.55, 1), math.min((Size / 1500) ^ 2, 0.55)) -- So technically, the ACTUAL windfield falloff should ALWAYS be 1, but I want varying / large windfields for small tornadoes.

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

        language.Add("xt3_tornadoes_randomtornado", "Random Tornado")
        killicon.Add("xt3_tornadoes_randomtornado", "materials/KillIcons/EF".. math.random(0, 5) .."KillIcon.png", Color(255, 255, 255))
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


AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Tornado Siren"
ENT.Spawnable = true
ENT.AdminOnly = false

local SirenAudioPath = "Miscellaneous/TornadoSirenLoop.wav"
ENT.CheckInterval = 3

-- yes twin I'm reusing the siren code from xt2 twin I HATE siren AUTISTS... FUCK YOU!!!!! DIE!!!! 

function ENT:Initialize()
    self.CheckInterval = (math.random(30, 80) / 10)
    if SERVER then
        self:SetModel("models/es_sth10/siren_001.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetCollisionGroup(COLLISION_GROUP_WORLD)
        self:SetModelScale(1)

        local PhysicsObject = self:GetPhysicsObject()
        if PhysicsObject:IsValid() then PhysicsObject:Wake() end
    else -- CLIENT
        util.PrecacheSound(SirenAudioPath)
        self.SirenSound = nil -- Only need one sound object since we're just looping the same sound
        self.SirenPlaying = false
        timer.Simple(0, function() self:CheckForTornadoes() end) -- Initial check for tornadoes
    end
end

function ENT:CheckForTornadoes()
    if CLIENT then
        local tornadoExists = false
        for _, ent in ipairs(ents.FindByClass("xt3_tornadoes*")) do
            if ent.IsTornadic then
                tornadoExists = true
                break
            end
        end

        if tornadoExists and not self.SirenPlaying then
            self:StartSiren()
        elseif not tornadoExists and self.SirenPlaying then
            self:StopSiren()
        end

        timer.Simple(self.CheckInterval, function()
            if IsValid(self) then
                self:CheckForTornadoes()
            end
        end) -- Re-check periodically
    end
end

function ENT:StartSiren()
    if CLIENT and not self.SirenPlaying then
        self.SirenSound = CreateSound(self, SirenAudioPath)
        self.SirenSound:SetSoundLevel(19000)
        self.SirenSound:PlayEx(1, 100)
        self.SirenPlaying = true
    end
end

function ENT:StopSiren()
    if CLIENT and self.SirenPlaying then
        if self.SirenSound then
            self.SirenSound:Stop()
            self.SirenSound = nil
        end
        self.SirenPlaying = false
    end
end

function ENT:OnRemove()
    if CLIENT then
        self:StopSiren() -- Ensure sounds are stopped immediately upon entity removal
    end
end
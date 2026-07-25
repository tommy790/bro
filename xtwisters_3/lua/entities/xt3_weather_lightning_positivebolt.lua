AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.Spawnable = false
ENT.AdminOnly = false
ENT.PlayerSpawned = true

ENT.DisplayName = "Ball Lightning"
ENT.PrintName = "XTwisters3 Positive Lightning"
ENT.Category = "XT3"

local TestBoltParticleName = "astral_positivebolt_strikearc1"
local TestBoltImpactParticleName = "astral_positivebolt_strike"

function ENT:Initialize()
    if SERVER then

        self:SetModel("models/props_junk/garbage_metalcan001a.mdl")
        self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
        self:SetColor(Color(0, 0, 0, 0))
        self:SetRenderMode(RENDERMODE_TRANSALPHA)
        self:SetMoveType(MOVETYPE_FLY)
        self:SetSolid(SOLID_NONE)
        self:SetCollisionGroup(1)

        if self.PlayerSpawned then

            timer.Simple(.1, function()
                local LightningStartPosition = self:GetPos()

                local FindSky = util.TraceLine({
                    start = LightningStartPosition,
                    endpos = LightningStartPosition + Vector(0, 0, 100000),
                    mask = MASK_NPCWORLDSTATIC,
                    filter = self
                })

                local ConnectToGround = util.TraceLine({
                    start = FindSky.HitPos,
                    endpos = FindSky.HitPos - Vector(0, 0, 100000),
                    mask = MASK_WATER + MASK_SOLID,
                    filter = self
                })

                local BoltSpawn, BoltSpawnPosition = XT3GetPositionInRadius(FindSky.HitPos, 10000, 500)
                self.StrikeTo = (self:GetPos() - BoltSpawnPosition):GetNormalized()

                if not BoltSpawn then
                    self:SetPos(BoltSpawnPosition)
                    self:Strike(self.StrikeTo, 50000)
                else
                    self:Remove()
                end
            end)
        end

    elseif CLIENT then
        language.Add("xt3_weather_lightning_postivebolt", "Positive Lightning Bolt")
        killicon.Add("xt3_weather_lightning_postivebolt", "materials/KillIcons/ZapIcon.png", Color(255, 255, 255))
    end
end

function ENT:CreateHit(Position)
    local Target = ents.Create("base_gmodentity")

    Target:SetModel("models/props_junk/garbage_metalcan001a.mdl")
    Target:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    Target:SetColor(Color(0, 0, 0, 0))
    Target:DrawShadow(false)
    Target:SetRenderMode(RENDERMODE_TRANSALPHA)
    Target:SetMoveType(MOVETYPE_FLY)
    Target:SetSolid(SOLID_NONE)
    Target:SetCollisionGroup(1)

    Target:SetPos(Position)

    Target:Spawn()
    Target:Activate()
    return Target
end

function ENT:Strike(AimTorward, Length)

    local LightningPosition = self:GetPos()
    local BoltTrace = util.TraceLine({
        start = LightningPosition,
        endpos = LightningPosition + (AimTorward * Length),
        mask = MASK_WATER + MASK_SOLID
    })

    if BoltTrace.Hit then
        local TowardsBall = (LightningPosition - BoltTrace.HitPos):GetNormalized()
        local HitTarget = self:CreateHit(BoltTrace.HitPos - TowardsBall)
        local FlashTarget = self:CreateHit(LightningPosition)

        XT3CreateConnectedParticle(TestBoltParticleName, self:GetPos(), BoltTrace.HitPos)   
        XT3ParticleEffect(TestBoltImpactParticleName, BoltTrace.HitPos, Angle(), self)

        local LightLifetime = SuperRandom(0.15, 0.25) * 1.5
        local LightSize = SuperRandom(15000, 30000)

        local LightType = 1
        local LightBrightness = 15

        if GetConVar("xtwisters3_lightningflashes"):GetBool() then
            LightType = 2
            LightBrightness = SuperRandom(350, 1000) * 2
        end

        local LightParams = {
            StartColor = {
                R = 185,
                G = 245,
                B = 255
            },

            EndColor = {
                R = 145,
                G = 175,
                B = 240
            },

            StartLightSize = LightSize,
            EndLightSize = LightSize,

            LifeTime = LightLifetime,
            LifeFadeExponent = 2,

            LightBrightness = LightBrightness,
            LightDecay = 1,

            Type = LightType
        }

        net.Start("xt3_newdynamiclight")
        net.WriteEntity(HitTarget)
        net.WriteTable(LightParams)

        net.Broadcast()

        timer.Simple(LightLifetime, function()
            if HitTarget and HitTarget:IsValid() then
                HitTarget:Remove()
            end

            if FlashTarget and FlashTarget:IsValid() then
                FlashTarget:Remove()
            end
        end)

        local Size = SuperRandom(3.5, 3.75)
        local DecalParams = {
            Decal = {
                MaterialName = "decals/scorch1.png",
                PNGName = "Scorch"
            },
            Position = BoltTrace.HitPos - TowardsBall,
            Normal = TowardsBall,
            Color = Color(255, 255, 255),
            Width = Size,
            Height = Size
        }

        net.Start("xt3_newdecal")
        net.WriteEntity(BoltTrace.Entity)
        net.WriteTable(DecalParams)

        net.Broadcast()

        EmitSound("ambient/ambience/rainscapes/thunder_close0" .. math.random(1, 4) .. ".wav", BoltTrace.HitPos, 0, CHAN_AUTO, 1, 120, 0, 100)
        EmitSound("ambient/ambience/rainscapes/thunder_close0" .. math.random(1, 4) .. ".wav", BoltTrace.HitPos, 0, CHAN_AUTO, 1, 0, 0, 75)
        EmitSound("ambient/ambience/rainscapes/thunder_close0" .. math.random(1, 4) .. ".wav", BoltTrace.HitPos, 0, CHAN_AUTO, 1, 0, 0, 50)

        EmitSound("ambient/weather/thunder_distant_0" .. math.random(3, 5) .. ".wav", BoltTrace.HitPos, 0, CHAN_AUTO, 1, 0)

        EmitSound("ambient/explosions/explode_" .. math.random(1, 4) .. ".wav", BoltTrace.HitPos, 0, CHAN_AUTO, 1, 80)
        
        -- EmitSound("ambient/energy/ion_cannon_shot" .. math.random(1, 3) .. ".wav", BoltTrace.HitPos, 0, CHAN_AUTO, 1, 80)
        EmitSound("Explosions/LightningBlastExtreme" .. math.random(1, 3) .. ".mp3", BoltTrace.HitPos, 0, CHAN_AUTO, 1, 120)

        util.ScreenShake(BoltTrace.HitPos, 100, 25, 1, 4700, true)
        local StrikeSize = 350

        local Entities = ents.FindInSphere(BoltTrace.HitPos + Vector(0, 0, 1), StrikeSize)
        for Index = 1, #Entities do
            local Entity = Entities[Index]
            if Entity:IsValid() and Entity ~= self and Entity:GetClass() ~= "gmod_ghost" and Entity:GetClass() ~= "sent_anim" and not Entity:IsWorld() and not Entity:IsWeapon() then
                local PhysObject = Entity:GetPhysicsObject()

                if PhysObject:IsValid() then
                    if (Entity:IsPlayer() and Entity:GetMoveType() ~= MOVETYPE_NOCLIP) or Entity:IsNPC() then
                        local DamageMult = 1

                        if Entity:IsPlayer() and Entity:InVehicle() then
                            DamageMult = 0.5
                        end
                        
                        local BoltDamage = SuperRandom(150, 735) * (1 - math.min((BoltTrace.HitPos - (Entity:GetPos() + Vector(0, 0, 30))):Length() / StrikeSize, 1))
                        XT3CauseDamage(self, self, Entity, BoltDamage * DamageMult, DMG_SHOCK)
                        Entity:Ignite(SuperRandom(1, 5) * DamageMult)

                        local Velocity = -(BoltTrace.HitPos - Entity:GetPos()):GetNormalized() * 350000 * (1 - math.min((BoltTrace.HitPos - Entity:GetPos()):Length() / StrikeSize, 1))

                        if Entity.AddVelocity then
                            Entity:AddVelocity(Velocity)
                        else
                            Entity:SetVelocity(Velocity)
                        end
                    elseif not Entity:IsPlayer() and not Entity:IsNPC() then
                        local BoltDamage = SuperRandom(200, 1000) * (1 - math.min((BoltTrace.HitPos - Entity:GetPos()):Length() / StrikeSize, 1))
                        Entity:Ignite(SuperRandom(5, 30) * (1 - math.min((BoltTrace.HitPos - Entity:GetPos()):Length() / StrikeSize, 1)))
                        local Velocity = -(BoltTrace.HitPos - Entity:GetPos()):GetNormalized() * 350000 * (1 - math.min((BoltTrace.HitPos - Entity:GetPos()):Length() / StrikeSize, 1))

                        if math.random() > 0.25 then
                            if constraint.HasConstraints() and not Entity:IsVehicle() and not Entity:IsRagdoll() then
                                constraint.RemoveAll(Entity)
                                Entity:EmitSound("PropDamage/break" .. math.random(1, 16) .. ".wav", SuperRandom(50, 130))
                            end

                            if not PhysObject:IsMotionEnabled() then
                                PhysObject:Wake()
                                PhysObject:EnableMotion(true)
                            end
                        end

                        PhysObject:ApplyForceCenter(Velocity)
                        XT3CauseDamage(self, self, Entity, BoltDamage, DMG_SHOCK)
                    end
                end
            end
        end

        local Entity = BoltTrace.Entity
        if Entity:IsValid() and Entity ~= self and Entity:GetClass() ~= "gmod_ghost" and Entity:GetClass() ~= "sent_anim" and not Entity:IsWorld() and not Entity:IsWeapon() then
            local PhysObject = Entity:GetPhysicsObject()

            if PhysObject:IsValid() then
                --Entity:EmitSound("ambient/levels/labs/electric_explosion" .. math.random(1, 4) .. ".wav", SuperRandom(90, 110))

                if (Entity:IsPlayer() and Entity:GetMoveType() ~= MOVETYPE_NOCLIP) or Entity:IsNPC() then
                    local BoltDamage = SuperRandom(90, 235) * (1 - math.min((BoltTrace.HitPos - (Entity:GetPos() + Vector(0, 0, 30))):Length() / StrikeSize, 1))
                    XT3CauseDamage(self, self, Entity, BoltDamage, DMG_SHOCK)
                    Entity:Ignite(SuperRandom(1, 5))
                elseif not Entity:IsPlayer() and not Entity:IsNPC() then
                    local BoltDamage = SuperRandom(125, 575) * (1 - math.min((BoltTrace.HitPos - Entity:GetPos()):Length() / StrikeSize, 1))

                    PhysObject:ApplyForceCenter(-(BoltTrace.HitPos - Entity:GetPos()):GetNormalized() * 15000)

                    if math.random(1, 4) == 1 then
                        Entity:Ignite(SuperRandom(5, 30))
                    end

                    if (math.random(1, 2)) == 1 then
                        if constraint.HasConstraints() and not Entity:IsVehicle() and not Entity:IsRagdoll() then
                            constraint.RemoveAll(Entity)

                            Entity:EmitSound("PropDamage/break" .. math.random(1, 16) .. ".wav", SuperRandom(50, 130))
                            Entity:EmitSound("ambient/explosions/explode_" .. math.random(1, 9) .. ".wav", SuperRandom(50, 130))
                        end

                        if not PhysObject:IsMotionEnabled() then
                            PhysObject:Wake()
                            PhysObject:EnableMotion(true)
                        end
                    end

                    XT3CauseDamage(self, self, Entity, BoltDamage, DMG_SHOCK)
                end
            end
        end
    end

    timer.Simple(1, function()
        if self and self:IsValid() then
            self:Remove()
        end
    end)
end

function ENT:OnRemove()
    self:StopParticles()
end

function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

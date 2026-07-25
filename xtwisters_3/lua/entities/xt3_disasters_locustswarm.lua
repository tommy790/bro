AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.Spawnable = false
ENT.AdminOnly = false

ENT.DisplayName = "Locust Swarm"
ENT.PrintName = "XTwisters3 Locus Swarm"
ENT.Category = "XT3"

function ENT:Initialize()
    if SERVER then
        timer.Simple(0.1, function()
            if self and self:IsValid() then
                ParticleEffectAttach("astral_ball_lightning", PATTACH_POINT_FOLLOW, self, 0)
            end
        end)

        self.MovementDirection = Vector(SuperRandom(-1, 1), 0, SuperRandom(-1, 1))
        self.LightningSound = CreateSound(self, "ambient/energy/electric_loop.wav")
        self.LightningSound:SetSoundLevel(90)
        self.LightningSound:Play()

        self:SetModel("models/props_junk/garbage_metalcan001a.mdl")
        self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
        self:SetColor(Color(0, 0, 0, 0))
        self:SetRenderMode(RENDERMODE_TRANSALPHA)
        self:SetMoveType(MOVETYPE_FLY)
        self:SetSolid(SOLID_NONE)
        self:SetCollisionGroup(1)

    elseif CLIENT then
        language.Add("xt3_weather_ball_lightning", "Ball Lightning")
        killicon.Add("xt3_weather_ball_lightning", "materials/KillIcons/johncenanudes.png", Color(255, 255, 255))
    end
end

function ENT:CalculateMovement()
    local VortexPosition = self:GetPos()
    local Speed = (5 * 23.472 * FrameTime())

    local NoiseSize = 300
    local DeviateTime = CurTime() / Lerp(perlinNoise3D(VortexPosition[1] / NoiseSize, CurTime(), VortexPosition[2] / NoiseSize) + 0.5, 1, 30)
    local DeviationOffset = Vector(math.cos(DeviateTime), math.sin(DeviateTime), 0) * Lerp(perlinNoise3D(VortexPosition[1] / NoiseSize, -CurTime(), VortexPosition[2] / NoiseSize) + 0.35, 0.05, 0.0005)

    self.MovementDirection = ((self.MovementDirection + DeviationOffset) * Vector(1, 1, 0)):GetNormalized()

    local HeightCheck = util.TraceLine({
        start = VortexPosition + Vector(0, 0, self.Height),
        endpos = VortexPosition - Vector(0, 0, 10000),
        mask = MASK_WATER + MASK_SOLID_BRUSHONLY,
        filter = self
    })

    local WallCheck = util.TraceLine({
        start = VortexPosition + Vector(0, 0, self.Height),
        endpos = VortexPosition + Vector(0, 0, self.Height) + (self.MovementDirection * math.max(Speed* 2, 10)),
        mask = MASK_WATER + MASK_SOLID_BRUSHONLY,
        filter = self
    })

    if WallCheck.Hit then
        self.MovementDirection = (self.MovementDirection - (2 * self.MovementDirection:Dot(WallCheck.HitNormal) * WallCheck.HitNormal) + (-(VortexPosition - Vector(0, 0, 0)):GetNormalized() * SuperRandom(1, 0))):GetNormalized()
    end

    if HeightCheck.Hit then
        self:SetPos((HeightCheck.HitPos + self.MovementDirection * Speed) + Vector(0, 0, self.Height))
    else
        self:SetPos(VortexPosition + self.MovementDirection * Speed)
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

function ENT:ShootZapper(AimTorward, Length)
    local LightningBallPosition = self:GetPos()
    local BoltTrace = util.TraceLine({
        start = LightningBallPosition,
        endpos = LightningBallPosition + (AimTorward * Length),
        mask = MASK_WATER + MASK_SOLID
    })

    if BoltTrace.Hit then
        util.ScreenShake(BoltTrace.HitPos, 5, 1, 1, 400, true)

        local TowardsBall = (LightningBallPosition - BoltTrace.HitPos):GetNormalized()
        local HitTarget = self:CreateHit(BoltTrace.HitPos - TowardsBall)

        XT3CreateConnectedParticle("astral_ball_lightning_strikearc1", LightningBallPosition, BoltTrace.HitPos)
        XT3ParticleEffect("astral_ball_lightning_strike", BoltTrace.HitPos, Angle(), self)

        local LightLifetime = SuperRandom(0.1, 0.2)
        local LightSize = SuperRandom(1000, 3000)

        local LightParams = {
            StartColor = {
                R = 255,
                G = 190,
                B = 255
            },
            EndColor = {
                R = 255,
                G = 190,
                B = 255
            },

            StartLightSize = LightSize,
            EndLightSize = LightSize,

            LifeTime = LightLifetime,
            LifeFadeExponent = 2,

            LightBrightness = 1,
            LightDecay = 1
        }

        net.Start("xt3_newdynamiclight")
        net.WriteEntity(HitTarget)
        net.WriteTable(LightParams)

        net.Broadcast()

        local Size = SuperRandom(0.5, 0.75)
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

        timer.Simple(5, function()
            if HitTarget:IsValid() then
                HitTarget:Remove()
            end
        end)

        local StrikeSize = 70

        local Entities = ents.FindInSphere(BoltTrace.HitPos + Vector(0, 0, 1), 70)
        for Index = 1, #Entities do
            local Entity = Entities[Index]
            if Entity:IsValid() and Entity ~= self and Entity:GetClass() ~= "gmod_ghost" and Entity:GetClass() ~= "sent_anim" and not Entity:IsWorld() and not Entity:IsWeapon() then
                local PhysObject = Entity:GetPhysicsObject()

                if PhysObject:IsValid() then
                    if (Entity:IsPlayer() and Entity:GetMoveType() ~= MOVETYPE_NOCLIP) or Entity:IsNPC() then
                        local BoltDamage = SuperRandom(25, 75) * (1 - math.min((BoltTrace.HitPos - (Entity:GetPos() + Vector(0, 0, 30))):Length() / StrikeSize, 1))
                        XT3CauseDamage(self, self, Entity, BoltDamage, DMG_SHOCK)
                        Entity:Ignite(SuperRandom(1, 5))
                    elseif not Entity:IsPlayer() and not Entity:IsNPC() then
                        local BoltDamage = SuperRandom(25, 75) * (1 - math.min((BoltTrace.HitPos - Entity:GetPos()):Length() / StrikeSize, 1))

                        PhysObject:ApplyForceCenter(-(BoltTrace.HitPos - Entity:GetPos()):GetNormalized() * 15000)
                        Entity:Ignite(SuperRandom(5, 30))

                        if (math.random(1, 2)) == 1 then
                            if constraint.HasConstraints() and not Entity:IsVehicle() and not Entity:IsRagdoll() then
                                constraint.RemoveAll(Entity)
                                Entity:EmitSound("PropDamage/break" .. math.random(1, 16) .. ".wav", SuperRandom(50, 130))
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

        local Entity = BoltTrace.Entity
        if Entity:IsValid() and Entity ~= self and Entity:GetClass() ~= "gmod_ghost" and Entity:GetClass() ~= "sent_anim" and not Entity:IsWorld() and not Entity:IsWeapon() then
            local PhysObject = Entity:GetPhysicsObject()

            if PhysObject:IsValid() then
                Entity:EmitSound("ambient/levels/labs/electric_explosion" .. math.random(1, 4) .. ".wav", SuperRandom(90, 110))
                util.ScreenShake(BoltTrace.HitPos, 25, 25, 1, 700, true)

                if (Entity:IsPlayer() and Entity:GetMoveType() ~= MOVETYPE_NOCLIP) or Entity:IsNPC() then
                    local BoltDamage = SuperRandom(25, 75) * (1 - math.min((BoltTrace.HitPos - (Entity:GetPos() + Vector(0, 0, 30))):Length() / StrikeSize, 1))
                    XT3CauseDamage(self, self, Entity, BoltDamage, DMG_SHOCK)
                    Entity:Ignite(SuperRandom(1, 5))
                elseif not Entity:IsPlayer() and not Entity:IsNPC() then
                    local BoltDamage = SuperRandom(25, 75) * (1 - math.min((BoltTrace.HitPos - Entity:GetPos()):Length() / StrikeSize, 1))

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

        EmitSound("ambient/energy/spark" .. math.random(1, 6) .. ".wav", BoltTrace.HitPos)
    end
end

function ENT:Think()
    if SERVER then
        self.Height = (100) + (50 * math.sin(CurTime()) / 2)
        self:CalculateMovement()

        if math.random(1, 5) == 1 then
            self:ShootZapper(Vector(SuperRandom(-1, 1), SuperRandom(-1, 1), SuperRandom(-1, 1)), 500)
        end

        local Entities = ents.FindInSphere(self:GetPos() + Vector(0, 0, 1), 500)
        for Index = 1, #Entities do
            local Entity = Entities[Index]
            if Entity:IsValid() and Entity ~= self and Entity:GetClass() ~= "gmod_ghost" and Entity:GetClass() ~= "sent_anim" and not Entity:IsWorld() and not Entity:IsWeapon() then
                local PhysObject = Entity:GetPhysicsObject()

                if PhysObject:IsValid() and (self:GetPos() - Entity:GetPos()):Length() < 55 then
                    if (Entity:IsPlayer() and Entity:GetMoveType() ~= MOVETYPE_NOCLIP) or Entity:IsNPC() then
                        local BoltDamage = SuperRandom(5, 10) * (1 - math.min((self:GetPos() - (Entity:GetPos() + Vector(0, 0, 30))):Length() / 50, 1))
                        XT3CauseDamage(self, self, Entity, BoltDamage, DMG_SHOCK)
                        Entity:Ignite(SuperRandom(1, 5))
                    elseif not Entity:IsPlayer() and not Entity:IsNPC() then
                        local BoltDamage = SuperRandom(5, 10) * (1 - math.min((self:GetPos() - Entity:GetPos()):Length() / 50, 1))

                        Entity:Ignite(SuperRandom(5, 30))

                        if (math.random(1, 2)) == 1 then
                            if constraint.HasConstraints() and not Entity:IsVehicle() and not Entity:IsRagdoll() then
                                constraint.RemoveAll(Entity)
                                Entity:EmitSound("PropDamage/break" .. math.random(1, 16) .. ".wav", SuperRandom(50, 130))
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

        local Entity = Entities[math.random(1, #Entities)]
        if Entity:IsValid() and Entity ~= self and Entity:GetClass() ~= "gmod_ghost" and Entity:GetClass() ~= "sent_anim" and not Entity:IsWorld() and not Entity:IsWeapon() then
            local PhysObject = Entity:GetPhysicsObject()

            if PhysObject:IsValid() then
                if (Entity:IsPlayer() and Entity:GetMoveType() ~= MOVETYPE_NOCLIP) or Entity:IsNPC() and math.random(1, 2) == 1 then
                    local BoltDirection = -(self:GetPos() - (Entity:GetPos() + Vector(0, 0, 30))):GetNormalized()
                    self:ShootZapper(BoltDirection, 500)
                elseif not Entity:IsPlayer() and not Entity:IsNPC() and (math.random(1, 5) == 1) or (Entity:IsRagdoll() and math.random(1, 2) == 1) then
                    local BoltDirection = -(self:GetPos() - (Entity:GetPos())):GetNormalized()
                    self:ShootZapper(BoltDirection, 500)
                end
            end
        end

    elseif CLIENT then

        local ZapperSpeedMult = 1
        local ZapperRandomance = (math.sin(SysTime() * 30 * ZapperSpeedMult) * 0.25) + (math.sin(SysTime() * 10 * ZapperSpeedMult) * 0.25) + (math.sin(SysTime() * 75 * ZapperSpeedMult) * 0.25) + (math.sin(SysTime() * 50 * ZapperSpeedMult) * 0.25)
        if ZapperRandomance ~= ZapperRandomance then
            ZapperRandomance = 0
            print("nan")
        end

        local DynamicLight = DynamicLight(self:EntIndex())
        if (DynamicLight) then
            DynamicLight.pos = self:GetPos()
            DynamicLight.r = 255
            DynamicLight.g = 100
            DynamicLight.b = 255
            DynamicLight.brightness = (3 + (1 * ZapperRandomance))
            DynamicLight.Decay = 1
            DynamicLight.Size = (2500 + (4000 * ZapperRandomance))
            DynamicLight.DieTime = CurTime() + 0.1
        end

    end

    self:NextThink(CurTime())
    return true
end

function ENT:OnRemove()
    self:StopParticles()

    if self.LightningSound then
        self.LightningSound:Stop()
        self.LightningSound = nil
    end
end

function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

AddCSLuaFile()

SWEP.PrintName = "Lightning gun"
SWEP.Author = "RainbowDoesStuff"
SWEP.Purpose = "Strike Them Down"
SWEP.Category = "XTwisters_Sweps"
SWEP.Slot = 1
SWEP.SlotPos = 3

SWEP.ViewModel = Model("models/weapons/c_superphyscannon.mdl")
SWEP.WorldModel = Model("models/weapons/w_Physics.mdl")
SWEP.ViewModelFOV = 54
SWEP.UseHands = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = true
SWEP.Secondary.Ammo = "none"

SWEP.DrawAmmo = false

function SWEP:Initialize()
    self:SetHoldType("physgun")
end

function SWEP:Reload()
    
end

function SWEP:CanBePickedUpByNPCs()
    return true
end

function SWEP:CreateHit(Position)
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

function SWEP:ShootZapper(AimTorward, Length)
    local Owner = self:GetOwner()
    local ShootPosition = (Owner:EyePos() + (Owner:GetAimVector() * 16)) or Owner:GetShootPos()

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
    net.WriteEntity(Owner)
    net.WriteTable(LightParams)

    net.Broadcast()

    if math.random() > 0.95 then
        EmitSound("ambient/ambience/rainscapes/thunder_close0" .. math.random(1, 4) .. ".wav", ShootPosition, 0, CHAN_AUTO, 1, 110)
    end

    EmitSound("ambient/energy/zap" .. math.random(1, 4) .. ".wav", ShootPosition, 0, CHAN_AUTO, 0.5, 75)

    local BoltTrace = util.TraceLine({
        start = ShootPosition,
        endpos = ShootPosition + (AimTorward * Length),
        mask = MASK_WATER + MASK_SOLID,
        filter = Owner
    })

    if not BoltTrace.Hit then
        BoltTrace = {
            Hit = true,
            HitPos = ShootPosition + (AimTorward * Length)
        }
    end

    if BoltTrace.Hit then
        local TowardsBall = (ShootPosition - BoltTrace.HitPos):GetNormalized()
        local ShootTarget = self:CreateHit(ShootPosition)
        local HitTarget = self:CreateHit(BoltTrace.HitPos)

        net.Start("xt3_connectbolt")
        net.WriteEntity(ShootTarget)
        net.WriteEntity(HitTarget)
        net.WriteString("astral_ball_lightning_strikearc1")

        net.Broadcast()

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
            Width = 0.5,
            Height = 0.5
        }

        timer.Simple(5, function()
            if HitTarget:IsValid() then
                HitTarget:Remove()
                ShootTarget:Remove()
            end
        end)

        local StrikeSize = 70

        if BoltTrace.Entity then
            net.Start("xt3_newdecal")
            net.WriteEntity(BoltTrace.Entity)
            net.WriteTable(DecalParams)

            net.Broadcast()

            local Entities = ents.FindInSphere(BoltTrace.HitPos + Vector(0, 0, 1), 70)
            for Index = 1, #Entities do
                local Entity = Entities[Index]
                if Entity:IsValid() and Entity ~= BoltTrace.Entity and Entity ~= Owner and Entity ~= self and Entity:GetClass() ~= "gmod_ghost" and Entity:GetClass() ~= "sent_anim" and not Entity:IsWorld() and not Entity:IsWeapon() then
                    local PhysObject = Entity:GetPhysicsObject()

                    local DistanceMult = (1 - math.min((BoltTrace.HitPos - (Entity:GetPos() + Vector(0, 0, 30))):Length() / StrikeSize, 1))
                    if PhysObject:IsValid() then
                        if (Entity:IsPlayer() and Entity:GetMoveType() ~= MOVETYPE_NOCLIP) or Entity:IsNPC() then
                            local BoltDamage = SuperRandom(15, 50) * DistanceMult
                            XT3CauseDamage(Owner, Owner, Entity, BoltDamage, DMG_SHOCK)
                            Entity:Ignite(SuperRandom(1, 5))
                        elseif not Entity:IsPlayer() and not Entity:IsNPC() then
                            local BoltDamage = SuperRandom(15, 50) * DistanceMult

                            PhysObject:ApplyForceCenter(-(BoltTrace.HitPos - Entity:GetPos()):GetNormalized() * 15000 * DistanceMult)
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

                            XT3CauseDamage(Owner, Owner, Entity, BoltDamage, DMG_SHOCK)
                        end
                    end
                end
            end

            local Entity = BoltTrace.Entity
            if Entity:IsValid() and Entity ~= Owner and Entity ~= self and Entity:GetClass() ~= "gmod_ghost" and Entity:GetClass() ~= "sent_anim" and not Entity:IsWorld() and not Entity:IsWeapon() then
                local PhysObject = Entity:GetPhysicsObject()

                if PhysObject:IsValid() then
                    Entity:EmitSound("ambient/levels/labs/electric_explosion" .. math.random(1, 4) .. ".wav", SuperRandom(90, 110))

                    if (Entity:IsPlayer() and Entity:GetMoveType() ~= MOVETYPE_NOCLIP) or Entity:IsNPC() then
                        local BoltDamage = SuperRandom(10, 35)
                        XT3CauseDamage(Owner, Owner, Entity, BoltDamage, DMG_SHOCK)
                        Entity:Ignite(SuperRandom(1, 5))
                    elseif not Entity:IsPlayer() and not Entity:IsNPC() then
                        local BoltDamage = SuperRandom(25, 75)

                        PhysObject:ApplyForceCenter(-TowardsBall * 15000)

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

                        XT3CauseDamage(Owner, Owner, Entity, BoltDamage, DMG_SHOCK)
                    end
                end
            end
        end

        local VectorAngle = TowardsBall:Angle()
        local ParticleAngle = Angle(VectorAngle.X, VectorAngle.Y, VectorAngle.Z)

        EmitSound("ambient/energy/spark" .. math.random(1, 6) .. ".wav", BoltTrace.HitPos)
        ParticleEffect("astral_ball_lightning_strike", BoltTrace.HitPos, ParticleAngle, self)
    end
end

function SWEP:PrimaryAttack()
    local Owner = self:GetOwner()

    self:SetNextPrimaryFire(CurTime() + 0.1)
    self:ShootEffects(self)

    if CLIENT then
        return
    end

    self:ShootZapper(Owner:GetAimVector() or Owner:GetShootPos(), 100000)
end

function SWEP:SecondaryAttack()
    local Owner = self:GetOwner()

    self:SetNextSecondaryFire(CurTime() + 0.035)

    self:ShootEffects(self)

    if CLIENT then
        return
    end

    self:ShootZapper((Owner:GetAimVector() or Owner:GetShootPos()) + Vector(SuperRandom(-1, 1), SuperRandom(-1, 1), SuperRandom(-1, 1)) / 10, 100000)
end

function SWEP:Think()
    if CLIENT then
        local LocalPlayer = LocalPlayer()
     
        local ViewModel = LocalPlayer:GetViewModel()
        ViewModel:SetPoseParameter("active", Lerp(perlinNoise1D(os.clock()*5)+0.5, 0.9, 1))
    end
end

function SWEP:ShouldDropOnDie()
    return false
end

function SWEP:GetNPCRestTimes()
    return 0.3, 0.6
end

function SWEP:GetNPCBurstSettings()
    return 1, 6, 0.1
end

function SWEP:GetNPCBulletSpread(proficiency)
    return 1
end

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.DisplayName = "Large Geyser"
ENT.PrintName = "XTwisters3 Geyser Large"

ENT.TimeSinceLastErupt = CurTime()
ENT.EruptElapsed = CurTime()
ENT.Erupting = false
ENT.EmittingEruptionParticle = false

ENT.NextEruptTime = 10
ENT.EruptTime = 60
ENT.BuildTime = 10

ENT.GeyserSize = 200
ENT.EruptSize = 200
ENT.EruptStrength = 200

local GeyserScale = Vector(5, 6, 1)
function ENT:Initialize()

    if SERVER then
        self.GyserSound = CreateSound(self, "ambient/levels/canals/dam_water_loop2.wav")
        self.GyserSound:Play()

        self.TimeSinceLastErupt = CurTime()

        timer.Simple(0.1, function()
            if self and self:IsValid() then
                ParticleEffectAttach("astral_largegeyser_idle", PATTACH_POINT_FOLLOW, self, 0)
            end
        end)

        self:SetModel("models/props_debris/concrete_spawnplug001a.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_FLY)

        local PhysicsObject = self:GetPhysicsObject()
        local PhysicsMesh = PhysicsObject:GetMeshConvexes()
        PhysicsObject:EnableMotion(false)

        for convexkey, convex in pairs(PhysicsMesh) do
            for poskey, postab in pairs(convex) do
                convex[poskey] = postab.pos * GeyserScale
            end
        end

        self:PhysicsInitMultiConvex(PhysicsMesh)
        self:EnableCustomCollisions(true)
        PhysicsObject = self:GetPhysicsObject()
        PhysicsObject:SetMass(15000)

    elseif CLIENT then

        local Matrix = Matrix()
        Matrix:Scale(GeyserScale * Vector(1, 1, 2))

        self:EnableMatrix("RenderMultiply", Matrix)

        local CornerMin, CornerMax = self:GetCollisionBounds()
        self:SetRenderBounds(CornerMin * GeyserScale, CornerMax * GeyserScale)

        language.Add("xt3_misc_geyser_large", "Large Geyser")
        killicon.Add("xt3_misc_geyser_large", "materials/KillIcons/johncenanudes.png", Color(255, 255, 255))
    end
end

function ENT:Think()
    if SERVER then
        local TimeSinceLastErupt = (CurTime() - self.TimeSinceLastErupt)

        if not self.Erupting and TimeSinceLastErupt > self.NextEruptTime then
            self.Erupting = true
            self.EruptElapsed = CurTime()
        end

        local GeyserPosition = self:GetPos() - (self:GetUp() * 2)
        if self.Erupting then
            local EruptElaspedTime = (CurTime() - self.EruptElapsed)
            local EruptTheta = math.min(EruptElaspedTime / self.EruptTime, 1)

            local EruptStrength = InverseLerp(EruptElaspedTime, 0, self.BuildTime)
            local EruptEnder = 1 - InverseLerp(EruptElaspedTime, self.EruptTime * 0.8, self.EruptTime)
            EruptStrength = self.EruptStrength * (EruptStrength * EruptEnder)

            self.GyserSound:ChangeVolume(InverseLerp(EruptStrength, 0, 100), 0)
            self.GyserSound:ChangePitch(Lerp(InverseLerp(EruptStrength, 50, 200), 65, 125), 0)
            self.GyserSound:SetSoundLevel(180)

            local Entities = ents.FindInSphere(GeyserPosition, self.EruptSize * 10)

            for Index = 1, #Entities do
                local Entity = Entities[Index]

                if Entity:IsValid() and Entity ~= self and Entity:GetClass() ~= "gmod_ghost" and Entity:GetClass() ~= "sent_anim" and not Entity:IsWorld() and not Entity:IsWeapon() then
                    local PhysObject = Entity:GetPhysicsObject()
                    if PhysObject:IsValid() then
                        local EntityPosition = Entity:GetPos()

                        local NormallizedVector = (GeyserPosition - EntityPosition)
                        local AwayVector = -NormallizedVector:GetNormalized()
                        local VectorLength = NormallizedVector:Length()

                        local UpDot = math.Clamp(AwayVector:Dot(self:GetUp()), 0, 1) ^ 2
                        local UpGeyserFade = UpDot * (self.EruptSize * 10)

                        local ForceIntensity = EruptStrength * ((1 - math.min(math.max(VectorLength - self.GeyserSize, 0) / (self.EruptSize + UpGeyserFade), 1)) ^ 2)
                        local ForceVector = (AwayVector + (self:GetUp() * 2)):GetNormalized() * ForceIntensity

                        local StrengthExponent = math.min((ForceIntensity ^ 2) / 10000, 1)
                        local ForceMultiplier = FrameTime() * 4

                        if Entity:IsRagdoll() then
                            ForceMultiplier = ForceMultiplier * 3
                        end

                        if PhysObject:IsMotionEnabled() and not (Entity:IsNPC() or Entity:IsPlayer()) then
                            local MaxWeight = math.max(1 - (PhysObject:GetMass() * GetConVar("xtwisters3_debrisweightmultiplier"):GetFloat()) / (ForceIntensity ^ 2 * 5), 0)
                            PhysObject:SetDamping(1.25 * StrengthExponent, 0)
                            PhysObject:SetDragCoefficient(1 * StrengthExponent)
                            PhysObject:ApplyForceCenter(ForceVector * 50 * math.max((math.min(PhysObject:GetMass(), 5000) * (1 / GetConVar("xtwisters3_debrisweightmultiplier"):GetFloat())) / 12, 1) * MaxWeight * ForceMultiplier)
                            PhysObject:AddAngleVelocity(ForceVector * 0.5 * MaxWeight * ForceMultiplier)
                        elseif GetConVar("xtwisters3_unweldprops"):GetBool() then
                            local WindResistance = 50 * (PhysObject:GetMass() / 10000)
                            local BreakChance = Lerp(InverseLerp(ForceIntensity, 40, 170 + WindResistance) ^ 0.045, 2700 + (6000 * (1 - StrengthExponent ^ 0.25)), 1)
                            BreakChance = BreakChance * Lerp(InverseLerp(ForceIntensity, 20, 40), 1000, 1)

                            if not PhysObject:IsMotionEnabled() and math.random(1, BreakChance) == 1 then
                                PhysObject:Wake()
                                PhysObject:EnableMotion(true)
                            end
                        end

                        if Entity:IsNPC() or Entity:IsRagdoll() or Entity:IsPlayer() then
                            if Entity:IsPlayer() then
                                ForceMultiplier = ForceMultiplier * 3
                            end

                            if Entity.AddVelocity then
                                Entity:AddVelocity(ForceVector * ForceMultiplier)
                            else
                                Entity:SetVelocity(ForceVector * ForceMultiplier)
                            end

                            local Damage = (5 * math.max((ForceIntensity - 60) / 350, 0)) / 10
                            if Damage >= 0.01 then
                                XT3CauseDamage(self, self, Entity, Damage * GetConVar("xtwisters3_damagemultiplier"):GetFloat(), DMG_BURN)
                            end
                        end
                    end
                end
            end

            if not self.EmittingEruptionParticle then
                ParticleEffectAttach("astral_largegeyser", PATTACH_POINT_FOLLOW, self, 0)
                self.EmittingEruptionParticle = true
                self:EmitSound("ambient/water/wave" .. math.random(1, 6) .. ".wav", 75, 100, 1)
            end

            if EruptTheta >= 1 then
                self.Erupting = false
                self.EmittingEruptionParticle = false
                self.NextEruptTime = math.random(10, 400)
                self.TimeSinceLastErupt = CurTime()
            end
        else
            local EruptStrength = self.EruptStrength / 10
            local Entities = ents.FindInSphere(GeyserPosition, self.GeyserSize * 2)

            self.GyserSound:ChangeVolume(InverseLerp(EruptStrength, 0, 100), 0)
            self.GyserSound:ChangePitch(Lerp(InverseLerp(EruptStrength, 50, 200), 65, 125), 0)
            self.GyserSound:SetSoundLevel(180)

            for Index = 1, #Entities do
                local Entity = Entities[Index]

                if Entity:IsValid() and Entity ~= self and Entity:GetClass() ~= "gmod_ghost" and Entity:GetClass() ~= "sent_anim" and not Entity:IsWorld() and not Entity:IsWeapon() then
                    local PhysObject = Entity:GetPhysicsObject()
                    if PhysObject:IsValid() then
                        local EntityPosition = Entity:GetPos()

                        local NormallizedVector = (GeyserPosition - EntityPosition)
                        local AwayVector = -NormallizedVector:GetNormalized()
                        local VectorLength = NormallizedVector:Length()

                        local UpDot = math.Clamp(AwayVector:Dot(self:GetUp()), 0, 1) ^ 2
                        local UpGeyserFade = UpDot * (self.EruptSize * 10)

                        local ForceIntensity = EruptStrength * ((1 - math.min(math.max(VectorLength - self.GeyserSize, 0) / (self.EruptSize + UpGeyserFade), 1)) ^ 2)
                        local ForceVector = (AwayVector + (self:GetUp() * 2)):GetNormalized() * ForceIntensity

                        local StrengthExponent = math.min((ForceIntensity ^ 2) / 10000, 1)
                        local ForceMultiplier = FrameTime() * 4

                        if Entity:IsRagdoll() then
                            ForceMultiplier = ForceMultiplier * 3
                        end

                        if PhysObject:IsMotionEnabled() and not (Entity:IsNPC() or Entity:IsRagdoll() or Entity:IsPlayer()) then
                            local MaxWeight = math.max(1 - (PhysObject:GetMass() * GetConVar("xtwisters3_debrisweightmultiplier"):GetFloat()) / (ForceIntensity ^ 2 * 5), 0)
                            PhysObject:SetDamping(1.25 * StrengthExponent, 0)
                            PhysObject:SetDragCoefficient(1 * StrengthExponent)
                            PhysObject:ApplyForceCenter(ForceVector * 50 * math.max((math.min(PhysObject:GetMass(), 5000) * (1 / GetConVar("xtwisters3_debrisweightmultiplier"):GetFloat())) / 12, 1) * MaxWeight * ForceMultiplier)
                            PhysObject:AddAngleVelocity(ForceVector * 0.5 * MaxWeight * ForceMultiplier)
                        elseif GetConVar("xtwisters3_unweldprops"):GetBool() then
                            local WindResistance = 50 * (PhysObject:GetMass() / 10000)
                            local BreakChance = Lerp(InverseLerp(ForceIntensity, 40, 170 + WindResistance) ^ 0.045, 2700 + (6000 * (1 - StrengthExponent ^ 0.25)), 1)
                            BreakChance = BreakChance * Lerp(InverseLerp(ForceIntensity, 20, 40), 1000, 1)

                            if not PhysObject:IsMotionEnabled() and math.random(1, BreakChance) == 1 then
                                PhysObject:Wake()
                                PhysObject:EnableMotion(true)
                            end
                        end

                        if Entity:IsNPC() or Entity:IsRagdoll() or Entity:IsPlayer() then
                            if Entity:IsPlayer() then
                                ForceMultiplier = ForceMultiplier * 3
                            end

                            if Entity.AddVelocity then
                                Entity:AddVelocity(ForceVector * ForceMultiplier)
                            else
                                Entity:SetVelocity(ForceVector * ForceMultiplier)
                            end

                            local Damage = (5 * math.max((ForceIntensity - 60) / 350, 0)) / 10
                            if Damage >= 0.01 then
                                XT3CauseDamage(self, self, Entity, Damage * GetConVar("xtwisters3_damagemultiplier"):GetFloat(), DMG_BURN)
                            end
                        end
                    end
                end
            end
        end
    end

    self:NextThink(CurTime())
    return true
end

function ENT:OnRemove()
    self:StopParticles()
    if SERVER  then
        XT3RemoveSound(self.GyserSound)
    end

end

function ENT:UpdateTransmitState()

    return TRANSMIT_ALWAYS
end

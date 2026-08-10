-- V-NPCs 3D Regurgitation & Ejection Physics Animation Engine (vnpcs_regurgitation_anim.lua)
-- Animates prey ejection from predator's mouth with burp foley and forward physics impulse

local regurg_enabled = CreateConVar("vnpcs_regurgitate_animation", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable 3D mouth ejection animation on regurgitation")
local regurg_force = CreateConVar("vnpcs_regurgitate_force", "260", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Forward physics force applied to regurgitated prey")
local regurg_up_force = CreateConVar("vnpcs_regurgitate_up_force", "130", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Upward physics force applied to regurgitated prey")

function VNPC_StartRegurgitationAnimation(pred, prey, belly)
    if not regurg_enabled:GetBool() then return end
    if not IsValid(prey) then return end

    local forward = Vector(1, 0, 0)
    local up = Vector(0, 0, 1)
    local origin = prey:GetPos()

    if IsValid(pred) then
        forward = pred:GetForward()
        up = pred:GetUp()

        -- Attempt to find mouth/head position
        local headBone = pred:LookupBone("ValveBiped.Bip01_Head1") or pred:LookupBone("Head1")
        if headBone then
            local bonePos = pred:GetBonePosition(headBone)
            if isvector(bonePos) and bonePos ~= vector_origin then
                origin = bonePos + (forward * 20) + (up * 5)
            end
        else
            origin = pred:GetPos() + Vector(0, 0, pred:OBBMaxs().z * 0.75) + (forward * 25)
        end

        -- Play burp audio and facial burp pose
        pred:EmitSound("burps/burp" .. math.random(1, 23) .. ".wav", 85, math.random(95, 105))
        if pred.SetFacialExpression then
            pcall(pred.SetFacialExpression, pred, 3)
            timer.Simple(1.25, function()
                if IsValid(pred) and pred.SetFacialExpression then
                    pcall(pred.SetFacialExpression, pred, 0)
                end
            end)
        end
    end

    prey:SetPos(origin)
    prey:SetAngles(Angle(0, forward:Angle().y, 0))

    local fForce = regurg_force:GetFloat()
    local uForce = regurg_up_force:GetFloat()
    local ejectVel = (forward * fForce) + (up * uForce)

    local phys = prey:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(true)
        phys:Wake()
        phys:SetVelocity(ejectVel)
    else
        prey:SetVelocity(ejectVel)
    end
end

concommand.Add("vnpcs_regurgitate_status", function(ply)
    print("=========================================")
    print("[V-NPCs] 3D Regurgitation Animation Status")
    print("Animation Enabled: " .. tostring(regurg_enabled:GetBool()))
    print("Forward Force: " .. tostring(regurg_force:GetFloat()))
    print("Upward Force: " .. tostring(regurg_up_force:GetFloat()))
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Regurgitation status printed to console.")
    end
end)

concommand.Add("vnpcs_test_regurgitate", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsPlayer() or target:IsNextBot()) then
        target = ply
    end
    local belly = target.VNPC_Belly or target.Belly
    if IsValid(belly) and belly.Prey and #belly.Prey > 0 then
        belly:Regurgitate(1)
        ply:ChatPrint("[V-NPCs] Tested regurgitate on " .. tostring(target))
    else
        ply:ChatPrint("[V-NPCs] Target has no prey to regurgitate!")
    end
end)

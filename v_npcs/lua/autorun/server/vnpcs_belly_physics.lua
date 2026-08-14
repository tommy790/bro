-- V-NPCs Belly Physics Engine - "Ragdoll Matrix" (vnpcs_belly_physics.lua)
-- Replaces the "invisible inventory slot" with a live internal physics simulation.
-- Every swallowed prey becomes a mass point inside the belly volume:
--   * gravity, drag, struggle impulses (personality + trait driven), soft-wall
--     containment inside the measured belly ellipsoid, and pairwise prey repulsion,
--   * the aggregate center-of-mass and slosh drive the GPU belly deformation
--     (via sh_vnpc_weight_paint.lua), the visual belly entity jiggle, slosh
--     sounds, and a movement weight penalty on the predator,
--   * optional visible "ragdoll matrix" copies (prop_ragdoll of each prey)
--     ride along inside the belly for the inside-camera and belly-view setups.
--
-- The integrator core (VNPC_BellyPhysicsStep) is pure and mirror-tested by
-- test_belly_physics_sim.py so the math is verifiable without a game server.

CreateConVar("vnpcs_belly_physics_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable the internal belly physics simulation (struggle masses, slosh, weight slowdown)")
CreateConVar("vnpcs_belly_physics_rate", "12", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Physics substeps per second for the belly mass simulation")
CreateConVar("vnpcs_belly_ragdoll_visual", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Create hidden ragdoll copies of swallowed NPCs inside the belly (ragdoll matrix, visible with the inside camera)")
CreateConVar("vnpcs_belly_ragdoll_max", "6", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Maximum ragdoll matrix copies per predator")
CreateConVar("vnpcs_belly_weight_slow", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Master multiplier for movement slowdown from belly weight")
CreateConVar("vnpcs_belly_struggle_kick", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Struggling prey physically kick the belly (slosh sound + mesh impulse)")
CreateConVar("vnpcs_belly_debug", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Debug the belly physics sim (console spam)")

-- ---------------------------------------------------------------------------
-- Pure simulation core (no entity access - unit-testable)
-- state.masses: { id, x, y, z, vx, vy, vz, mass, rx, ry, rz, kick, alive, struggle }
-- radii: belly ellipsoid half-extents (x right, y forward, z up)
-- ---------------------------------------------------------------------------

function VNPC_BellyPhysicsCreateState(masses)
    return {
        masses = masses or {},
        com = Vector(0, 0, 0),
        totalMass = 0,
        restlessness = 0,
        slosh = Vector(0, 0, 0),
        time = 0
    }
end

function VNPC_BellyPhysicsStep(state, dt, radii)
    if not state or not istable(state.masses) then return state end
    if not isvector(radii) then radii = Vector(16, 20, 13) end

    local g = 340.0          -- gravity toward belly bottom (units/s^2)
    local drag = 0.94        -- per-step velocity damping
    local restitution = 0.42 -- belly wall bounciness
    local kickBase = 46.0    -- struggle impulse base

    local masses = state.masses
    local n = #masses
    if n == 0 then
        state.com = Vector(0, 0, 0)
        state.totalMass = 0
        state.restlessness = math.max(0, (state.restlessness or 0) - dt * 2.2)
        return state
    end

    local rx, ry, rz = radii.x, radii.y, radii.z
    local totalMass = 0
    local com = Vector(0, 0, 0)
    local restlessness = state.restlessness or 0
    local slosh = state.slosh or Vector(0, 0, 0)

    -- 1. Integrate
    for i = 1, n do
        local m = masses[i]
        m.vz = m.vz - g * dt
        -- Struggle kicks: alive prey push against the belly
        local kick = m.kick or 0
        if kick > 0.01 then
            m.kick = math.max(0, kick - dt * 5.0)
        end
        if m.struggle and m.struggle > 0.01 then
            local impulse = kickBase * m.struggle * dt
            m.vx = m.vx + (math.random() - 0.5) * 2 * impulse
            m.vy = m.vy + (math.random() - 0.5) * 2 * impulse * 0.6
            m.vz = m.vz + math.abs(math.random() - 0.3) * impulse * 1.2
            restlessness = restlessness + impulse * dt
        end

        m.vx = m.vx * drag
        m.vy = m.vy * drag
        m.vz = m.vz * drag

        m.x = m.x + m.vx * dt
        m.y = m.y + m.vy * dt
        m.z = m.z + m.vz * dt

        -- 2. Soft-wall containment inside the belly ellipsoid
        local ex = m.x / math.max(rx, 1)
        local ey = m.y / math.max(ry, 1)
        local ez = m.z / math.max(rz, 1)
        local d = math.sqrt(ex * ex + ey * ey + ez * ez)
        if d > 1 then
            -- project the mass back onto the belly surface (hard containment)
            local corr = (1.0 - 0.015) / d
            m.x = m.x * corr
            m.y = m.y * corr
            m.z = m.z * corr
            -- reflect the outward velocity component (bounce)
            local nx, ny, nz = ex / d, ey / d, ez / d
            local vn = m.vx * nx + m.vy * ny + m.vz * nz
            if vn > 0 then
                m.vx = m.vx - (1 + restitution) * vn * nx
                m.vy = m.vy - (1 + restitution) * vn * ny
                m.vz = m.vz - (1 + restitution) * vn * nz
            end
            slosh = slosh + Vector(nx * math.abs(vn) * 0.5, ny * math.abs(vn) * 0.5, nz * math.abs(vn) * 0.5)
        end

        totalMass = totalMass + m.mass
        com = com + Vector(m.x, m.y, m.z) * m.mass
    end

    -- 3. Pairwise prey repulsion (prey cannot occupy the same space)
    for i = 1, n do
        for j = i + 1, n do
            local a, b = masses[i], masses[j]
            local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
            local rr = (a.rx + b.rx) * 0.55
            local d2 = dx * dx + dy * dy + dz * dz
            if d2 < rr * rr and d2 > 0.0001 then
                local d = math.sqrt(d2)
                local push = (rr - d) * 0.5 * dt * 10
                local nx, ny, nz = dx / d, dy / d, dz / d
                local ma = a.mass + b.mass
                local fa = b.mass / ma
                local fb = a.mass / ma
                a.x = a.x - nx * push * fb
                a.y = a.y - ny * push * fb
                a.z = a.z - nz * push * fb
                b.x = b.x + nx * push * fa
                b.y = b.y + ny * push * fa
                b.z = b.z + nz * push * fa
            end
        end
    end

    state.com = com / totalMass
    state.totalMass = totalMass
    state.restlessness = math.max(0, restlessness - dt * 3.0)
    state.slosh = slosh * 0.92
    state.time = (state.time or 0) + dt
    return state
end

-- Movement slowdown multiplier (0..1) from carried belly mass.
-- weight_resistance trait divides the effective weight; vnpcs_belly_weight_slow
-- is the global master. 1.0 = no slowdown.
function VNPC_GetBellyWeightSlow(pred)
    if not IsValid(pred) then return 1.0 end
    local enabled = GetConVar("vnpcs_belly_physics_enabled")
    if enabled and not enabled:GetBool() then return 1.0 end
    local master = GetConVar("vnpcs_belly_weight_slow")
    local masterMul = master and master:GetFloat() or 1.0
    if masterMul <= 0 then return 1.0 end

    local phys = pred.VNPC_BellyPhysics
    if not phys or not phys.totalMass or phys.totalMass <= 0 then return 1.0 end

    local effective = phys.totalMass
    if VNPC_GetTraitStat then
        effective = effective / math.max(VNPC_GetTraitStat(pred, "weight_resistance"), 0.1)
    end
    -- ~100 kg of prey -> ~15% slower; 400 kg -> ~45% slower
    local slow = 1.0 - (effective * 0.0016 * masterMul)
    return math.Clamp(slow, 0.4, 1.0)
end

-- Current slosh vector (local space) for mesh jiggle / sway.
function VNPC_GetBellySlosh(pred)
    if not IsValid(pred) or not pred.VNPC_BellyPhysics then return Vector(0, 0, 0) end
    return pred.VNPC_BellyPhysics.slosh or Vector(0, 0, 0)
end

-- ---------------------------------------------------------------------------
-- Server integration
-- ---------------------------------------------------------------------------

if SERVER then
    local function isMatrixCandidate(prey)
        if not IsValid(prey) then return false end
        if prey:IsPlayer() then return false end
        return prey:IsNPC() or prey:IsNextBot() or prey.IsDrGNextbot
    end

    local function getMatrixRagdoll(pred, preyId)
        local phys = pred.VNPC_BellyPhysics
        if not phys or not phys.matrix then return nil end
        return phys.matrix[preyId]
    end

    local function removeMatrixRagdoll(pred, preyId)
        local phys = pred.VNPC_BellyPhysics
        if not phys or not phys.matrix then return end
        local rag = phys.matrix[preyId]
        if IsValid(rag) then
            rag:Remove()
        end
        phys.matrix[preyId] = nil
    end

    -- ------------------------------------------------------------------
    -- Ragdoll matrix posing.
    --
    -- A prop_ragdoll renders from its PHYSICS OBJECTS, not from the entity
    -- transform, so SetPos/SetParent on the ragdoll entity leaves the copy
    -- frozen in its spawn bind pose ("standing there"). Instead we:
    --   1. pose the ragdoll into a curled swallowed ball once, using forward
    --      kinematics driven by the prey's measured body-part lengths and the
    --      addon's known-good "full belly" sit bone pose,
    --   2. store every bone as a local offset/angle relative to the pelvis,
    --   3. drive each bone physics object to the prey mass position every
    --      physics tick so the curled copy rides inside the belly.
    -- ------------------------------------------------------------------
    local MATRIX_BONE_ALTS = {
        ["ValveBiped.Bip01_Pelvis"] = { "Pelvis", "pelvis", "bip_pelvis" },
        ["ValveBiped.Bip01_Spine"] = { "Spine", "spine", "bip_spine_0" },
        ["ValveBiped.Bip01_Spine1"] = { "Spine1", "spine1", "bip_spine_1" },
        ["ValveBiped.Bip01_Spine2"] = { "Spine2", "spine2", "bip_spine_2" },
        ["ValveBiped.Bip01_Neck1"] = { "Neck1", "Neck", "neck", "bip_neck" },
        ["ValveBiped.Bip01_Head1"] = { "Head1", "Head", "head" },
        ["ValveBiped.Bip01_L_Thigh"] = { "L_Thigh", "l_thigh" },
        ["ValveBiped.Bip01_R_Thigh"] = { "R_Thigh", "r_thigh" },
        ["ValveBiped.Bip01_L_Calf"] = { "L_Calf", "l_calf" },
        ["ValveBiped.Bip01_R_Calf"] = { "R_Calf", "r_calf" },
        ["ValveBiped.Bip01_L_Foot"] = { "L_Foot", "l_foot" },
        ["ValveBiped.Bip01_R_Foot"] = { "R_Foot", "r_foot" },
        ["ValveBiped.Bip01_L_Clavicle"] = { "L_Clavicle", "l_clavicle" },
        ["ValveBiped.Bip01_R_Clavicle"] = { "R_Clavicle", "r_clavicle" },
        ["ValveBiped.Bip01_L_UpperArm"] = { "L_UpperArm", "l_upperarm" },
        ["ValveBiped.Bip01_R_UpperArm"] = { "R_UpperArm", "r_upperarm" },
        ["ValveBiped.Bip01_L_Forearm"] = { "L_Forearm", "l_forearm" },
        ["ValveBiped.Bip01_R_Forearm"] = { "R_Forearm", "r_forearm" },
        ["ValveBiped.Bip01_L_Hand"] = { "L_Hand", "l_hand" },
        ["ValveBiped.Bip01_R_Hand"] = { "R_Hand", "r_hand" }
    }

    -- FK chain: parent-before-child order used to propagate positions. The
    -- child offset is taken from the ragdoll's REST geometry (exact, no axis
    -- convention guessing) and reoriented by the child's new world angle.
    local MATRIX_FK = {
        { name = "ValveBiped.Bip01_Spine",   parent = "ValveBiped.Bip01_Pelvis" },
        { name = "ValveBiped.Bip01_Spine1",  parent = "ValveBiped.Bip01_Spine" },
        { name = "ValveBiped.Bip01_Spine2",  parent = "ValveBiped.Bip01_Spine1" },
        { name = "ValveBiped.Bip01_Neck1",   parent = "ValveBiped.Bip01_Spine2" },
        { name = "ValveBiped.Bip01_Head1",   parent = "ValveBiped.Bip01_Neck1" },
        { name = "ValveBiped.Bip01_L_Clavicle", parent = "ValveBiped.Bip01_Spine2" },
        { name = "ValveBiped.Bip01_R_Clavicle", parent = "ValveBiped.Bip01_Spine2" },
        { name = "ValveBiped.Bip01_L_UpperArm", parent = "ValveBiped.Bip01_L_Clavicle" },
        { name = "ValveBiped.Bip01_R_UpperArm", parent = "ValveBiped.Bip01_R_Clavicle" },
        { name = "ValveBiped.Bip01_L_Forearm", parent = "ValveBiped.Bip01_L_UpperArm" },
        { name = "ValveBiped.Bip01_R_Forearm", parent = "ValveBiped.Bip01_R_UpperArm" },
        { name = "ValveBiped.Bip01_L_Hand",   parent = "ValveBiped.Bip01_L_Forearm" },
        { name = "ValveBiped.Bip01_R_Hand",   parent = "ValveBiped.Bip01_R_Forearm" },
        { name = "ValveBiped.Bip01_L_Thigh",  parent = "ValveBiped.Bip01_Pelvis" },
        { name = "ValveBiped.Bip01_R_Thigh",  parent = "ValveBiped.Bip01_Pelvis" },
        { name = "ValveBiped.Bip01_L_Calf",   parent = "ValveBiped.Bip01_L_Thigh" },
        { name = "ValveBiped.Bip01_R_Calf",   parent = "ValveBiped.Bip01_R_Thigh" },
        { name = "ValveBiped.Bip01_L_Foot",   parent = "ValveBiped.Bip01_L_Calf" },
        { name = "ValveBiped.Bip01_R_Foot",   parent = "ValveBiped.Bip01_R_Calf" }
    }

    -- All bones we want to pose, in rest-capture order.
    local MATRIX_POSE_ORDER = {
        "ValveBiped.Bip01_Pelvis",
        "ValveBiped.Bip01_Spine",
        "ValveBiped.Bip01_Spine1",
        "ValveBiped.Bip01_Spine2",
        "ValveBiped.Bip01_Neck1",
        "ValveBiped.Bip01_Head1",
        "ValveBiped.Bip01_L_Clavicle",
        "ValveBiped.Bip01_R_Clavicle",
        "ValveBiped.Bip01_L_UpperArm",
        "ValveBiped.Bip01_R_UpperArm",
        "ValveBiped.Bip01_L_Forearm",
        "ValveBiped.Bip01_R_Forearm",
        "ValveBiped.Bip01_L_Hand",
        "ValveBiped.Bip01_R_Hand",
        "ValveBiped.Bip01_L_Thigh",
        "ValveBiped.Bip01_R_Thigh",
        "ValveBiped.Bip01_L_Calf",
        "ValveBiped.Bip01_R_Calf",
        "ValveBiped.Bip01_L_Foot",
        "ValveBiped.Bip01_R_Foot"
    }

    local function matrixFindBonePhys(rag, name)
        if not IsValid(rag) or not rag.LookupBone then return nil end
        local id = rag:LookupBone(name)
        if id and id >= 0 then
            local po = rag:GetPhysicsObject(id)
            if IsValid(po) then return po end
        end
        for _, alt in ipairs(MATRIX_BONE_ALTS[name] or {}) do
            id = rag:LookupBone(alt)
            if id and id >= 0 then
                local po = rag:GetPhysicsObject(id)
                if IsValid(po) then return po end
            end
        end
        return nil
    end

    -- Pose the ragdoll into a curled swallowed ball and store per-bone local
    -- offsets/angles relative to the pelvis so the update loop can drive it.
    --
    -- Semantics match the addon's ManipulateBoneAngles usage: each pose offset
    -- rotates the bone around its OWN rest frame (worldAng = restAng * offset).
    -- Positions propagate rigidly: every child keeps its rest offset from its
    -- parent, reoriented by the child's new world angle - so the pose matches
    -- whatever the same offsets do to NPCs in-game, and the limbs stay
    -- connected instead of exploding.
    function VNPC_PoseMatrixRagdoll(rag, prey)
        -- capture rest geometry (bind pose, before any physics tick)
        local rest = {}
        for _, name in ipairs(MATRIX_POSE_ORDER) do
            local po = matrixFindBonePhys(rag, name)
            if po then
                rest[name] = { po = po, pos = po:GetPos(), ang = po:GetAngles() }
            end
        end
        local pelvis = rest["ValveBiped.Bip01_Pelvis"]
        if not pelvis then return false end

        -- Pose offsets: prefer the addon's proven in-game sitting keyframe
        -- (childbirth pose = knees up, shins folded, arms wrapped), then the
        -- measured "full belly" fixed pose, then identity.
        local pose = VNPC_GetFixedBonePose and VNPC_GetFixedBonePose(prey)
        local full = pose and pose[2] or nil
        local function poseAng(name, fallback)
            local kf = VNPC_ChildbirthSittingPoseKeyframe
            if kf and kf[name] and kf[name].ang then return kf[name].ang end
            if full and full[name] and full[name].ang then return full[name].ang end
            return fallback
        end

        local pelvisAng = pelvis.ang * poseAng("ValveBiped.Bip01_Pelvis", Angle(0, 0, 0))
        pelvis.po:SetAngles(pelvisAng)
        pelvis.po:SetPos(pelvis.pos)

        local posed = { ["ValveBiped.Bip01_Pelvis"] = { pos = pelvis.pos, ang = pelvisAng } }
        local bones = {
            { phys = pelvis.po, lx = 0, ly = 0, lz = 0, localAng = Angle(0, 0, 0) }
        }

        for _, link in ipairs(MATRIX_FK) do
            local parent = posed[link.parent]
            local child = rest[link.name]
            if parent and child then
                local parentRest = rest[link.parent]
                local newAng = child.ang * poseAng(link.name, Angle(0, 0, 0))
                -- rest offset of the child from its parent, in the child's rest frame
                local restOffset = child.ang:WorldToLocal(child.pos - (parentRest and parentRest.pos or parent.pos))
                local newPos = parent.pos + newAng:LocalToWorld(restOffset)
                child.po:SetPos(newPos)
                child.po:SetAngles(newAng)
                posed[link.name] = { pos = newPos, ang = newAng }
                -- Angle:WorldToLocal rotates around the origin, so pass the
                -- position relative to the pelvis root
                local lp = pelvisAng:WorldToLocal(newPos - pelvis.pos)
                table.insert(bones, {
                    phys = child.po,
                    lx = lp.x,
                    ly = lp.y,
                    lz = lp.z,
                    localAng = pelvisAng:Inverse() * newAng
                })
            end
        end

        rag.VNPC_MatrixBones = bones
        return true
    end

    function VNPC_CreateMatrixRagdoll(pred, prey, mass)
        local enabled = GetConVar("vnpcs_belly_ragdoll_visual")
        if enabled and not enabled:GetBool() then return nil end
        local cap = GetConVar("vnpcs_belly_ragdoll_max")
        local maxRags = cap and cap:GetInt() or 6
        local phys = pred.VNPC_BellyPhysics
        if not phys or not phys.matrix then return nil end
        if table.Count(phys.matrix) >= maxRags then return nil end

        local mdl = prey:GetModel()
        if not isstring(mdl) or mdl == "" or not util.IsValidModel(mdl) then return nil end

        local rag = ents.Create("prop_ragdoll")
        if not IsValid(rag) then return nil end
        rag:SetModel(mdl)
        rag.VNPC_RagdollMatrix = true
        rag.VNPC_MatrixOwner = prey
        rag:SetPos(pred:GetPos())
        rag:Spawn()
        rag:Activate()
        rag:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        rag:SetSolid(SOLID_NONE)
        -- Freeze every bone so the copy costs ~nothing and never fights the belly
        for i = 0, rag:GetPhysicsObjectCount() - 1 do
            local physObj = rag:GetPhysicsObject(i)
            if IsValid(physObj) then
                physObj:EnableMotion(false)
                physObj:EnableCollisions(false)
                physObj:Sleep()
            end
        end
        -- Scale the copy to the prey's model scale
        if rag.SetModelScale then
            rag:SetModelScale(prey:GetModelScale() or 1)
        end
        -- Curl it into the swallowed pose; if the model has no usable pelvis
        -- skeleton, drop the copy instead of leaving a standing ghost.
        if not VNPC_PoseMatrixRagdoll(rag, prey) then
            rag:Remove()
            return nil
        end
        rag.VNPC_MatrixMass = mass
        phys.matrix[prey:EntIndex()] = rag
        return rag
    end

    -- Build masses from the belly's prey list and sync with ragdoll copies.
    local function rebuildPhysics(pred, belly, now)
        local phys = pred.VNPC_BellyPhysics
        if not phys then return end

        local byId = {}
        for _, m in ipairs(phys.masses) do
            byId[m.id] = m
        end

        local newMasses = {}
        local seen = {}
        if istable(belly.Prey) then
            for _, info in ipairs(belly.Prey) do
                if not istable(info) then continue end
                if info.Absorbing then continue end
                if info.WombPrey or info.NoDigest or (IsValid(info.Entity) and (info.Entity.VNPC_IsWombPrey or info.Entity.VNPC_IsUnbornBaby)) then continue end
                local prey = info.Entity
                if not IsValid(prey) then continue end
                local id = prey:EntIndex()
                seen[id] = true

                local m = byId[id]
                if not m then
                    local blob = VNPC_GetPreyShapeBlob and VNPC_GetPreyShapeBlob(prey)
                    m = {
                        id = id,
                        x = 0,
                        y = 8,  -- enter near the top (esophagus)
                        z = 4,
                        vx = 0,
                        vy = -30,
                        vz = 0,
                        mass = blob and blob.mass or 45,
                        rx = blob and blob.rx or 7.5,
                        ry = blob and blob.ry or 9,
                        rz = blob and blob.rz or 6.5,
                        kick = 0,
                        struggle = 0,
                        lastStruggle = 0
                    }
                end
                m.alive = prey:Health() > 0 and info.Alive ~= false
                m.swallowing = prey.VNPC_IsBeingSwallowed == true
                -- Struggle drive: personality * trait * alive
                local struggle = 0
                if m.alive and not m.swallowing then
                    struggle = 1.0
                    if VNPC_GetPreyPersonality then
                        local _, pdata = VNPC_GetPreyPersonality(prey)
                        if pdata and pdata.struggle_multiplier then
                            struggle = struggle * pdata.struggle_multiplier
                        end
                    end
                    if VNPC_GetTraitStat then
                        struggle = struggle * VNPC_GetTraitStat(prey, "struggle_energy")
                    end
                    if prey.VNPC_IsExhausted then
                        struggle = struggle * 0.3
                    end
                end
                m.struggle = struggle
                table.insert(newMasses, m)

                -- Ragdoll matrix copies
                if isMatrixCandidate(prey) then
                    local rag = getMatrixRagdoll(pred, id)
                    if not IsValid(rag) then
                        rag = VNPC_CreateMatrixRagdoll(pred, prey, m)
                    end
                    if IsValid(rag) then
                        rag.VNPC_MatrixMass = m
                    end
                else
                    removeMatrixRagdoll(pred, id)
                end
            end
        end

        -- Remove masses and ragdolls for prey that left the belly
        for _, m in ipairs(phys.masses) do
            if not seen[m.id] then
                removeMatrixRagdoll(pred, m.id)
            end
        end
        phys.masses = newMasses
    end

    function VNPC_UpdateMatrixRagdolls(pred)
        local phys = pred.VNPC_BellyPhysics
        if not phys or not phys.matrix then return end
        local now = CurTime()
        for preyId, rag in pairs(phys.matrix) do
            if not IsValid(rag) then
                phys.matrix[preyId] = nil
            else
                local m = rag.VNPC_MatrixMass
                if not m or not rag.VNPC_MatrixBones then
                    phys.matrix[preyId] = nil
                    rag:Remove()
                else
                    -- Base frame: the prey mass position in the predator's local
                    -- space. The sim runs in pred-local axes (x right, y forward,
                    -- z up), so the ragdoll ball rides exactly where the belly
                    -- mesh bulges.
                    local basePos = pred:LocalToWorld(Vector(m.x, m.y, m.z))
                    local baseAng = pred:LocalToWorldAngles(Angle(0, 0, 0))

                    -- Wobble so the curled copy feels alive while the prey struggles
                    local wobble = 0
                    if m.struggle and m.struggle > 0.3 then
                        wobble = math.sin(now * 5.2 + preyId) * 0.6 * math.min(m.struggle, 1.5)
                    end

                    for i, bone in ipairs(rag.VNPC_MatrixBones) do
                        if IsValid(bone.phys) then
                            -- pelvis (i=1) anchors exactly on the mass point; limbs wobble
                            local limbWob = (i > 1) and wobble * 0.4 * (1 - i / 24) or 0
                            local worldPos = basePos
                                + baseAng:Right() * (bone.lx + limbWob * 0.5)
                                + baseAng:Forward() * bone.ly
                                + baseAng:Up() * (bone.lz + limbWob * 0.3)
                            bone.phys:SetPos(worldPos)
                            bone.phys:SetAngles(baseAng * bone.localAng)
                        end
                    end
                end
            end
        end
    end

    local function applyPredEffects(pred, phys, dt)
        -- Weight slowdown (predators slow down as they get heavier)
        local slow = VNPC_GetBellyWeightSlow(pred)
        if pred.VNPC_BaseRunSpeed == nil and pred.RunSpeed then
            pred.VNPC_BaseRunSpeed = pred.RunSpeed
        end
        if pred.VNPC_BaseWalkSpeed == nil and pred.WalkSpeed then
            pred.VNPC_BaseWalkSpeed = pred.WalkSpeed
        end
        if pred.VNPC_BaseRunSpeed and pred.SetRunSpeed then
            pcall(pred.SetRunSpeed, pred, pred.VNPC_BaseRunSpeed * slow)
        end
        if pred.VNPC_BaseWalkSpeed and pred.SetWalkSpeed then
            pcall(pred.SetWalkSpeed, pred, pred.VNPC_BaseWalkSpeed * slow)
        end

        -- Slosh sounds on hard kicks / fast mass motion
        local kickEnabled = GetConVar("vnpcs_belly_struggle_kick")
        if kickEnabled and kickEnabled:GetBool() and (phys.slosh or Vector(0,0,0)):Length() > 22 then
            if (pred.VNPC_NextSloshSound or 0) <= CurTime() then
                pred.VNPC_NextSloshSound = CurTime() + 1.1
                if VNPC_EmitBellySlosh then
                    pcall(VNPC_EmitBellySlosh, pred)
                end
            end
        end

        -- Feed the GPU jiggle an impulse so the belly visibly bounces on kicks
        local kickMag = 0
        for _, m in ipairs(phys.masses) do
            if m.kick and m.kick > 0.5 then
                kickMag = math.max(kickMag, m.kick)
            end
        end
        pred.VNPC_GPUKickBoost = math.max(pred.VNPC_GPUKickBoost or 0, kickMag * 0.35)
    end

    hook.Add("Think", "VNPC_BellyPhysics_SimLoop", function()
        local enabled = GetConVar("vnpcs_belly_physics_enabled")
        if enabled and not enabled:GetBool() then return end
        local rate = GetConVar("vnpcs_belly_physics_rate")
        local subDt = 1.0 / math.max(4, rate and rate:GetInt() or 12)
        local now = CurTime()

        for _, pred in ipairs(ents.GetAll()) do
            if not IsValid(pred) or pred:IsPlayer() then continue end
            if not (pred.Predator or pred.VNPC_FemaleModelVore or pred.IsDrGNextbot) then continue end
            if pred.Vored or pred.VNPC_Vored then continue end

            local belly = pred.VNPC_Belly or pred.Belly
            if not IsValid(belly) then
                pred.VNPC_BellyPhysics = nil
                continue
            end

            if not pred.VNPC_BellyPhysics then
                pred.VNPC_BellyPhysics = VNPC_BellyPhysicsCreateState()
                pred.VNPC_BellyPhysics.matrix = {}
            end
            local phys = pred.VNPC_BellyPhysics
            if (phys.nextThink or 0) > now then continue end
            phys.nextThink = now + subDt * 2

            rebuildPhysics(pred, belly, now)

            -- Ellipsoid radii from the weight-paint metrics (fallback: fixed)
            local radii = Vector(15, 18, 12)
            if VNPC_GetBellyDeformMetrics then
                local metrics = VNPC_GetBellyDeformMetrics(pred)
                if metrics then
                    radii = Vector(math.max(8, metrics.rx), math.max(9, metrics.ry), math.max(7, metrics.rz))
                end
            end

            -- Multiple substeps for stability
            for _ = 1, 2 do
                VNPC_BellyPhysicsStep(phys, subDt, radii)
            end

            VNPC_UpdateMatrixRagdolls(pred)
            applyPredEffects(pred, phys, subDt * 2)

            -- Replicate blobs for the client mesh every 0.2s
            if (phys.nextSync or 0) <= now then
                phys.nextSync = now + 0.2
                if VNPC_SyncPaintBlobNW then
                    VNPC_SyncPaintBlobNW(pred)
                end
            end
        end
    end)

    -- Cleanup when a predator dies or is removed
    hook.Add("EntityRemoved", "VNPC_BellyPhysics_Cleanup", function(ent)
        if not IsValid(ent) or not ent.VNPC_BellyPhysics or not ent.VNPC_BellyPhysics.matrix then return end
        for _, rag in pairs(ent.VNPC_BellyPhysics.matrix) do
            if IsValid(rag) then rag:Remove() end
        end
        ent.VNPC_BellyPhysics.matrix = {}
    end)

    -- Cleanup when a prey is regurgitated / removed (handled by rebuildPhysics
    -- via the seen list, but also catch direct removals)
    hook.Add("EntityRemoved", "VNPC_BellyPhysics_PreyCleanup", function(prey)
        if not IsValid(prey) then return end
        for _, pred in ipairs(ents.GetAll()) do
            if IsValid(pred) and pred.VNPC_BellyPhysics and pred.VNPC_BellyPhysics.matrix then
                removeMatrixRagdoll(pred, prey:EntIndex())
            end
        end
    end)

    -- Headless self-test: run the pure integrator on synthetic masses.
    concommand.Add("vnpcs_belly_physics_sim", function(ply)
        local state = VNPC_BellyPhysicsCreateState()
        for i = 1, 3 do
            table.insert(state.masses, {
                id = i, x = 0, y = 8 + i * 2, z = 5, vx = 0, vy = -20, vz = 0,
                mass = 50 + i * 10, rx = 7, ry = 8, rz = 6, kick = 0, struggle = 1.0
            })
        end
        local radii = Vector(15, 18, 12)
        local simTime = 0
        local maxSpeed = 0
        local dt = 1 / 20
        while simTime < 6 do
            VNPC_BellyPhysicsStep(state, dt, radii)
            simTime = simTime + dt
            for _, m in ipairs(state.masses) do
                local sp = math.sqrt(m.vx * m.vx + m.vy * m.vy + m.vz * m.vz)
                if sp > maxSpeed then maxSpeed = sp end
            end
        end
        print("===============================================================")
        print("     V-NPCs BELLY PHYSICS HEADLESS SIMULATION (6 sim seconds) ")
        print("===============================================================")
        print(" - Masses: 3 synthetic prey (50/60/70 kg)")
        print(" - Max particle speed during sim: " .. string.format("%.2f u/s", maxSpeed))
        print(" - Final center of mass: " .. tostring(state.com))
        print(" - Final total mass: " .. string.format("%.1f kg", state.totalMass))
        print(" - Final restlessness: " .. string.format("%.2f", state.restlessness))
        local inside = true
        for _, m in ipairs(state.masses) do
            local d = math.sqrt((m.x / 15) ^ 2 + (m.y / 18) ^ 2 + (m.z / 12) ^ 2)
            if d > 1.01 then inside = false end
            print(string.format(" - Mass[%d] pos=(%.1f, %.1f, %.1f) containment=%.2f %s", m.id, m.x, m.y, m.z, d, (d <= 1.01) and "OK" or "BREACHED"))
        end
        print(" - Sim stable: " .. tostring(inside and maxSpeed < 400))
        print("===============================================================")
        if IsValid(ply) then
            ply:ChatPrint("[V-NPCs] Belly physics sim finished. See console for results.")
        end
    end)

    concommand.Add("vnpcs_belly_physics_status", function(ply)
        print("===============================================================")
        print("        V-NPCs BELLY PHYSICS ENGINE (RAGDOLL MATRIX) STATUS    ")
        print("===============================================================")
        print(" - Physics Enabled: " .. tostring(GetConVar("vnpcs_belly_physics_enabled"):GetBool()))
        print(" - Sim Rate: " .. tostring(GetConVar("vnpcs_belly_physics_rate"):GetInt()) .. " Hz")
        print(" - Ragdoll Matrix Visuals: " .. tostring(GetConVar("vnpcs_belly_ragdoll_visual"):GetBool()) .. " (max " .. tostring(GetConVar("vnpcs_belly_ragdoll_max"):GetInt()) .. "/pred)")
        print(" - Weight Slow Master: " .. tostring(GetConVar("vnpcs_belly_weight_slow"):GetFloat()))
        print(" - Struggle Kicks: " .. tostring(GetConVar("vnpcs_belly_struggle_kick"):GetBool()))
        local count = 0
        for _, pred in ipairs(ents.GetAll()) do
            if IsValid(pred) and pred.VNPC_BellyPhysics and pred.VNPC_BellyPhysics.masses and #pred.VNPC_BellyPhysics.masses > 0 then
                count = count + 1
                local phys = pred.VNPC_BellyPhysics
                local rags = table.Count(phys.matrix or {})
                local slow = VNPC_GetBellyWeightSlow(pred)
                print(string.format(" -> #%d [%s] masses=%d totalMass=%.1fkg com=%s slosh=%.1f ragdolls=%d slow=%.0f%%",
                    pred:EntIndex(), pred.PrintName or pred:GetClass(), #phys.masses, phys.totalMass,
                    tostring(phys.com), (phys.slosh or Vector(0,0,0)):Length(), rags, (1 - slow) * 100))
            end
        end
        if count == 0 then print(" - No predators with simulated belly content.") end
        print("===============================================================")
        if IsValid(ply) then
            ply:ChatPrint("[V-NPCs] Belly physics status printed to console. Simulated predators: " .. count)
        end
    end)

    concommand.Add("vnpcs_test_belly_kick", function(ply)
        if not IsValid(ply) then return end
        local target = ply:GetEyeTrace().Entity
        if not IsValid(target) or not (target.Predator or target.VNPC_FemaleModelVore or target.IsDrGNextbot) then
            ply:ChatPrint("[V-NPCs] Aim at a predator to kick its belly physics!")
            return
        end
        local phys = target.VNPC_BellyPhysics
        if not phys or #phys.masses == 0 then
            ply:ChatPrint("[V-NPCs] That predator has no simulated belly content.")
            return
        end
        for _, m in ipairs(phys.masses) do
            m.kick = m.kick + 8
            m.struggle = 2.0
        end
        if VNPC_EmitBellySlosh then pcall(VNPC_EmitBellySlosh, target) end
        ply:ChatPrint(string.format("[V-NPCs] Kicked the belly of %s (%d masses) - watch the mesh and listen for slosh!", tostring(target), #phys.masses))
    end)
end

-- Note: belly_modules/mechanics.lua's ragdoll-removal safety hooks check for
-- ent.VNPC_RagdollMatrix and skip our matrix copies (see the edit there).

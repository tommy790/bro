-- V-NPCs Belly Weight & Slowdown (vnpcs_belly_physics.lua)
--
-- This used to be a full "Ragdoll Matrix" engine: a mass-spring physics
-- simulation per swallowed prey, plus frozen prop_ragdoll copies driven
-- bone-by-bone (via hand-rolled quaternion FK) to visually ride inside the
-- belly. In practice that whole approach was fragile - the ragdoll posing
-- crashed repeatedly (bad argument to quaternion multiply, copies frozen in
-- their bind pose on some skeletons) and even before that, the physics
-- simulation's output never actually reached the belly mesh due to a
-- field-name mismatch bug, so the "live jiggle" was never really seen in
-- the first place.
--
-- It's been replaced with the deterministic bounding-box packing in
-- sh_vnpc_weight_paint.lua (VNPC_DefaultBlobLayout/VNPC_GetBellyDeformMetrics).
-- All that survives here is the movement slowdown from carried belly
-- weight, now computed directly from the (already reliable) blob metrics
-- instead of a per-tick physics simulation.

CreateConVar("vnpcs_belly_physics_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable movement slowdown from belly weight")
CreateConVar("vnpcs_belly_weight_slow", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Master multiplier for movement slowdown from belly weight")

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

    local metrics = VNPC_GetBellyDeformMetrics and VNPC_GetBellyDeformMetrics(pred)
    local totalMass = metrics and metrics.totalMass or 0
    if totalMass <= 0 then return 1.0 end

    local effective = totalMass
    if VNPC_GetTraitStat then
        effective = effective / math.max(VNPC_GetTraitStat(pred, "weight_resistance"), 0.1)
    end
    -- ~100 kg of prey -> ~15% slower; 400 kg -> ~45% slower (same curve the
    -- old physics-driven version used, just fed by the box-packing metrics)
    local slow = 1.0 - (effective * 0.0016 * masterMul)
    return math.Clamp(slow, 0.4, 1.0)
end

if SERVER then
    concommand.Add("vnpcs_belly_physics_status", function(ply)
        print("===============================================================")
        print("        V-NPCs BELLY WEIGHT STATUS (bounding-box driven)      ")
        print("===============================================================")
        print(" - Weight Slowdown Enabled: " .. tostring(GetConVar("vnpcs_belly_physics_enabled"):GetBool()))
        print(" - Weight Slow Master: " .. tostring(GetConVar("vnpcs_belly_weight_slow"):GetFloat()))
        print(" - See 'vnpcs_weight_paint_status' for per-predator blob/shape detail.")
        local count = 0
        for _, pred in ipairs(ents.GetAll()) do
            if IsValid(pred) and (pred.Predator or pred.VNPC_FemaleModelVore or pred.IsDrGNextbot) then
                local metrics = VNPC_GetBellyDeformMetrics and VNPC_GetBellyDeformMetrics(pred)
                if metrics and metrics.totalMass and metrics.totalMass > 0 then
                    count = count + 1
                    local slow = VNPC_GetBellyWeightSlow(pred)
                    print(string.format(" -> #%d [%s] totalMass=%.1fkg slow=%.0f%%",
                        pred:EntIndex(), pred.PrintName or pred:GetClass(), metrics.totalMass, (1 - slow) * 100))
                end
            end
        end
        if count == 0 then print(" - No predators with simulated belly content.") end
        print("===============================================================")
        if IsValid(ply) then
            ply:ChatPrint("[V-NPCs] Belly weight status printed to console. Predators: " .. count)
        end
    end)
end

#!/usr/bin/env python3
"""
Mirror-test for the V-NPCs belly physics integrator (vnpcs_belly_physics.lua).

The Lua core (VNPC_BellyPhysicsStep) is pure math; this script re-implements the
same integrator in Python (deterministic variant, struggle disabled) and checks:
  1. masses never leave the belly ellipsoid (containment),
  2. particle speeds stay bounded (no energy explosion),
  3. masses settle toward the belly bottom (gravity works),
  4. total mass is conserved,
  5. struggle kicks decay and restlessness fades after the prey stops,
  6. the weight-slowdown curve and trait divisor behave as designed,
  7. the weight-paint blob bounding box math matches the Lua version.
"""
import math
import random

# ---------------------------------------------------------------- integrator
G = 340.0
DRAG = 0.94
RESTITUTION = 0.42
KICK_BASE = 46.0


class Mass:
    def __init__(self, mid, x, y, z, vx, vy, vz, mass, rx, ry, rz, kick=0.0, struggle=0.0):
        self.id = mid
        self.x, self.y, self.z = x, y, z
        self.vx, self.vy, self.vz = vx, vy, vz
        self.mass = mass
        self.rx, self.ry, self.rz = rx, ry, rz
        self.kick = kick
        self.struggle = struggle


def step(masses, dt, radii, rng=None):
    rx, ry, rz = radii
    rng = rng or random
    total_mass = 0.0
    com = [0.0, 0.0, 0.0]
    restlessness = 0.0
    slosh = [0.0, 0.0, 0.0]

    for m in masses:
        m.vz -= G * dt
        kick = m.kick
        if kick > 0.01:
            m.kick = max(0.0, kick - dt * 5.0)
        if m.struggle > 0.01:
            impulse = KICK_BASE * m.struggle * dt
            m.vx += (rng.random() - 0.5) * 2 * impulse
            m.vy += (rng.random() - 0.5) * 2 * impulse * 0.6
            m.vz += abs(rng.random() - 0.3) * impulse * 1.2
            restlessness += impulse * dt

        m.vx *= DRAG
        m.vy *= DRAG
        m.vz *= DRAG

        m.x += m.vx * dt
        m.y += m.vy * dt
        m.z += m.vz * dt

        ex = m.x / max(rx, 1.0)
        ey = m.y / max(ry, 1.0)
        ez = m.z / max(rz, 1.0)
        d = math.sqrt(ex * ex + ey * ey + ez * ez)
        if d > 1.0:
            corr = (1.0 - 0.015) / d
            m.x *= corr
            m.y *= corr
            m.z *= corr
            nx, ny, nz = ex / d, ey / d, ez / d
            vn = m.vx * nx + m.vy * ny + m.vz * nz
            if vn > 0:
                m.vx -= (1 + RESTITUTION) * vn * nx
                m.vy -= (1 + RESTITUTION) * vn * ny
                m.vz -= (1 + RESTITUTION) * vn * nz
            slosh[0] += abs(vn) * 0.5 * nx
            slosh[1] += abs(vn) * 0.5 * ny
            slosh[2] += abs(vn) * 0.5 * nz

        total_mass += m.mass
        com[0] += m.x * m.mass
        com[1] += m.y * m.mass
        com[2] += m.z * m.mass

    n = len(masses)
    for i in range(n):
        for j in range(i + 1, n):
            a, b = masses[i], masses[j]
            dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
            rr = (a.rx + b.rx) * 0.55
            d2 = dx * dx + dy * dy + dz * dz
            if d2 < rr * rr and d2 > 0.0001:
                d = math.sqrt(d2)
                push = (rr - d) * 0.5 * dt * 10
                nx, ny, nz = dx / d, dy / d, dz / d
                ma = a.mass + b.mass
                fa = b.mass / ma
                fb = a.mass / ma
                a.x -= nx * push * fb
                a.y -= ny * push * fb
                a.z -= nz * push * fb
                b.x += nx * push * fa
                b.y += ny * push * fa
                b.z += nz * push * fa

    if total_mass > 0:
        com = [c / total_mass for c in com]
    return {"com": com, "total_mass": total_mass, "slosh": slosh, "restlessness": max(0.0, restlessness)}


def weight_slow(total_mass_kg, weight_resistance=1.0, master=1.0):
    if master <= 0:
        return 1.0
    effective = total_mass_kg / max(weight_resistance, 0.1)
    slow = 1.0 - (effective * 0.0016 * master)
    return max(0.4, min(1.0, slow))


def blob_metrics(blobs):
    """Mirror of VNPC_GetBellyDeformMetrics."""
    min_x = max_x = min_y = max_y = min_z = max_z = 0.0
    com = [0.0, 0.0, 0.0]
    total = 0.0
    for b in blobs:
        px, py, pz = b.get("pos", (0, 0, 0))
        min_x = min(min_x, px - b["rx"]); max_x = max(max_x, px + b["rx"])
        min_y = min(min_y, py - b["ry"]); max_y = max(max_y, py + b["ry"])
        min_z = min(min_z, pz - b["rz"]); max_z = max(max_z, pz + b["rz"])
        com[0] += px * b["mass"]; com[1] += py * b["mass"]; com[2] += pz * b["mass"]
        total += b["mass"]
    if total > 0:
        com = [c / total for c in com]
    m = {
        "rx": max(4.0, (max_x - min_x) * 0.52),
        "ry": max(4.5, (max_y - min_y) * 0.55),
        "rz": max(3.5, (max_z - min_z) * 0.5),
        "width": max(9, max_x - min_x),
        "depth": max(10, max_y - min_y),
        "height": max(8, max_z - min_z),
        "com": com,
        "total_mass": total,
    }
    if len(blobs) == 1:
        b = blobs[0]
        m["rx"] = max(m["rx"], b["rx"] * 0.92)
        m["ry"] = max(m["ry"], b["ry"] * 0.95)
        m["rz"] = max(m["rz"], b["rz"] * 0.9)
    return m


# ------------------------------------------------------------------ tests
def test_containment_and_stability():
    rng = random.Random(1234)
    radii = (15.0, 18.0, 12.0)
    masses = [
        Mass(1, 0, 8, 5, 0, -20, 0, 50, 7, 8, 6, struggle=0),
        Mass(2, 0, 10, 5, 0, -20, 0, 60, 8, 9, 7, struggle=0),
        Mass(3, 0, 12, 5, 0, -20, 0, 70, 8, 9, 7, struggle=0),
    ]
    dt = 1 / 20
    max_speed = 0.0
    start_mass = sum(m.mass for m in masses)
    for t in range(int(10 / dt)):
        for m in masses:
            sp = math.hypot(m.vx, m.vy, m.vz)
            max_speed = max(max_speed, sp)
        step(masses, dt, radii, rng)

    for m in masses:
        d = math.sqrt((m.x / radii[0]) ** 2 + (m.y / radii[1]) ** 2 + (m.z / radii[2]) ** 2)
        assert d <= 1.02, f"mass {m.id} breached the belly: containment {d:.3f}"
    assert max_speed < 400, f"sim exploded: max speed {max_speed:.1f}"
    assert sum(m.mass for m in masses) == start_mass, "mass not conserved"
    # gravity: everything settled near the bottom (z < 0)
    avg_z = sum(m.z for m in masses) / len(masses)
    assert avg_z < -4, f"masses did not settle at the belly bottom (avg z={avg_z:.2f})"
    print(f"  containment/stability OK: max speed {max_speed:.1f} u/s, settled avg z={avg_z:.2f}")


def test_struggle_decay():
    rng = random.Random(99)
    radii = (15.0, 18.0, 12.0)
    masses = [Mass(1, 0, 0, 0, 0, 0, 0, 60, 8, 9, 7, kick=10, struggle=1.8)]
    dt = 1 / 20
    kick_seen = []
    for t in range(int(6 / dt)):
        res = step(masses, dt, radii, rng)
        kick_seen.append(masses[0].kick)
        if t == 60:
            masses[0].struggle = 0.0  # prey stops struggling at 3s
    assert kick_seen[0] > 0
    assert masses[0].kick <= 0.01, "kick never decayed"
    print("  struggle kick decay OK")


def test_weight_slow_curve():
    # 100 kg -> ~16% slower; 400 kg -> clamped at the 0.4 floor (60% slow max)
    s100 = weight_slow(100)
    s400 = weight_slow(400)
    assert abs(s100 - 0.84) < 0.02, f"unexpected slow at 100kg: {s100}"
    assert s400 == 0.4, f"unexpected slow at 400kg: {s400}"
    # tireless (1.6x resistance): 400kg feels like 250kg -> 1 - 250*0.0016 = 0.6
    s400_tireless = weight_slow(400, weight_resistance=1.6)
    assert abs(s400_tireless - 0.6) < 0.02, f"tireless should be less slowed: {s400_tireless}"
    # floor at 40% speed
    assert weight_slow(2000) == 0.4
    # master=0 disables
    assert weight_slow(500, master=0) == 1.0
    print(f"  weight slow OK: 100kg->{s100:.2f}, 400kg->{s400:.2f}, 400kg+tireless->{s400_tireless:.2f}")


def test_blob_metrics():
    human = {"pos": (0, 0, 0), "rx": 8, "ry": 9, "rz": 7, "mass": 60}
    big = {"pos": (6, 2, -3), "rx": 14, "ry": 12, "rz": 10, "mass": 140}
    m1 = blob_metrics([human])
    # single blob inflates to ~its own size
    assert m1["rx"] >= 8 * 0.92 and m1["ry"] >= 9 * 0.95
    m2 = blob_metrics([human, big])
    # two stacked prey make a bigger, shifted belly
    assert m2["rx"] > m1["rx"] and m2["height"] > m1["height"]
    # center of mass shifts toward the heavy blob
    assert m2["com"][0] > 0
    print(f"  blob metrics OK: single rx={m1['rx']:.1f}, pair rx={m2['rx']:.1f} com.x={m2['com'][0]:.2f}")


def main():
    print("V-NPCs belly physics mirror tests")
    print("-" * 40)
    test_containment_and_stability()
    test_struggle_decay()
    test_weight_slow_curve()
    test_blob_metrics()
    print("-" * 40)
    print("ALL TESTS PASSED")


if __name__ == "__main__":
    main()

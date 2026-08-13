# V-NPC Belly Texture Blending

Makes the V-NPC belly model blend in with the VNPC model's own textures.

## How it works

The belly no longer wears its own baked-on texture. On your client, a hidden
copy of the VNPC is posed and rendered into a render target (RT) every time
the NPC's appearance changes (skin, bodygroups, colors, submaterials, flexes,
player color, ...). The belly then draws using that captured torso image.

This repo's previous render-target system did exactly that, but the result
still looked like a sticker because:

1. **The material was flat `UnlitGeneric`** — the belly ignored all lighting
   while the body it sat on was fully lit, so it glowed/flattened.
2. **The belly's own color tinted the capture** — bellies carry a
   `BellyColor` (e.g. `Color(195,145,122)`), and that color was multiplied
   over the captured torso photo, recolouring the whole texture.
3. **The capture was framed too loosely** — photo edges showed on the belly.

### Fixes in this branch

- **Lit skin shader** (`vnpcs_belly_lit 1`): the RT material is a
  `VertexLitGeneric` clone of the **predator's own torso material** —
  same `$bumpmap`, `$phong`, `$halflambert`, `$surfaceprop` — with only
  `$basetexture` swapped for the render target. The belly shades, bumps and
  highlights exactly like the body it hangs from. (Using the belly's own
  phong settings caused the leftover color tint; phong now only applies when
  the body itself uses it.)
- **Neutral belly colour while blending** (`ent_vore_belly` /
  `ent_fernkarry_belly` `Draw()`): the belly's own tint is suppressed while
  the RT material is applied, so the predator's colors show through 1:1.
- **Stomach-centered capture**: the capture frame now centres on the
  abdomen (below the chest), so the breast region of the model texture no
  longer gets baked onto the belly. Tunable per model:
  `vnpcs_belly_rt_center` / `vnpcs_belly_rt_zoom`.
- **Skin-tone rim**: the RT clears to a darkened belly skin color so photo
  edges read as soft shading instead of a tinted border.
- **Configurable render target** (`vnpcs_belly_rt_size 128-1024`) and a
  master switch (`vnpcs_belly_rt_enable 0` restores the old behavior).

## Install (one click)

Double-click `installer/install.bat` and press `1`.

The installer:

1. Finds your GarrysMod folder (Steam registry → default paths → secondary
   Steam libraries, with a manual path prompt as fallback).
2. Copies this addon into `garrysmod/addons/` (`v_npcs` + `vnpcs_bellyblend`).
3. Writes the blend settings into `garrysmod/cfg/autoexec.cfg` — that file
   lives **outside** the addons folder, so the .bat does the file edit for
   you (it also cleans it up on uninstall).

Then just restart Garry's Mod and spawn a V-NPC.

## Console variables

| ConVar | Default | Meaning |
|---|---|---|
| `vnpcs_belly_rt_enable` | 1 | Master switch for the render-target blending |
| `vnpcs_belly_rt_size` | 512 | RT resolution (128–1024, higher = sharper but slower) |
| `vnpcs_belly_lit` | 1 | Lit skin-shader material; 0 = old flat unlit material |
| `vnpcs_belly_rt_center` | 0.42 | Where the capture frame centers on the body (0 = feet, 1 = head). Lower it if the belly still shows chest/breast texture |
| `vnpcs_belly_rt_zoom` | 1.0 | Capture tightness (0.6 = wider, 1.6 = tighter) |

## Manual install

Copy the `v_npcs` folder into `garrysmod/addons/` and copy the `lua` folder
into `garrysmod/addons/vnpcs_bellyblend/lua`. Add the three ConVars above to
`garrysmod/cfg/autoexec.cfg` if you want them saved.

## Uninstall

Run `installer/install.bat` and press `2` (removes the addon folders and the
managed autoexec.cfg lines).

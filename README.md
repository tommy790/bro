# V-NPC Belly Texture Blending

Makes the V-NPC belly model blend in with the VNPC model's own textures.

## How it works (mesh mode - no camera)

The belly model's triangles are rebuilt as a custom mesh whose UVs are
remapped into the **abdomen region of the VNPC's own skin texture** (the
predator model's triangles that sit directly under the belly, projected into
UV space). The belly then renders with a clone of the **predator's own
material** - the same `$basetexture`, `$bumpmap`, `$phong` and
`$halflambert` settings the body uses.

That means the belly IS the body's skin: identical texture, identical
lighting, identical shading - by construction. No camera, no render target,
no capture lag, no resolution limits, and the chest can never end up in the
frame because the sampled region is found by 3D position, not by framing.

The belly's own spring/wobble/struggle animations are applied to the mesh
directly (scale, rotation, and the flexes from `belly_modules/animations.lua`
become mesh ripples), so the belly still grows, jiggles and bulges like
before.

**Fallback**: if a model's mesh data can't be read, the belly automatically
falls back to the older render-target camera system
(`vnpcs_belly_rt.lua`), which photographs the predator's torso and uses it
as the belly texture.

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
| `vnpcs_belly_mesh` | 1 | Mesh mode (belly samples the body's own skin texture). 0 = old RT camera path |
| `vnpcs_belly_mesh_flipu` | 0 | Flip the sampled texture horizontally (if the skin looks mirrored) |
| `vnpcs_belly_mesh_flipv` | 0 | Flip the sampled texture vertically |
| `vnpcs_belly_rt_enable` | 1 | RT-camera fallback master switch |
| `vnpcs_belly_rt_size` | 512 | RT resolution (128–1024) used by the fallback |
| `vnpcs_belly_lit` | 1 | Lit material on the RT fallback |
| `vnpcs_belly_rt_center` | 0.42 | RT fallback frame center (0 = feet, 1 = head) |
| `vnpcs_belly_rt_zoom` | 1.0 | RT fallback frame tightness |

## Manual install

Copy the `v_npcs` folder into `garrysmod/addons/` and copy the `lua` folder
into `garrysmod/addons/vnpcs_bellyblend/lua`. Add the ConVars above to
`garrysmod/cfg/autoexec.cfg` if you want them saved.

## Uninstall

Run `installer/install.bat` and press `2` (removes the addon folders and the
managed autoexec.cfg lines).

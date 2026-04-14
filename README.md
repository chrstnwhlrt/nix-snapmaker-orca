# nix-snapmaker-orca

Nix flake packaging [Snapmaker Orca](https://www.snapmaker.com/snapmaker-orca)
— a beta slicer for the Snapmaker U1 multi-color 3D printer, forked from
[OrcaSlicer](https://github.com/SoftFever/OrcaSlicer) with SnapSwap
multi-color support and Snapmaker-curated filament profiles.

This flake **builds Snapmaker Orca from source** against nixpkgs
dependencies — no AppImage, no FHS sandbox, no bind-mount tricks for
`/run/opengl-driver`. The derivation is modelled on nixpkgs' upstream
`orca-slicer` package and adds three small patches to make Snapmaker's
fork build under nixpkgs tooling (modern CMake, GCC 15, and the
explicit webkit2gtk-4.1 link that Snapmaker gates behind a `FLATPAK`
check).

## Quick start

Run without installing:

```bash
nix run github:chrstnwhlrt/nix-snapmaker-orca
```

Install imperatively to your user profile:

```bash
nix profile install github:chrstnwhlrt/nix-snapmaker-orca
```

## As a flake input

```nix
{
  inputs.snapmaker-orca.url = "github:chrstnwhlrt/nix-snapmaker-orca";

  outputs = { self, nixpkgs, snapmaker-orca, ... }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            snapmaker-orca.packages.${pkgs.system}.default
          ];
        })
      ];
    };
  };
}
```

## Via overlay

```nix
{
  nixpkgs.overlays = [ inputs.snapmaker-orca.overlays.default ];
  environment.systemPackages = [ pkgs.snapmaker-orca ];
}
```

## NVIDIA support

The derivation defaults to `withNvidiaGLWorkaround = true`. On NVIDIA
hosts the proprietary driver's EGL implementation regularly fails with
`EGL_BAD_PARAMETER` on modern Wayland compositors; the workaround
routes OpenGL through mesa + zink (OpenGL over Vulkan) so that the
slicer's 3D preview stays functional regardless of the NVIDIA driver's
EGL state.

To use native NVIDIA EGL instead (e.g. on hosts where it works), pass
an override when consuming the overlay or `callPackage`-ing the
derivation directly:

```nix
snapmaker-orca = final.callPackage snapmakerOrca { withNvidiaGLWorkaround = false; };
```

## Updating to a new upstream release

When Snapmaker publishes a new release:

```bash
nix run nixpkgs#nix-update -- --flake snapmaker-orca
git diff flake.nix                  # review version + hash bump
nix build .#default                 # verify it still builds
git commit -am "snapmaker-orca: bump to <version>"
```

Or manually: change `version` in `flake.nix`, set
`hash = lib.fakeHash;`, run `nix build .#default` — Nix reports the
real hash, paste it in, rebuild.

After any upstream bump re-check the three patches:
`link-webkit2gtk-on-linux.patch`, `dont-link-opencv-world-orca.patch`,
`no-ilmbase.patch`. If Snapmaker moves the corresponding source lines
the patches' context hunks will need small adjustments.

## Flake outputs

| output                          | purpose                                         |
| ------------------------------- | ----------------------------------------------- |
| `packages.x86_64-linux.default` | the slicer derivation, built from source        |
| `apps.x86_64-linux.default`     | `nix run` target                                |
| `overlays.default`              | adds `pkgs.snapmaker-orca`                      |
| `checks.x86_64-linux.build`     | `nix flake check` will actually build it        |
| `formatter.x86_64-linux`        | `nix fmt` uses `pkgs.nixfmt`                    |

## Requirements

- Your user in the `dialout` group for USB serial to the U1
- `avahi` / mDNS for network printer discovery (most distros already)
- Working OpenGL stack (any recent mesa or NVIDIA driver)
- A machine with enough RAM for the build (~6 GB peak; the derivation
  compiles ~3 GB of C++ translation units)

## Build time

First build is **~25 minutes on 24 cores** (no superbuild — nixpkgs
provides Boost, OCCT, wxWidgets and friends, and only Snapmaker's
vendored `deps_src/` libraries plus the slicer itself are compiled).
Subsequent rebuilds are fully cached unless a dependency changes.

## Patches applied

Three patches live in `./patches/`:

- **`link-webkit2gtk-on-linux.patch`** — Snapmaker only links
  `libwebkit2gtk-4.1` inside the `if (FLATPAK)` branch of
  `src/slic3r/CMakeLists.txt`, but `WebView.cpp` references webkit
  symbols directly. Without this patch the final executable link
  fails with "DSO missing from command line".
- **`dont-link-opencv-world-orca.patch`** (from nixpkgs upstream) —
  links `opencv_core` + `opencv_imgproc` instead of the unified
  `opencv_world`, because nixpkgs' opencv is split.
- **`no-ilmbase.patch`** (from nixpkgs upstream, originally
  [PrusaSlicer #14207](https://github.com/prusa3d/PrusaSlicer/pull/14207))
  — removes the obsolete IlmBase dependency from `FindOpenVDB.cmake`.
  Required because nixpkgs' OpenVDB no longer pulls in IlmBase.

In addition, a small `prePatch` adjusts include paths (`nlopt_cxx` →
`nlopt` and `libnoise/noise.h` → `noise/noise.h`) to match nixpkgs'
layout.

## Disclaimer

This is an **unofficial, community-maintained** Nix packaging of
Snapmaker Orca. It is **not affiliated with, endorsed by, or
supported by Snapmaker**. Snapmaker®, Snapmaker Orca, Snapmaker U1,
and SnapSwap are trademarks of their respective owners. This
repository only provides Nix-side build plumbing and downloads the
unmodified upstream source at build time.

- Bugs in the slicer itself (UI, slicing behaviour, printer
  communication, crashes): report upstream at
  <https://github.com/Snapmaker/OrcaSlicer>.
- Issues specific to **this Nix flake** (build failure, patch
  regression, dependency problem on NixOS): open an issue here.

The software is provided without any warranty. You use it at your
own risk.

## License

The Nix packaging code (`flake.nix`, `patches/*.patch`, and related
files) is MIT licensed — see [LICENSE](./LICENSE).

The built Snapmaker Orca binary remains under
[AGPL-3.0-only](https://spdx.org/licenses/AGPL-3.0-only.html) per
upstream.

## Links

- Upstream source: <https://github.com/Snapmaker/OrcaSlicer>
- Snapmaker Orca homepage: <https://www.snapmaker.com/snapmaker-orca>
- Snapmaker U1 wiki: <https://wiki.snapmaker.com/en/FAQ/u1>
- nixpkgs' sibling `orca-slicer`:
  <https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name/or/orca-slicer>

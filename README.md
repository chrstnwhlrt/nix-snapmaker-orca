# nix-snapmaker-orca

Nix flake packaging the [Snapmaker Orca](https://www.snapmaker.com/snapmaker-orca)
AppImage — a beta slicer for the Snapmaker U1 multi-color 3D printer,
forked from [OrcaSlicer](https://github.com/SoftFever/OrcaSlicer) with
SnapSwap multi-color support and Snapmaker-curated filament profiles.

Upstream is AppImage-only; this flake wraps it with nixpkgs'
`appimageTools.wrapType2` so it runs on NixOS like any native package:
proper XDG desktop entry, hicolor icons, MIME-type registration for
STL/3MF/OBJ/AMF, and the NVIDIA/Wayland `WEBKIT_DISABLE_COMPOSITING_MODE`
workaround baked in.

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
    # NixOS configuration
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

## Updating to a new upstream release

When Snapmaker publishes a new release:

```bash
nix run nixpkgs#nix-update -- --flake snapmaker-orca
git diff flake.nix        # review version + hash bump
nix flake check           # verify it still builds
git commit -am "snapmaker-orca: bump to <version>"
```

Or manually: change `version` in `flake.nix`, set `hash = lib.fakeHash;`,
run `nix build .#default` — Nix reports the real hash, paste it in,
rebuild.

## Flake outputs

| output                          | purpose                                      |
| ------------------------------- | -------------------------------------------- |
| `packages.x86_64-linux.default` | the wrapped slicer derivation                |
| `apps.x86_64-linux.default`     | `nix run` target                             |
| `overlays.default`              | adds `pkgs.snapmaker-orca`                   |
| `checks.x86_64-linux.build`     | `nix flake check` will actually build it     |
| `formatter.x86_64-linux`        | `nix fmt` uses `pkgs.nixfmt`                 |

## Requirements

- User in the `dialout` group for USB serial to the U1
- `avahi` / mDNS for network printer discovery (most distros already)
- Working GL stack (OpenGL driver in user session)

## Disclaimer

This is an **unofficial, community-maintained** Nix packaging of Snapmaker
Orca. It is **not affiliated with, endorsed by, or supported by Snapmaker**.
Snapmaker®, Snapmaker Orca, Snapmaker U1, and SnapSwap are trademarks of
their respective owners. This repository only provides a Nix-side wrapper
and redistributes the unmodified upstream AppImage under its original
license.

- Bugs in the slicer itself (UI, slicing behaviour, printer communication,
  crashes): report upstream at
  <https://github.com/Snapmaker/OrcaSlicer>.
- Issues specific to **this Nix flake** (build failure, wrapper runtime
  issue, dependency problem on NixOS): open an issue here.

The software is provided without any warranty. You use it at your own risk.

## License

The Nix packaging code (`flake.nix` and related files) is MIT licensed — see
[LICENSE](./LICENSE).

The wrapped Snapmaker Orca binary remains under
[AGPL-3.0-only](https://spdx.org/licenses/AGPL-3.0-only.html) per upstream,
and is redistributed unchanged via the `fetchurl` at build time.

## Links

- Upstream: https://github.com/Snapmaker/OrcaSlicer
- Snapmaker Orca homepage: https://www.snapmaker.com/snapmaker-orca
- Snapmaker U1 wiki: https://wiki.snapmaker.com/en/FAQ/u1

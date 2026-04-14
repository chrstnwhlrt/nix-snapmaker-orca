{
  description = "Snapmaker Orca — beta slicer for Snapmaker U1 (AppImage wrapper)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            inherit system;
            pkgs = nixpkgs.legacyPackages.${system};
          }
        );

      # Package derivation. The function signature is nixpkgs-conformant so
      # the whole block can be dropped verbatim into nixpkgs as
      # `pkgs/by-name/sn/snapmaker-orca/package.nix` when PR'ing upstream.
      snapmakerOrca =
        {
          lib,
          fetchurl,
          appimageTools,
          makeDesktopItem,
          nix-update-script,
          webkitgtk_4_1,
          libsoup_3,
          libsecret,
          glib-networking,
          gst_all_1,
        }:

        let
          pname = "snapmaker-orca";
          version = "2.3.0";

          # Beta / Ubuntu-build tags kept as single-point-of-truth vars so
          # future releases that change the asset naming need one edit only.
          channel = "Beta";
          buildTag = "Ubuntu2404";

          src = fetchurl {
            url = "https://github.com/Snapmaker/OrcaSlicer/releases/download/v${version}/Snapmaker_Orca_Linux_AppImage_${buildTag}_V${version}_${channel}.AppImage";
            # Stable store-path name, decoupled from the asset filename.
            name = "${pname}-${version}.AppImage";
            hash = "sha256-02du3A5Thd61N6ROh0lqTHtjEAeIS61SNNzE9cjYsJs=";
          };

          # Extract the AppImage once — only needed to lift out the icon.
          contents = appimageTools.extract { inherit pname version src; };

          # Fresh desktop item instead of patching the upstream one; more
          # robust against future changes in the shipped .desktop file.
          desktopItem = makeDesktopItem {
            name = pname;
            exec = "${pname} %F";
            icon = pname;
            desktopName = "Snapmaker Orca";
            genericName = "3D Slicer";
            comment = "Beta slicer for Snapmaker U1 (OrcaSlicer fork)";
            categories = [
              "Graphics"
              "3DGraphics"
              "Engineering"
            ];
            mimeTypes = [
              "model/stl"
              "application/vnd.ms-3mfdocument"
              "application/prs.wavefront-obj"
              "application/x-amf"
            ];
            keywords = [
              "slicer"
              "3d-printing"
              "snapmaker"
              "orca"
              "gcode"
            ];
            startupNotify = true;
            startupWMClass = "Snapmaker_Orca";
          };
        in
        appimageTools.wrapType2 {
          inherit pname version src;

          # Runtime libraries the AppImage does not bundle itself.
          # Reference: nixpkgs' orca-slicer (from-source) buildInputs.
          extraPkgs = pkgs: [
            webkitgtk_4_1 # Embedded browser (marketplace / settings views)
            libsoup_3 # WebKit HTTP stack
            libsecret # Credential storage (web logins)
            glib-networking # TLS backend for WebKit
            gst_all_1.gstreamer
            gst_all_1.gst-plugins-base
            gst_all_1.gst-plugins-good
            gst_all_1.gst-plugins-bad # h264 decoder for print previews
          ];

          # NVIDIA / Wayland blank-window workaround, same as nixpkgs
          # orca-slicer applies via its preFixup.
          extraBwrapArgs = [
            "--setenv"
            "WEBKIT_DISABLE_COMPOSITING_MODE"
            "1"
          ];

          extraInstallCommands = ''
            install -Dm644 ${desktopItem}/share/applications/${pname}.desktop \
              $out/share/applications/${pname}.desktop

            # Mirror every hicolor size upstream ships and rename it to our
            # pname, so future AppImages with more/different sizes are picked
            # up without a code change.
            if [ -d ${contents}/usr/share/icons/hicolor ]; then
              for png in ${contents}/usr/share/icons/hicolor/*/apps/Snapmaker_Orca.png; do
                size_dir=$(dirname "$(dirname "$png")")
                size=$(basename "$size_dir")
                install -Dm644 "$png" "$out/share/icons/hicolor/$size/apps/${pname}.png"
              done
            fi
          '';

          # Lets `nix-update snapmaker-orca` bump version + hash automatically.
          passthru.updateScript = nix-update-script { };

          meta = {
            description = "Beta slicer for the Snapmaker U1 (OrcaSlicer fork with SnapSwap multi-color)";
            longDescription = ''
              Snapmaker Orca is a fork of OrcaSlicer maintained by Snapmaker,
              tuned for the Snapmaker U1 multi-color printer with SnapSwap
              integration and Snapmaker-curated filament profiles. This
              package wraps the upstream Linux AppImage for reproducible use
              on NixOS.

              The project is in public beta; release cadence is irregular.
            '';
            homepage = "https://www.snapmaker.com/snapmaker-orca";
            changelog = "https://github.com/Snapmaker/OrcaSlicer/releases/tag/v${version}";
            license = lib.licenses.agpl3Only;
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            platforms = [ "x86_64-linux" ];
            mainProgram = pname;
            maintainers = [ ];
          };
        };
    in
    {
      packages = forAllSystems (
        { pkgs, ... }:
        rec {
          snapmaker-orca = pkgs.callPackage snapmakerOrca { };
          default = snapmaker-orca;
        }
      );

      apps = forAllSystems (
        { system, ... }:
        rec {
          snapmaker-orca = {
            type = "app";
            program = nixpkgs.lib.getExe self.packages.${system}.snapmaker-orca;
            meta = self.packages.${system}.snapmaker-orca.meta;
          };
          default = snapmaker-orca;
        }
      );

      overlays.default = final: _prev: {
        snapmaker-orca = final.callPackage snapmakerOrca { };
      };

      checks = forAllSystems (
        { system, ... }:
        {
          build = self.packages.${system}.default;
        }
      );

      formatter = forAllSystems ({ pkgs, ... }: pkgs.nixfmt);
    };
}

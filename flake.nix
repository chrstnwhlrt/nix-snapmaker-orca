{
  description = "Snapmaker Orca — beta slicer for the Snapmaker U1 (from-source build)";

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

      # Package derivation. Signature matches what nixpkgs' callPackage
      # expects, so the block can be dropped verbatim into nixpkgs as
      # `pkgs/by-name/sn/snapmaker-orca/package.nix` when PR'ing upstream.
      #
      # Structurally this is nixpkgs' `orca-slicer` derivation adapted for
      # Snapmaker's fork: Snapmaker's CMake project builds the `Snapmaker_Orca`
      # binary and retains Orca's upstream cmake options and dependency
      # tree. Only a subset of nixpkgs' patches applies: the webkit2gtk-
      # linker patch targets a line range that Snapmaker's fork has moved,
      # and the PR 7650 backport is dropped because Snapmaker carries an
      # equivalent fix. All other dependencies, build flags and GL
      # workarounds mirror the upstream derivation.
      snapmakerOrca =
        {
          stdenv,
          lib,
          binutils,
          fetchFromGitHub,
          cmake,
          pkg-config,
          wrapGAppsHook3,
          boost186,
          cereal,
          cgal_5,
          curl,
          dbus,
          draco,
          eigen,
          expat,
          ffmpeg,
          gcc-unwrapped,
          glew,
          glfw,
          glib,
          glib-networking,
          gmp,
          gst_all_1,
          gtest,
          gtk3,
          hicolor-icon-theme,
          libsecret,
          libpng,
          mpfr,
          nix-update-script,
          nlopt,
          opencascade-occt_7_6,
          openvdb,
          opencv,
          pcre,
          systemd,
          onetbb,
          webkitgtk_4_1,
          wxwidgets_3_1,
          libx11,
          libnoise,
          withSystemd ? stdenv.hostPlatform.isLinux,
          # Default true: on NVIDIA + Wayland the native EGL path regularly
          # fails with EGL_BAD_PARAMETER. Forcing mesa+zink (OpenGL via Vulkan)
          # sidesteps the proprietary driver's EGL implementation entirely
          # and is stable across NVIDIA driver releases.
          withNvidiaGLWorkaround ? true,
        }:
        let
          wxGTK' =
            (wxwidgets_3_1.override {
              withCurl = true;
              withPrivateFonts = true;
              withWebKit = true;
              withEGL = false;
            }).overrideAttrs
              (old: {
                buildInputs = old.buildInputs ++ [ libsecret ];
                configureFlags = old.configureFlags ++ [
                  "--enable-debug=no"
                  "--enable-secretstore"
                ];
              });
        in
        stdenv.mkDerivation (finalAttrs: {
          pname = "snapmaker-orca";
          version = "2.3.1";

          src = fetchFromGitHub {
            owner = "Snapmaker";
            repo = "OrcaSlicer";
            tag = "v${finalAttrs.version}";
            hash = "sha256-klPwPEiZ9hpvrJrZdvM0S1GSgWH4WTIFNkBTetIdMWs=";
          };

          nativeBuildInputs = [
            cmake
            pkg-config
            wrapGAppsHook3
            wxGTK'
          ];

          buildInputs = [
            binutils
            (boost186.override {
              enableShared = true;
              enableStatic = false;
              extraFeatures = [
                "log"
                "thread"
                "filesystem"
              ];
            })
            boost186.dev
            cereal
            cgal_5
            curl
            dbus
            draco
            eigen
            expat
            ffmpeg
            gcc-unwrapped
            glew
            glfw
            glib
            glib-networking
            gmp
            gst_all_1.gstreamer
            gst_all_1.gst-plugins-base
            gst_all_1.gst-plugins-bad
            gst_all_1.gst-plugins-good
            gtk3
            hicolor-icon-theme
            libsecret
            libpng
            mpfr
            nlopt
            opencascade-occt_7_6
            openvdb
            pcre
            onetbb
            webkitgtk_4_1
            wxGTK'
            libx11
            opencv.cxxdev
            libnoise
          ]
          ++ lib.optionals withSystemd [ systemd ]
          ++ finalAttrs.checkInputs;

          patches = [
            # Snapmaker only links webkit2gtk in the FLATPAK branch; on
            # a native nixpkgs build the final link fails because
            # WebView.cpp references webkit symbols directly. Always
            # link webkit2gtk on Linux.
            ./patches/link-webkit2gtk-on-linux.patch
            # nixpkgs orca-slicer: link opencv_core + opencv_imgproc instead
            # of the unified opencv_world (nixpkgs' opencv is split).
            ./patches/dont-link-opencv-world-orca.patch
            # nixpkgs orca-slicer: remove obsolete IlmBase dependency from
            # FindOpenVDB, cherry-picking PrusaSlicer PR #14207. Required
            # because nixpkgs openvdb no longer pulls in ilmbase.
            ./patches/no-ilmbase.patch
          ];

          doCheck = true;
          checkInputs = [ gtest ];

          separateDebugInfo = true;

          env = {
            NLOPT = nlopt;

            NIX_CFLAGS_COMPILE = toString (
              [
                "-Wno-ignored-attributes"
                "-I${opencv.out}/include/opencv4"
                "-Wno-error=incompatible-pointer-types"
                "-Wno-template-id-cdtor"
                "-Wno-uninitialized"
                "-Wno-unused-result"
                "-Wno-deprecated-declarations"
                "-Wno-use-after-free"
                "-Wno-format-overflow"
                "-Wno-stringop-overflow"
                "-DBOOST_ALLOW_DEPRECATED_HEADERS"
                "-DBOOST_MATH_DISABLE_STD_FPCLASSIFY"
                "-DBOOST_MATH_NO_LONG_DOUBLE_MATH_FUNCTIONS"
                "-DBOOST_MATH_DISABLE_FLOAT128"
                "-DBOOST_MATH_NO_QUAD_SUPPORT"
                "-DBOOST_MATH_MAX_FLOAT128_DIGITS=0"
                "-DBOOST_CSTDFLOAT_NO_LIBQUADMATH_SUPPORT"
                "-DBOOST_MATH_DISABLE_FLOAT128_BUILTIN_FPCLASSIFY"
              ]
              ++ lib.optionals (stdenv.cc.isGNU && lib.versionAtLeast stdenv.cc.version "14") [
                "-Wno-error=template-id-cdtor"
              ]
            );

            NIX_LDFLAGS = toString [
              (lib.optionalString withSystemd "-ludev")
              "-L${boost186}/lib"
              "-lboost_log"
              "-lboost_log_setup"
            ];
          };

          prePatch = ''
            sed -i 's|nlopt_cxx|nlopt|g' cmake/modules/FindNLopt.cmake
            sed -i 's|"libnoise/noise.h"|"noise/noise.h"|' src/libslic3r/PerimeterGenerator.cpp
            sed -i 's|"libnoise/noise.h"|"noise/noise.h"|' src/libslic3r/Feature/FuzzySkin/FuzzySkin.cpp
          '';

          cmakeFlags = [
            (lib.cmakeBool "SLIC3R_STATIC" false)
            (lib.cmakeBool "SLIC3R_FHS" true)
            (lib.cmakeFeature "SLIC3R_GTK" "3")
            (lib.cmakeBool "BBL_RELEASE_TO_PUBLIC" true)
            (lib.cmakeBool "BBL_INTERNAL_TESTING" false)
            (lib.cmakeBool "SLIC3R_BUILD_TESTS" false)
            (lib.cmakeFeature "CMAKE_CXX_FLAGS" "-DGL_SILENCE_DEPRECATION")
            (lib.cmakeFeature "CMAKE_EXE_LINKER_FLAGS" "-Wl,--no-as-needed")
            (lib.cmakeBool "ORCA_VERSION_CHECK_DEFAULT" false)
            (lib.cmakeFeature "LIBNOISE_INCLUDE_DIR" "${libnoise}/include")
            # Snapmaker's Findlibnoise.cmake searches for LIBNOISE_LIBRARY
            # (not _RELEASE like upstream SoftFever). Point it directly at
            # nixpkgs libnoise's static archive.
            (lib.cmakeFeature "LIBNOISE_LIBRARY" "${libnoise}/lib/libnoise-static.a")
            # Snapmaker bundles paho-mqtt-c (for U1 network-print support)
            # which declares cmake_minimum_required < 3.5 and also uses
            # `typedef unsigned int bool;` in MQTTPacket.h — both rejected
            # by modern tooling (CMake 4+ and GCC 15's default C23 mode).
            # Force the older CMake compatibility shim and pin C to C17
            # so the typedef stays legal. Upstream orca-slicer does not
            # bundle paho so these flags are Snapmaker-specific.
            (lib.cmakeFeature "CMAKE_POLICY_VERSION_MINIMUM" "3.5")
            (lib.cmakeFeature "CMAKE_C_STANDARD" "17")
            "-Wno-dev"
          ];

          postBuild = "( cd .. && ./scripts/run_gettext.sh )";

          preFixup = ''
            gappsWrapperArgs+=(
              --prefix LD_LIBRARY_PATH : "$out/lib:${lib.makeLibraryPath [ glew ]}"
              --set WEBKIT_DISABLE_COMPOSITING_MODE 1
              ${lib.optionalString withNvidiaGLWorkaround ''
                --set __GLX_VENDOR_LIBRARY_NAME mesa
                --set __EGL_VENDOR_LIBRARY_FILENAMES /run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json
                --set MESA_LOADER_DRIVER_OVERRIDE zink
                --set GALLIUM_DRIVER zink
                --set WEBKIT_DISABLE_DMABUF_RENDERER 1
              ''}
            )
          '';

          postInstall = ''
            rm -f $out/LICENSE.txt
          '';

          passthru.updateScript = nix-update-script { };

          meta = {
            description = "Beta slicer for the Snapmaker U1 (OrcaSlicer fork with SnapSwap multi-color)";
            longDescription = ''
              Snapmaker Orca is a fork of OrcaSlicer maintained by Snapmaker,
              tuned for the Snapmaker U1 multi-color printer with SnapSwap
              integration and Snapmaker-curated filament profiles. This
              derivation builds the slicer from source against nixpkgs
              dependencies (no AppImage, no FHS sandbox), mirroring the
              setup of the upstream `orca-slicer` nixpkgs package.

              On NVIDIA hosts the default GL path uses mesa + zink (OpenGL
              over Vulkan) to avoid the proprietary driver's unstable EGL
              implementation; set `withNvidiaGLWorkaround = false` to use
              the native NVIDIA EGL path if it works on your system.
            '';
            homepage = "https://www.snapmaker.com/snapmaker-orca";
            changelog = "https://github.com/Snapmaker/OrcaSlicer/releases/tag/v${finalAttrs.version}";
            license = lib.licenses.agpl3Only;
            platforms = [ "x86_64-linux" ];
            mainProgram = "snapmaker-orca";
            maintainers = [ ];
          };
        });
    in
    {
      packages = forAllSystems (
        { pkgs, ... }:
        rec {
          # HOTFIX — remove once nixpkgs ships pango >= 1.57.1
          # (tracked in nixpkgs PR #505692). pango 1.57.0 crashes with a
          # NULL-pointer deref in `ensure_faces` when the Preferences
          # language combobox asks for text extents of its CJK entries
          # (upstream pango issue #867, fixed in 1.57.1). Injected via
          # LD_LIBRARY_PATH in preFixup so neither gtk3 nor webkitgtk_4_1
          # need a rebuild — ABI is stable across 1.57.x.
          pango-hotfix = pkgs.pango.overrideAttrs (_: rec {
            version = "1.57.1";
            src = pkgs.fetchurl {
              url = "mirror://gnome/sources/pango/1.57/pango-${version}.tar.xz";
              hash = "sha256-5l1tEXCA3Drut9i0s7UY9zg6oubPziMRfGI81iR2TC8=";
            };
          });

          snapmaker-orca = (pkgs.callPackage snapmakerOrca { }).overrideAttrs (old: {
            preFixup = (old.preFixup or "") + ''
              gappsWrapperArgs+=( --prefix LD_LIBRARY_PATH : "${pango-hotfix}/lib" )
            '';
          });
          default = snapmaker-orca;
        }
      );

      apps = forAllSystems (
        { system, ... }:
        rec {
          snapmaker-orca = {
            type = "app";
            program = nixpkgs.lib.getExe self.packages.${system}.snapmaker-orca;
            inherit (self.packages.${system}.snapmaker-orca) meta;
          };
          default = snapmaker-orca;
        }
      );

      overlays.default = final: _prev: {
        snapmaker-orca = final.callPackage snapmakerOrca { };
      };

      # NixOS module — ships the package plus the CJK fonts it requires.
      #
      # Why: Orca's Preferences dialog lists languages in native scripts
      # (简体中文, 한국어, 日本語, etc.). Pango crashes with SIGSEGV in
      # `ensure_faces` when no CJK fallback font is available in
      # fontconfig, which happens on minimal NixOS installs that only
      # ship Latin-script Noto variants. These two packages cover every
      # glyph range the combobox iterates through.
      #
      # The CJK dependency is expressed here (declaratively, next to the
      # package) rather than bundled into the derivation's closure so it
      # benefits other CJK-using apps on the host and remains consistent
      # with nixpkgs' upstream `orca-slicer` package (which does not
      # bundle fonts either).
      nixosModules.default =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        {
          options.programs.snapmaker-orca = {
            enable = lib.mkEnableOption "Snapmaker Orca (also adds the CJK fonts its Preferences dialog requires)";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.snapmaker-orca;
              defaultText = lib.literalExpression "inputs.snapmaker-orca.packages.\${pkgs.stdenv.hostPlatform.system}.snapmaker-orca";
              description = "The snapmaker-orca derivation to install.";
            };
          };

          config = lib.mkIf config.programs.snapmaker-orca.enable {
            environment.systemPackages = [ config.programs.snapmaker-orca.package ];
            fonts.packages = with pkgs; [
              noto-fonts-cjk-sans
              noto-fonts-cjk-serif
            ];
          };
        };

      # `nix flake check` runs evaluation only by default; we expose the
      # build as an explicit check for CI runs that can afford it.
      checks = forAllSystems (
        { system, ... }:
        {
          build = self.packages.${system}.default;
        }
      );

      formatter = forAllSystems ({ pkgs, ... }: pkgs.nixfmt);
    };
}

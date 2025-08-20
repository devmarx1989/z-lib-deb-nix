{
  description = "Z-Library desktop app repackaged from .deb for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    # Add "aarch64-linux" later if/when you have a matching .deb.
    systems = ["x86_64-linux"];

    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system:
        f (import nixpkgs {
          inherit system;
          config = {
            # allow just this package:
            allowUnfreePredicate = pkg:
              builtins.elem (nixpkgs.lib.getName pkg) ["zlibrary"];
            # or: allowUnfree = true;
          };
        }));

    hasDeb = builtins.pathExists ./vendor/zlibrary.deb;
  in {
    ############################################################################
    ## Packages
    ############################################################################
    packages = forAllSystems (
      pkgs: let
        system = pkgs.stdenv.hostPlatform.system;

        runtimeLibs = with pkgs; [
          # Depends from the .deb
          gtk3
          libnotify
          nss
          xorg.libXScrnSaver
          xorg.libXtst
          xdg-utils
          at-spi2-core
          libsecret
          util-linux

          # Electron/Chromium bits
          glib
          pango
          cairo
          gdk-pixbuf
          nspr
          dbus
          libxkbcommon
          xorg.libX11
          xorg.libXext
          xorg.libXcursor
          xorg.libXcomposite
          xorg.libXdamage
          xorg.libXfixes
          xorg.libXi
          xorg.libXrandr
          xorg.libXrender
          xorg.libxcb
          xorg.libxshmfence
          libdrm
          mesa
          wayland

          # Recommends / extras
          libappindicator-gtk3
          stdenv.cc.cc.lib
          expat
          openssl

          # Audio
          alsa-lib
        ];

        missingDebDrv = pkgs.runCommand "zlibrary-missing-deb" {} ''
          echo "ERROR: Missing vendor/zlibrary.deb" >&2
          echo "Please place the .deb at ./vendor/zlibrary.deb and rebuild." >&2
          exit 1
        '';
      in rec {
        zlibrary =
          if hasDeb
          then
            pkgs.stdenv.mkDerivation {
              pname = "zlibrary";
              version = "2.4.3";

              src = ./vendor/zlibrary.deb;
              dontUnpack = true;

              nativeBuildInputs = [pkgs.dpkg pkgs.autoPatchelfHook pkgs.makeWrapper];
              buildInputs = runtimeLibs;

              installPhase = ''
                runHook preInstall

                mkdir -p $TMP/extracted control
                dpkg-deb -x $src $TMP/extracted
                dpkg-deb -e $src control

                mkdir -p $out
                cp -r $TMP/extracted/* $out/

                main="$out/opt/Z-Library/z-library"
                if [ ! -x "$main" ]; then
                  echo "Main binary not found at $main" >&2
                  exit 1
                fi

                # Avoid setuid sandbox issues
                if [ -f "$out/opt/Z-Library/chrome-sandbox" ]; then
                  chmod -x "$out/opt/Z-Library/chrome-sandbox" || true
                fi

                mkdir -p $out/bin
                makeWrapper "$main" "$out/bin/zlibrary" \
                  --set-default ELECTRON_DISABLE_SECURITY_WARNINGS 1 \
                  --add-flags "--no-sandbox" \
                  --add-flags "--ozone-platform-hint=auto" \
                  --prefix PATH : ${pkgs.xdg-utils}/bin

                makeWrapper "$main" "$out/bin/zlibrary-x11" \
                  --add-flags "--no-sandbox" \
                  --add-flags "--ozone-platform-hint=x11" \
                  --prefix PATH : ${pkgs.xdg-utils}/bin

                makeWrapper "$main" "$out/bin/zlibrary-wayland" \
                  --add-flags "--no-sandbox" \
                  --add-flags "--ozone-platform-hint=wayland" \
                  --prefix PATH : ${pkgs.xdg-utils}/bin

                # Fix desktop entries to point to wrapper
                if [ -d "$out/usr/share/applications" ]; then
                  mkdir -p $out/share/applications
                  for f in $out/usr/share/applications/*.desktop; do
                    sed -i "s|^Exec=.*|Exec=$out/bin/zlibrary %U|g" "$f" || true
                    cp "$f" "$out/share/applications/$(basename "$f")"
                  done
                fi

                # Icons
                if [ -d "$out/usr/share/icons" ]; then
                  mkdir -p $out/share/icons
                  cp -r $out/usr/share/icons/* $out/share/icons/ || true
                fi
                if [ -d "$out/usr/share/pixmaps" ]; then
                  mkdir -p $out/share/pixmaps
                  cp -r $out/usr/share/pixmaps/* $out/share/pixmaps/ || true
                fi

                runHook postInstall
              '';

              postInstall = ''
                echo "===== deb control ====="
                [ -f control/control ] && cat control/control || true
              '';

              meta = with pkgs.lib; {
                description = "Z-Library desktop client (repacked from .deb)";
                homepage = "https://singlelogin.re";
                license = licenses.unfreeRedistributable // {free = false;};
                platforms = platforms.linux;
                mainProgram = "zlibrary";
              };
            }
          else missingDebDrv;

        # Alias so your top-level flake can rely on .packages.${system}.default
        default = zlibrary;
      }
    );

    ############################################################################
    ## Apps (nix run)
    ############################################################################
    apps = forAllSystems (
      pkgs: let
        system = pkgs.stdenv.hostPlatform.system;

        missingScript = pkgs.writeShellScriptBin "zlibrary" ''
          echo "ERROR: Missing vendor/zlibrary.deb" >&2
          echo "Place the .deb at ./vendor/zlibrary.deb then \`nix build .#zlibrary\` or \`nix run .\`." >&2
          exit 1
        '';

        binDefault =
          if hasDeb
          then "${self.packages.${system}.zlibrary}/bin/zlibrary"
          else "${missingScript}/bin/zlibrary";

        binX11 =
          if hasDeb
          then "${self.packages.${system}.zlibrary}/bin/zlibrary-x11"
          else "${missingScript}/bin/zlibrary";

        binWayland =
          if hasDeb
          then "${self.packages.${system}.zlibrary}/bin/zlibrary-wayland"
          else "${missingScript}/bin/zlibrary";
      in {
        default = {
          type = "app";
          program = binDefault;
        };
        x11 = {
          type = "app";
          program = binX11;
        };
        wayland = {
          type = "app";
          program = binWayland;
        };
      }
    );
  };
}

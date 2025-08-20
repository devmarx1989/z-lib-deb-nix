{
  description = "Z-Library desktop app repackaged from .deb for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
  let
    # Adjust if you truly have an aarch64 build of the .deb
    systems = [ "x86_64-linux" ];

    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system:
        f (import nixpkgs {
          inherit system;
          config = {
            # allow just this package:
            allowUnfreePredicate = pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [ "zlibrary" ];
            # or allow all:
            # allowUnfree = true;
          };
        }));

    hasDeb = builtins.pathExists ./vendor/zlibrary.deb;
  in
  {
    ###########################################################################
    ## Packages
    ###########################################################################
    packages = forAllSystems (pkgs:
      if hasDeb then
        let
          runtimeLibs = with pkgs; [
            # From Depends of the .deb:
            gtk3
            libnotify
            nss
            xorg.libXScrnSaver
            xorg.libXtst
            xdg-utils
            at-spi2-core
            libsecret
            util-linux

            # Common Electron/Chromium deps for autoPatchelf:
            glib pango cairo gdk-pixbuf nspr dbus
            libxkbcommon
            xorg.libX11 xorg.libXext xorg.libXcursor xorg.libXcomposite
            xorg.libXdamage xorg.libXfixes xorg.libXi xorg.libXrandr
            xorg.libXrender xorg.libxcb xorg.libxshmfence
            libdrm mesa wayland

            # Recommends/typical extras:
            libappindicator-gtk3
            stdenv.cc.cc.lib expat openssl

            # Audio
            alsa-lib
          ];
        in
        rec {
          zlibrary = pkgs.stdenv.mkDerivation {
            pname = "zlibrary";
            version = "2.4.3";

            src = ./vendor/zlibrary.deb;
            dontUnpack = true;

            nativeBuildInputs = [
              pkgs.dpkg
              pkgs.autoPatchelfHook
              pkgs.makeWrapper
            ];

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
              license = licenses.unfreeRedistributable // { free = false; };
              platforms = platforms.linux;
              mainProgram = "zlibrary";
            };
          };

          # Make your top-level flake happy:
          default = zlibrary;
        }
      else
        # No vendored deb → no packages; keeps `flake show` from erroring.
        {}
    );

    ###########################################################################
    ## Apps (nix run)
    ###########################################################################
    apps = forAllSystems (pkgs:
      if hasDeb then
        let
          system = pkgs.stdenv.hostPlatform.system;
          bin = "${self.packages.${system}.zlibrary}/bin";
        in
        {
          default = {
            type = "app";
            program = "${bin}/zlibrary";
          };
          x11 = {
            type = "app";
            program = "${bin}/zlibrary-x11";
          };
          wayland = {
            type = "app";
            program = "${bin}/zlibrary-wayland";
          };
        }
      else
        {}
    );
  };
}


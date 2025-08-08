{
  description = "Z-Library desktop app repackaged for NixOS from .deb";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
  let
    systems = [ "x86_64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
  in
  {
    packages = forAllSystems (pkgs:
      let
        # If you want to keep the .deb in-repo, use: src = ./vendor/zlibrary_x.y.z_amd64.deb;
        srcDeb = pkgs.fetchurl {
          # replace with your real .deb source and hash
          url = "file://${toString ./vendor/zlibrary.deb}";
          sha256 = nixpkgs.lib.fakeSha256
        };

        # Likely runtime libs for a Chromium/Electron-style app. We'll trim after first build.
        electronLibs = with pkgs; [
          stdenv.cc.cc.lib
          glib gtk3 pango cairo gdk-pixbuf atk at-spi2-atk
          nspr nss
          xorg.libX11 xorg.libXext xorg.libXcursor xorg.libXcomposite xorg.libXdamage
          xorg.libXfixes xorg.libXi xorg.libXtst xorg.libXrandr xorg.libXScrnSaver
          xorg.libXrender xorg.libxcb xorg.libxshmfence
          libxkbcommon
          cups
          dbus
          libdrm
          mesa
          wayland
          xdg-utils
          libnotify
          libsecret
          expat
          openssl
          # sometimes needed:
          ffmpeg
          # appindicator for tray icons (many Electron apps use it):
          libappindicator-gtk3
        ];
      in {
        zlibrary = pkgs.stdenv.mkDerivation {
          pname = "zlibrary";
          version = "local-from-deb";

          src = srcDeb;

          # autoPatchelf runs in fixupPhase, after installPhase—so make sure ELF files end up in $out before then.
          nativeBuildInputs = [
            pkgs.autoPatchelfHook
            pkgs.dpkg
            pkgs.makeWrapper
          ];

          buildInputs = electronLibs;

          # If the binary needs GSettings schemas, icons, etc., wrapGAppsHook3 can help.
          # Uncomment if you discover missing schemas at runtime.
          # nativeBuildInputs = nativeBuildInputs ++ [ pkgs.wrapGAppsHook3 ];

          dontUnpack = true;

          installPhase = ''
            runHook preInstall
            mkdir -p $TMP/extracted control
            dpkg-deb -x $src $TMP/extracted
            dpkg-deb -e $src control

            # Move everything into $out
            mkdir -p $out
            cp -r $TMP/extracted/* $out/

            # Find the main ELF; most Electron apps install under /opt/<Name>/<binary>
            main="$(find $out/opt -maxdepth 3 -type f -perm -111 2>/dev/null | head -n1)"
            if [ -z "$main" ]; then
              # Fallback: search broadly for an executable ELF
              main="$(find $out -type f -perm -111 -exec file {} \; \
                | grep -E 'ELF .* (executable|shared object)' \
                | cut -d: -f1 | head -n1)"
            fi
            if [ -z "$main" ]; then
              echo "Could not find main executable in .deb payload." >&2
              exit 1
            fi

            # Create a stable entrypoint
            mkdir -p $out/bin
            makeWrapper "$main" "$out/bin/zlibrary" \
              --set-default ELECTRON_DISABLE_SECURITY_WARNINGS 1 \
              --add-flags "--enable-features=UseOzonePlatform" \
              --add-flags "--ozone-platform=auto" \
              --prefix PATH : ${pkgs.xdg-utils}/bin

            # Desktop integration (if shipped)
            if [ -d "$out/usr/share/applications" ]; then
              mkdir -p $out/share/applications
              # rewrite Exec= line to point to our wrapper
              for f in $out/usr/share/applications/*.desktop; do
                sed -i "s|^Exec=.*|Exec=$out/bin/zlibrary %U|g" "$f" || true
                # place under canonical path
                cp "$f" "$out/share/applications/$(basename "$f")"
              done
            fi

            # Icons if any were in usr/share/icons or pixmaps
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

          # Helpful for debugging: prints control metadata into the build log
          postInstall = ''
            echo "===== deb control metadata ====="
            if [ -f control/control ]; then
              cat control/control || true
            fi
          '';

          # Optionally, you can fine-tune RPATH here if the binary is picky.
          # postFixup = ''
          #   patchelf --set-rpath "$(patchelf --print-rpath $out/bin/zlibrary):${pkgs.lib.makeLibraryPath [ /* add libs */ ]}" $out/bin/zlibrary
          # '';

          meta = with pkgs.lib; {
            description = "Z-Library desktop client repackaged from .deb for NixOS";
            # If it’s proprietary, keep this unfree; you’ll need allowUnfree = true to build/run.
            license = licenses.unfreeRedistributable // { free = false; };
            platforms = platforms.linux;
            maintainers = [ ];
          };
        };
      });

    apps = nixpkgs.lib.genAttrs systems (system: {
      type = "app";
      program = "${self.packages.${system}.zlibrary}/bin/zlibrary";
    });
  };
}


{
  description = "Z-Library desktop app from .deb for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
  let
    forAllSystems = f:
      nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system:
        f (import nixpkgs { inherit system; }));
  in
  {
    packages = forAllSystems (pkgs:
      let
        # Tweak this path to your .deb
        srcDeb = pkgs.fetchurl {
          # If the deb is local, replace with: src = ./vendor/zlibrary.deb;
          # Using fetchurl is nicer for cachability; otherwise use `src = ./vendor/zlibrary.deb;`
          url = "file://${toString ./zlibrary.deb}";
          sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # update
        };
      in {
        zlibrary = pkgs.stdenv.mkDerivation {
          pname = "zlibrary";
          version = "local";

          src = srcDeb;

          nativeBuildInputs = [
            pkgs.autoPatchelfHook
            pkgs.makeWrapper
            pkgs.dpkg
          ];

          # Likely runtime deps for Electron-style apps. Trim/add as needed.
          buildInputs = with pkgs; [
            stdenv.cc.cc.lib
            glib
            gtk3
            nss
            nspr
            atk
            at-spi2-atk
            pango
            cairo
            gdk-pixbuf
            libdrm
            cups
            dbus
            libxkbcommon
            xorg.libX11
            xorg.libXext
            xorg.libXcursor
            xorg.libXcomposite
            xorg.libXdamage
            xorg.libXfixes
            xorg.libXi
            xorg.libXtst
            xorg.libXrandr
            xorg.libXScrnSaver
            xorg.libXrender
            xorg.libxcb
            xorg.libxshmfence
            xdg-utils
            libnotify
            openssl
            expat
            libsecret
            mesa
            mesa.drivers               # if you need GPU
            wayland
            libpulseaudio
            ffmpeg                      # some Electron apps need this
            libappindicator-gtk3        # tray icons
          ];

          unpackPhase = ''
            runHook preUnpack
            # Extract the data payload to $TMP/extracted
            mkdir extracted control
            dpkg-deb -x $src extracted
            dpkg-deb -e $src control
            runHook postUnpack
          '';

          # If the app ships under /opt/<name>, patch binaries in there
          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r extracted/* $out/

            # Find main binary (adjust if different)
            # Common locations: $out/opt/*/zlibrary, $out/usr/lib/*/zlibrary, etc.
            main="$(echo $out/opt/*/* | head -n1)"
            if [ -x "$main" ]; then
              mkdir -p $out/bin
              makeWrapper "$main" "$out/bin/zlibrary" \
                --set-default ELECTRON_DISABLE_SECURITY_WARNINGS 1 \
                --prefix PATH : ${pkgs.xdg-utils}/bin
            else
              # Fallback: try to find an ELF executable
              main="$(find $out -type f -maxdepth 4 -perm -111 -exec file {} \; \
                | grep -E 'ELF .* executable' | cut -d: -f1 | head -n1)"
              test -n "$main"
              mkdir -p $out/bin
              makeWrapper "$main" "$out/bin/zlibrary" \
                --set-default ELECTRON_DISABLE_SECURITY_WARNINGS 1 \
                --prefix PATH : ${pkgs.xdg-utils}/bin
            fi

            # Desktop file & icon (optional)
            if [ -d "$out/usr/share" ]; then
              mkdir -p $out/share
              cp -r $out/usr/share/* $out/share/ || true
            fi
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Z-Library desktop app repackaged for NixOS";
            platforms = platforms.linux;
            license = licenses.unfreeRedistributable; # adjust if you know better
          };
        };
      });

    apps.x86_64-linux.default = {
      type = "app";
      program = "${self.packages.x86_64-linux.zlibrary}/bin/zlibrary";
    };
  };
}


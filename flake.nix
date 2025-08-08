{
  description = "Z-Library desktop app repackaged from .deb for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system:
        f (import nixpkgs {
          inherit system;
          config = {
            # allow just this package:
            allowUnfreePredicate = pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [ "zlibrary" ];
            # or if you don't care, allow all:
            # allowUnfree = true;
          };
        }));
  in {
    packages = forAllSystems (pkgs: let
      # Put your deb at ./vendor/zlibrary.deb
      srcDeb = ./vendor/zlibrary.deb;

      # Debian Depends → Nix packages (plus common Electron bits)
      runtimeLibs = with pkgs; [
        # From Depends:
        gtk3 # libgtk-3-0
        libnotify # libnotify4
        nss # libnss3
        xorg.libXScrnSaver # libxss1
        xorg.libXtst # libxtst6
        xdg-utils # xdg-utils
        at-spi2-core # libatspi2.0-0
        libsecret # libsecret-1-0
        util-linux # libuuid1 (libuuid)

        # Usual Electron/Chromium deps that autoPatchelf may need:
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

        # Recommends:
        libappindicator-gtk3

        # Often harmless & useful:
        stdenv.cc.cc.lib
        expat
        openssl
      ];
    in {
      zlibrary = pkgs.stdenv.mkDerivation {
        pname = "zlibrary";
        version = "2.4.3";

        src = srcDeb;
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

          # Known main binary from your listing:
          main="$out/opt/Z-Library/z-library"
          if [ ! -x "$main" ]; then
            echo "Main binary not found at $main" >&2
            exit 1
          fi

          # Avoid setuid sandbox requirements on Nix:
          if [ -f "$out/opt/Z-Library/chrome-sandbox" ]; then
            chmod -x "$out/opt/Z-Library/chrome-sandbox" || true
          fi

          mkdir -p $out/bin
          makeWrapper "$main" "$out/bin/zlibrary" \
            --set-default ELECTRON_DISABLE_SECURITY_WARNINGS 1 \
            --add-flags "--no-sandbox" \
            --add-flags "--enable-features=UseOzonePlatform" \
            --add-flags "--ozone-platform=auto" \
            --prefix PATH : ${pkgs.xdg-utils}/bin

          # Desktop entry → point Exec to our wrapper
          if [ -d "$out/usr/share/applications" ]; then
            mkdir -p $out/share/applications
            for f in $out/usr/share/applications/*.desktop; do
              sed -i "s|^Exec=.*|Exec=$out/bin/zlibrary %U|g" "$f" || true
              cp "$f" "$out/share/applications/$(basename "$f")"
            done
          fi

          # Icons into canonical path
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

        # Helpful to see control metadata in build log
        postInstall = ''
          echo "===== deb control ====="
          [ -f control/control ] && cat control/control || true
        '';

        meta = with pkgs.lib; {
          description = "Z-Library desktop client (repacked from .deb)";
          homepage = "https://singlelogin.re";
          license = licenses.unfreeRedistributable // {free = false;};
          platforms = platforms.linux;
        };
      };
    });

    apps = nixpkgs.lib.genAttrs systems (system: {
      type = "app";
      program = "${self.packages.${system}.zlibrary}/bin/zlibrary";
    });
  };
}

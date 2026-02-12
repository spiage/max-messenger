{
  description = "MAX Messenger for NixOS (Single File Flake)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true; 
        };

        version = "26.4.1";
        debFile = "MAX-26.4.1.46437.deb";
        
      in
      {
        packages.default = pkgs.stdenv.mkDerivation rec {
          pname = "max";
          inherit version;

          src = pkgs.fetchurl {
            url = "https://download.max.ru/linux/deb/pool/main/m/max/${debFile}";
            # ИСПРАВЛЕННЫЙ ХЕШ (из строки "got" в твоей ошибке)
            hash = "sha256-pKHOsmfN7HLeQliiCirJcZ5BrkKwlviomO5CXI6dxvA=";
          };

          nativeBuildInputs = with pkgs; [ 
            dpkg 
            autoPatchelfHook 
            makeWrapper 
          ];

          buildInputs = with pkgs; [
            alsa-lib
            at-spi2-atk
            at-spi2-core
            cups
            dbus
            expat
            fontconfig
            freetype
            glib
            gtk3
            libdrm
            libgbm
            libglvnd
            libnotify
            libva
            libvdpau
            libxkbcommon
            mesa
            nspr
            nss
            pango
            wayland
            libx11
            libxcomposite
            libxdamage
            libxext
            libxfixes
            libxrandr
            libxrender
            libxscrnsaver
            libxcb
          ];

          unpackPhase = "dpkg -x $src .";

          installPhase = ''
            runHook preInstall

            mkdir -p $out
            
            mv usr/* $out/ || true
            if [ -d "opt" ]; then
                mv opt/* $out/
            fi

            if [ -f "$out/opt/MAX/MAX" ]; then
              MAIN_BIN="$out/opt/MAX/MAX"
            elif [ -f "$out/opt/MAX/max" ]; then
              MAIN_BIN="$out/opt/MAX/max"
            else
              echo "Error: MAX binary not found!"
              exit 1
            fi

            chmod +x $MAIN_BIN

            mkdir -p $out/bin
            makeWrapper "$MAIN_BIN" "$out/bin/max" \
              --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs} \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]}

            if [ -f "$out/opt/MAX/max.desktop" ]; then
              mkdir -p $out/share/applications
              cp $out/opt/MAX/max.desktop $out/share/applications/
              substituteInPlace $out/share/applications/max.desktop \
                --replace "Exec=MAX" "Exec=$out/bin/max" \
                --replace "/opt/MAX" "$out/opt/MAX"
            fi

            if [ -d "$out/opt/MAX/icons" ]; then
               mkdir -p $out/share/icons
               cp -r $out/opt/MAX/icons/* $out/share/icons/
            fi

            runHook postInstall
          '';

          meta = {
            description = "MAX Messenger (Deb repack for NixOS)";
            homepage = "https://max.ru";
            platforms = [ "x86_64-linux" ];
          };
        };
      }
    );
}

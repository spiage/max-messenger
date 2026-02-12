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
            hash = "sha256-pKHOsmfN7HLeQliiCirJcZ5BrkKwlviomO5CXI6dxvA=";
          };

          nativeBuildInputs = with pkgs; [ 
            dpkg 
            autoPatchelfHook 
            makeWrapper 
          ];

          buildInputs = with pkgs; [
            # Базовый набор Electron
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

            # Основные X11 библиотеки
            libx11
            libxcomposite
            libxdamage
            libxext
            libxfixes
            libxrandr
            libxrender
            libxscrnsaver
            libxcb

            # ДОБАВЛЕННЫЕ ЗАВИСИМОСТИ (из лога ошибок)
            libXmu          # libXmu.so.6, libXmuu.so.1
            libXpm          # libXpm.so.4
            libXres         # libXRes.so.1
            libXt           # libXt.so.6
            libXtst         # libXtst.so.6

            # ЗАВИСИМОСТИ XCB (Финальные имена из nix search)
            libxcb-wm            # (покрывает libxcb-icccm.so.4 и libxcb-ewmh.so.2)
            libxcb-image         # libxcb-image.so.0
            libxcb-render-util   # libxcb-render-util.so.0 (ИСПРАВЛЕНО НА ДЕФИСЫ)
            libxcb-util          # libxcb-util.so.1
          ];

          unpackPhase = "dpkg -x $src .";

          installPhase = ''
            runHook preInstall

            mkdir -p $out

            # Переносим /usr
            if [ -d "usr" ]; then
                mv usr/* $out/ 2>/dev/null || true
            fi

            # Переносим /opt
            if [ -d "opt" ]; then
                mv opt/* $out/ 2>/dev/null || true
            fi

            # Автопоиск основного бинарника
            MAIN_BIN=$(find $out -type f -executable -iname "MAX" | head -n 1)

            if [ -z "$MAIN_BIN" ]; then
              echo "ERROR: Binary 'MAX' not found in $out!"
              exit 1
            fi

            echo "Found MAX binary at: $MAIN_BIN"

            # Создаем обертку
            mkdir -p $out/bin
            makeWrapper "$MAIN_BIN" "$out/bin/max" \
              --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs} \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]}

            # Исправление .desktop
            DESKTOP_FILE=$(find $out/share/applications -name "*.desktop" 2>/dev/null | head -n 1)
            if [ -n "$DESKTOP_FILE" ]; then
                substituteInPlace "$DESKTOP_FILE" \
                  --replace "Exec=MAX" "Exec=$out/bin/max" \
                  --replace "/opt/MAX" "$out/opt/MAX" \
                  --replace "Exec=max" "Exec=$out/bin/max"
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

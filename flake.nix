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

          dontWrapQtApps = true;

          nativeBuildInputs = with pkgs; [ 
            dpkg 
            autoPatchelfHook 
            makeWrapper 
          ];

          buildInputs = with pkgs; [
            # Базовый набор
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

            # Доп. библиотеки
            libXmu
            libXpm
            libXres
            libXt
            libXtst
            libxcb-wm
            libxcb-image
            libxcb-render-util
            libxcb-util

            # Зависимости из лога
            libxkbfile
            libXv
            libfontenc
            libXaw
            qt6.qtserialport
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

            # ---------------------------------------------------------
            # НАСТРОЙКА СЕРВИСА (max-service)
            # Мы сохраняем структуру папок, чтобы симлинки в lib64 работали.
            # Оборачиваем только бинарный файл внутри папки.
            # ---------------------------------------------------------
            SERVICE_BIN_REAL="$out/share/max/bin/max-service/bin/max-service"

            if [ -f "$SERVICE_BIN_REAL" ]; then
              echo "Wrapping MAX Service binary..."
              
              mv "$SERVICE_BIN_REAL" "$SERVICE_BIN_REAL.real"
              
              # Папки для ресурсов сервиса (относительные к его локации)
              SERVICE_LIB_DIR="$out/share/max/bin/max-service/lib64"
              SERVICE_PLUGINS_DIR="$out/share/max/bin/max-service/plugins"

              makeWrapper "$SERVICE_BIN_REAL.real" "$SERVICE_BIN_REAL" \
                --prefix LD_LIBRARY_PATH : "$SERVICE_LIB_DIR" \
                --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs} \
                --set QT_PLUGIN_PATH "$SERVICE_PLUGINS_DIR"
            else
              echo "Warning: MAX Service binary not found!"
            fi

            # ---------------------------------------------------------
            # ОБРАБОТКА ГЛАВНОГО ПРИЛОЖЕНИЯ
            # ---------------------------------------------------------
            MAIN_BIN=$(find $out -type f -executable -iname "MAX" | head -n 1)

            if [ -z "$MAIN_BIN" ]; then
              echo "ERROR: MAX binary not found in $out!"
              exit 1
            fi

            echo "Found MAX binary at: $MAIN_BIN"

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

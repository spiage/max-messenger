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

        version = "26.5.1";
        debFile = "MAX-26.5.1.48203.deb";
        
      in
      {
        packages.default = pkgs.stdenv.mkDerivation rec {
          pname = "max";
          inherit version;

          src = pkgs.fetchurl {
            url = "https://download.max.ru/linux/deb/pool/main/m/max/${debFile}";
            hash = "sha256-Wralrk1JzfL96jfGQvdgqHeIv46xSDlL/rT4E8v0Sb0=";
          };

          dontWrapQtApps = true;

          nativeBuildInputs = with pkgs; [ 
            dpkg 
            autoPatchelfHook 
            makeWrapper 
          ];

          buildInputs = with pkgs; [
            # Системные библиотеки
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
            pipewire 

            # X11 библиотеки
            libx11
            libxcomposite
            libxdamage
            libxext
            libxfixes
            libxrandr
            libxrender
            libxscrnsaver
            libxcb

            # Доп. библиотеки X11
            libXmu
            libXpm
            libXres
            libXt
            libXtst
            libxcb-wm
            libxcb-image
            libxcb-render-util
            libxcb-util

            # Зависимости
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

            # Переносим файлы из deb-пакета
            if [ -d "usr" ]; then mv usr/* $out/ 2>/dev/null || true; fi
            if [ -d "opt" ]; then mv opt/* $out/ 2>/dev/null || true; fi

            # ---------------------------------------------------------
            # УДАЛЕНИЕ КОНФЛИКТУЮЩИХ БИБЛИОТЕК
            # ---------------------------------------------------------
            # Удаляем только libmount и libselinux из сервиса.
            # НЕ удаляем libstdc++, libgcc_s, libtracernative, libtracer_crash_reporter,
            # чтобы autoPatchelfHook мог их найти и пропатчить.
            SERVICE_LIB_DIR="$out/share/max/bin/max-service/lib64"
            if [ -d "$SERVICE_LIB_DIR" ]; then
              rm -f "$SERVICE_LIB_DIR/libmount.so.1"
              rm -f "$SERVICE_LIB_DIR/libselinux.so.1"
            fi

            # ---------------------------------------------------------
            # НАСТРОЙКА СЕРВИСА (max-service)
            # ---------------------------------------------------------
            SERVICE_BIN_REAL="$out/share/max/bin/max-service/bin/max-service"
            SERVICE_DIR="$out/share/max/bin/max-service"

            if [ -f "$SERVICE_BIN_REAL" ]; then
              echo "Wrapping MAX Service binary..."
              mv "$SERVICE_BIN_REAL" "$SERVICE_BIN_REAL.real"
              
              SERVICE_PLUGINS_DIR="$SERVICE_DIR/plugins"

              makeWrapper "$SERVICE_BIN_REAL.real" "$SERVICE_BIN_REAL" \
                --prefix LD_LIBRARY_PATH : "$SERVICE_LIB_DIR" \
                --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs} \
                --set QT_PLUGIN_PATH "$SERVICE_PLUGINS_DIR"
            fi

            # ---------------------------------------------------------
            # ОБРАБОТКА ГЛАВНОГО ПРИЛОЖЕНИЯ (max)
            # ---------------------------------------------------------
            MAIN_BIN=$(find $out -type f -executable -iname "MAX" | head -n 1)

            if [ -z "$MAIN_BIN" ]; then
              echo "ERROR: MAX binary not found in $out!"
              exit 1
            fi

            echo "Found MAX binary at: $MAIN_BIN"

            # Определяем путь к плагинам Qt
            QT_PLUGINS_DIR=""
            if [ -d "$out/share/max/plugins" ]; then
              QT_PLUGINS_DIR="$out/share/max/plugins"
            elif [ -d "$out/share/max/lib64/plugins" ]; then
              QT_PLUGINS_DIR="$out/share/max/lib64/plugins"
            fi

            # Обертка для запуска
            if [ -n "$QT_PLUGINS_DIR" ]; then
              makeWrapper "$MAIN_BIN" "$out/bin/max" \
                --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs} \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]} \
                --set QT_PLUGIN_PATH "$QT_PLUGINS_DIR" \
                --set QT_QPA_PLATFORM "wayland;xcb"
            else
              makeWrapper "$MAIN_BIN" "$out/bin/max" \
                --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs} \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]} \
                --set QT_QPA_PLATFORM "wayland;xcb"
            fi

            # ---------------------------------------------------------
            # ИСПРАВЛЕНИЕ ЯРЛЫКА
            # ---------------------------------------------------------
            DESKTOP_FILE=$(find $out/share/applications -name "*.desktop" 2>/dev/null | head -n 1)
            if [ -n "$DESKTOP_FILE" ]; then
                substituteInPlace "$DESKTOP_FILE" \
                  --replace "/usr/share/max/bin/max" "$out/bin/max" \
                  --replace "Exec=MAX" "Exec=$out/bin/max" \
                  --replace "/opt/MAX" "$out/opt/MAX" \
                  --replace "Exec=max" "Exec=$out/bin/max"
                substituteInPlace "$DESKTOP_FILE" \
                  --replace "Icon=/usr/share/max" "Icon=max"
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
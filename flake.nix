{
  description = "MAX Messenger for NixOS (Single File Flake)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/";
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
            openssl
            
            # === X11 библиотеки (новые имена top-level, без xorg.*) ===
            libx11
            libxcomposite
            libxdamage
            libxext
            libxfixes
            libxrandr
            libxrender
            libxscrnsaver    # Исправлено: было xorg.libXscrnsaver
            libxcb
            
            # Доп. библиотеки X11
            libxmu
            libxpm
            libxres
            libxt
            libxtst
            libxkbfile
            libxv
            libfontenc
            libxaw

            # === Qt6 модули ===
            qt6.qtbase
            qt6.qtdeclarative
            qt6.qtsvg
            qt6.qtimageformats
            qt6.qtserialport
            qt6.qtmultimedia
            qt6.qtwebchannel
            qt6.qtwebengine
            qt6.qtwebview
            qt6.qtpositioning
            qt6.qtquick3d
            qt6.qtlottie
            qt6.qtwayland
          ];

          unpackPhase = "dpkg -x $src .";

          installPhase = ''
            runHook preInstall

            mkdir -p $out

            # Переносим файлы
            if [ -d "usr" ]; then mv usr/* $out/ 2>/dev/null || true; fi
            if [ -d "opt" ]; then mv opt/* $out/ 2>/dev/null || true; fi

            # ---------------------------------------------------------
            # УДАЛЕНИЕ КОНФЛИКТУЮЩИХ БИБЛИОТЕК
            # ---------------------------------------------------------
            echo "Removing bundled libraries to use Nixpkgs versions..."

            clean_libs() {
              local LIB_DIR="$1"
              if [ -d "$LIB_DIR" ]; then
                echo "Cleaning $LIB_DIR..."
                rm -f "$LIB_DIR"/libQt6*.so*
                rm -f "$LIB_DIR"/libicu*.so*
                rm -f "$LIB_DIR"/libssl.so*
                rm -f "$LIB_DIR"/libcrypto.so*
                rm -f "$LIB_DIR"/libgio-2.0.so*
                rm -f "$LIB_DIR"/libglib-2.0.so*
                rm -f "$LIB_DIR"/libgmodule-2.0.so*
                rm -f "$LIB_DIR"/libgobject-2.0.so*
                rm -f "$LIB_DIR"/libmount.so*
                rm -f "$LIB_DIR"/libselinux.so*
              fi
            }

            clean_libs "$out/share/max/lib64"
            clean_libs "$out/share/max/bin/max-service/lib64"

            # ---------------------------------------------------------
            # НАСТРОЙКА СЕРВИСА (max-service)
            # ---------------------------------------------------------
            SERVICE_BIN_REAL="$out/share/max/bin/max-service/bin/max-service"
            SERVICE_DIR="$out/share/max/bin/max-service"

            if [ -f "$SERVICE_BIN_REAL" ]; then
              echo "Wrapping MAX Service binary..."
              mv "$SERVICE_BIN_REAL" "$SERVICE_BIN_REAL.real"
              
              makeWrapper "$SERVICE_BIN_REAL.real" "$SERVICE_BIN_REAL" \
                --prefix LD_LIBRARY_PATH : "$out/share/max/lib64" \
                --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs} \
                --set QT_PLUGIN_PATH "$SERVICE_DIR/plugins"
            fi

            # ---------------------------------------------------------
            # ОБРАБОТКА ГЛАВНОГО ПРИЛОЖЕНИЯ (max)
            # ---------------------------------------------------------
            MAIN_BIN=$(find $out -type f -executable -iname "MAX" | head -n 1)

            if [ -z "$MAIN_BIN" ]; then
              echo "ERROR: MAX binary not found!"
              exit 1
            fi

            echo "Found MAX binary at: $MAIN_BIN"

            QT_PLUGINS_DIR=""
            if [ -d "$out/share/max/plugins" ]; then
              QT_PLUGINS_DIR="$out/share/max/plugins"
            elif [ -d "$out/share/max/lib64/plugins" ]; then
              QT_PLUGINS_DIR="$out/share/max/lib64/plugins"
            fi

            # Обертка с поддержкой Wayland
            if [ -n "$QT_PLUGINS_DIR" ]; then
              makeWrapper "$MAIN_BIN" "$out/bin/max" \
                --prefix LD_LIBRARY_PATH : "$out/share/max/lib64" \
                --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs} \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]} \
                --set QT_PLUGIN_PATH "$QT_PLUGINS_DIR" \
                --set QT_QPA_PLATFORM "wayland;xcb"
            else
              makeWrapper "$MAIN_BIN" "$out/bin/max" \
                --prefix LD_LIBRARY_PATH : "$out/share/max/lib64" \
                --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs} \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]} \
                --set QT_QPA_PLATFORM "wayland;xcb"
            fi

            # ---------------------------------------------------------
            # ИСПРАВЛЕНИЕ ЯРЛЫКА
            # ---------------------------------------------------------
            DESKTOP_FILE=$(find $out/share/applications -name "*.desktop" 2>/dev/null | head -n 1)
            if [ -n "$DESKTOP_FILE" ]; then
                echo "Patching .desktop file: $DESKTOP_FILE"
                substituteInPlace "$DESKTOP_FILE" \
                  --replace-warn "/usr/share/max/bin/max" "$out/bin/max" \
                  --replace-warn "/opt/MAX/bin/max" "$out/bin/max"
                
                ICON_PATH=$(find $out/share/pixmaps -name "*.png" 2>/dev/null | head -n 1)
                if [ -n "$ICON_PATH" ]; then
                   substituteInPlace "$DESKTOP_FILE" --replace-warn "Icon=max" "Icon=$ICON_PATH"
                fi
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
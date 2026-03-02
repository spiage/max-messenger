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

        # Примечание: для обновления хеша используйте:
        # nix-prefetch-url https://download.max.ru/linux/deb/pool/main/m/max/MAX-26.5.1.48203.deb --print-path2

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
            # Системные библиотеки (используем для GLib и всего остального)
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
            qt6.qtdeclarative # <-- Решает ошибку с libQt6Qml
            qt6.qtwayland     # <-- Для работы на Wayland
            qt6.qtsvg         # <-- Часто нужен для иконок/графики
            qt6.qtimageformats
            qt6.qtbase
            openssl
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
            # 1. УДАЛЕНИЕ СИСТЕМНЫХ БИБЛИОТЕК ИЗ БАНДЛА
            # Это заставит приложение использовать системные версии (как в Astra),
            # но оставит встроенный libstdc++ (чтобы избежать вылета при закрытии).
            # ---------------------------------------------------------
            echo "Purging bundled system libraries to enforce system usage..."

            # Логируем структуру для отладки
            echo "=== Structure after unpack ==="
            find $out -type f -name "*.so*" | head -20 || true

            # Удаляем старые GLib libs (взаимодействие с systemd/dbus)
            rm -f $out/share/max/lib64/libgio-2.0.so.0
            rm -f $out/share/max/lib64/libglib-2.0.so.0
            rm -f $out/share/max/lib64/libgmodule-2.0.so.0
            rm -f $out/share/max/lib64/libgobject-2.0.so.0

            # Удаляем старые libmount/libselinux (чтобы не было конфликта с системным GLib)
            rm -f "$out/share/max/lib64/libmount.so.1"
            rm -f "$out/share/max/lib64/libselinux.so.1"

            # Удаляем OpenSSL, т.к. встроенный конфликтует с libngtcp2 из nixpkgs
            rm -f $out/share/max/lib64/libssl.so*
            rm -f $out/share/max/lib64/libcrypto.so*

            # === ДОБАВИТЬ УДАЛЕНИЕ QT И ICU ===
            # Удаляем Qt библиотеки, чтобы использовать модули из buildInputs (решает ошибку Qt_6_PRIVATE_API)
            rm -f $out/share/max/lib64/libQt6*.so*
            
            # Удаляем ICU (библиотеки юникода), т.к. они жестко привязаны к версии Qt
            rm -f $out/share/max/lib64/libicu*.so*

            # То же самое для сервиса
            rm -f $out/share/max/bin/max-service/lib64/libgio-2.0.so.0
            rm -f $out/share/max/bin/max-service/lib64/libglib-2.0.so.0
            rm -f $out/share/max/bin/max-service/lib64/libgmodule-2.0.so.0
            rm -f $out/share/max/bin/max-service/lib64/libgobject-2.0.so.0
            rm -f "$out/share/max/bin/max-service/lib64/libmount.so.1"
            rm -f "$out/share/max/bin/max-service/lib64/libselinux.so.1"
            rm -f $out/share/max/bin/max-service/lib64/libssl.so*
            rm -f $out/share/max/bin/max-service/lib64/libcrypto.so*     
            rm -f $out/share/max/bin/max-service/lib64/libQt6*.so*
            rm -f $out/share/max/bin/max-service/lib64/libicu*.so*

            # ---------------------------------------------------------
            # 2. НАСТРОЙКА СЕРВИСА (max-service)
            # ---------------------------------------------------------
            SERVICE_BIN_REAL="$out/share/max/bin/max-service/bin/max-service"
            SERVICE_DIR="$out/share/max/bin/max-service"

            if [ -f "$SERVICE_BIN_REAL" ]; then
              echo "Wrapping MAX Service binary..."
              mv "$SERVICE_BIN_REAL" "$SERVICE_BIN_REAL.real"
              SERVICE_LIB_DIR="$SERVICE_DIR/lib64"
              SERVICE_PLUGINS_DIR="$SERVICE_DIR/plugins"

              # Сервис использует свои библиотеки (хотя GLib тоже удален, и он возьмет системный)
              makeWrapper "$SERVICE_BIN_REAL.real" "$SERVICE_BIN_REAL" \
                --prefix LD_LIBRARY_PATH : "$SERVICE_LIB_DIR" \
                --prefix LD_LIBRARY_PATH : "$out/share/max/lib64" \
                --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs} \
                --set QT_PLUGIN_PATH "$SERVICE_PLUGINS_DIR"
            else
              echo "Warning: MAX Service binary not found at $SERVICE_BIN_REAL"
            fi

            # ---------------------------------------------------------
            # 3. ОБРАБОТКА ГЛАВНОГО ПРИЛОЖЕНИЯ (max)
            # ---------------------------------------------------------
            MAIN_BIN=$(find $out -type f -executable -iname "MAX" | head -n 1)

            if [ -z "$MAIN_BIN" ]; then
              echo "ERROR: MAX binary not found!"
              exit 1
            fi

            echo "Found MAX binary at: $MAIN_BIN"

            # Определяем путь к плагинам Qt (если существует)
            QT_PLUGINS_DIR=""
            if [ -d "$out/share/max/plugins" ]; then
              QT_PLUGINS_DIR="$out/share/max/plugins"
            elif [ -d "$out/share/max/lib64/plugins" ]; then
              QT_PLUGINS_DIR="$out/share/max/lib64/plugins"
            elif [ -d "$out/plugins" ]; then
              QT_PLUGINS_DIR="$out/plugins"
            fi

            # Используем встроенный libstdc++ (через папку lib64), но системный GLib (так как мы его удалили из lib64)
            if [ -n "$QT_PLUGINS_DIR" ]; then
              echo "Using Qt plugins from: $QT_PLUGINS_DIR"
              makeWrapper "$MAIN_BIN" "$out/bin/max" \
                --prefix LD_LIBRARY_PATH : "$out/share/max/lib64" \
                --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs} \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]} \
                --set QT_PLUGIN_PATH "$QT_PLUGINS_DIR"
            else
              echo "Warning: Qt plugins directory not found, skipping QT_PLUGIN_PATH"
              makeWrapper "$MAIN_BIN" "$out/bin/max" \
                --prefix LD_LIBRARY_PATH : "$out/share/max/lib64" \
                --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs} \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]}
            fi

            # ---------------------------------------------------------
            # 4. ИСПРАВЛЕНИЕ ЯРЛЫКА (.desktop file)
            # ---------------------------------------------------------
            DESKTOP_FILE=$(find $out/share/applications -name "*.desktop" 2>/dev/null | head -n 1)
            if [ -n "$DESKTOP_FILE" ]; then
                echo "Patching .desktop file: $DESKTOP_FILE"
                
                # Исправляем Exec (может быть с %U или без)
                substituteInPlace "$DESKTOP_FILE" \
                  --replace-warn "/usr/share/max/bin/max" "$out/bin/max" \
                  --replace-warn "/opt/MAX/bin/max" "$out/bin/max" \
                  --replace-warn "Exec=MAX " "Exec=$out/bin/max " \
                  --replace-warn "Exec=max " "Exec=$out/bin/max "
                
                # Исправляем иконку если путь абсолютный системный
                substituteInPlace "$DESKTOP_FILE" \
                  --replace-warn "Icon=max" "Icon=$out/share/pixmaps/max.png" \
                  --replace-warn "Icon=/usr/share/pixmaps/max.png" "Icon=$out/share/pixmaps/max.png" \
                  --replace-warn "Icon=/opt/MAX/share/pixmaps/max.png" "Icon=$out/share/pixmaps/max.png"
                
                # Исправляем WorkingDirectory если есть
                substituteInPlace "$DESKTOP_FILE" \
                  --replace-warn "Path=/opt/MAX" "Path=$out" \
                  --replace-warn "Path=/usr/share/max" "Path=$out"
            else
              echo "Warning: .desktop file not found"
            fi

            runHook postInstall
          '';

          fixupPhase = ''
            runHook preFixup

            # Удаляем .la файлы (могут ссылаться на удалённые библиотеки)
            find $out -name "*.la" -delete || true

            # Проверяем, что бинарники существуют
            if [ -f "$out/bin/max" ]; then
              echo "Verifying wrapper: $out/bin/max"
              file "$out/bin/max"
            fi

            runHook postFixup
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
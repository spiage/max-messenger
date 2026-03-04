{
  description = "MAX Messenger Native for NixOS (Full Native)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true; 
        };

        version = "26.7.0";
        debFile = "MAX-26.7.0.49753.deb";
        srcUrl = "https://download.max.ru/linux/deb/pool/main/m/max/${debFile}";
        srcHash = "sha256-7w0e0bRvf2OnDuo21h17P2tuEIQawOy1mz2XrWeBiJU=";

        libs = with pkgs; [
          # X11 Core
          libX11 libXcomposite libXcursor libXdamage libXext
          libXfixes libXi libXrandr libXrender libXScrnSaver
          libXtst libice libsm libxshmfence libxkbfile
          
          # X11 Toolkit libs
          libXt libXmu libXpm libXaw libXres
          
          # Доп. X11
          libXv libfontenc

          # XCB Utils
          libxcb-util libxcb-cursor libxcb-keysyms libxcb-image libxcb-render-util libxcb-wm

          # XCB Base
          libxcb
          
          # Graphics & Video
          libGL libglvnd mesa libdrm libgbm libva libvdpau
          
          # Wayland & Input
          wayland libxkbcommon
          
          # Audio
          alsa-lib pipewire
          libpulseaudio
          
          # Basic Stack
          glib fontconfig freetype dbus openssl nss nspr
          
          # System libs (Имена пакетов по твоему поиску)
          util-linux libselinux pcre2 libcap
          
          # QT Modules
          qt6.qtserialport

          # System & Auth
          cups krb5 libnotify
          
          # Tray Icon
          libappindicator-gtk3
        ];

        desktopItem = pkgs.makeDesktopItem {
          name = "MAX"; 
          exec = "max %U";
          icon = "max";
          desktopName = "MAX";
          comment = "MAX Messenger";
          categories = [ "Network" "InstantMessaging" ];
          startupNotify = true;
          terminal = false;
          mimeTypes = [ "x-scheme-handler/max" ];
          startupWMClass = "max"; 
        };

      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "max-native";
          inherit version;

          src = pkgs.fetchurl {
            url = srcUrl;
            hash = srcHash;
          };

          dontWrapQtApps = true;

          nativeBuildInputs = with pkgs; [
            dpkg
            autoPatchelfHook
            makeWrapper
            copyDesktopItems
          ];

          buildInputs = libs;
          desktopItems = [ desktopItem ];

          unpackPhase = ''
            dpkg -x $src .
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/share

            # --- 1. КОПИРОВАНИЕ РЕСУРСОВ (ПО ФАКТАМ) ---
            # Факт: find показал, что иконки в usr/share/icons и usr/share/pixmaps
            # Поэтому копируем эти папки целиком, а не только share/max
            
            # Копируем приложение
            cp -r usr/share/max $out/share/
            
            # Копируем иконки (чтобы makeDesktopItem нашел их и не было пустой папки)
            if [ -d "usr/share/icons" ]; then
              cp -r usr/share/icons $out/share/
            fi
            if [ -d "usr/share/pixmaps" ]; then
              cp -r usr/share/pixmaps $out/share/
            fi

            # --- 2. ПОЛНАЯ ОЧИСТКА ОТ КОНФЛИКТУЮЩИХ СИСТЕМНЫХ БИБЛИОТЕК ---
            # Удаляем bundled версии, чтобы autoPatchelfHook подцепил системные пакеты
            echo "Removing conflicting system libraries (glib, mount, selinux, etc.)..."
            
            # Очистка от старой glib (Клиент и Сервис)
            rm -f $out/share/max/lib64/libglib-2.0.so*
            rm -f $out/share/max/lib64/libgobject-2.0.so*
            rm -f $out/share/max/lib64/libgio-2.0.so*
            rm -f $out/share/max/lib64/libgmodule-2.0.so*
            rm -f $out/share/max/lib64/libgthread-2.0.so*

            rm -f $out/share/max/bin/max-service/lib64/libglib-2.0.so*
            rm -f $out/share/max/bin/max-service/lib64/libgobject-2.0.so*
            rm -f $out/share/max/bin/max-service/lib64/libgio-2.0.so*
            rm -f $out/share/max/bin/max-service/lib64/libgmodule-2.0.so*
            rm -f $out/share/max/bin/max-service/lib64/libgthread-2.0.so*

            # Очистка от старых утилит (вызывали ошибку MOUNT_2_40)
            rm -f $out/share/max/bin/max-service/lib64/libmount.so.1*
            rm -f $out/share/max/bin/max-service/lib64/libblkid.so.1*
            rm -f $out/share/max/bin/max-service/lib64/libselinux.so.1*
            rm -f $out/share/max/bin/max-service/lib64/libuuid.so.1*
            rm -f $out/share/max/bin/max-service/lib64/libpcre2-8.so.0*
            rm -f $out/share/max/bin/max-service/lib64/libcap.so.2*

            # --- 3. ИСПРАВЛЕНИЕ СИМЛИНКА ---
            SERVICE_LIB_DIR="$out/share/max/bin/max-service/lib64"
            if [ -L "$SERVICE_LIB_DIR/libtracernative.so" ]; then
              echo "Fixing broken symlink in max-service..."
              rm "$SERVICE_LIB_DIR/libtracernative.so"
              ln -s ../../../lib64/libtracernative.so "$SERVICE_LIB_DIR/libtracernative.so"
            fi

            # --- 4. QT.CONF ---
            mkdir -p $out/share/max/bin
            echo "[Paths]" > $out/share/max/bin/qt.conf
            echo "Prefix = .." >> $out/share/max/bin/qt.conf
            echo "Libraries = lib64" >> $out/share/max/bin/qt.conf
            echo "Plugins = plugins" >> $out/share/max/bin/qt.conf

            mkdir -p $out/share/max/bin/max-service/bin
            echo "[Paths]" > $out/share/max/bin/max-service/bin/qt.conf
            echo "Prefix = ../../.." >> $out/share/max/bin/max-service/bin/qt.conf
            echo "Libraries = lib64" >> $out/share/max/bin/max-service/bin/qt.conf
            echo "Plugins = plugins" >> $out/share/max/bin/max-service/bin/qt.conf

            # Блок ручного поиска иконки УДАЛЕН, так как мы уже скопировали их на шаге 1

            runHook postInstall
          '';

          autoPatchelfSearchPath = [
            "$out/share/max/lib64"
            "$out/share/max/bin/max-service/lib64"
          ];

          postFixup = ''
            # --- 5. WRAPPERS ---
            
            # Основной клиент
            wrapProgram $out/share/max/bin/max \
              --set QT_QPA_PLATFORM "wayland;xcb" \
              --set QT_PLUGIN_PATH "$out/share/max/plugins" \
              --prefix XDG_DATA_DIRS : "$out/share"

            # Сервис
            wrapProgram $out/share/max/bin/max-service/bin/max-service \
              --set QT_QPA_PLATFORM "wayland;xcb" \
              --prefix LD_LIBRARY_PATH : "$out/share/max/bin/max-service/lib64:$out/share/max/lib64" \
              --set QT_PLUGIN_PATH "$out/share/max/plugins:$out/share/max/bin/max-service/plugins" \
              --prefix XDG_DATA_DIRS : "$out/share"

            mkdir -p $out/bin
            ln -sf $out/share/max/bin/max $out/bin/max
            ln -sf $out/share/max/bin/max-service/bin/max-service $out/bin/max-service
          '';

          meta = with pkgs.lib; {
            description = "MAX Messenger (Native NixOS build, Full Native)";
            homepage = "https://max.ru";
            platforms = [ "x86_64-linux" ];
            maintainers = [ "spiage" ];
            license = licenses.unfree;
          };
        };
      }
    );
}
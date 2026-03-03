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

        version = "26.6.0";
        debFile = "MAX-26.6.0.49380.deb";
        srcUrl = "https://download.max.ru/linux/deb/pool/main/m/max/${debFile}";
        srcHash = "sha256-qMrcvnGTzC65BBG70+DCaLtF8XwAyQ4SHULyN5eC+BM=";

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
          name = "max";
          exec = "max %U";
          icon = "max";
          desktopName = "MAX";
          comment = "MAX Messenger";
          categories = [ "Network" "InstantMessaging" ];
          startupNotify = true;
          terminal = false;
          mimeTypes = [ "x-scheme-handler/max" ];
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

            # 1. Копируем саму программу
            mkdir -p $out/share/max
            cp -r usr/share/max/* $out/share/max/

            # 2. Копируем иконки (НАЙДЕНО КОМАНДОЙ FIND)
            # Прошлый код не копировал эти папки, поэтому иконки пропадали.
            
            # Копируем папку с иконками темы (hicolor)
            if [ -d "usr/share/icons" ]; then
              cp -r usr/share/icons $out/share/
            fi

            # Копируем папку pixmaps (где лежит max.png напрямую)
            if [ -d "usr/share/pixmaps" ]; then
              cp -r usr/share/pixmaps $out/share/
            fi

            # --- 1. УДАЛЕНИЕ max-service ---
            echo "Removing max-service directory..."
            rm -rf $out/share/max/bin/max-service

            # --- 1.5 ОЧИСТКА БИТЫХ СИМЛИНКОВ ---
            echo "Cleaning up broken symlinks caused by max-service removal..."
            find $out/share/max/lib64 -xtype l -delete

            # --- 2. УДАЛЕНИЕ СТАРОЙ GLIB ---
            echo "Removing bundled GLib libraries to use system GLib..."
            rm -f $out/share/max/lib64/libglib-2.0.so*
            rm -f $out/share/max/lib64/libgobject-2.0.so*
            rm -f $out/share/max/lib64/libgio-2.0.so*
            rm -f $out/share/max/lib64/libgmodule-2.0.so*
            rm -f $out/share/max/lib64/libgthread-2.0.so*

            # --- 3. QT.CONF ---
            mkdir -p $out/share/max/bin
            echo "[Paths]" > $out/share/max/bin/qt.conf
            echo "Prefix = .." >> $out/share/max/bin/qt.conf
            echo "Libraries = lib64" >> $out/share/max/bin/qt.conf
            echo "Plugins = plugins" >> $out/share/max/bin/qt.conf

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
            maintainers = [ "you" ];
            license = licenses.unfree;
          };
        };
      }
    );
}
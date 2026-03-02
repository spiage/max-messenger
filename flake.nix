{
  description = "MAX Messenger for NixOS (FHS Env)";

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
        srcUrl = "https://download.max.ru/linux/deb/pool/main/m/max/${debFile}";
        srcHash = "sha256-Wralrk1JzfL96jfGQvdgqHeIv46xSDlL/rT4E8v0Sb0=";

        max-unpacked = pkgs.stdenv.mkDerivation {
          pname = "max-contents";
          inherit version;
          src = pkgs.fetchurl { url = srcUrl; hash = srcHash; };
          
          nativeBuildInputs = [ pkgs.dpkg ];
          
          installPhase = ''
            mkdir -p $out
            dpkg -x $src .
            if [ -d "usr" ]; then cp -r usr/* $out/; fi
            if [ -d "opt" ]; then mkdir -p $out/opt && cp -r opt/* $out/opt/; fi
            
            # Удаляем битой симлинк
            find $out -type l -name "libtracernative.so" -exec rm -f {} \;

            # --- ИСПРАВЛЕНИЕ КОНФЛИКТА БИБЛИОТЕК ---
            # Создаем wrapper для max-service, чтобы он использовал свои библиотеки в приоритете.
            # Это решает ошибку "undefined symbol" при запуске сервиса.
            
            SVC_DIR="$out/share/max/bin/max-service"
            SVC_BIN="$SVC_DIR/bin/max-service"

            # Переименовываем оригинальный бинарник
            mv "$SVC_BIN" "$SVC_BIN.bin"

            # Создаем скрипт-обертку
            cat <<EOF > "$SVC_BIN"
            #!/bin/sh
            # Меняем порядок поиска: сначала библиотеки сервиса, потом общие, потом системные
            export LD_LIBRARY_PATH="$SVC_DIR/lib64:/usr/share/max/lib64:/usr/lib:/usr/lib64"
            exec "$SVC_BIN.bin" "\$@"
            EOF
            chmod +x "$SVC_BIN"
          '';
        };

        max-fhs = pkgs.buildFHSEnv {
          name = "max-fhs";

          targetPkgs = pkgs: with pkgs; [
            # Основные системные библиотеки
            zlib zstd glib nss nspr expat openssl alsa-lib cups dbus fontconfig freetype
            
            # Зависимости для GLib/GIO
            util-linux libselinux libsepol
            
            # Графика и мультимедиа
            gdk-pixbuf libgbm libGL libglvnd mesa libdrm
            libpulseaudio pipewire
            libxkbcommon wayland
            krb5
            
            # X11 Libraries (Базовые)
            libX11 libXcomposite libXcursor libXdamage libXext
            libXfixes libXi libXrandr libXrender libXScrnSaver
            libXtst libxcb
            libice libsm
            libxshmfence libxkbfile
            
            # X11 Libraries (Для max-service)
            libxt
            libxv
            libxaw
            libxmu
            libxpm
            libxinerama
            libxxf86vm
            libfontenc
            libxres
            libxau
            libxdmcp
            
            # xcb утилиты
            libxcb-cursor     
            libxcb-keysyms
            libxcb-wm
            libxcb-util
            libxcb-image
            libxcb-render-util

            libnotify libva libvdpau pango
            
            # Трей
            libappindicator-gtk3

            max-unpacked
          ];

          runScript = pkgs.writeShellScript "start-max" ''
            export QT_QPA_PLATFORM="wayland;xcb"
            
            # Стандартный путь для клиента: системные -> библиотеки приложения -> библиотеки сервиса
            export LD_LIBRARY_PATH=/usr/lib:/usr/lib64:/usr/share/max/lib64:/usr/share/max/bin/max-service/lib64
            
            export QT_PLUGIN_PATH="/usr/share/max/plugins:/usr/share/max/bin/max-service/plugins"

            exec /usr/share/max/bin/max "$@"
          '';
        };

      in
      {
        packages.default = max-fhs;
      }
    );    
}
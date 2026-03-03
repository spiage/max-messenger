{
  description = "MAX Messenger Native for NixOS (No Service)";

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

        version = "26.5.1";
        debFile = "MAX-${version}.48203.deb";
        srcUrl = "https://download.max.ru/linux/deb/pool/main/m/max/${debFile}";
        srcHash = "sha256-Wralrk1JzfL96jfGQvdgqHeIv46xSDlL/rT4E8v0Sb0=";

        desktopItem = pkgs.makeDesktopItem {
          name = "max";
          exec = "max %U";
          icon = "max";
          desktopName = "MAX";
          categories = [ "Network" "InstantMessaging" ];
          mimeTypes = [ "x-scheme-handler/max" ];
          terminal = false;
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
            autoPatchelfHook
            dpkg
            desktop-file-utils
            makeWrapper
            copyDesktopItems
          ];

          buildInputs = with pkgs; [
            # GL / OpenGL
            libglvnd
            
            # GLib
            glib
            gdk-pixbuf
            
            # X11 / XCB
            libX11 libXcomposite libXdamage libXext libXfixes libXrender
            libXrandr libXtst libXi libxcb libxkbfile libxshmfence
            libxcb-wm 
            
            # Input
            libxkbcommon
            
            # Font
            fontconfig freetype expat
            
            # Audio
            pulseaudio alsa-lib
            
            # Notification / DBus
            libnotify dbus
            
            # Video / DRM
            libdrm libgbm libva libvdpau
            
            # Crypto
            nss nspr libgcrypt krb5
            
            # Compression
            zlib zstd
            
            # Desktop integration
            hicolor-icon-theme

            qt6.qtserialport 
            gtk3 
            pango
            cairo
            atk
            
            libxcb-util
            libxcb-cursor
            libxcb-image
            libxcb-keysyms
            libxcb-render-util
          ];
          
          desktopItems = [ desktopItem ];

          unpackPhase = ''
            dpkg -x $src .
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/share/max
            if [ -d "usr/share/max" ]; then
              cp -r usr/share/max/* $out/share/max/
            fi

            # --- 1. УДАЛЕНИЕ max-service ---
            echo "Removing max-service directory..."
            rm -rf $out/share/max/bin/max-service

            # --- 1.5 ОЧИСТКА БИТЫХ СИМЛИНКОВ ---
            echo "Cleaning up broken symlinks caused by max-service removal..."
            find $out/share/max/lib64 -xtype l -delete

            # # --- 2. УДАЛЕНИЕ СТАРОЙ GLIB ---
            # echo "Removing bundled GLib libraries to use system GLib..."
            # rm -f $out/share/max/lib64/libglib-2.0.so*
            # rm -f $out/share/max/lib64/libgobject-2.0.so*
            # rm -f $out/share/max/lib64/libgio-2.0.so*
            # rm -f $out/share/max/lib64/libgmodule-2.0.so*
            # rm -f $out/share/max/lib64/libgthread-2.0.so*

            # --- 3. QT.CONF ---
            mkdir -p $out/share/max/bin
            echo "[Paths]" > $out/share/max/bin/qt.conf
            echo "Prefix = .." >> $out/share/max/bin/qt.conf
            echo "Libraries = lib64" >> $out/share/max/bin/qt.conf
            echo "Plugins = plugins" >> $out/share/max/bin/qt.conf

            # --- 4. ПОИСК ИКОНКИ ---
            mkdir -p $out/share/pixmaps
            find $out/share/max -iname "max.png" | head -1 | while read icon; do
              cp "$icon" $out/share/pixmaps/max.png
            done
            if [ ! -f "$out/share/pixmaps/max.png" ]; then
              find . -path "*/pixmaps/max.png" -o -path "*/icons/hicolor/*/apps/max.png" | head -1 | xargs -r cp -t $out/share/pixmaps/max.png || true
            fi

            runHook postInstall
          '';

          autoPatchelfSearchPath = [
            "$out/share/max/lib64"
          ];

          postFixup = ''
            # --- 5. WRAPPER ---
            wrapProgram $out/share/max/bin/max \
              --set QT_QPA_PLATFORM "wayland;xcb" \
              --set QT_PLUGIN_PATH "$out/share/max/plugins" \
              --prefix XDG_DATA_DIRS : "$out/share"

            mkdir -p $out/bin
            ln -sf $out/share/max/bin/max $out/bin/max
          '';

          meta = with pkgs.lib; {
            description = "MAX Messenger (Native NixOS build, no service)";
            homepage = "https://max.ru";
            platforms = [ "x86_64-linux" ];
            maintainers = [ "spiage" ];
            license = licenses.unfree;
          };
        };
      }
    );
}
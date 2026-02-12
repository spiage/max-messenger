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
            # Последний рабочий хеш
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

            # Переносим /usr
            if [ -d "usr" ]; then
                mv usr/* $out/ 2>/dev/null || true
            fi

            # Переносим /opt (тут обычно лежит папка MAX)
            if [ -d "opt" ]; then
                # Переносим всё содержимое opt в корень $out
                # Например: opt/MAX/ -> $out/MAX/
                mv opt/* $out/ 2>/dev/null || true
            fi

            # АВТОПОИСК БИНАРНОГО ФАЙЛА
            # Ищем файл с именем MAX или max, который можно выполнить
            # -iname делает поиск регистронезависимым
            MAIN_BIN=$(find $out -type f -executable -iname "MAX" | head -n 1)

            if [ -z "$MAIN_BIN" ]; then
              echo "=========================================="
              echo "ERROR: Binary 'MAX' not found in $out!"
              echo "Listing all files to debug:"
              find $out -type f -name "*AX*"
              find $out -type f -name "*ax*"
              echo "=========================================="
              exit 1
            fi

            echo "Found MAX binary at: $MAIN_BIN"

            # Создаем лаунчер в bin
            mkdir -p $out/bin
            makeWrapper "$MAIN_BIN" "$out/bin/max" \
              --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath buildInputs} \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]}

            # Настраиваем .desktop файл
            # Ищем файл desktop где угодно в $out
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

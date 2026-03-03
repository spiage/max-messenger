#!/usr/bin/env bash
#
# update-version.sh — Автоматическое обновление версии MAX Messenger
#

set -euo pipefail

FLAKE_FILE="$(dirname "$0")/../flake.nix"
REPO_URL="https://download.max.ru/linux/deb"

# Функция для обновления flake.nix
update_flake() {
    local VERSION="$1"
    local DEB_FILE="$2"
    local DEB_URL="$3"

    echo "✅ Целевая версия: $VERSION"
    echo "   Файл: $DEB_FILE"

    # Проверяем текущую версию и файл во flake.nix
    CURRENT_VERSION=$(grep -oP 'version = "\K[^"]+' "$FLAKE_FILE" | head -n 1)
    CURRENT_DEB=$(grep -oP 'debFile = "\K[^"]+' "$FLAKE_FILE" | head -n 1)

    if [[ "$DEB_FILE" == "$CURRENT_DEB" ]]; then
        echo "✓ Версия актуальна: $CURRENT_VERSION"
        echo "   Но хеш может быть устаревшим, поэтому продолжим..."
        echo ""
    else
        echo "📥 Текущая версия: $CURRENT_VERSION ($CURRENT_DEB)"
        echo "📥 Новая версия: $VERSION ($DEB_FILE)"
        echo ""
    fi

    # Проверяем доступность файла
    echo "🔍 Проверка доступности файла..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$DEB_URL")

    if [[ "$HTTP_CODE" != "200" ]]; then
        echo "❌ Ошибка: файл недоступен (HTTP $HTTP_CODE)"
        exit 1
    fi

    # Получаем размер файла
    FILE_SIZE=$(curl -s -I "$DEB_URL" | grep -i content-length | awk '{print $2}' | tr -d '\r')
    if [[ -n "$FILE_SIZE" ]]; then
        echo "   Размер: $(numfmt --to=iec-i --suffix=B "$FILE_SIZE" 2>/dev/null || echo "$FILE_SIZE байт")"
    fi

    echo "✅ Файл доступен"
    echo ""

    # Скачиваем файл для вычисления хеша
    TEMP_FILE=$(mktemp --suffix=.deb)
    trap 'rm -f "$TEMP_FILE"' EXIT

    echo "⬇️  Скачивание для вычисления хеша..."
    curl -L -s -o "$TEMP_FILE" "$DEB_URL"

    echo "🔐 Вычисление SHA256 хеша..."
    # Используем nix hash file --sri для получения хеша в формате SRI (base64)
    if command -v nix &> /dev/null; then
        HASH=$(nix hash file --sri "$TEMP_FILE" 2>/dev/null)
    elif command -v nix-prefetch-url &> /dev/null; then
        # Fallback: nix-prefetch-url возвращает base16, нужно конвертировать
        HASH=$(nix-prefetch-url "file://$TEMP_FILE" 2>/dev/null | tail -n 1)
        HASH="sha256-$HASH"
        echo "⚠️  Используем base16 хеш (возможна проблема с форматом)"
    else
        # Если nix нет, просто считаем хеш
        HASH=$(sha256sum "$TEMP_FILE" | awk '{print $1}')
        echo "⚠️  nix не найден, хеш в base16: $HASH"
    fi

    if [[ -z "$HASH" ]]; then
        echo "❌ Не удалось вычислить хеш"
        exit 1
    fi

    echo "✅ Хеш: $HASH"
    echo ""

    # Обновляем flake.nix
    echo "📝 Обновление $FLAKE_FILE..."

    sed -i "s/version = \"[^\"]*\";/version = \"$VERSION\";/" "$FLAKE_FILE"
    sed -i "s/debFile = \"[^\"]*\";/debFile = \"$DEB_FILE\";/" "$FLAKE_FILE"
    sed -i "s/srcHash = \"[^\"]*\";/srcHash = \"$HASH\";/" "$FLAKE_FILE"

    echo ""
    echo "✅ Готово!"
    echo ""
    if [[ "$DEB_FILE" == "$CURRENT_DEB" ]]; then
        echo "Изменения:"
        echo "  hash:     обновлён (версия не изменилась)"
    else
        echo "Изменения:"
        echo "  version:  $CURRENT_VERSION → $VERSION"
        echo "  debFile:  $CURRENT_DEB → $DEB_FILE"
        echo "  hash:     обновлён"
    fi
}

# Функция для получения версии из репозитория (без apt)
get_version_from_repo() {
    echo "🔍 Получение информации о версии из репозитория..."
    
    # Ссылка на файл со списком пакетов
    local PACKAGES_URL="${REPO_URL}/dists/stable/main/binary-amd64/Packages.gz"
    
    echo "   URL индекса: $PACKAGES_URL"

    # Создаем временный файл
    local TEMP_PKG=$(mktemp)
    trap 'rm -f "$TEMP_PKG"' RETURN

    # Скачиваем и распаковываем индекс пакетов
    if ! curl -fsSL "$PACKAGES_URL" | gunzip > "$TEMP_PKG" 2>/dev/null; then
        echo "❌ Не удалось скачать или распаковать Packages.gz"
        exit 1
    fi

    # Ищем блок с пакетом 'max'.
    # Добавлен флаг --max-count=1 (или exit в awk), чтобы взять ТОЛЬКО ПЕРВУЮ (свежую) версию.
    local PKG_BLOCK=$(awk '/Package: max$/,/^$/ {print; if (/^$/) exit}' "$TEMP_PKG")

    if [[ -z "$PKG_BLOCK" ]]; then
        echo "❌ Пакет max не найден в индексе."
        echo "[DEBUG] Первые 20 строк файла индекса:"
        head -n 20 "$TEMP_PKG"
        exit 1
    fi

    # Выводим отладочную информацию
    echo "[DEBUG] Найденный блок мета-данных пакета:"
    echo "$PKG_BLOCK" | head -n 10 
    echo "   ..."

    # Извлекаем Version и Filename.
    # Добавлен head -n 1 для надежности.
    local REPO_VERSION=$(echo "$PKG_BLOCK" | awk -F ': ' '/^Version:/ {print $2}' | head -n 1)
    local REPO_FILENAME=$(echo "$PKG_BLOCK" | awk -F ': ' '/^Filename:/ {print $2}' | head -n 1)

    if [[ -z "$REPO_VERSION" || -z "$REPO_FILENAME" ]]; then
        echo "❌ Не удалось извлечь Version или Filename из блока."
        echo "[DEBUG] BLOCK CONTENT:"
        echo "$PKG_BLOCK"
        exit 1
    fi

    echo "[DEBUG] Распознанная версия: $REPO_VERSION"
    echo "[DEBUG] Путь к файлу: $REPO_FILENAME"

    # Формируем итоговые данные
    local CLEAN_VERSION="${REPO_VERSION#*:}"
    local DEB_FILE=$(basename "$REPO_FILENAME")
    local DEB_URL="${REPO_URL}/${REPO_FILENAME}"

    update_flake "$CLEAN_VERSION" "$DEB_FILE" "$DEB_URL"
}

# Основная логика
echo "🚀 MAX Messenger Version Updater"
echo ""

# Автоматический режим — парсим репозиторий
get_version_from_repo
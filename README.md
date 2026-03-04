# MAX Messenger для NixOS

Пакет для установки мессенджера **MAX** на NixOS через механизм flake.

## О MAX

MAX — российский корпоративный мессенджер для безопасной коммуникации в бизнес-среде.

## Требования

- NixOS с поддержкой flake
- Архитектура: `x86_64-linux`

## Установка

### Через flake в configuration.nix (рекомендуется)

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/";
  inputs.max-messenger.url = "github:spiage/max-messenger";
  inputs.max-messenger.inputs.nixpkgs.follows = "nixpkgs";
}
```

```nix
{ config, pkgs, inputs, ... }:
{
  environment.systemPackages = with pkgs; [
    inputs.max-messenger.packages.${pkgs.system}.default
  ];
}
```

Затем выполните:

```bash
sudo nixos-rebuild switch
```

### Локальная сборка и установка в профиль

```bash
# Клонирование
git clone https://github.com/spiage/max-messenger.git
cd max-messenger

# Сборка и установка
nix build
nix profile install .

# Запуск
max
```

### Одноразовый запуск

```bash
nix run github:spiage/max-messenger
```

## Структура проекта

```text
max-messenger/
├── flake.nix              # Определение Nix flake
├── README.md              # Документация
├── .gitignore             # Игнорируемые файлы
└── scripts/
    └── update-version.sh  # Скрипт обновления версии
```

## Особенности сборки

- **Версия:** 26.7.0 (сборка 49753)
- **Источник:** официальный DEB-пакет с `download.max.ru`
- **Qt 6** с полной поддержкой плагинов
- **Системные библиотеки:** GLib, GTK3, X11, Wayland используются из Nixpkgs

## Обновление версии

### Автоматически (рекомендуется)

Скрипт автоматически определит последнюю версию из репозитория MAX, скачает файл, вычислит хеш и обновит flake.nix:

```bash
./scripts/update-version.sh
```

Скрипт не требует прав root и работает напрямую с индексом репозитория.

После выполнения проверьте изменения и закоммитьте:

```bash
git diff flake.nix
git commit -am "Update MAX to <версия>"
```

### Вручную

1. Скачайте новый DEB-файл
2. Получите хеш:

   ```bash
   nix hash file --sri /путь/к/MAX-<версия>.deb
   ```

3. Обновите `version`, `debFile` и `srcHash` в `flake.nix`

## Решение проблем

### Приложение не запускается

Проверьте наличие необходимых зависимостей:

```bash
nix build --print-build-logs
```

### Проблемы с иконкой

Иконка устанавливается в `$out/share/pixmaps/max.png` и автоматически прописывается в `.desktop` файл.

### Ошибки библиотек

Пакет использует `autoPatchelfHook` для автоматической настройки RPATH в ELF-бинарниках.

## Лицензия

MAX Messenger — проприетарное ПО. Данный flake предоставляет способ упаковки официального DEB-пакета для NixOS.

## Ссылки

- [Официальный сайт](https://max.ru)
- [NixOS Wiki](https://nixos.wiki)

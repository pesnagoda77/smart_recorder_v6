# Для Фила: Как добавить иконку

## Вариант 1: Через flutter_launcher_icons (рекомендуется)

```bash
# 1. Установить пакет
flutter pub add flutter_launcher_icons

# 2. Запустить генерацию
flutter pub run flutter_launcher_icons:main
```

Конфиг уже создан: `flutter_launcher_icons.yaml`

## Вариант 2: Вручную (если пакет не работает)

Иконка есть в `assets/icons/launcher_icon.png` (260KB, 1024x1024)

Нужно скопировать в:
- `android/app/src/main/res/mipmap-*/ic_launcher.png`
- `android/app/src/main/res/mipmap-*/ic_launcher_round.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

Размеры для Android:
- mdpi: 48x48
- hdpi: 72x72
- xhdpi: 96x96
- xxhdpi: 144x144
- xxxhdpi: 192x192

## Проверка

После сборки APK иконка должна появиться в:
- Список приложений
- Настройки → Приложения
- Рабочий стол (если добавлен)

## Дата: 2026-05-28

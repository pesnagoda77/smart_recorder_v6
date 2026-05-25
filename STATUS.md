## 📦 Smart Recorder v6 — Статус

**Путь:** `D:\Projects\Mobile\smart_recorder_v6`  
**Релиз:** ❌ Нет (только debug APK)

### Фичи, которые нужно доделать для релиза:
- [ ] Финальная проверка транскрипции VOSK
- [ ] Экспорт аудио/текста (share_plus уже подключен)
- [ ] Подписка PRO / Freemium модель
- [ ] Настройки качества записи
- [ ] Иконка и splash screen
- [ ] Подписанный APK (keystore)

### Сборка релиза:
```bash
cd D:\Projects\Mobile\smart_recorder_v6
flutter build apk --release
flutter build appbundle --release  # Для Google Play
```

**Следующий шаг:** Доделать фичи → собрать APK → перенести в `D:\Projects\Releases\smart_recorder_v1.0.0_android`

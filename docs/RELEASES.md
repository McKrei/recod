# Система релизов Recod

## Обзор

Recod использует **Sparkle** для авто-обновлений и **GitHub Actions** для автоматической сборки.

При создании нового релиза:
1. Ты запускаешь `make release`
2. Создаётся git-тег (например `v1.03`)
3. GitHub Actions автоматически собирает `.app`, подписывает и публикует релиз
4. Приложение на других Mac-ах подтягивает обновление через Sparkle

## Версионирование

Формат: **`MAJOR.MINOR`** (например `1.01`, `1.02`, ..., `1.99`, `2.01`)

- **Minor** (01–99) — инкрементируется автоматически при каждом `make release`
- **Major** (1, 2, 3...) — указывается вручную, когда хочешь начать новую мажорную версию

## Команды

| Команда | Описание |
|---------|----------|
| `make version` | Показать текущую и следующую версию |
| `make release` | Выпустить обновление (auto-increment minor) |
| `make release MAJOR=2` | Начать новую мажорную версию (2.01) |
| `make app` | Собрать `.app` бандл локально |
| `make dmg` | Создать DMG-образ |
| `make run` | Собрать и запустить для разработки |

## Как выпустить обновление

```bash
# 1. Убедись, что все изменения закоммичены и запушены
git add -A && git commit -m "описание изменений" && git push

# 2. Выпустить новую версию
make release
```

Всё! GitHub Actions сделает остальное. Через ~5 минут релиз появится на [GitHub Releases](https://github.com/McKrei/recod/releases).

## Как начать мажорную версию (например v2)

```bash
make release MAJOR=2
# Создаст v2.01, далее make release будет: v2.02, v2.03, ...
```

## Как обновляется приложение на других Mac

1. При запуске Recod автоматически проверяет `appcast.xml` на GitHub
2. Если есть новая версия — показывает диалог «Доступно обновление»
3. Нажимаешь «Обновить» → скачивается и устанавливается
4. Также можно проверить вручную: **меню → Check for Updates...**

## Первая установка на новый Mac

1. Скачать `Recod.zip` с [GitHub Releases](https://github.com/McKrei/recod/releases)
2. Распаковать
3. В терминале: `xattr -cr ~/Downloads/Recod.app`
4. Перетащить `Recod.app` в `/Applications`
5. При первом запуске разрешить в **Системные настройки → Конфиденциальность**

## Архитектура

```
push tag v* → GitHub Actions → swift build → .app бандл → zip + EdDSA подпись → GitHub Release
                                                                                     ↓
                                                         Recod.app проверяет appcast.xml
                                                                                     ↓
                                                              Sparkle: диалог обновления
```

## Конфигурация

- **Публичный ключ EdDSA** → `Info.plist` → `SUPublicEDKey`
- **Приватный ключ EdDSA** → GitHub Secrets → `SPARKLE_PRIVATE_KEY`
- **URL обновлений** → `Info.plist` → `SUFeedURL`
- **CI/CD workflow** → `.github/workflows/release.yml`

# PrismMusic для iOS 26

Нативный iOS-клиент PrismMusic в стилистике web-версии: тёмная Liquid Glass-эстетика с настоящим `.glassEffect()`, синхронизированный текст с пословной подсветкой, Apple Music-style анимированные обложки и полноценный Dynamic Island через Live Activities.

## Стек

- **iOS 26** — Liquid Glass (`.glassEffect()`), `tabBarMinimizeBehavior`, native glass tab bar
- **Swift 6.1** + `@Observable` macro
- **SwiftUI** — полностью декларативный UI
- **AVFoundation** — AVPlayer для стриминга, AVAudioSession для фонового воспроизведения
- **MediaPlayer** — `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` для lock screen / control center
- **ActivityKit + WidgetKit** — Live Activity и Dynamic Island
- **CoreMotion** — gyroscope parallax на обложках
- **CryptoKit** — хэширование ключей кэша

## Backend

Приложение работает поверх существующего PrismMusic Next.js-бэкенда:

| Endpoint | Назначение |
|---|---|
| `GET /api/music/search?q=...&token=...` | Поиск треков (Yandex + SoundCloud) |
| `GET /api/music/recommendations` | Лента рекомендаций |
| `GET /api/music/stream?url=...&token=...` | Проксированный аудиопоток с поддержкой Range |
| `GET /api/music/lyrics?artist=...&title=...` | Синхронизированный текст (LRCLIB / NetEase / OVH) |

URL бэкенда задаётся в `PrismMusic/Networking/APIConfig.swift` — константа `defaultBackendURL`. Изменить можно либо там, либо в Settings уже в приложении.

## Сборка

### 1. Установить XcodeGen (на Mac)

```bash
brew install xcodegen
```

### 2. Сгенерировать .xcodeproj

```bash
cd IOS-PrismMusic
xcodegen generate
```

### 3. Открыть в Xcode 16+ (для iOS 26 SDK нужна beta)

```bash
open PrismMusic.xcodeproj
```

### 4. Подписать и собрать

- Выбрать Team в Signing & Capabilities обоих таргетов (`PrismMusic`, `PrismMusicLiveActivity`)
- Run (`⌘R`) на симулятор iPhone 16 Pro / iOS 26
- Для теста Dynamic Island: симулятор iPhone 15 Pro+ или физическое устройство

## Что внутри

```
IOS-PrismMusic/
├── project.yml                          # XcodeGen-спека
├── PrismMusic/
│   ├── PrismMusicApp.swift              # @main entry
│   ├── Info.plist                       # capabilities + audio background mode
│   ├── App/                             # AppState, RootView, TabRoot
│   ├── Networking/                      # APIClient + DTOs
│   ├── Models/                          # Track, Lyrics
│   ├── Audio/                           # AudioPlayer, AudioSession, NowPlaying
│   ├── LiveActivity/                    # запуск/обновление Live Activity
│   ├── Design/                          # Theme, Glass-компоненты
│   ├── Features/
│   │   ├── Home/                        # лента рекомендаций
│   │   ├── Search/                      # поиск
│   │   ├── Library/                     # лайки + история
│   │   └── Player/                      # NowPlaying, MiniPlayer, AnimatedCover, SyncedLyrics
│   ├── Utilities/                       # ColorExtractor, LRC parser
│   └── Assets.xcassets/
└── PrismMusicLiveActivity/              # Widget Extension
    ├── LiveActivityAttributes.swift     # ActivityAttributes
    ├── LiveActivityBundle.swift
    └── LiveActivityViews.swift          # Dynamic Island + lock screen UI
```

## Capabilities

- **Background Modes** → `audio` (фоновое воспроизведение)
- **Push Notifications** (опционально, для удалённых обновлений Live Activity)
- **Sign In with Apple** (опционально, для синка с web-аккаунтом)

## Что не работает на симуляторе

- **Dynamic Island** — нужен физический iPhone 15 Pro / 16 Pro+. На симуляторе Live Activity показывается только на lock screen.
- **CoreMotion parallax** — gyroscope-данные мок только на физическом девайсе. На симуляторе обложка анимируется только zoom-эффектом.

## Лицензия

Личное использование. PrismMusic backend и интеграции с Yandex Music / SoundCloud остаются за тобой.

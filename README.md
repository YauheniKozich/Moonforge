# Moonforge

Moonforge — «лунная кузница»: название связывает Metal-рендеринг с лунным освещением и готической атмосферой демонстрационной сцены.

## Описание

Проект демонстрирует рендеринг 3D-сцен на `Metal + SwiftUI` с архитектурой, ориентированной на расширяемость, потокобезопасность и логическое отделение движка от приложения.

Ключевые возможности:

- рендеринг геометрии и моделей через `MetalEngine`
- runtime-переключение геометрии
- debug-панель с FPS и состоянием рендера
- snapshot-подход для безопасной передачи состояния в render thread
- компонентная архитектура рендера
- отдельная структура `MetalEngine` и слой интеграции с приложением; вынос в самостоятельный модуль пока не завершён
- разделение движка и приложения на уровне исходной структуры; `MetalEngine` пока собирается в том же app target
- pinch напрямую меняет расстояние между камерой и моделью, приближая и отдаляя объект

## О проекте

Moonforge — iOS-приложение для просмотра интерактивных 3D-сцен на Metal. Текущая демо-сцена показывает персонажа Sorceress из USDZ-модели на готическом фоне. Пользователь может вращать камеру вокруг модели и плавно менять расстояние до неё.

В сцене используются панорамный фон, каменные арки и постамент, источники света, карта теней, HDR/Bloom и анимированные частицы. Геометрия и материалы модели загружаются через ModelIO и MetalKit. Приложение подготавливает модели вне MainActor, затем переключает сцену на MainActor. При ошибке сохраняется предыдущая сцена и показывается сообщение; устаревшие и отменённые запросы не заменяют её.

Интерфейс включает экран сцены, настройки и отладочную панель с FPS, выбранной геометрией, состоянием рендера и статусом модели.

## Технологии

- Swift: языковой режим 6 (Swift 6 Strict Concurrency, `SWIFT_VERSION = 6.0`)
- SwiftUI
- Metal / MetalKit
- ModelIO
- simd
- iOS 18+

## Структура проекта

```text
Moonforge/
├── App/
│   ├── Coordinator/
│   ├── DI/
│   ├── DebugViews/
│   ├── Resources/
│   └── MoonforgeApp.swift
│
├── Domain/
│   ├── Errors/
│   ├── Logging/
│   ├── Protocols/
│   └── Scene/
│
├── Features/
│   ├── About/
│   ├── Scene/
│   └── Settings/
│
├── Integrations/
│   └── MetalEngine/
│       ├── Composition/
│       ├── Domain/
│       ├── Logging/
│       └── UI/
│
├── MetalEngine/
│   ├── Core/
│   ├── ExtensionPoints/
│   ├── Pipeline/
│   ├── Public/
│   │   └── Debug/
│   ├── Rendering/
│   │   └── Components/
│   ├── Resources/
│   │   ├── Meshes/
│   │   └── Textures/
│   ├── Shaders/
│   └── Utilities/
│       ├── Data/
│       └── Math/
│
├── Assets.xcassets
└── Preview Content/
```

`MoonforgeTests/` и `Moonforge.xcodeproj/` находятся рядом с каталогом `Moonforge/` в корне репозитория. В `Moonforge.xcodeproj` используется механизм `PBXFileSystemSynchronizedRootGroup` (Xcode 16), автоматически синхронизирующий файловую структуру с таргетами сборки: ресурсы из `Moonforge/App/Resources/` (PNG-текстуры и 3D-модели USDZ/OBJ) автоматически компилируются (`copypng`) и упаковываются в application bundle без ручного добавления в файл проекта.

## Архитектура

### Слои и зависимости

Проект разделён на четыре основные зоны:

- `MetalEngine/` — ядро рендеринга
- `Integrations/MetalEngine/` — glue-слой между движком и приложением
- `Domain/` — use case и app-level абстракции
- `App/` и `Features/` — UI, навигация, DI и presentation logic

Целевое направление зависимостей:

```text
App / Features / Domain / Integrations -> MetalEngine
MetalEngine -> только системные фреймворки и собственные engine-типы
```

Вынос движка в самостоятельный модуль пока не завершён: `TextureRepository`, `TextureLoader`, `TextureCache` и `MTLTextureFactory` используют протоколы из `Domain/Protocols/TextureProtocols.swift`. Поэтому указанная схема описывает целевую границу, а не полностью обеспеченную границу модулей.

### Почему `MetalEngine` не вынесен в отдельный target

На текущем этапе `MetalEngine` остаётся в составе app target:

- интеграция вынесена в `Integrations/MetalEngine/`
- перед выносом в framework потребуется перенести общие ресурсные протоколы в движок и проверить границу API

Изоляция движка на уровне отдельных build targets пока отсутствует.

### Что считается публичным API движка

Внешний контракт движка находится в `MetalEngine/Public/`.

Основные capability-протоколы:

- `GeometrySwitching`
- `CameraControlling`
- `ObjectRotating`
- `ModelTextureSwitching`

`MetalRenderable` — контракт интеграции для создания `MTKView` и связи UI с рендерером. Сейчас он тоже находится в `Public/`, поэтому README не трактует эту папку как отдельный Swift-модуль или гарантию стабильности API.

Debug API (`RenderDebugInfo`, `RenderDebugInfoProvider`, `ModelLoadStatus`) находится в `MetalEngine/Public/Debug/` и доступен в текущей сборке приложения. Отдельной compile-time границы для исключения его из релизного API пока нет.

Внутренние контракты и реализации рендера находятся в `MetalEngine/Rendering/`, включая `MetalRenderer`, `MetalViewRendering`, `MetalViewDelegate` и конкретные renderer-классы.

### Где живёт интеграция с приложением

Всё, что знает и про приложение, и про `MetalEngine`, находится в `Integrations/MetalEngine/`:

- `Composition/` — app-specific bootstrap и настройка сцены
- `Domain/` — адаптеры между engine capability API и use case/domain слоем
- `Logging/` — bridge между app logger и `MetalLogger`
- `UI/` — SwiftUI/MTKView интеграция

Если тип можно использовать повторно без знания про `App`, `Features` и `Domain`, он должен жить в `MetalEngine/`, а не в `Integrations/`.

### Компоненты рендера

**CameraComponent**

- потокобезопасно управляет камерой
- поддерживает `orbit`, `pan`, `zoom`, `reset`
- отдаёт snapshot состояния для render thread

**RenderTimingComponent**

- отслеживает `deltaTime`
- считает FPS по отправленным command buffer; обновления snapshot от жестов не увеличивают счётчик
- не измеряет число кадров, фактически показанных дисплеем, или время выполнения GPU
- используется для render diagnostics

**SnapshotBuilder**

- строит immutable `RenderSnapshot`
- подготавливает данные для render thread
- связывает камеру, матрицы, pipeline и текстуры

## Расширение движка

`MetalEngine` спроектирован так, чтобы его можно было расширять без размывания границ.

Основные точки расширения:

- `ExtensionPoints/GeometryRegistry.swift` — регистрация новых geometry sources
- `Resources/` — новые mesh/texture/resource providers
- `Core/RendererFactory.swift` и bootstrap-слой — создание и конфигурация renderer
- `Rendering/SceneRenderer.swift` — ядро renderer-поведения
- `Integrations/MetalEngine/Composition/` — app-specific составление demo-сцены
- `Public/` capability-протоколы — внешний способ управления renderer

Ориентиры дальнейшего развития:

- product policy не зашивается в core renderer
- demo-сцена и app defaults конфигурируются снаружи
- concrete internals движка не должны становиться extension point без необходимости
- object rotation и camera zoom расширяются отдельными capability-протоколами, а не общим `rotate(...)`

Выбор начальной геометрии находится в `SceneRendererBootstrap`. Готическое окружение, его ресурсы и положение постамента пока заданы непосредственно в `SceneRenderer`/`GothicEnvironment`.

## Конфигурация

Единственный набор констант движка находится в `Moonforge/MetalEngine/Core/MetalConfiguration.swift`. `Configuration` и `RendererConfiguration` удалены; код приложения и тестов использует `MetalConfiguration`.

| Параметр | Значение |
| --- | --- |
| Обычная дистанция камеры | `2.8` |
| Начальная дистанция для Sorceress/USDZ | `3.6` |
| Допустимая дистанция камеры | `0.5...5.0` |
| Поле зрения | `π / 4` |
| Near / far clipping | `0.1 / 100.0` |
| Размер fallback-текстуры | `256 × 256` |
| Лимит pipeline-кэша | `128` записей |

Параметры статические: передаваемый экземпляр `MetalConfiguration.default` пока не предоставляет индивидуальных настроек для каждого renderer. Частота кадров задаётся отдельно настройками приложения: `30`, `60` или `120` FPS, по умолчанию `60`.

## Правила развития структуры

При добавлении нового кода стоит придерживаться простого правила:

- если код можно переиспользовать без знания о приложении, он идёт в `MetalEngine/`
- если код связывает движок с UI, DI, логированием приложения или domain-слоем, он идёт в `Integrations/MetalEngine/`
- если код описывает продуктовый сценарий, экран, настройку пользователя или навигацию, он остаётся в `App/`, `Features/` или `Domain/`

Практические ориентиры:

- новые capability-контракты renderer добавляются в `MetalEngine/Public/`
- debug-модели и debug-протоколы добавляются в `MetalEngine/Public/Debug/`
- новые точки расширения движка добавляются в `MetalEngine/ExtensionPoints/`
- concrete renderer-реализации и view-facing semi-internal контракты живут в `MetalEngine/Rendering/`
- app-specific bootstrap, logger bridge и SwiftUI/MTKView bridge живут в `Integrations/MetalEngine/`

## Потоки и кадрирование

`MTKView` настроен на непрерывный рендеринг (`isPaused = false`, `enableSetNeedsDisplay = false`) и вызывает делегат `draw(in:)`. В коде `draw(in:)` описан как render thread, но это комментарий к контракту рендера, а не гарантия выделенного потока: отдельный render loop или `CAMetalDisplayLink` проект явно не создаёт.

UI-жесты и изменения камеры выполняются через `@MainActor`. Это соответствует источнику ввода и защищает состояние интерфейса. `SnapshotBuilder` собирает готовый `RenderSnapshot`, а `OSAllocatedUnfairLock` в `BaseRenderer` защищает запись и чтение ссылки на snapshot между кодом обновления и draw-вызовом. Блокировка оставлена, потому что доступ проходит между этими контекстами; в этой реализации snapshot не мутируется после публикации.

Класс `MetalViewDelegate` изолирован на `@MainActor` (соответствует вызову `MTKViewDelegate.draw(in:)` из главного потока UIKit). Вызов `updateRenderSnapshot()` выполняется синхронно перед кодированием кадра без создания асинхронных `Task { @MainActor }`, исключая лишние аллокации в render loop. Настройка и отложенная очистка renderer связаны поколением (`lifecycleGeneration`): очистка старого setup не удаляет ресурсы нового setup.

### Загрузка и переключение моделей

Начальная загрузка и переключение моделей из UI используют `switchGeometryAsync(named:)`. `GeometryRegistry` поддерживает асинхронные фабрики, а `ModelIOGeometryCache.prepare` помечен `@concurrent`: чтение ассета, подготовка mesh и создание текстур выполняются вне MainActor. Готовая модель передаётся через `sending`; её публикация и создание render pipeline происходят на MainActor.

Старая сцена продолжает использовать свой snapshot до готовности новой. Перед заменой проверяются отмена задачи, актуальность запроса и поколение renderer. Синхронные API `switchGeometry(named:)` и `getGeometry(...)` сохранены, но сами по себе не выносят загрузку с MainActor.

В начале первой загрузки возможна строка `Render snapshot skipped — resources not ready`: геометрия ещё не готова. Если после завершения подготовки snapshot остаётся недоступным, это уже требует отдельной проверки.

### HDR и Bloom

Сцена и промежуточный MSAA-буфер используют `rgba16Float`. Это сохраняет значения яркости выше `1` до извлечения Bloom. Затем выполняются извлечение ярких участков, уменьшение разрешения в четыре раза по каждой оси, два прохода размытия и композиция. Перед выводом в SDR-drawable применяется fitted ACES tone mapping; формат drawable — `bgra8Unorm_srgb`.

При поддержке используется MSAA 4×, иначе 1×. HDR здесь относится к промежуточному рендерингу: вывод EDR/HDR на дисплей не реализован. Float-буферы увеличивают расход GPU-памяти; измерений памяти и производительности на физическом устройстве пока нет.

## Debug-панель

Панель отображает:

- FPS
- Session ID
- Geometry
- pipeline / snapshot / texture status
- model status
- текущее расстояние камеры
- переключение geometry и model texture

## Модели, кэши и ограничения

Ресурсы моделей хранятся в:

```text
Moonforge/App/Resources/Models/
```

По умолчанию используются demo-модели приложения. Выбор начальной модели находится в integration/composition слое. Геометрия ModelIO хранится в LRU-кэше вместимостью до 5 вариантов; ключ учитывает имя, расширение, bundle и начальную дистанцию камеры.

`TextureRepository` использует внедрённые `TextureLoading`, `StringTextureCaching` и `TextureFactory`. Он ищет файл по имени и расширению в bundle и его каталоге `Textures`, а при отсутствии файла обращается к asset catalog. Загрузчик использует переданный Metal device, без создания нового системного устройства. При ошибке используется процедурная checkerboard-текстура с заполненными mipmap-уровнями. Отмена загрузки не запускает fallback; атомарная проверка поколения под `stateLock` предотвращает публикацию и кэширование устаревшего результата при конкурентных вызовах `loadTexture` и `cleanup`.

Текстуры материалов ModelIO загружаются отдельно внутри `ModelIOGeometry` через `MTKTextureLoader` с тем же device. `TextureRepository` не является общим кэшем всех текстур USDZ. Кэши ограничивают количество записей, а не объём памяти в байтах. `LRUCache` обеспечивает реентрантную безопасность в `removeValues(where:)` (предикат вычисляется вне блокировки) и условную Sendable-конформативность (`where Key: Sendable, Value: Sendable`). В `TextureCache` расчёт `hitRatio` атомарен внутри единого захвата `statsLock`. Статистика `TextureCache.evictions` учитывает фактическое вытеснение; замена существующего ключа не считается вытеснением. Специальной политики очистки по memory warning пока нет.

Отдельная обработка перехода приложения в фон, восстановления рендера и memory warnings пока не описана как реализованный сценарий. Поведение `MTKView` в этих состояниях зависит от системного жизненного цикла приложения.

## Диагностика JPEG-текстур Sorceress

В симуляторе iPhone 18 Pro с iOS 27 воспроизводятся сообщения:

```text
CVPixelBufferCreate returned err -6680. width 2048, height 2048, pixel format RGBA
CVPixelBufferCreate returned err -6680. width 1024, height 1024, pixel format RGBA
```

`-6680` — [`kCVReturnInvalidPixelFormat`](https://developer.apple.com/documentation/corevideo/kcvreturninvalidpixelformat): запрошенный формат не поддерживается для этого буфера. Это не код ошибки нехватки памяти.

Диагностика LLDB 14 октября 2026 года установила источник: `ModelIOGeometry.init` → `asset.loadTextures()` → ModelIO → CoreGraphics → JPEG-декодер ImageIO → CMPhoto → `CVPixelBufferCreate`. Размеры соответствуют двум emission-картам внутри `Sorceress.usdz`:

- `0/Material.002_emissive_scale0.jpg` — 2048×2048;
- `0/Material_emissive.jpg` — 1024×1024.

После сообщений подготовка модели завершается: в отладчике подтверждены emission-текстуры у всех четырёх submesh — три 2048×2048 и одна 1024×1024, формат `rgba8Unorm_srgb`. Sorceress отображалась в проверенном запуске. Это показывает, что ошибка внутреннего пути JPEG-декодирования не прервала загрузку; попиксельное сравнение с исходниками не выполнялось. Ошибка возникает до создания Metal-текстур материалов и не связана с `rgba16Float` в Bloom.

Поведение на физическом iPhone и других версиях ОС не проверено, поэтому считать сообщение исключительно проблемой симулятора пока нельзя. USDZ и способ загрузки не изменялись ради подавления лога. Возможный следующий диагностический эксперимент — отдельная копия USDZ с двумя emission-картами в PNG и сравнение логов и изображения; этот обход пока не проверен.

## Проверенная среда и результаты

Проверки выполнены 15 октября 2026 года: Xcode 27.0, Apple Swift 6, Debug-сборка, iPhone 18 Pro Simulator / iOS 18 (Darwin 27).

- Проект `Moonforge` и тестовый таргет `MoonforgeTests` компилируются в нативном режиме Swift 6 (`SWIFT_VERSION = 6.0`) с нулевым количеством предупреждений (**0 compiler warnings**).
- Полный прогон `MoonforgeTests`: **92 теста из 92 успешно пройдены (0 failures, 0 unexpected)**.
- Добавлены детерминированные регрессионные тесты Concurrency:
  - `TextureRepositoryConcurrencyTests` (проверка согласованности поколений при конкурентных загрузках и отмене);
  - `LRUCacheTests.testRemoveValuesReentrancy` (проверка реентрантности предиката фильтрации);
  - `TextureCacheTests.testConcurrentHitRatioConsistency` (атомарность расчёта статистики кэша).
- Выполнена runtime Metal-верификация в симуляторе с активным слоем Metal API Validation (`SIMCTL_CHILD_MTL_DEBUG_LAYER=1`): подтверждена корректная отрисовка готического окружения, 3D-модели Sorceress, теней и bloom-постпроцессинга без ошибок и сбоев GPU/API валидатора.

## Тестирование

`MoonforgeTests/` содержит 92 unit-теста XCTest, покрывающих управление камерой, вычисление матриц проекции и вида, построение `RenderSnapshot`, многопоточные LRU- и texture-кэши, тайминг рендера, use cases и view models настроек и сцены. Тесты запускаются стандартным вызовом `xcodebuild test` в среде iOS Simulator.

## Сборка и запуск

Открывайте `Moonforge.xcodeproj`, схема приложения — `Moonforge`, тестовый target — `MoonforgeTests`. Имя продукта, Swift-модуль и отображаемое имя приложения — `Moonforge`.

Bundle ID приложения `qwerty.MyMetal` и тестового bundle `qwerty.MyMetalTests` сохранены при переименовании. Это идентификаторы существующих bundles: сохранение app ID позволяет обновлять установленное приложение и сохранять его настройки. Старое имя в этих идентификаторах является намеренным.

```bash
# Сборка
xcodebuild -project Moonforge.xcodeproj -scheme Moonforge -destination 'generic/platform=iOS Simulator' build

# Тесты
xcodebuild -project Moonforge.xcodeproj -scheme Moonforge -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

Если нужен список доступных destination:

```bash
xcodebuild -project Moonforge.xcodeproj -scheme Moonforge -showdestinations
```

## Требования

- iOS 18+ (deployment target проекта).
- Xcode с поддержкой Swift 6 (проверенная версия — Xcode 27.0).
- Языковой режим Swift 6 (`SWIFT_VERSION = 6.0`) со строгой проверкой параллелизма (Swift 6 Strict Concurrency).
- Metal-устройство для рендеринга и соответствующих тестов.

## Лицензии

Лицензия MIT относится к коду проекта. Модель Sorceress/USDZ, панорама и текстуры — отдельные ресурсы; перед распространением приложения необходимо проверить и указать условия лицензии каждого ассета. Наличие MIT в репозитории само по себе не распространяет эту лицензию на сторонние материалы.

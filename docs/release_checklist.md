# Release checklist: App Store и Google Play

Актуальность аудита: 17 июля 2026 года. Этот документ фиксирует состояние репозитория, но не заменяет юридическую консультацию, проверку в App Store Connect/Play Console или тестирование подписанных сборок на реальных устройствах.

## Текущий вердикт

Приложение **не готово к публикации в сторах**. Компиляционный CI и базовые защитные настройки подготовлены, но production identity, подпись, домен, push credentials, store metadata, privacy declarations и договоры владельца продукта отсутствуют или не подтверждены.

| Область | Состояние | Что уже сделано / что блокирует релиз |
| --- | --- | --- |
| CI | Подготовлено для проверки кода и ручной подписи iOS | `mobile_quality.yml` выполняет format/analyze/tests и compile gates. Существующий dispatch-путь `build_ipa.yml` теперь экспортирует IPA только с distribution certificate/profile; неподписанный `.app` больше не упаковывается и не называется IPA. |
| Android signing | Защищено от ошибочного релиза | Release больше не подписывается debug-ключом. Без upload keystore сборка release останавливается с явной ошибкой. |
| iOS push entitlement | Частично | Debug использует APNs development, Profile/Release — production. Нужны App ID, Push Notifications capability, APNs key и provisioning profiles. |
| Transport security | Подготовлено | Cleartext запрещен в release; `localhost` и `10.0.2.2` разрешены только в Android debug source set. Android backup локальных account/chat caches отключен. |
| Runtime config | Частично | Supabase, Firebase, Telegram и analyzer можно задавать через `--dart-define-from-file`; production values и секреты еще не заведены в CI environments. |
| Store identity | Блокер | iOS bundle ID, Android application ID, namespace, OAuth scheme и test target все еще используют `com.example.clothes`. |
| Подпись и публикация | Блокер | Нет Apple Team/Distribution certificate/profile/App Store Connect API key и Android upload key/Play App Signing configuration. |
| Брендинг | Блокер | Иконка — стандартный Flutter logo, launch screen фактически шаблонный, store screenshots и финальное название не утверждены. |
| Deep links и sharing | Блокер | Код раздает `https://clothes.app/...`, но владение доменом, web fallback, AASA и `assetlinks.json` не подтверждены. Universal Links/App Links не настроены. |
| Privacy / legal | Блокер | Нет подтвержденных privacy policy/support URLs, privacy manifest/data labels, retention matrix и согласованного юридического лица/оператора данных. |
| App Review completeness | Блокер | Нужны живой backend, demo account, review notes и полный ручной прогон production-сценариев. |

## Репозиторные правила release-конфигурации

### Android подпись

Локально скопировать `android/key.properties.example` в `android/key.properties` и заполнить четыре значения. В CI вместо файла можно передать:

- `ANDROID_KEYSTORE_PATH`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Настоящие `key.properties`, keystore, `.p12`, provisioning profiles и dart-define файлы игнорируются Git. Upload key хранить в password manager/secret manager с резервной копией и документированным владельцем. Android прямо указывает, что debug key непригоден для Play Store и release должен подписываться приватным release key: [Android release signing](https://developer.android.com/build/building-cmdline#sign_cmdline).

### iOS IPA только через GitHub Actions

Ручной workflow `.github/workflows/build_ipa.yml` существует на прежнем пути,
поэтому после попадания новой версии workflow в default branch его можно вызвать
через `workflow_dispatch` и выбрать нужный `ref`. Он не запускается по push и не
создает фиктивный IPA из `--no-codesign` сборки.

В GitHub Environment `ios-release` необходимо настроить protection rules и:

- variable `IOS_TEAM_ID` — Apple Developer Team ID;
- secret `IOS_DISTRIBUTION_CERTIFICATE_BASE64` — base64 от `.p12` с private key;
- secret `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` — пароль `.p12`;
- secret `IOS_PROVISIONING_PROFILE_BASE64` — base64 от App Store Connect либо Ad Hoc `.mobileprovision`;
- secret `IOS_RELEASE_DART_DEFINES_BASE64` — base64 от production JSON на основе `config/release.dart-defines.example.json`.

Dispatch требует финальный `bundle_id`, версию, возрастающий build number и метод
`app-store-connect` либо `ad-hoc`. Job до сборки проверяет совпадение Team ID,
bundle ID, production APNs entitlement, тип provisioning profile, native OAuth
scheme, Firebase bundle ID и отсутствие placeholder runtime values. Затем Xcode
экспортирует distribution-signed IPA, подпись проверяется `codesign`, а artifact
содержит IPA и SHA-256. `app-store-connect` artifact предназначен для загрузки в
App Store Connect; `ad-hoc` устанавливается только на устройства, уже включенные
в соответствующий profile.

Release job запускается на GitHub `macos-26` и до архива проверяет Xcode 26+
вместе с iOS SDK 26+. Это важно: образ `macos-15` всё ещё может выбирать Xcode
16.4 по умолчанию, который App Store Connect больше не принимает:
[состав GitHub runner `macos-15`](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).

Workflow намеренно не загружает бинарник в App Store Connect. Для автоматической
загрузки отдельно понадобятся App Store Connect API key (`.p8`), issuer ID и key
ID, protected environment/reviewer и явный release approval. APNs `.p8` нужен
backend для live push, но не должен попадать в IPA job.

### Build-time параметры

Создать локальный файл на основе `config/release.dart-defines.example.json` и передавать его только из защищенного environment:

```text
flutter build appbundle --release --dart-define-from-file=config/release.dart-defines.json
flutter build ipa --release --dart-define-from-file=config/release.dart-defines.json
```

Supabase anon/publishable key является публичным клиентским идентификатором, а не server secret. `service_role`, provider client secrets, APNs private key и Firebase service-account key никогда не должны попадать в Flutter bundle или Git; они остаются в backend secret store. Production сборка должна явно переопределять fallback-проект и не использовать development backend по случайности.

`APP_URL_SCHEME` в Dart обязан в точности совпасть с native URL scheme в Android Manifest, iOS Info.plist и redirect URL во всех OAuth/Supabase кабинетах. До выбора финального ID менять только одну сторону нельзя.

## Внешние P0-блокеры до первой store-сборки

### 1. Identity, аккаунты и домен

- Утвердить юридическое название издателя, публичное название продукта и неизменяемые reverse-DNS identifiers.
- Зарегистрировать final iOS App ID и Android package name. Затем атомарно заменить `com.example.clothes` в Xcode target/tests, Android `applicationId`/`namespace`/Kotlin package, OAuth callbacks, Firebase apps и Supabase redirect allowlist.
- Подтвердить владение production-доменом. Если `clothes.app` не принадлежит владельцу продукта, ссылки из приложения нельзя выпускать в production.
- Разместить HTTPS web fallback для `/products/:id` и `/outfits/:id`, `apple-app-site-association` и `/.well-known/assetlinks.json`; добавить Associated Domains и Android verified App Links.
- Перевести mobile OAuth с legacy implicit callback (access token во фрагменте custom-scheme URI) на проверенный PKCE/state flow. Custom scheme без verified HTTPS link может быть перехвачен другим приложением; миграцию проводить вместе с OAuth/Supabase allowlists и тестами всех провайдеров.
- Создать отдельные staging и production проекты Firebase/Supabase и ограничить доступ сотрудников с MFA.

### 2. Apple signing и capabilities

- Production archive должен собираться Xcode 26+ с iOS 26 SDK: это обязательное требование для загрузок с 28 апреля 2026 года. Версию Xcode в release runner нужно выбрать явно и подтвердить в build log: [Apple SDK minimum requirements](https://developer.apple.com/news/upcoming-requirements/).
- Apple Developer Program: Team ID, App ID, Distribution certificate либо cloud-managed signing, provisioning profile и App Store Connect API key.
- Включить Push Notifications, выпустить APNs authentication key, привязать его к Firebase Cloud Messaging и проверить sandbox/production токены.
- Если сторонние логины используются как основной способ создания аккаунта, проверить требование App Review 4.8 и реализовать эквивалентный privacy-preserving login; для Sign in with Apple нужен capability и server-side token revocation при удалении аккаунта.
- Не добавлять `ITSAppUsesNonExemptEncryption` наугад. Сначала пройти export-compliance determination в App Store Connect; Apple отдельно предупреждает об ответственности за неверное заявление: [export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance).

### 3. Google Play signing и target API

- Создать upload key, включить Play App Signing, сохранить backup и recovery contacts.
- Текущий Flutter SDK задает target/compile SDK 36. Перед загрузкой подтвердить это по собранному AAB; с 31 августа 2026 новые приложения и обновления должны target Android 16 / API 36: [Google Play target API requirement](https://developer.android.com/google/play/requirements/target-sdk).
- Заполнить Play Console App access, Ads, Content rating, Target audience, Data safety и permissions declarations.
- Приложение показывает собственную сетку медиатеки через `photo_manager`, поэтому широкие `READ_MEDIA_IMAGES/VIDEO` требуют документированного core use case и проверки Play policy. Для разового вложения/аватара использовать системный Photo Picker, который не требует broad permission: [Android Photo Picker](https://developer.android.com/training/data-storage/shared/photo-picker), [media permission limitations](https://developer.android.com/training/data-storage/shared/media).

### 4. Privacy, UGC и удаление аккаунта

- Провести data inventory: ФИО/handle, email/телефон, адрес доставки, объявления, фото/видео, сообщения, заказы, история взаимодействий/просмотров, push token, moderation/report data, provider transaction IDs и server logs.
- Для каждого поля зафиксировать цель, правовое основание/согласие, получателей, регион хранения, срок retention, процедуру выгрузки и удаления.
- Опубликовать доступные без входа HTTPS страницы Privacy Policy, Terms/offer, Support/contacts и Account deletion. Ссылки должны быть и в store metadata, и внутри приложения.
- Заполнить App Store Privacy и Play Data safety строго по фактическому сетевому трафику production-сборки и SDK privacy reports.
- Создать валидный `PrivacyInfo.xcprivacy` только после data/required-reason API inventory; пустой или выдуманный manifest опаснее его честно отмеченного отсутствия. App Store Connect отклоняет невалидные manifests, а обязательные SDK должны поставлять свои: [Apple privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/).
- Проверить реальное полное удаление auth user и связанных данных/storage, повторную аутентификацию и понятный статус сохраненных по закону заказов. Apple требует инициировать удаление полного аккаунта внутри приложения: [account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app).
- Для пользовательских объявлений/образов/чатов обязательны reporting, blocking, moderation SLA, публичные контакты поддержки, abuse/rate limits и обработка незаконного контента. Сверить с [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

### 5. Бренд и store metadata

- Заменить Flutter icon полным набором финальных иконок без прозрачности для App Store; проверить adaptive/monochrome icon Android.
- Сделать финальный launch screen без рекламы и динамического контента.
- Подготовить описание, keywords, category, copyright/trademark permissions, age/content rating, screenshots для реально поддерживаемых iPhone/iPad/Android форм-факторов и support/marketing URLs.
- Ответить на обновленные вопросы Apple age rating; при распространении в ЕС также подтвердить DSA trader status и публичные контакты продавца.
- Решить, поддерживается ли iPad и landscape. Сейчас target включает iPhone и iPad, а iOS plist разрешает landscape; это означает отдельный UI/QA и screenshots, а не формальный checkbox.

## Production backend и review environment

- Все Supabase migrations применены в staging, затем production; RLS/Storage policies проверены для anon, buyer, seller, moderator и admin ролей.
- Edge Functions имеют versioned deployment, idempotency, webhook signature verification, replay protection, timeouts/retry/dead-letter handling и redaction логов.
- SMTP/SMS/provider quotas, backup/PITR и restore drill, monitoring/crash reporting, alerts и incident contacts настроены до review.
- YooKassa/доставка включаются feature flags только после договоров, provider sandbox certification и end-to-end reconciliation/refund/cancel tests. Не показывать Review функции, которые заканчиваются placeholder/error.
- Для App Review подготовить отдельный стабильный demo account, тестовые объявления/чаты/заказы, включенный backend и review notes. Apple требует рабочий backend и доступ к account-based features: [App Review preparation](https://developer.apple.com/app-store/review/).

## Единый финальный прогон перед подписью

Запускать один раз после объединения всех исправлений, а не после каждой локальной правки:

```text
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --release --no-codesign
```

После появления credentials отдельно выполнить production artifacts:

```text
flutter build appbundle --release --dart-define-from-file=config/release.dart-defines.json
flutter build ipa --release --dart-define-from-file=config/release.dart-defines.json
```

Затем обязательны:

1. Установка signed build через internal testing/TestFlight на чистые реальные устройства.
2. Cold start, upgrade, logout/login, OAuth callbacks, push foreground/background/terminated, denied permissions и offline/poor network.
3. Фото/видео camera/library, отправка и получение чата, share/deep links с установленным и неустановленным приложением.
4. Полный buyer/seller order flow, cancel/refund/retry/idempotency и provider webhook reconciliation.
5. Account deletion, data export/retention, report/block/moderation и восстановление после force-kill.
6. Проверка AAB/IPA identifiers, signing certificate/profile, entitlements, privacy report и отсутствие private secrets в распакованном artifact.

CI использует pinned commit SHA для сторонних GitHub Actions и минимальное `contents: read`; GitHub также позволяет принудительно требовать full-length SHA на уровне repository settings: [GitHub Actions security setting](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository).

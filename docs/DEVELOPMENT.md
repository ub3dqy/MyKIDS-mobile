# Android development / Разработка приложения Android

[English](#english) · [Русский](#русский)

## English

This repository contains the **MyKIDS Android application, version 0.1.122**. The server implementation, deployment tools, and operational configuration are not distributed here.

### Tools

Use Flutter **3.47.8**, as pinned in `mobile/.fvmrc`, Dart **3.13.7**, JDK **17**, and Android SDK **37**. Application dependencies are locked in `mobile/pubspec.lock`; Android build versions are recorded in `mobile/android/build-tool-versions.properties`.

### Build and check the app

From the repository root, with the matching Flutter version available:

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
```

Use an Android emulator for development. To connect a debug build to a compatible family service that you have permission to use, replace the example address below with its HTTPS address:

```powershell
flutter run --debug --dart-define=API_URL=https://family.example.com
```

An existing family requires its own account or a parent invitation. This source checkout does not provide server access, credentials, or a shared demo family. Some network and native integration checks require separate isolated service fixtures and run outside the standalone client checkout.

### Notifications and signed builds

Firebase notifications require your own `mobile/android/app/google-services.json`. Release signing requires your own `mobile/android/key.properties` and keystore. Keep all of these outside Git. Release builds require HTTPS.

Use only fictional data in tests and screenshots. Review the files and history you are about to publish. Backend code, server tools, databases, private documents, and credentials must not be added to this application repository.

## Русский

В репозитории опубликовано **только приложение MyKIDS для Android, версия 0.1.122**. Серверный код, средства размещения и рабочие настройки сервера здесь не распространяются.

Нужны Flutter **3.47.8** из `mobile/.fvmrc`, Dart **3.13.7**, JDK **17** и Android SDK **37**. Зависимости приложения закреплены в `mobile/pubspec.lock`, версии средств сборки Android — в `mobile/android/build-tool-versions.properties`.

Команды выше устанавливают зависимости приложения, проверяют код и запускают клиентские проверки. Для запуска используйте эмулятор Android. В примере адреса укажите собственный совместимый семейный сервис, к которому у вас есть доступ. Для входа нужны семейный аккаунт или приглашение родителя; серверные доступы и общая демонстрационная семья в эту копию не входят.

Для уведомлений Firebase и подписи выпуска нужны свои настройки и ключи. Не добавляйте их в Git. Обычная сборка требует HTTPS. Часть сетевых и системных проверок использует отдельные изолированные окружения и запускается отдельно от этого клиентского проекта.

В проверках и снимках экранов используйте только вымышленные данные. Перед открытой отправкой проверяйте файлы и историю. Серверную часть, служебные программы сервера, базы, личные документы, пароли и ключи в этот репозиторий не добавлять.

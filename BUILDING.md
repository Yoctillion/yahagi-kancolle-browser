# 源码构建与验证

简体中文 ｜ [English](BUILDING.en.md) ｜ [한국어](BUILDING.ko.md)

本指南面向需要自行构建 Android 客户端或参与开发的人。安装已发布应用请使用 [GitHub Releases](https://github.com/yamatosaki/yahagi-kancolle-browser/releases)。主分支源码可能领先于安装包；需要某个发布版本的源码时，请选择发布页对应的标签，并以该标签的配置为准。

## 开发环境

当前 [CI 配置](.github/workflows/ci.yml) 使用：

- Flutter **3.44.8 stable**；Dart 随 Flutter 安装，版本约束见 `pubspec.yaml`。
- JDK **17**。运行 Android 原生测试时，让 `JAVA_HOME` 指向 JDK 17。
- Android SDK、命令行工具及接受许可的构建组件。`compileSdk` 和 NDK 版本由 Flutter SDK 决定，见 `android/app/build.gradle.kts`。
- Git、Python 3。Python 数据构建测试还需要 Pillow。

先安装上述工具，再用 `flutter doctor -v` 检查环境；Android 许可可通过 `flutter doctor --android-licenses` 确认。首次构建需要下载 Flutter、Pub、Gradle 和 Android 相关依赖。

## 获取源码并构建 debug

在终端中执行：

```sh
git clone https://github.com/yamatosaki/yahagi-kancolle-browser.git
cd yahagi-kancolle-browser
flutter pub get
flutter build apk --debug
```

生成的安装包位于 `build/app/outputs/flutter-apk/app-debug.apk`。连接调试设备后，也可以运行 `flutter run`。

debug 构建使用本机自动生成的调试签名，不需要维护者的签名密钥、账号数据、游戏数据库或备份文件。Android SDK 路径等本机配置由工具生成，不应提交进仓库。

## 验证命令

在仓库根目录执行与 CI 对应的检查：

```sh
python -m pip install pillow
python -m unittest tool.test_check_repository_hygiene -v
python tool/check_repository_hygiene.py
python -m unittest tool.test_build_sortie_release tool.test_build_enemy_release tool.test_verify_data_release -v
dart run tool/verify_data_release.dart
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Android 原生单元测试，在 Windows PowerShell 中执行：

```powershell
.\android\gradlew.bat -p android :app:testDebugUnitTest --console=plain
```

在 Linux 或 macOS 中执行：

```sh
chmod +x android/gradlew
./android/gradlew -p android :app:testDebugUnitTest --console=plain
```

部分集成测试使用仅保存在本地的原始样本，公开检出缺少这些样本时会明确跳过。公开的人工合成测试不需要真实账号或游戏接口转储；不要为运行本地集成测试而把原始数据加入仓库。

## release 签名

`flutter build apk` 默认选择 release 模式。该模式需要自行配置签名；首次验证源码能否构建时，请使用上面的 `--debug` 命令。

制作自己的 release 包时，将签名配置放在仓库外，用环境变量 `YAHAGI_SIGNING_PROPERTIES` 指向该文件。配置字段为 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`，具体读取逻辑见 `android/app/build.gradle.kts`。配置完成后可运行 `flutter build apk --release`。

密钥、签名配置、本机 SDK 配置、安装包、日志和记录备份均不应提交。第三方代码与资源许可见 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES)，提交规范见 [贡献指南](CONTRIBUTING.md)。

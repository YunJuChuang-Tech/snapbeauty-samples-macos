# SnapBeauty macOS Samples

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey.svg)](#环境要求)

本仓库提供 SnapBeauty SDK 1.3.1 的 macOS 接入示例。两个入口都使用公开的 `snapbeauty/desktop.h` C 接口。

| 示例 | 内容 |
| --- | --- |
| [相机美颜](macos/main.m) | AVFoundation 采集 BGRA8 → SnapBeauty → AppKit 预览。可切换与 Android 示例一致的 15 套妆容 |
| [纯 C 接入](examples/minimal.c) | 生成一张 RGBA8 渐变，初始化授权、创建引擎、处理一帧并释放资源 |

## 环境要求

- Apple 芯片（arm64）、macOS 12 及以上、支持 Metal 的设备。
- Xcode 或带 macOS SDK 的 Xcode Command Line Tools，构建调用 `xcrun clang`。
- 相机示例需要可访问的摄像头。

## 快速开始

### 1. 解压 SDK

从 SnapBeauty 官方渠道获取 `SnapBeauty-macOS-1.3.1.zip`。下载入口开放前，可向 SnapBeauty SDK 提供方获取 ZIP。将文件放在 `~/Downloads/`，在仓库根目录执行以下命令。也可解压至任意目录，并通过构建的第一个参数或 `SNAPBEAUTY_SDK_ROOT` 指定包含 `include/`、`lib/`、`Assets/`、`Shaders/` 的目录。

```bash
mkdir -p .local/sdk
shasum -a 256 "$HOME/Downloads/SnapBeauty-macOS-1.3.1.zip"
unzip "$HOME/Downloads/SnapBeauty-macOS-1.3.1.zip" -d .local/sdk
```

本示例对应的 ZIP SHA-256 为 `129ea862cc4837334f64ca6bec3135bcb1cc70960f0f3b42454e2dd2190adf61`。

### 2. 构建

```bash
export SNAPBEAUTY_BUNDLE_ID=ai.snapbeauty.samples.macos
bash macos/build.sh .local/sdk/SnapBeauty-macOS-1.3.1 build/macos
```

输出 `build/macos/SnapBeautyCamera.app` 和 `build/macos/snapbeauty-minimal`。重复构建时指定新的输出目录。脚本把 SDK 动态库放入 `Contents/Frameworks`，用 `@executable_path/../Frameworks` 加载；`Assets/` 和 `Shaders/` 一起放入 `Contents/Resources`。默认使用本地 ad hoc 签名组装示例 App。

### 3. 运行与授权

默认构建会把 `macos/SampleLicense/snapbeauty.license` 打包进相机 App。这是用于默认 Bundle ID `ai.snapbeauty.samples.macos` 和纯 C 示例默认身份 `ai.snapbeauty.samples.macos.minimal` 的 macOS 离线体验授权，有效期至 2029 年 11 月 10 日。

```bash
open -n build/macos/SnapBeautyCamera.app
```

macOS 授权需与移动端分开签发。使用自有 Bundle ID 时，在构建前设置 `SNAPBEAUTY_BUNDLE_ID`，并向 SnapBeauty 提供平台 `macos` 和该 Bundle ID 申请授权。构建自有 Bundle ID 时可用 `open -n --env "SNAPBEAUTY_LICENSE_FILE=/path/to/your.license" build/macos/SnapBeautyCamera.app` 启动，环境变量指定的文件优先于内置文件。纯 C 示例的自定义身份由 `SNAPBEAUTY_APP_ID` 指定。

相机 App 的 [Info.plist](macos/Info.plist) 用 `NSCameraUsageDescription` 声明用途。首次使用时允许访问摄像头；如已拒绝，到「系统设置 → 隐私与安全性 → 摄像头」启用后重新启动 App。

用预览窗口右下角的妆容菜单切换预设。每套妆容同时使用 Android 示例为它搭配的滤镜，妆容和滤镜强度均为 0.4。「不使用妆容」会清除两者。默认使用 App 自带的妆容资源。

纯 C 示例通过 `SNAPBEAUTY_LICENSE_FILE` 读取同一份体验授权。合成帧没有人脸，适合验证接口调用。

```bash
SNAPBEAUTY_LICENSE_FILE="$PWD/macos/SampleLicense/snapbeauty.license" \
  SNAPBEAUTY_ASSETS="$PWD/.local/sdk/SnapBeauty-macOS-1.3.1/Assets" build/macos/snapbeauty-minimal
```

`xm_desktop_init` 的状态 JSON 中 `code=0` 表示授权有效，`code=2` 表示缺少授权。没有有效授权时，SDK 返回原帧。相机程序使用单调时钟，给 SDK 提供采集缓冲区的实际步幅，并在销毁引擎前停止采集。

## 许可

查看 [Apache 2.0 许可证](LICENSE)和[第三方声明](THIRD_PARTY_NOTICES.md)。

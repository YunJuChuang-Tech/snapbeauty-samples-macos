# Third-party notices

The sample source and original makeup artwork are provided under the repository's Apache 2.0 license. The SnapBeauty SDK, its models and its bundled engine resources are separately licensed. See the SDK package's `NOTICE` and `Licenses/` and the provider's terms for use and redistribution.

Builds use the locally obtained SnapBeauty macOS SDK 1.3.9 distribution. The SDK archive, headers, binaries and engine resources are supplied separately. AppKit, AVFoundation, CoreMedia, CoreVideo and CoreGraphics come from the Apple platform SDK.

## 滤镜 LUT

`assets/host-filters/luts/` 中的 10 张滤镜（`bright3`、`rose3`、`stylized11`、`mono1`、`warm1`、`warm2`、`fresh1`、`muted5`、`natural2`、`natural4`）不属于 SnapBeauty SDK，由本示例随 App 一起打包，在创建引擎后用 SDK 的 `registerFilter` 注册，之后和 SDK 内置滤镜一样用 `setFilter` 选择。

- 素材来源：RawTherapee Film Simulation Collection 2015-09-20（https://rawtherapee.com/shared/HaldCLUT.zip ），作者 **Pat David、Pavlov Dmitry、Michael Ezra**。
- 改动：重采样为 64³，用强度、提亮、冷暖、色调、饱和度、对比度六个全局参数调整，再三线性采样为 16³ 并量化为 RGB8（256×16）。
- 基于本示例发布 App 时，如保留这些滤镜，须一并保留上述署名与许可文件；不需要时删除该目录即可，其余功能不受影响。

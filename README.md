# LocalSend arm64 重编译版（glibc 2.31）

官方那个 arm64 deb 在麒麟 V10 上一启动就报 `GLIBC_2.34 not found`，装不上也跑不了。这里是拿 LocalSend 1.19.0 的源码在 glibc 2.31 的机器上重新编的，二进制最高只要 2.30，装上就能用。

功能没动，和官方一模一样。

## 安装

从 [Releases](../../releases) 下 deb，然后：

```bash
sudo apt install ./localsend_1.19.0+65-1kylin1_arm64.deb
```

装完菜单里搜 LocalSend，或者命令行敲 `localsend_app`。

包名和安装路径都跟官方一致（`/opt/localsend_app`），版本号比官方高（`1.19.0+65-1kylin1` > `1.19.0+65`），所以之前装过官方包的会被直接替换，不用先卸。

卸载：`sudo apt remove localsend`

## 哪些机器能用

arm64，glibc 2.31 及以上。x86 的机器用官方包就行，别用这个。

我只在麒麟 V10 SP1 上实测过（飞腾 CPU，glibc 2.31-0kylin9.1k22.5），别的 arm64 发行版理论上没问题，但我没试。

想知道差在哪的话：官方包里 C++ runner 和 Rust 核心库都要求 GLIBC 2.34，这个包里分别是 2.17 和 2.30。Flutter 引擎本身两边都是 2.18。

## 一个已知问题

界面可能会走软件渲染。飞腾那批机器的 Mesa 驱动给不出 Flutter 要的 GL 上下文，程序会自己退回用 CPU 画。功能完全不受影响，就是首次启动慢两三秒，传文件这种场景基本感觉不到。

想试试硬加速：

```bash
FLUTTER_LINUX_RENDERER=opengl localsend_app
```

没成功就还是软的，别折腾。

## 自己编译

```bash
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev libayatana-appindicator3-dev
./build-all.sh
```

`build-all.sh` 会把源码、Flutter SDK、Rust、打包一条龙做完。

有两个坑记一下，省得你重踩：

**Flutter 官方不给 arm64 Linux 的预编译包。** 但不用自己编引擎，`git clone --branch 3.41.9` 检出的时候它会按本机架构下 arm64 的 Dart SDK 现场搭起来。官方 CI 也是这么干的。

**麒麟的 clang-10 包里没有 ld.lld。** Flutter 3.41 的构建步骤非要找它。脚本的做法是把 clang 复制一份到 `~/.local/llvm-shim/`，再把系统的 `ld` 软链成 `ld.lld` 顶上。这里必须是复制不能是软链——Flutter 会对 clang 路径做 realpath 解析，软链会被解回 `/usr/lib/llvm-10/bin`，等于没换，白忙。

另外 `packages/localsend_isolates/pubspec.yaml` 里的 `flutter_rust_bridge` 得钉死成 `2.12.0`。仓库里 Rust 那边和生成的 Dart 绑定都是 2.12.0，用 `^` 一旦升到 2.13 启动就直接拒绝执行，报 `codegen version (2.12.0) should be the same as runtime version (2.13.0)`。

## 改了什么

就一行，跟功能无关：

```diff
# packages/localsend_isolates/pubspec.yaml
-  flutter_rust_bridge: ^2.12.0
+  flutter_rust_bridge: 2.12.0
```

打包脚本是我加的，上游代码没动。

## 协议

上游是 Apache-2.0，这个仓库跟着走，`LICENSE` 就是原文件。版权归 Tienisto 和 LocalSend 的贡献者。

跟官方项目没关系，有问题提这边，别去打扰上游。

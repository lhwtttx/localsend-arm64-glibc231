#!/bin/bash
# 从源码构建可在 glibc 2.31 arm64 上运行的 LocalSend，并打成 deb
#
# 实测环境：银河麒麟 V10 SP1 / aarch64 / glibc 2.31 / gcc 9.3
# 在别的 arm64 发行版上应该也能用，但未逐一验证。
#
# 用法:  ./build-all.sh [源码目录]
#   源码目录默认 ./localsend-main，不存在则自动 clone 对应 tag
set -euo pipefail

LOCALSEND_REF="${LOCALSEND_REF:-v1.19.0}"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.9}"
FLUTTER_DIR="${FLUTTER_DIR:-$HOME/flutter}"
SRC="${1:-$(cd "$(dirname "$0")" && pwd)/localsend-main}"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31m错误: %s\033[0m\n' "$*" >&2; exit 1; }

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) echo "提示: 当前架构是 $(uname -m)，本脚本针对 arm64 编写，继续可能失败。";;
esac

# ---------------------------------------------------------------- 1. 系统依赖
say "1/6 检查系统依赖"
missing=()
for c in clang cmake ninja pkg-config git curl unzip; do
  command -v "$c" >/dev/null || missing+=("$c")
done
pkg-config --exists gtk+-3.0 2>/dev/null || missing+=("libgtk-3-dev")
pkg-config --exists ayatana-appindicator3-0.1 2>/dev/null || missing+=("libayatana-appindicator3-dev")
if [ ${#missing[@]} -gt 0 ]; then
  echo "缺少: ${missing[*]}"
  echo "Debian/Ubuntu/麒麟系请先执行:"
  echo "  sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev libayatana-appindicator3-dev"
  die "系统依赖不全"
fi

# ---------------------------------------------------------------- 2. 源码
say "2/6 准备源码"
if [ ! -f "$SRC/pubspec.yaml" ]; then
  echo "未找到源码，clone $LOCALSEND_REF ..."
  git clone --depth 1 --branch "$LOCALSEND_REF" https://github.com/localsend/localsend.git "$SRC"
fi
cd "$SRC"

# Flutter Rust Bridge 版本必须与预生成的绑定一致，否则启动即报
# codegen version ... should be the same as runtime version
if grep -q 'flutter_rust_bridge: \^2.12.0' packages/localsend_isolates/pubspec.yaml 2>/dev/null; then
  sed -i 's/flutter_rust_bridge: \^2.12.0/flutter_rust_bridge: 2.12.0/' packages/localsend_isolates/pubspec.yaml
  echo "已把 flutter_rust_bridge 固定为 2.12.0（与 Rust crate 及生成的绑定对齐）"
fi

# ---------------------------------------------------------------- 3. Flutter
say "3/6 准备 Flutter $FLUTTER_VERSION（官方无 arm64 Linux 预编译包，从源码自举）"
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"
flutter config --no-analytics >/dev/null 2>&1 || true
flutter --version

# ---------------------------------------------------------------- 4. Rust
say "4/6 检查 Rust 工具链"
if ! command -v cargo >/dev/null; then
  echo "未找到 cargo，正在安装 rustup ..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
  # shellcheck disable=SC1091
  . "$HOME/.cargo/env"
fi
cargo --version

# ---------------------------------------------------------------- 5. 链接器
say "5/6 准备 clang 包装（规避部分发行版 clang 包不带 ld.lld）"
# Flutter 3.41 的 native assets 步骤会在 clang 所在目录找 ld.lld。
# 麒麟 V10 的 clang-10 包里没有它，这里用 binutils 的 ld 顶上。
# 注意：clang 必须是「副本」而不是软链，Flutter 会 realpath 解析软链。
SHIM="$HOME/.local/llvm-shim"
mkdir -p "$SHIM"
CLANG_REAL="$(readlink -f "$(command -v clang)")"
if [ ! -x "$SHIM/clang" ]; then
  cp "$CLANG_REAL" "$SHIM/clang"
  cp "$CLANG_REAL" "$SHIM/clang++"
fi
ln -sf "$(command -v ld)" "$SHIM/ld"
ln -sf "$(command -v ld)" "$SHIM/ld.lld"
for t in ar ranlib nm strip objcopy objdump; do
  command -v "$t" >/dev/null && ln -sf "$(command -v "$t")" "$SHIM/$t"
done
export PATH="$SHIM:$PATH"

# ---------------------------------------------------------------- 6. 构建
say "6/6 构建并打包"
flutter pub get
( cd app && flutter build linux --release )

./build-deb.sh "$SRC/app/build/linux/arm64/release/bundle" ./dist

say "完成"
ls -lh ./dist/*.deb

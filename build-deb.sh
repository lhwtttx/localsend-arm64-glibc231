#!/bin/bash
# 把 Flutter 的 linux release bundle 打成 deb 包
#
# 用法:
#   ./build-deb.sh [bundle目录] [输出目录]
# 默认:
#   bundle目录 = ../localsend-main/app/build/linux/arm64/release/bundle
#   输出目录   = ./dist
#
# 本脚本不需要 root：生成的包属主统一为 root:root，解包安装才需要 sudo。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-$HERE/../localsend-main/app/build/linux/arm64/release/bundle}"
OUT="${2:-$HERE/dist}"

PKG_NAME="localsend"
UPSTREAM_VERSION="1.19.0+65"          # 与 app/pubspec.yaml 的 version 一致
PKG_REVISION="1kylin1"                # 本机重建版的修订号
ARCH="arm64"
INSTALL_DIR="/opt/localsend_app"

[ -x "$SRC/localsend_app" ] || { echo "错误: $SRC 下没有 localsend_app，请先 flutter build linux --release"; exit 1; }

WORK="$(mktemp -d)"
STAGE="$WORK/${PKG_NAME}_${UPSTREAM_VERSION}-${PKG_REVISION}_${ARCH}"
trap 'rm -rf "$WORK"' EXIT

echo "==> 拷贝程序文件"
mkdir -p "$STAGE$INSTALL_DIR" "$STAGE/DEBIAN" \
         "$STAGE/usr/bin" \
         "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/icons/hicolor/128x128/apps" \
         "$STAGE/usr/share/icons/hicolor/256x256/apps" \
         "$STAGE/usr/share/icons/hicolor/512x512/apps"
cp -a "$SRC"/. "$STAGE$INSTALL_DIR"/

# 归一化权限：目录 755、文件 644、主程序 755（避免把家目录的 775 带进系统目录）
find "$STAGE$INSTALL_DIR" -type d -exec chmod 755 {} +
find "$STAGE$INSTALL_DIR" -type f -exec chmod 644 {} +
chmod 755 "$STAGE$INSTALL_DIR/localsend_app"

echo "==> 生成启动入口与桌面集成"
# 命令行入口：与官方 deb 保持一致，桌面文件可直接 Exec=localsend_app
ln -sf "$INSTALL_DIR/localsend_app" "$STAGE/usr/bin/localsend_app"

cat > "$STAGE/usr/share/applications/localsend_app.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=LocalSend
GenericName=An open source cross-platform alternative to AirDrop
Icon=localsend_app
Exec=localsend_app %U
Categories=GTK;FileTransfer;Utility;
Keywords=Sharing;LAN;Files;
StartupNotify=true
StartupWMClass=org.localsend.localsend_app
EOF

ASSETS="$STAGE$INSTALL_DIR/data/flutter_assets/assets/img"
cp "$ASSETS/logo-128.png" "$STAGE/usr/share/icons/hicolor/128x128/apps/localsend_app.png"
cp "$ASSETS/logo-256.png" "$STAGE/usr/share/icons/hicolor/256x256/apps/localsend_app.png"
cp "$ASSETS/logo-512.png" "$STAGE/usr/share/icons/hicolor/512x512/apps/localsend_app.png"

INSTALLED_SIZE="$(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)"

echo "==> 写 control (Installed-Size: ${INSTALLED_SIZE} KB)"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: ${UPSTREAM_VERSION}-${PKG_REVISION}
Section: net
Priority: optional
Architecture: $ARCH
Maintainer: LocalSend arm64 glibc2.31 rebuild <noreply@example.com>
Installed-Size: $INSTALLED_SIZE
Depends: libgtk-3-0, libayatana-appindicator3-1, libayatana-ido3-0.4-0, libdbusmenu-glib4, libegl1, libgles2, libstdc++6, xdg-user-dirs
Recommends: xdg-desktop-portal
Homepage: https://localsend.org/
Description: 局域网文件互传工具（arm64 / glibc 2.31 兼容重建版）
 LocalSend 是一个开源跨平台文件互传工具，可在同一局域网内的手机、电脑之间
 直接收发文件与文本，无需联网、无需账号。
 .
 本包在本机（glibc 2.31 的 arm64 Linux，如银河麒麟 V10）上从源码重新编译，
 二进制实际只需要 GLIBC 2.30，因此可在官方 deb（要求 GLIBC 2.34）无法运行的
 老系统上使用。
EOF

echo "==> 写维护脚本"
cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    # 刷新桌面数据库与图标缓存，失败不影响安装
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
EOF

cat > "$STAGE/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
fi
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

echo "==> 打包"
# 全局归一化权限（本机 umask 是 002，会把 775/664 带进系统目录）
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$STAGE$INSTALL_DIR/localsend_app" "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"
mkdir -p "$OUT"
DEB="$OUT/${PKG_NAME}_${UPSTREAM_VERSION}-${PKG_REVISION}_${ARCH}.deb"
dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$DEB" >/dev/null

echo "==> 完成: $DEB"
ls -lh "$DEB"

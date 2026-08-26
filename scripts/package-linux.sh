#!/usr/bin/env bash
#
# Package a standalone Qt executable build into a self-contained tarball:
# the binary, every non-system shared library it (and its Qt plugins)
# actually pull in, the Qt plugins themselves, and a launcher that points
# the loader at them before anything from the host system can interfere --
# the failure this exists for is a machine whose /usr Qt is older than the
# one the binary was built against.
#
# Excluded from the bundle, deliberately: the glibc family (must match the
# host kernel/loader, bundling it breaks rather than fixes things) and the
# graphics/display stack (GL/EGL/X11/xcb/wayland/drm/udev -- every desktop
# has these, and the host's matches the host's driver). Everything else,
# including libstdc++, OpenSSL and whatever compression libs Qt drags in,
# travels with us.
#
# Usage: package-linux.sh <path-to-executable> <output.tar.gz>
# Requires QT_ROOT_DIR to point at the Qt install the binary was built with.

set -euo pipefail

BIN="$(readlink -f "${1:?usage: package-linux.sh <executable> <out.tar.gz>}")"
OUT="${2:?usage: package-linux.sh <executable> <out.tar.gz>}"
APP="$(basename "$BIN")"
QT_ROOT_DIR="${QT_ROOT_DIR:?QT_ROOT_DIR must point at the Qt install}"

NAME="$(basename "$OUT" .tar.gz)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/$NAME/bin" "$STAGE/$NAME/lib" "$STAGE/$NAME/plugins"
cp "$BIN" "$STAGE/$NAME/bin/$APP"

# Qt plugins any real desktop session touches. xcbglintegrations is not
# optional: Quick renders through OpenGL, and under xcb the load goes
# through this plugin whether the code asks for it or not.
PLUGINS_SRC="$QT_ROOT_DIR/plugins"
for d in platforms platforminputcontexts platformthemes \
         imageformats iconengines styles tls xcbglintegrations \
         networkinformation; do
    [ -d "$PLUGINS_SRC/$d" ] && cp -r "$PLUGINS_SRC/$d" "$STAGE/$NAME/plugins/"
done

# Loader names that must resolve on the HOST, never from our lib/.
EXCLUDE_RE='^(linux-vdso|ld-linux|libc\.so|libm\.so|libpthread|librt\.so|libdl\.so|libresolv|libanl|libutil|libnsl|libGL|libEGL|libGLESv[12]|libOpenGL|libglx|libX11|libXext|libXrender|libXcursor|libXi|libXfixes|libXrandr|libXss|libXau|libXdmcp|libxcb|libxkbcommon-x11|libX11-xcb|libdrm|libgbm|libwayland|libudev|libsystemd)'

# Shared Qt resolves its QML modules (QtQuick, Controls, styles...) from
# <Qt>/qml at runtime -- without this the app dies on "module
# \"QtQuick.Controls\" plugin ... not found" even though it linked fine.
cp -r "$QT_ROOT_DIR/qml" "$STAGE/$NAME/qml"

# Walk the dependency closure to a fixpoint: start from the binary, every
# copied plugin AND every copied QML module plugin (they link Qt libs of
# their own -- missing one here is how the loader ends up mixing our 6.10
# with the system's 6.2 and dying on private symbols). Three passes over
# lib/ is more than the chain is ever deep; existence checks make extra
# passes free.
scan() {
    local obj="$1"
    # Resolution MUST prefer the Qt we built with: without this, a machine
    # that also has a system Qt sees ldd resolve a QML plugin's dependencies
    # onto /usr's older soname-identical libraries, and the bundle ships a
    # 6.2/6.10 mix that dies on private-symbol mismatches at first QML load.
    # (Found the hard way -- see the smoke test this was written beside.)
    LD_LIBRARY_PATH="$QT_ROOT_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    ldd "$obj" 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i ~ /^\//) {print $i; break}}' | while read -r dep; do
        [ -f "$dep" ] || continue
        base="$(basename "$dep")"
        [[ "$base" =~ $EXCLUDE_RE ]] && continue
        [ -f "$STAGE/$NAME/lib/$base" ] && continue
        cp -L "$dep" "$STAGE/$NAME/lib/$base"
    done
}

scan "$BIN"
find "$STAGE/$NAME/plugins" "$STAGE/$NAME/qml" -type f -name '*.so' | while read -r p; do scan "$p"; done
for _ in 1 2 3; do
    find "$STAGE/$NAME/lib" -type f | while read -r l; do scan "$l"; done
done

cat > "$STAGE/$NAME/bin/qt.conf" <<EOF
# Paths relative to this file's directory; Prefix points one level up.
[Paths]
Prefix=..
Plugins=plugins
Qml2Imports=qml
EOF

cat > "$STAGE/$NAME/run.sh" <<EOF
#!/bin/sh
# Self-contained launcher: bundled libs first, host system second.
HERE="\$(cd "\$(dirname "\$(readlink -f "\$0")")" && pwd)"
LD_LIBRARY_PATH="\$HERE/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "\$HERE/bin/$APP" "\$@"
EOF
chmod +x "$STAGE/$NAME/run.sh"

cp "$(dirname "$(readlink -f "$0")")/../README.md" "$STAGE/$NAME/" 2>/dev/null || true

tar -czf "$OUT" -C "$STAGE" "$NAME"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1)): $(find "$STAGE/$NAME/lib" -type f | wc -l) libs, $(find "$STAGE/$NAME/plugins" -type f | wc -l) plugin files"

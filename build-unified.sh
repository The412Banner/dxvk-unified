#!/usr/bin/env bash
# Builds DXVK (D3D8-11) + VKD3D-Proton (D3D12) into a single output directory.
# Usage: ./build-unified.sh <version> <destdir> [--no-package] [--dev-build] [--64-only] [--32-only]

set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 version destdir [--no-package] [--dev-build] [--64-only] [--32-only]"
  exit 1
fi

VERSION="$1"
DEST=$(realpath "$2")
UNIFIED_DIR="$DEST/dxvk-unified-$VERSION"
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

shift 2

opt_nopackage=0
opt_devbuild=0
opt_64_only=0
opt_32_only=0

while [ $# -gt 0 ]; do
  case "$1" in
    "--no-package") opt_nopackage=1 ;;
    "--dev-build")  opt_nopackage=1; opt_devbuild=1 ;;
    "--64-only")    opt_64_only=1 ;;
    "--32-only")    opt_32_only=1 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

DXVK_STAGE="$DEST/dxvk-stage-$VERSION"
VKD3D_STAGE="$DEST/vkd3d-stage-$VERSION"

# ── Build DXVK (D3D8/9/10/11 + DXGI) ────────────────────────────────────────
echo ">>> Building DXVK..."

DXVK_ARGS=(--no-package)
[ $opt_devbuild -eq 1 ] && DXVK_ARGS+=(--dev-build)
[ $opt_64_only  -eq 1 ] && DXVK_ARGS+=(--64-only)
[ $opt_32_only  -eq 1 ] && DXVK_ARGS+=(--32-only)

bash "$SCRIPT_DIR/package-release.sh" "$VERSION" "$DEST" "${DXVK_ARGS[@]}"
mv "$DEST/dxvk-$VERSION" "$DXVK_STAGE"

# ── Build VKD3D-Proton (D3D12) ────────────────────────────────────────────────
echo ">>> Building VKD3D-Proton..."

VKD3D_ARGS=(--no-package)
[ $opt_devbuild -eq 1 ] && VKD3D_ARGS+=(--dev-build)

bash "$SCRIPT_DIR/vkd3d-proton/package-release.sh" "$VERSION" "$DEST" "${VKD3D_ARGS[@]}"
mv "$DEST/vkd3d-proton-$VERSION" "$VKD3D_STAGE"

# ── Merge into unified output ─────────────────────────────────────────────────
echo ">>> Merging into $UNIFIED_DIR..."
mkdir -p "$UNIFIED_DIR"

for arch in x32 x64; do
  # skip arch if only-other was requested
  [ $opt_64_only -eq 1 ] && [ "$arch" = "x32" ] && continue
  [ $opt_32_only -eq 1 ] && [ "$arch" = "x64" ] && continue

  mkdir -p "$UNIFIED_DIR/$arch"

  # DXVK DLLs
  if [ -d "$DXVK_STAGE/$arch" ]; then
    cp "$DXVK_STAGE/$arch/"*.dll "$UNIFIED_DIR/$arch/" 2>/dev/null || true
  fi

  # VKD3D-Proton DLLs
  if [ -d "$VKD3D_STAGE/$arch" ]; then
    cp "$VKD3D_STAGE/$arch/"*.dll "$UNIFIED_DIR/$arch/" 2>/dev/null || true
  fi
done

# Setup script — chains both installers
cat > "$UNIFIED_DIR/setup_dxvk_unified.sh" << 'EOF'
#!/usr/bin/env bash
# Installs DXVK (D3D8-11) + VKD3D-Proton (D3D12) into a Wine prefix.
# Usage: ./setup_dxvk_unified.sh install|uninstall [--symlinks]

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

case "$1" in
  install|uninstall)
    ACTION="$1"
    ;;
  *)
    echo "Usage: $0 install|uninstall [--symlinks]"
    exit 1
    ;;
esac

SYMLINKS=""
[ "$2" = "--symlinks" ] && SYMLINKS="--symlinks"

# Resolve architecture from WINEARCH or running prefix
if [ -z "$WINEPREFIX" ]; then
  WINEPREFIX="$HOME/.wine"
fi

if [ "$(wine cmd /c echo %PROCESSOR_ARCHITECTURE% 2>/dev/null | tr -d '\r')" = "AMD64" ]; then
  ARCH="x64"
else
  ARCH="x32"
fi

SYS32="$WINEPREFIX/drive_c/windows/system32"
SYS32_NATIVE="$WINEPREFIX/drive_c/windows/syswow64"

function install_dll {
  local src="$1"
  local dest="$2"
  local name=$(basename "$src")

  if [ "$ACTION" = "install" ]; then
    if [ -n "$SYMLINKS" ]; then
      ln -sf "$src" "$dest/$name"
    else
      cp "$src" "$dest/$name"
    fi
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" \
      /v "${name%.dll}" /t REG_SZ /d native /f &>/dev/null || true
  else
    rm -f "$dest/$name"
    wine reg delete "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" \
      /v "${name%.dll}" /f &>/dev/null || true
  fi
}

for dll in "$SCRIPT_DIR/$ARCH/"*.dll; do
  install_dll "$dll" "$SYS32"
done

if [ "$ARCH" = "x64" ] && [ -d "$SCRIPT_DIR/x32" ]; then
  for dll in "$SCRIPT_DIR/x32/"*.dll; do
    install_dll "$dll" "$SYS32_NATIVE"
  done
fi

echo "dxvk-unified $ACTION complete."
EOF
chmod +x "$UNIFIED_DIR/setup_dxvk_unified.sh"

# Copy configs
cp "$SCRIPT_DIR/dxvk.conf"                        "$UNIFIED_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/VP_DXVK_requirements.json"         "$UNIFIED_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/vkd3d-proton/profiles/"*.json      "$UNIFIED_DIR/" 2>/dev/null || true

# Clean up staging dirs
rm -rf "$DXVK_STAGE" "$VKD3D_STAGE"

echo ""
echo "=== dxvk-unified $VERSION built ==="
echo "  D3D8/9/10/11 → Vulkan  (DXVK)"
echo "  D3D12        → Vulkan  (VKD3D-Proton)"
echo "  Output: $UNIFIED_DIR"

if [ $opt_nopackage -eq 0 ]; then
  tar -C "$DEST" -czf "$DEST/dxvk-unified-$VERSION.tar.gz" "dxvk-unified-$VERSION"
  echo "  Archive: $DEST/dxvk-unified-$VERSION.tar.gz"
fi

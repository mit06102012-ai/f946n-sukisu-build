#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${GITHUB_WORKSPACE:-$ROOT}/work"
ASSETS="$WORK/assets"
OUT="$WORK/out"
mkdir -p "$ASSETS" "$OUT"

need=(
  BASE_URL DTS_URL PATCH_URL TOOLCHAIN_URL
  BOOT_URL INIT_BOOT_URL TARGET LTO_MODE
)
for v in "${need[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "Missing env: $v" >&2
    exit 2
  fi
done

echo "[1/9] Download assets"
curl -L --fail --retry 3 -o "$ASSETS/base.zip" "$BASE_URL"
curl -L --fail --retry 3 -o "$ASSETS/dts.zip" "$DTS_URL"
curl -L --fail --retry 3 -o "$ASSETS/patch.zip" "$PATCH_URL"
curl -L --fail --retry 3 -o "$ASSETS/toolchain.tar.gz" "$TOOLCHAIN_URL"
curl -L --fail --retry 3 -o "$ASSETS/boot_stock.img" "$BOOT_URL"
curl -L --fail --retry 3 -o "$ASSETS/init_boot_stock.img" "$INIT_BOOT_URL"

echo "[2/9] Extract source"
rm -rf "$WORK/Kernel"
mkdir -p "$WORK/Kernel"
unzip -p "$ASSETS/base.zip" Kernel.tar.gz | tar -xzf - -C "$WORK/Kernel"
unzip -p "$ASSETS/dts.zip" '*.tar.gz' | tar -xzf - -C "$WORK"
unzip -p "$ASSETS/patch.zip" '*.tar.gz' | tar -xzf - -C "$WORK"

echo "[3/9] Extract toolchain"
mkdir -p "$WORK/Kernel/kernel_platform"
if tar -tzf "$ASSETS/toolchain.tar.gz" | head -20 | grep -q '^prebuilts/'; then
  tar -xzf "$ASSETS/toolchain.tar.gz" -C "$WORK/Kernel/kernel_platform"
else
  mkdir -p "$WORK/Kernel/kernel_platform/prebuilts/clang/host/linux-x86/clang-r450784e"
  tar -xzf "$ASSETS/toolchain.tar.gz" \
    -C "$WORK/Kernel/kernel_platform/prebuilts/clang/host/linux-x86/clang-r450784e"
fi
CLANG_BIN="$(find "$WORK/Kernel/kernel_platform" -type f -path '*/clang-r450784e/bin/clang' | head -1 || true)"
if [ -z "$CLANG_BIN" ]; then
  CLANG_BIN="$(find "$WORK/Kernel/kernel_platform" -type f -name clang -path '*/bin/clang' | head -1 || true)"
fi
if [ -z "$CLANG_BIN" ]; then
  echo "clang not found in toolchain" >&2
  exit 3
fi
export PATH="$(dirname "$CLANG_BIN"):/usr/bin:/bin:/usr/sbin:/sbin"

# Host tool fallbacks for a clang-only toolchain.
BT="$WORK/Kernel/kernel_platform/build/kernel/build-tools/path/linux-x86"
if [ -d "$BT" ]; then
  chmod u+w "$BT/bison" "$BT/flex" 2>/dev/null || true
  rm -f "$BT/bison" "$BT/flex"
  ln -s /usr/bin/bison "$BT/bison"
  ln -s /usr/bin/flex "$BT/flex"
fi

# Samsung build expects exact NDK prebuilts; blank it when only clang is present.
for cfg in \
  "$WORK/Kernel/kernel_platform/common/build.config.aarch64" \
  "$WORK/Kernel/kernel_platform/msm-kernel/build.config.aarch64"; do
  [ -f "$cfg" ] || continue
  chmod u+w "$cfg"
  sed -i 's/^NDK_TRIPLE=.*/NDK_TRIPLE=/' "$cfg"
done

echo "[4/9] KernelSU Next Samsung KDP source"
rm -rf "$WORK/kdp"
git clone --depth=1 https://github.com/250965249/KernelSU-Next-Samsung.git "$WORK/kdp"

echo "[5/9] Integrate KDP module"
cd "$WORK/Kernel/kernel_platform/common"
rm -rf drivers/kernelsu
cp -a "$WORK/kdp/kernel" drivers/kernelsu
chmod -R u+w drivers/kernelsu drivers/Makefile drivers/Kconfig
grep -q 'kernelsu' drivers/Makefile || echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig || echo 'source "drivers/kernelsu/Kconfig"' >> drivers/Kconfig

chmod u+w arch/arm64/configs/gki_defconfig
sed -i '/^CONFIG_LOCALVERSION=/d' arch/arm64/configs/gki_defconfig
sed -i '/^# CONFIG_LOCALVERSION_AUTO/d' arch/arm64/configs/gki_defconfig
cat >> arch/arm64/configs/gki_defconfig <<'EOF'
CONFIG_KSU=m
CONFIG_KSU_SAMSUNG_KDP=y
CONFIG_KSU_SAMSUNG_RKP=y
CONFIG_KSU_SAMSUNG_DEFEX=y
CONFIG_KALLSYMS_ALL=y
EOF

# Exact Samsung localversion suffix for boot/vendor modules
chmod u+w scripts/setlocalversion
cat > scripts/setlocalversion <<'EOF'
#!/bin/sh
printf '%s\n' '-29539737-abF946NKSS5DYBD'
EOF
chmod +x scripts/setlocalversion

echo "[6/9] Build"
cd "$WORK/Kernel"
sed -i "s/^BUILD_TARGET=.*/BUILD_TARGET=${TARGET}/" build_kernel_GKI.sh
export HERMETIC_TOOLCHAIN=0
export LTO="$LTO_MODE"
export PATH="$PATH"
mkdir -p out/target/product/q5q
mkdir -p out/target/product/q5q
chmod u+x build_kernel_GKI.sh
set +e
printf 'y\n' | ./build_kernel_GKI.sh
BUILD_RC=$?
set -e
if [ "$BUILD_RC" -ne 0 ]; then
  echo "build.sh returned $BUILD_RC; checking for Image anyway" >&2
fi
IMG="$WORK/Kernel/out/msm-kalama-kalama-gki/gki_kernel/common/arch/arm64/boot/Image"
if [ ! -f "$IMG" ]; then
  echo "Image not found: $IMG" >&2
  find "$WORK/Kernel/out" -name Image -print >&2
  exit 4
fi
echo "kernel release: $(cat "$(dirname "$IMG")/../../../../../include/config/kernel.release" 2>/dev/null || true)"

KO="$(find "$WORK/Kernel/out" -name kernelsu.ko -print -quit)"
if [ -z "$KO" ]; then
  echo "kernelsu.ko not found" >&2
  find "$WORK/Kernel/out" -name '*.ko' >&2 | head -20
  exit 5
fi
cp "$KO" "$OUT/kernelsu.ko"
echo "module: $KO"
modinfo "$OUT/kernelsu.ko" | grep -E 'vermagic|name' || true

echo "[7/9] Pack boot.img"
MKBOOT="$WORK/Kernel/kernel_platform/tools/mkbootimg/mkbootimg.py"
python3 "$MKBOOT" \
  --kernel "$IMG" \
  --ramdisk /dev/null \
  --header_version 4 --pagesize 4096 \
  --os_version 13.0.0 --os_patch_level 2025-03 \
  -o "$OUT/boot.img"

cp "$ASSETS/init_boot_stock.img" "$OUT/init_boot.img"
tar -cf "$OUT/F946N_sukisu_boot.tar" -C "$OUT" boot.img init_boot.img

echo "[8/9] vbmeta disabled (optional; no Samsung key)"
AVBTOOL="$WORK/avbtool"
if [ ! -f "$AVBTOOL" ]; then
  if curl -LSs "https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool?format=TEXT" \
      | base64 -d > "$AVBTOOL" 2>/dev/null; then
    chmod +x "$AVBTOOL"
  else
    rm -f "$AVBTOOL"
    echo "WARNING: avbtool download failed; skipping vbmeta" >&2
  fi
fi
if [ -f "$AVBTOOL" ]; then
  python3 "$AVBTOOL" make_vbmeta_image --flags 2 --output "$OUT/F946N_sukisu_vbmeta_disabled.img" || true
fi

echo "[9/9] Artifacts"
cp "$OUT/init_boot.img" "$OUT/F946N_sukisu_init_boot_patched.img"
ls -lh "$OUT"

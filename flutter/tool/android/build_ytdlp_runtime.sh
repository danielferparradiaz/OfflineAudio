#!/usr/bin/env bash
# Construye el runtime autocontenido de yt-dlp para Android:
#   OfflineAudio-ytdlp-<abi>.zip  con  ytdlp  +  prefix/lib/...
#
# Contenido del zip (el motor lo extrae tal cual en <bin_dir>/ytdlp):
#   ytdlp/                      <- launcher (flutter/tool/android/ytdlp_stub.c)
#   prefix/lib/libpython3.X.so, *_python.so, python3.X/ (stdlib + lib-dynload)
#   prefix/lib/python3.X/site-packages/{yt_dlp,certifi}/
#
# No existe build oficial de yt-dlp para Android (bionic), así que el bundle
# junta el CPython embeddable oficial de python.org (solo libpython + stdlib,
# sin ejecutable) con el wheel de yt-dlp de PyPI. Validado en emulador
# arm64-v8a (API 35): --version, --dump-json, streaming a stdout y exit codes.
#
# Uso:
#   build_ytdlp_runtime.sh <arm64-v8a|x86_64> [out_dir]
#
# Env (con defaults pineados para reproducibilidad):
#   PYTHON_VERSION (3.14.7)  — embeddable de https://www.python.org/ftp/python
#   YTDLP_VERSION  (2026.8.19)
#   CERTIFI_VERSION (2026.7.22)
#   NDK_VERSION    (28.2.13676358) — también vale ANDROID_NDK_ROOT ya instalado
#   MIN_API        (24)
set -euo pipefail

ABI="${1:?uso: $0 <arm64-v8a|x86_64> [out_dir]}"
OUT_DIR="${2:-dist}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Versiones pineadas en un solo sitio (ver runtime_versions.env). Se pueden
# sobreescribir por env para probar un bump sin tocar el fichero.
# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/runtime_versions.env" ] && . "$SCRIPT_DIR/runtime_versions.env"
PYTHON_VERSION="${PYTHON_VERSION:-3.14.7}"
YTDLP_VERSION="${YTDLP_VERSION:-2026.8.19}"
CERTIFI_VERSION="${CERTIFI_VERSION:-2026.7.22}"
NDK_VERSION="${NDK_VERSION:-28.2.13676358}"
MIN_API="${MIN_API:-24}"

case "$ABI" in
  arm64-v8a) TRIPLE="aarch64-linux-android"; PY_TAG="aarch64-linux-android" ;;
  x86_64)    TRIPLE="x86_64-linux-android";  PY_TAG="x86_64-linux-android" ;;
  *) echo "ABI no soportada: $ABI (solo arm64-v8a y x86_64; python.org no publica CPython de 32 bits para Android)" >&2; exit 1 ;;
esac
PY_MM="${PYTHON_VERSION%.*}"   # 3.14

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
STUB="$REPO_ROOT/flutter/tool/android/ytdlp_stub.c"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- NDK ---------------------------------------------------------------
find_ndk() {
  for c in "${ANDROID_NDK_ROOT:-}" \
           "${ANDROID_HOME:-$HOME/Library/Android/sdk}/ndk/$NDK_VERSION" \
           "$HOME/Library/Android/sdk/ndk/$NDK_VERSION" \
           /usr/local/lib/android/sdk/ndk/"$NDK_VERSION" \
           /opt/android-sdk/ndk/"$NDK_VERSION"; do
    [ -n "$c" ] && [ -x "$c/toolchains/llvm/prebuilt/linux-x86_64/bin/${TRIPLE}${MIN_API}-clang" ] && { echo "$c/toolchains/llvm/prebuilt/linux-x86_64/bin"; return; }
    [ -n "$c" ] && [ -x "$c/toolchains/llvm/prebuilt/darwin-x86_64/bin/${TRIPLE}${MIN_API}-clang" ] && { echo "$c/toolchains/llvm/prebuilt/darwin-x86_64/bin"; return; }
  done
  return 1
}
NDKBIN="$(find_ndk)" || { echo "NDK no encontrado (ANDROID_NDK_ROOT o ndk;$NDK_VERSION bajo ANDROID_HOME)" >&2; exit 1; }
CC="$NDKBIN/${TRIPLE}${MIN_API}-clang"
echo "CC=$CC"

# --- CPython embeddable (python.org) ------------------------------------
PY_TGZ="python-$PYTHON_VERSION-$PY_TAG.tar.gz"
curl -sSL --fail --retry 3 --retry-all-errors \
  -o "$WORK/$PY_TGZ" "https://www.python.org/ftp/python/$PYTHON_VERSION/$PY_TGZ"
mkdir -p "$WORK/root" "$WORK/pyex"
# El tarball trae todo bajo `./prefix/` (+ README/android-env en la raíz).
tar -xzf "$WORK/$PY_TGZ" -C "$WORK/pyex"
mv "$WORK/pyex/prefix" "$WORK/root/prefix"
[ -f "$WORK/root/prefix/lib/libpython$PY_MM.so" ] || { echo "el embeddable no trae libpython$PY_MM.so" >&2; exit 1; }

# --- wheels yt-dlp + certifi (PyPI) -------------------------------------
python3 -m pip download --no-deps --dest "$WORK/wheels" \
  "yt-dlp==$YTDLP_VERSION" "certifi==$CERTIFI_VERSION" -q
SP="$WORK/root/prefix/lib/python$PY_MM/site-packages"
mkdir -p "$SP"
for whl in "$WORK"/wheels/*.whl; do
  python3 - "$whl" "$SP" <<'EOF'
import sys, zipfile
whl, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(whl) as z:
    tops = {n.split('/')[0] for n in z.namelist() if '/' in n}
    want = {t for t in tops if t in ('yt_dlp', 'certifi')}
    assert want, f"wheel sin yt_dlp/certifi: {whl}"
    for n in z.namelist():
        if n.split('/')[0] in want:
            z.extract(n, dest)
EOF
done
[ -f "$SP/yt_dlp/__main__.py" ] || { echo "yt_dlp no extraído" >&2; exit 1; }

# --- launcher (compila ANTES del recorte: necesita los headers) ------------
# PY_VER sale de PYTHON_VERSION (un solo source of truth): si se bumpe a
# 3.15 el stub sigue compilando sin editar el .c a mano.
"$CC" -O2 -Wno-comment -DPY_VER="\"$PY_MM\"" \
  -I"$WORK/root/prefix/include/python$PY_MM" \
  "$STUB" -L"$WORK/root/prefix/lib" -lpython"$PY_MM" -ldl -llog -lm \
  -Wl,-rpath,'$ORIGIN/prefix/lib' \
  -o "$WORK/root/ytdlp"

# --- recorte (el embeddable trae headers y tests que no viajan) ----------
rm -rf "$WORK/root/prefix/include" \
       "$WORK/root/prefix/lib/pkgconfig" \
       "$WORK/root/prefix/lib/python$PY_MM/test"
find "$WORK/root/prefix" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

# --- zip ------------------------------------------------------------------
mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/OfflineAudio-ytdlp-$ABI.zip"
rm -f "$ZIP"
(cd "$WORK/root" && zip -X -9 -qr "$ZIP" ytdlp prefix)

# --- smoke checks -----------------------------------------------------------
echo "--- contenido (raíz) ---"
# Nota pipefail: `grep -q` sobre un pipe cierra antes de tiempo y el
# escritor muere por SIGPIPE (falso negativo). El listado va a fichero y el
# grep lee del fichero: sin pipe no hay SIGPIPE.
unzip -l "$ZIP" > "$WORK/ziplist.txt"
awk '{print $4}' "$WORK/ziplist.txt" | grep -v '^$' | awk -F/ '{print $1}' | sort -u
for need in ' ytdlp$' 'prefix/lib/libpython' 'site-packages/yt_dlp/__main__.py' 'site-packages/certifi/'; do
  grep -q "$need" "$WORK/ziplist.txt" || { echo "FALTA en el zip: $need" >&2; exit 1; }
done
# La versión empaquetada debe ser exactamente la pineada: si PyPI resolvió
# otra (o el wheel vino corrupto), el fallo sale aquí, no en el móvil.
GOT_YTDLP="$(python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); n=[x for x in z.namelist() if x.endswith('yt_dlp/version.py')][0]; print(z.read(n).decode())" "$ZIP" | grep -oE '[0-9]{4}\.[0-9]+\.[0-9]+' | head -n1)"
[ "$GOT_YTDLP" = "$YTDLP_VERSION" ] || { echo "yt-dlp en zip ($GOT_YTDLP) != pineado ($YTDLP_VERSION)" >&2; exit 1; }
if command -v llvm-readelf >/dev/null; then READELF=llvm-readelf;
elif [ -x "$NDKBIN/llvm-readelf" ]; then READELF="$NDKBIN/llvm-readelf";
else READELF=""; fi
if [ -n "$READELF" ]; then
  "$READELF" -d "$WORK/root/ytdlp" | grep -q 'libpython'"$PY_MM"'.so' \
    || { echo "el launcher no enlaza libpython$PY_MM" >&2; exit 1; }
fi
echo "OK: $ZIP ($(du -h "$ZIP" | cut -f1))"

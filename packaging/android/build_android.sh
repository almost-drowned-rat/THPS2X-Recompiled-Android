#!/usr/bin/env bash
# build_android.sh - THPS 2X Recompiled for Android: the APK on the toolkit's templates/android (2026-11-24; the
# steps of Panzer Dragoon Orta's tools/build_android.sh, made for the template). The APK carries no game code: at
# the first start the player picks the disc image, the toolkit launcher lifts it with the embedded CPython, compiles
# and links libTHPS2X_game.so with clang / lld on the device, and the template's loader dlopen()s it.
#
#   packaging/android/build_android.sh [--release]
#
# Paths (environment; nothing of it is ever committed):
#   THPS_ANDROID_DEPS  build tools, each with SOURCE.txt: jdk-21/unpacked/*, gradle-9.9.1/unpacked/*, sdk/ (platforms;
#                      android-36, build-tools;36.0.0, ndk;30.0.16248370), python-3.15.2-android/unpacked/prefix,
#                      capstone-5.0.9/unpacked/* (the Python binding), src/SDL3 (release-3.4.18), src/libadrenotools
#   THPS_ANDROID_B     the toolkit's prebuilt Android parts (its tools/android scripts): device_toolchain/, xr_glslang/,
#                      device_tests/
#   THPS_ANDROID_SDK   the runtime SDK (make_runtime_sdk: the toolkit at THPS's pin, no APU / USB LLE)
#   THPS_CAPSTONE_SO   libcapstone.so for arm64
#   THPS_PRIVATE       the private output root (never the repo); the build goes to $THPS_PRIVATE/build
#   XBOXRECOMP_DIR     the toolkit checkout (option-c at THPS's pin; its templates/android is the APK project)
#   THPS_RELEASE_NAME  the release stamp (tools/release.txt; a new one makes the device build the game again)
#   THPS_VERSION_CODE, THPS_VERSION_NAME   the APK's version
#   THPS_RELEASE_KEY   --release only: the keystore (alias "thps2x") and <key>.pass beside it - never in a repo
set -euo pipefail

task=assembleDebug
[ "${1:-}" = "--release" ] && task=assembleRelease

repo=$(cd "$(dirname "$0")/../.." && pwd)
pk=$repo/packaging/android
deps=${THPS_ANDROID_DEPS:?THPS_ANDROID_DEPS = the build tools folder}
andb=${THPS_ANDROID_B:?THPS_ANDROID_B = the prebuilt Android parts of the toolkit}
rsdk=${THPS_ANDROID_SDK:?THPS_ANDROID_SDK = the runtime SDK folder}
csso=${THPS_CAPSTONE_SO:?THPS_CAPSTONE_SO = libcapstone.so for arm64}
priv=${THPS_PRIVATE:?THPS_PRIVATE = the private output root}
tk=${XBOXRECOMP_DIR:?XBOXRECOMP_DIR = the toolkit checkout}
vcode=${THPS_VERSION_CODE:-1}
vname=${THPS_VERSION_NAME:-2.0.0-dev}

die() { echo "build_android: $*" >&2; exit 1; }
first_dir() { local d; for d in "$1"/*/; do [ -d "$d" ] && { echo "${d%/}"; return; }; done; }
jdk=$(first_dir "$deps/jdk-21/unpacked")
gradle=$(first_dir "$deps/gradle-9.9.1/unpacked")
sdk=$deps/sdk
ndk=$sdk/ndk/30.0.16248370
py=$deps/python-3.15.2-android/unpacked/prefix
csbind=$(first_dir "$deps/capstone-5.0.9/unpacked")/bindings/python/capstone
sdl3=$deps/src/SDL3
adreno=$deps/src/libadrenotools
tmpl=$tk/templates/android
for p in "$jdk" "$gradle" "$ndk" "$sdk/platforms/android-36" "$py/lib/libpython3.15.so" "$csbind/__init__.py" \
         "$sdl3/android-project" "$adreno/CMakeLists.txt" "$tk/src/launcher/launcher.c" \
         "$tmpl/app/src/main/java/xboxrecomp/port/VistaSetupView.java" "$csso"; do
    [ -n "$p" ] && [ -e "$p" ] || die "missing: ${p:-a tool folder under $deps}"
done
for f in compile_flags.txt link_line.txt sdk.txt; do [ -f "$rsdk/$f" ] || die "runtime SDK incomplete ($rsdk/$f)"; done

out=$priv/build
mkdir -p "$out"
export JAVA_HOME=$jdk ANDROID_HOME=$sdk ANDROID_SDK_ROOT=$sdk
export GRADLE_USER_HOME=$deps/gradle-home ANDROID_USER_HOME=$deps/user-home
echo "build_android: $task (NDK $(basename "$ndk"), template $tmpl)"

# prebuilt runtime libs: libxr_glslang.so (+ its device test) -> nativeLibraryDir. No APU module: THPS 2X uses the
# DirectSound HLE (no MCPX APU emulation, nothing in runtime/)
pre=$out/prebuilt/arm64-v8a
rm -rf "$out/prebuilt"; mkdir -p "$pre"
cp -f "$andb/xr_glslang/libxr_glslang.so" "$pre/libxr_glslang.so"
[ -f "$andb/xr_glslang/xr_glslang_link_test" ] && cp -f "$andb/xr_glslang/xr_glslang_link_test" "$pre/libxr_glslang_test.so"

# the embedded CPython: libpython as a jniLib, the stdlib + the lifter as assets
cp -f "$py/lib/libpython3.15.so" "$pre/libpython3.15.so"
assets=$out/assets
rm -rf "$assets"
std=$assets/python/lib/python3.15
mkdir -p "$std"
skip=" test idlelib tkinter turtledemo ensurepip pydoc_data __phello__ lib2to3 venv sqlite3 curses dbm wsgiref xmlrpc unittest site-packages config-3.15-aarch64-linux-android "
for e in "$py/lib/python3.15"/*; do
    n=$(basename "$e")
    case "$skip" in *" $n "*) continue ;; esac
    cp -a "$e" "$std/"
done
find "$std" -type d -name __pycache__ -prune -exec rm -rf {} +
rm -f "$std"/lib-dynload/_test* "$std"/lib-dynload/xx*
sp=$std/site-packages
mkdir -p "$sp"
# capstone 5.0.9: the pure-Python binding from the same source as libcapstone.so (no debug info shipped)
cp -a "$csbind" "$sp/capstone"
find "$sp/capstone" -type d -name __pycache__ -prune -exec rm -rf {} +
rm -rf "$sp/capstone/lib"; mkdir -p "$sp/capstone/lib"
cp "$csso" "$sp/capstone/lib/libcapstone.so"
"$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" --strip-debug "$sp/capstone/lib/libcapstone.so"
printf '../../../../tools/lifter\n' > "$sp/xr_lifter.pth"

# the on-device compiler (the toolkit's make_device_toolchain): clang + ld.lld as lib*_exe.so, sysroot + resource dir
dtc=$andb/device_toolchain
toolsA=$assets/tools
mkdir -p "$toolsA/toolchain"
cp -f "$dtc/bin/clang" "$pre/libclang_exe.so"
cp -f "$dtc/bin/ld.lld" "$pre/liblld_exe.so"
cp -a "$dtc/sysroot" "$dtc/lib" "$dtc/LICENSES" "$toolsA/toolchain/"

# the lifter (the toolkit's tools/ packages + templates/runtime) and THPS's own lift inputs (tools/lift.txt's
# {TOOLS}/lifter/port: hooks + seeds, the same files as on Windows / Linux)
lifA=$toolsA/lifter
mkdir -p "$lifA/tools" "$lifA/port/seeds"
for f in __init__.py gameconfig.py variant_prefix.py; do cp "$tk/tools/$f" "$lifA/tools/$f"; done
for m in xbe_parser disasm func_id abi_analysis recomp ghidra_naming; do cp -a "$tk/tools/$m" "$lifA/tools/$m"; done
find "$lifA/tools" -type d \( -name __pycache__ -o -name tests \) -prune -exec rm -rf {} +
find "$lifA/tools" -name 'test_*.py' -delete
mkdir -p "$lifA/templates"; cp -a "$tk/templates/runtime" "$lifA/templates/runtime"
cp "$repo/config/hooks.toml" "$lifA/port/hooks.toml"
cp "$repo"/seeds/*_seeds.json "$lifA/port/seeds/"
tr -d '\r' < "$repo/tools/lift.txt" > "$toolsA/lift.txt"

# the port's sources (compiled on the device) and the runtime SDK
portSrc="main.c recomp_manual.c input.c settings.c soundtracks.c vk_check.c platform/host_linux.c"
mkdir -p "$toolsA/src/platform"
for f in $portSrc input.h settings.h vk_check.h platform/host.h; do cp "$repo/src/$f" "$toolsA/src/$f"; done
sdkA=$toolsA/sdk
mkdir -p "$sdkA/build" "$sdkA/extra/xbox" "$sdkA/lib"
cp -a "$rsdk/include" "$sdkA/include"
cp -a "$rsdk/lib/." "$sdkA/lib/"
cp "$rsdk/sdk.txt" "$sdkA/sdk.txt"
cp "$tk/include/xbox/xboxrecomp.h" "$sdkA/extra/xbox/xboxrecomp.h"
{ printf '/* generated from assets/icon_64.bmp (packaging/android/build_android.sh) */\nstatic const unsigned char g_port_icon_bmp[] = {'
  od -An -v -tx1 "$repo/assets/icon_64.bmp" | tr -s ' \n' ' ' | sed 's/^ //; s/ $//; s/\([0-9a-f][0-9a-f]\)/0x\1,/g; s/ //g'
  printf '};\n'; } > "$sdkA/build/port_icon.h"

# build.txt: compile + link from the SDK's lines; the game's Vulkan = the template's libvulkan_port.so (the system
# driver or Turnip), never -lvulkan
sysr='{TOOLS}/toolchain/sysroot'
drv=(--driver-mode=gcc --target=aarch64-linux-android29 "--sysroot=$sysr" '-resource-dir={TOOLS}/toolchain/lib/clang/23')
subst() { sed -e 's|\$SDK|{TOOLS}/sdk|g' -e "s|\\\$SYSROOT|$sysr|g" "$1" | tr -s ' \t\r\n' '\n' | sed '/^$/d'; }
mapfile -t sdkFlags < <(subst "$rsdk/compile_flags.txt" | grep -v -e '^--target=' -e '^--sysroot=')
cc=("${drv[@]}" -O2 -std=gnu11 "${sdkFlags[@]}" '-I{TOOLS}/src' '-I{GEN}' '-I{TOOLS}/sdk/build' '-I{TOOLS}/sdk/extra'
    -DTHPS_VULKAN=1 -DNOMINMAX -DWIN32_LEAN_AND_MEAN -D_GNU_SOURCE -w)
mapfile -t lline < <(subst "$rsdk/link_line.txt" | sed 's|^-lvulkan$|{NATIVE}/libvulkan_port.so|')
link=("${drv[@]}" -shared '--ld-path={NATIVE}/libld_exe.so' -Wl,--no-undefined -Wl,-z,max-page-size=16384
      -Wl,--export-dynamic -Wl,-soname,libTHPS2X_game.so "${lline[@]}" -llog)
join_tab() { local IFS=$'\t'; echo "$*"; }
{
    echo "# compile + link (packaging/android/build_android.sh, from the runtime SDK's lines): cc, src / gen, link"
    join_tab cc "${cc[@]}"
    for f in $portSrc; do printf 'src\t{TOOLS}/src/%s\n' "$f"; done
    printf 'gen\t*.c\n'
    join_tab link "${link[@]}"
} > "$toolsA/build.txt"
printf 'format\t2\nclang\t{NATIVE}/libclang_exe.so\npython\t{NATIVE}/libpython_exe.so\n' > "$toolsA/toolchain.txt"
rel=${THPS_RELEASE_NAME:-android-dev-$(git -C "$repo" rev-parse --short HEAD)}
echo "$rel" > "$toolsA/release.txt"
for t in libmmio_decode_a64_exe.so libmmio_trap_exe.so libcompat_bionic_exe.so libhost_stack_dump_exe.so; do
    [ -f "$andb/device_tests/$t" ] && cp -f "$andb/device_tests/$t" "$pre/$t"
done

# licence texts of everything the APK ships (BACK > Settings > About and licences). No Turnip driver is shipped.
licA=$assets/licenses
mkdir -p "$licA"
lic() { [ -f "$2" ] || die "licence text missing: $2"; cp "$2" "$licA/$1"; }
lic THPS2X-Recompiled_GPL-3.0.txt "$repo/LICENSE"
lic xboxrecomp_MIT.txt "$tk/LICENSE"
lic xboxrecomp_NOTICE.txt "$tk/NOTICE"
lic xemu-parts_LGPL-2.1.txt "$tk/LICENSES/LGPL-2.1.txt"
lic SMAA_MIT.txt "$tk/src/nv2a_vk/third_party/smaa/LICENSE.txt"
lic miniz_MIT.txt "$tk/src/shaderpack/third_party/miniz/LICENSE"
lic pl_mpeg_MIT.txt "$tk/src/bootvideo/third_party/pl_mpeg/LICENSE"
lic SDL3_zlib.txt "$sdl3/LICENSE.txt"
lic CPython_PSF.txt "$py/lib/python3.15/LICENSE.txt"
lic capstone_BSD-3.txt "$(dirname "$csbind")/../../LICENSE.TXT"
lic capstone_LLVM-parts.txt "$(dirname "$csbind")/../../LICENSE_LLVM.TXT"
lic libadrenotools_BSD-2.txt "$adreno/LICENSE"
lic linkernsbypass.txt "$adreno/lib/linkernsbypass/LICENSE"
lic glslang.txt "$deps/src/glslang-LICENSE.txt"
for f in "$dtc"/LICENSES/*; do [ -f "$f" ] && lic "toolchain_$(basename "$f")" "$f"; done
cat > "$licA/README.txt" <<'LICEOF'
THPS 2X Recompiled - Android: the licences of everything inside this app

THPS 2X Recompiled (this app's own code)  GPL-3.0-or-later   github.com/almost-drowned-rat/THPS2X-Recompiled-Android
xboxrecomp toolkit (option-c)           MIT, parts from xemu under LGPL-2.1-or-later (NOTICE lists them)
                                        github.com/almost-drowned-rat/xboxrecomp-option-c
  in it: SMAA (MIT), miniz (MIT), pl_mpeg (MIT, the boot animation)
SDL3                                    zlib               github.com/libsdl-org/SDL
CPython 3.15 (embedded, for the lift)   PSF License        python.org
capstone 5.0.9                          BSD-3-Clause (+ LLVM-derived parts)   github.com/capstone-engine/capstone
libadrenotools + linkernsbypass         BSD-2-Clause       github.com/bylaws/libadrenotools
glslang                                 BSD / MIT / Apache-2.0 (see glslang.txt)   github.com/KhronosGroup/glslang
LLVM clang + lld (the on-device compiler)  Apache-2.0 WITH LLVM-exception   github.com/llvm/llvm-project
Android NDK sysroot pieces              see toolchain_NDK-NOTICE.txt

No game data, no game code and no keys are part of this app: the game is built on the device from the player's own
disc. A Turnip driver (Mesa, MIT) is never shipped - the player chooses one.
Tony Hawk's Pro Skater is a trademark of Activision; this project is not affiliated with Activision or Microsoft.
LICEOF
echo "build_android: assets $(du -sm "$assets" | cut -f1) MB ($rel)"

# the port folder for the template: port_android.h + the generated port_icon.h
portDir=$out/port
rm -rf "$portDir"; mkdir -p "$portDir"
cp "$pk/port_android.h" "$portDir/"; cp "$sdkA/build/port_icon.h" "$portDir/"

sign=()
if [ "$task" = assembleRelease ]; then
    key=${THPS_RELEASE_KEY:-$deps/keys/thps2x-release.jks}
    [ -f "$key" ] && [ -f "${key%.jks}.pass" ] || die "release key or its password file missing: $key"
    sign=("-PreleaseStore=$key" "-PreleasePassFile=${key%.jks}.pass")
fi
"$gradle/bin/gradle" -p "$tmpl" --no-daemon --console=plain --project-cache-dir "$out/gradle-cache" \
    "-PappId=io.github.almostdrownedrat.thps2x" "-PappName=THPS 2X Recomp" "-PportTitle=THPS 2X Recomp" \
    "-PsavesPrefix=THPS2X" "-PtouchName=THPS 2X touch controls" "-PsetupGame=THPS 2X" "-PsetupDisc=THPS 2X (USA)" \
    "-PversionCode=$vcode" "-PversionName=$vname" "-PkeyAlias=thps2x" "-PportDir=$portDir" "-PportRes=$pk/res" \
    "-Psdl3Src=$sdl3" "-PndkPath=$ndk" "-PoutDir=$out" "-PprebuiltLibs=$out/prebuilt" "-PassetsDir=$assets" \
    "-PpythonPrefix=$py" "-Ptoolkit=$tk" "-PadrenotoolsSrc=$adreno" "${sign[@]}" "$task"
apk=$(find "$out" -name '*.apk' -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
[ -n "$apk" ] || die "no APK found"
echo "APK: $apk ($(du -m "$apk" | cut -f1) MB)"

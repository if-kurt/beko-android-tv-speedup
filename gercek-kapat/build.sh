#!/bin/sh
# Builds gercek-kapat.apk without Gradle.
# Needs (Ubuntu/Debian): android-sdk-platform-23 aapt dalvik-exchange zipalign apksigner, plus a JDK.
#   sudo apt install android-sdk-platform-23 aapt dalvik-exchange zipalign apksigner default-jdk
# Signing: put release.jks next to this script and its password in KS_PASS (see README).
set -eu
cd "$(dirname "$0")"

ANDROID_JAR=${ANDROID_JAR:-/usr/lib/android-sdk/platforms/android-23/android.jar}
VERSION=$(sed -n 's/.*android:versionName="\([^"]*\)".*/\1/p' AndroidManifest.xml)
OUT=build
rm -rf "$OUT"
mkdir -p "$OUT/classes"

# Java 8 bytecode so dx can read it; compiled against the Android API, not the JDK.
javac -nowarn -source 8 -target 8 -encoding UTF-8 \
    -bootclasspath "$ANDROID_JAR" -classpath "$ANDROID_JAR" \
    -d "$OUT/classes" $(find src -name '*.java')

dalvik-exchange --dex --output="$OUT/classes.dex" "$OUT/classes"

aapt package -f -M AndroidManifest.xml -I "$ANDROID_JAR" -F "$OUT/unsigned.apk"
(cd "$OUT" && aapt add unsigned.apk classes.dex >/dev/null)
zipalign -f 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"

: "${KS_PASS:?set KS_PASS to the keystore password}"
apksigner sign --ks release.jks --ks-key-alias gercekkapat \
    --ks-pass "env:KS_PASS" --key-pass "env:KS_PASS" \
    --out "$OUT/gercek-kapat-$VERSION.apk" "$OUT/aligned.apk"
apksigner verify "$OUT/gercek-kapat-$VERSION.apk"
echo "built $OUT/gercek-kapat-$VERSION.apk"

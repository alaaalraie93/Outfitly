#!/usr/bin/env bash
# Adjusts the generated Android project: app name, icon and internet permission.
set -e

MANIFEST=android/app/src/main/AndroidManifest.xml

# Internet is needed for the weather (the rest of the app works offline).
if ! grep -q "android.permission.INTERNET" "$MANIFEST"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$MANIFEST"
fi

# On-device background removal (ML Kit) model, downloaded by Google Play services.
if ! grep -q "com.google.mlkit.vision.DEPENDENCIES" "$MANIFEST"; then
  sed -i 's#</application>#    <meta-data android:name="com.google.mlkit.vision.DEPENDENCIES" android:value="subject_segment" />\n    </application>#' "$MANIFEST"
fi

# ML Kit background removal needs Android 7.0 (API 24) or newer.
for G in android/app/build.gradle.kts android/app/build.gradle; do
  if [ -f "$G" ]; then
    sed -i -E 's/minSdk( =|Version)? *(flutter\.minSdkVersion|[0-9]+)/minSdk = 24/' "$G"
    grep -n "minSdk" "$G" || true
  fi
done

# App name shown under the icon.
sed -i 's/android:label="[^"]*"/android:label="Outfitly"/' "$MANIFEST"

# App icon.
for d in branding/android/mipmap-*; do
  name=$(basename "$d")
  mkdir -p "android/app/src/main/res/$name"
  cp "$d/ic_launcher.png" "android/app/src/main/res/$name/ic_launcher.png"
done

# The template test refers to a demo app that does not exist here.
rm -f test/widget_test.dart

echo "Android project configured."
grep -n "INTERNET\|android:label" "$MANIFEST"

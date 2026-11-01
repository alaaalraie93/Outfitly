#!/usr/bin/env bash
# Adjusts the generated Android project: app name, icon and internet permission.
set -e

MANIFEST=android/app/src/main/AndroidManifest.xml

# Internet is needed for the weather (the rest of the app works offline).
if ! grep -q "android.permission.INTERNET" "$MANIFEST"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$MANIFEST"
fi

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

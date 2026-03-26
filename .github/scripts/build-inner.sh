#!/bin/sh
set -e
apk add alpine-sdk sudo
adduser -D builder && addgroup builder abuild
echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

mkdir -p /home/builder/.abuild
PUBKEY=$(ls /work/keys/*.pub | head -n 1)
PUBKEY_NAME=$(basename "$PUBKEY")
PRIVKEY_NAME="${PUBKEY_NAME%.pub}"

cat /work/.privkey > /home/builder/.abuild/$PRIVKEY_NAME
cp "$PUBKEY" /home/builder/.abuild/$PUBKEY_NAME
cp "$PUBKEY" /etc/apk/keys/$PUBKEY_NAME
echo "PACKAGER_PRIVKEY=/home/builder/.abuild/$PRIVKEY_NAME" > /home/builder/.abuild/abuild.conf

chown -R builder:builder /home/builder/.abuild
chown -R builder:builder /work

for pkg_dir in /work/main/*; do
  [ -f "$pkg_dir/APKBUILD" ] || continue

  pkgname=$(. "$pkg_dir/APKBUILD" 2>/dev/null; echo "$pkgname")
  pkgver=$(. "$pkg_dir/APKBUILD" 2>/dev/null; echo "$pkgver")
  pkgrel=$(. "$pkg_dir/APKBUILD" 2>/dev/null; echo "$pkgrel")

  EXPECTED="${pkgname}-${pkgver}-r${pkgrel}"
  if find /gh-pages/ -name "${EXPECTED}*.apk" 2>/dev/null | grep -q .; then
    echo "Skipping $EXPECTED (already built)"
    continue
  fi

  echo "Building $EXPECTED in $pkg_dir..."
  su builder -c "cd $pkg_dir && abuild -r -c" || exit 1
done

if [ -d /home/builder/packages ]; then
  cp -a /home/builder/packages/* /work/output_packages/
  echo "Build successful. Artifacts:"
  find /work/output_packages/ -type f
else
  echo "No new packages built."
fi

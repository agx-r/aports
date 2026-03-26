#!/bin/sh
set -e

apk add alpine-sdk sudo
adduser -D builder && addgroup builder abuild
echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

mkdir -p /home/builder/.abuild
PUBKEY=$(ls /work/keys/*.pub | head -n 1)
PUBKEY_NAME=$(basename "$PUBKEY")
PRIVKEY_NAME="${PUBKEY_NAME%.pub}"

cp "$PUBKEY" /etc/apk/keys/$PUBKEY_NAME
cat /work/.privkey > /home/builder/.abuild/$PRIVKEY_NAME
cp "$PUBKEY" /home/builder/.abuild/$PUBKEY_NAME
echo "PACKAGER_PRIVKEY=/home/builder/.abuild/$PRIVKEY_NAME" > /home/builder/.abuild/abuild.conf

ARCH=$(apk --print-arch)
LOCAL_REPODIR="/home/builder/packages"
mkdir -p "$LOCAL_REPODIR/$REPO/$ARCH"

chown -R builder:builder /home/builder
chown -R builder:builder /work

echo "$LOCAL_REPODIR/main" >> /etc/apk/repositories
echo "https://agx-r.github.io/aports/main" >> /etc/apk/repositories
apk update


for pkgname_dir in $PKGS; do
  pkg_dir="/work/$REPO/$pkgname_dir"
  [ -f "$pkg_dir/APKBUILD" ] || continue

  pkgname=$(. "$pkg_dir/APKBUILD" 2>/dev/null; echo "$pkgname")
  pkgver=$(. "$pkg_dir/APKBUILD" 2>/dev/null; echo "$pkgver")
  pkgrel=$(. "$pkg_dir/APKBUILD" 2>/dev/null; echo "$pkgrel")
  
  EXPECTED="${pkgname}-${pkgver}-r${pkgrel}"

  if find /gh-pages/ -name "${EXPECTED}*.apk" 2>/dev/null | grep -q .; then
    echo "--- Skipping $EXPECTED (already exists in gh-pages)"
    continue
  fi

  echo "--- Building $EXPECTED in $pkg_dir..."
  
  su builder -c "cd $pkg_dir && abuild -r -c" || exit 1

  echo "--- Updating local index for $ARCH..."
  cd "$LOCAL_REPODIR/main/$ARCH"
  
  su builder -c "apk index -o APKINDEX.tar.gz *.apk"
  su builder -c "abuild-sign -k /home/builder/.abuild/$PRIVKEY_NAME APKINDEX.tar.gz"
  
  apk update
done

if [ -d /home/builder/packages ]; then
  mkdir -p /work/output_packages
  cp -a /home/builder/packages/* /work/output_packages/
  echo "--- Build successful. Final artifacts:"
  find /work/output_packages/ -type f
else
  echo "--- No new packages were built."
fi

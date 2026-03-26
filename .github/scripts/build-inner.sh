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

ARCH=$(uname -m)
REPO_ROOT="/home/builder/packages/main"
mkdir -p "$REPO_ROOT/$ARCH"

if [ -d "/gh-pages/main/$ARCH" ]; then
    echo ">>> Importing existing packages from gh-pages..."
    cp /gh-pages/main/$ARCH/*.apk "$REPO_ROOT/$ARCH/" 2>/dev/null || true
fi

sed -i "1i $REPO_ROOT" /etc/apk/repositories

update_repo() {
    echo ">>> Updating repository index..."
    apk index --no-warnings -o "$REPO_ROOT/$ARCH/APKINDEX.tar.gz" "$REPO_ROOT/$ARCH"/*.apk
    
    abuild-sign -k "/home/builder/.abuild/$PRIVKEY_NAME" "$REPO_ROOT/$ARCH/APKINDEX.tar.gz"
}

update_repo

for pkg_name in wld st; do
    pkg_dir="/work/main/$pkg_name"
    [ -d "$pkg_dir" ] || continue
    [ -f "$pkg_dir/APKBUILD" ] || continue

    pkgver=$(. "$pkg_dir/APKBUILD" 2>/dev/null; echo "$pkgver")
    pkgrel=$(. "$pkg_dir/APKBUILD" 2>/dev/null; echo "$pkgrel")
    EXPECTED="${pkg_name}-${pkgver}-r${pkgrel}"

    if ls "$REPO_ROOT/$ARCH/$EXPECTED"*.apk >/dev/null 2>&1; then
        echo ">>> $EXPECTED already exists, skipping build."
        continue
    fi

    echo ">>> Building $EXPECTED..."
    su builder -c "cd $pkg_dir && abuild -r"
    
    update_repo
done

if [ -d /home/builder/packages ]; then
    cp -a /home/builder/packages/* /work/output_packages/
fi

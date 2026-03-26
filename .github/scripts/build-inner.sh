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
LOCAL_REPO="/home/builder/packages/main"

mkdir -p "$LOCAL_REPO/$ARCH"
if [ -d "/gh-pages/main/$ARCH" ]; then
    echo "Importing existing packages from gh-pages..."
    cp -r /gh-pages/main/$ARCH/*.apk "$LOCAL_REPO/$ARCH/" 2>/dev/null || true
fi

echo "$LOCAL_REPO" >> /etc/apk/repositories
update_index() {
    echo "Updating local repository index..."
    cd "$LOCAL_REPO/$ARCH"
    apk index -o APKINDEX.tar.gz *.apk
    abuild-sign APKINDEX.tar.gz
    cd /work
}

update_index
for pkg_name in wld st; do
    pkg_dir="/work/main/$pkg_name"
    [ -d "$pkg_dir" ] || continue
    [ -f "$pkg_dir/APKBUILD" ] || continue
    pkgver=$(. "$pkg_dir/APKBUILD" 2>/dev/null; echo "$pkgver")
    pkgrel=$(. "$pkg_dir/APKBUILD" 2>/dev/null; echo "$pkgrel")
    EXPECTED="${pkg_name}-${pkgver}-r${pkgrel}"

    if find "$LOCAL_REPO" -name "${EXPECTED}*.apk" 2>/dev/null | grep -q .; then
        echo "Skipping $EXPECTED (already exists in repo)"
        continue
    fi

    echo "Building $EXPECTED in $pkg_dir..."
    su builder -c "cd $pkg_dir && abuild -r -c" || exit 1
    update_index
done

if [ -d /home/builder/packages ]; then
    cp -a /home/builder/packages/* /work/output_packages/
    echo "Build successful. Final artifacts:"
    find /work/output_packages/ -type f
else
    echo "No new packages built."
fi

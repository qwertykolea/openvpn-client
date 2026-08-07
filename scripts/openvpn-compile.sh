#!/bin/sh
set -e

# Если переменная не задана, используем master
if [ -z "$OPENVPN_VERSION" ]; then
    BRANCH="master"
else
    BRANCH="v$OPENVPN_VERSION"   # теги в репозитории с префиксом 'v'
fi

apk add --no-cache \
    autoconf automake build-base gcc git libtool linux-headers make \
    pkgconfig file g++ wget openssl-dev lzo lzo-dev \
    linux-pam-dev libcap-ng libcap-ng-dev

git clone --branch "$BRANCH" https://github.com/OpenVPN/openvpn.git
cd openvpn
autoreconf -i -v -f
./configure --disable-dco --disable-lz4 --enable-small --disable-doc
make -j
make install

cd ..
rm -rf openvpn

apk del autoconf automake build-base gcc git libtool linux-headers make \
       pkgconfig file g++ wget openssl-dev lzo-dev \
       linux-pam-dev libcap-ng-dev

echo "bump"

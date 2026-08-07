#!/bin/sh

set -eu

apk add --no-cache autoconf automake build-base gcc git libtool linux-headers make pkgconfig file g++ wget openssl-dev lzo lzo-dev linux-pam-dev libcap-ng libcap-ng-dev python3

python3 -m ensurepip
pip3 install docutils

git clone -b xor_patch https://github.com/OpenVPN/openvpn.git
cd openvpn
autoreconf -i -v -f
./configure --disable-dco --disable-lz4 --enable-small
make -j
make install

cd ..
rm -rf openvpn

apk del autoconf automake build-base gcc git libtool linux-headers make pkgconfig file g++ wget python3 lzo-dev linux-pam-dev libcap-ng-dev

echo "bump"

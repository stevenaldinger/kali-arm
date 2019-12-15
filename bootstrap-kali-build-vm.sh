#!/bin/bash

mkdir /arm
cd /arm

git clone https://gitlab.com/kalilinux/build-scripts/kali-arm /arm/kali-arm

# install image build dependencies
dpkg --add-architecture i386 && \
apt-get update && \
apt-get -y install \
    debootstrap \
    device-tree-compiler \
    git \
    libncurses5:i386 \
    lzma \
    lzop \
    pixz \
    qemu-user-static \
    systemd-container \
    u-boot-tools && \
mkdir -p arm-stuff/kernel/toolchains && \
cd /arm/arm-stuff/kernel/toolchains && \
git clone https://gitlab.com/kalilinux/packages/gcc-arm-eabi-linaro-4-6-2.git

export ARCH=arm
export CROSS_COMPILE=/arm/arm-stuff/kernel/toolchains/gcc-arm-eabi-linaro-4.6.2/bin/arm-eabi-

# install golang 1.13
curl -Lo /tmp/go1.13.5.linux-amd64.tar.gz https://dl.google.com/go/go1.13.5.linux-amd64.tar.gz
tar -C /usr/local -xzf /tmp/go1.13.5.linux-amd64.tar.gz

export PATH=$PATH:/usr/local/go/bin

# cd /arm
# ./kali-arm/rpi.sh 2019.3

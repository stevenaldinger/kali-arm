#!/bin/bash

mkdir /arm
cd /arm

git clone https://gitlab.com/kalilinux/build-scripts/kali-arm /arm/kali-arm

dpkg --add-architecture i386 && \
apt-get update && \
apt-get -y install \
    debootstrap \
    device-tree-compiler \
    git \
    libncurses5:i386 pixz \
    lzma lzop u-boot-tools \
    qemu-user-static \
    systemd-container && \
mkdir -p arm-stuff/kernel/toolchains && \
cd /arm/arm-stuff/kernel/toolchains && \
git clone https://gitlab.com/kalilinux/packages/gcc-arm-eabi-linaro-4-6-2.git

export ARCH=arm
export CROSS_COMPILE=/arm/arm-stuff/kernel/toolchains/gcc-arm-eabi-linaro-4.6.2/bin/arm-eabi-

# cd /arm
# cd ./kali-arm/rpi.sh 2019.3

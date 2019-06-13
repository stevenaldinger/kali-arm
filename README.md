Kali-ARM-Build-Scripts
======================

Offensive Security Kali Linux ARM build scripts. We use these to build our official Kali Linux ARM images,
as can be found at http://www.kali.org/downloads/

- These scripts have been tested on a Kali Linux 32 and 64 bit installations only, after making sure
that all the dependencies have been installed.
- Make sure you run the build-deps.sh script first, which installs all required dependencies.

A sample workflow would look similar to (armhf):

    mkdir ~/arm-stuff
    cd ~/arm-stuff
    git clone https://gitlab.com/kalilinux/build-scripts/kali-arm
    cd ~/arm-stuff/kali-arm
    ./build-deps.sh
    ./chromebook-arm-exynos.sh 2019.2

If you are on 32bit, after the script finishes running, you will have an image
file located in ~/arm-stuff/kali-arm called
kali-linux-2019.2-exynos.img.  32bit does not have enough memory to compress the image
**_You will need to use your own preferred compression if you want to distribute it._**

On 64bit systems, after the script finishes running, you will have an image
files located in ~/arm-stuff/kali-arm/ called
kali-linux-2019.2-exynos.img.xz

Last Updated : 13th June, 2019 08:05:45 UTC

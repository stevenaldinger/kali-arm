#!/bin/bash
set -e

# This image is for the Pinebook.

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ $# -eq 0 ]] ; then
    echo "Please pass version number, e.g. $0 2.0"
    exit 0
fi

basedir=`pwd`/pinebook-$1

# Custom hostname variable
hostname=${2:-kali}
# Custom image file name variable - MUST NOT include .img at the end.
imagename=${3:-kali-linux-$1-pinebook}
# Size of image in megabytes (Default is 7000=7GB)
size=7000
# Suite to use.
# Valid options are:
# kali-rolling, kali-dev, kali-bleeding-edge, kali-dev-only, kali-experimental, kali-last-snapshot
# A release is done against kali-last-snapshot, but if you're building your own, you'll probably want to build
# kali-rolling.
suite=kali-rolling

# Generate a random machine name to be used.
machine=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)

# Make sure that the cross compiler can be found in the path before we do
# anything else, that way the builds don't fail half way through.
export CROSS_COMPILE=aarch64-linux-gnu-
if [ $(compgen -c $CROSS_COMPILE | wc -l) -eq 0 ] ; then
    echo "Missing cross compiler. Set up PATH according to the README"
    exit 1
fi
# Unset CROSS_COMPILE so that if there is any native compiling needed it doesn't
# get cross compiled.
unset CROSS_COMPILE

# Package installations for various sections.
# This will build a minimal XFCE Kali system with the top 10 tools.
# This is the section to edit if you would like to add more packages.
# See http://www.kali.org/new/kali-linux-metapackages/ for meta packages you can
# use. You can also install packages, using just the package name, but keep in
# mind that not all packages work on ARM! If you specify one of those, the
# script will throw an error, but will still continue on, and create an unusable
# image, keep that in mind.

arm="abootimg cgpt fake-hwclock ntpdate u-boot-tools vboot-utils vboot-kernel-utils"
base="apt-utils dkms e2fsprogs ifupdown initramfs-tools kali-defaults parted sudo usbutils firmware-linux firmware-atheros firmware-libertas firmware-realtek arm-trusted-firmware linux-headers-arm64 linux-image-arm64 u-boot-sunxi u-boot-menu"
desktop="kali-menu fonts-croscore fonts-crosextra-caladea fonts-crosextra-carlito gnome-theme-kali gtk3-engines-xfce kali-desktop-xfce kali-root-login lightdm network-manager network-manager-gnome xfce4 xserver-xorg-video-fbdev"
tools="aircrack-ng ethtool hydra john libnfc-bin mfoc nmap passing-the-hash sqlmap usbutils winexe wireshark"
services="apache2 openssh-server"
extras="firefox-esr xfce4-terminal wpasupplicant"

packages="${arm} ${base} ${services}"
architecture="arm64"
# If you have your own preferred mirrors, set them here.
# After generating the rootfs, we set the sources.list to the default settings.
mirror=http.kali.org

# Set this to use an http proxy, like apt-cacher-ng, and uncomment further down
# to unset it.
#export http_proxy="http://localhost:3142/"

mkdir -p "${basedir}"
cd "${basedir}"

# create the rootfs - not much to modify here, except maybe throw in some more packages if you want.
debootstrap --foreign --keyring=/usr/share/keyrings/kali-archive-keyring.gpg --include=kali-archive-keyring --arch ${architecture} ${suite} kali-${architecture} http://${mirror}/kali

cp /usr/bin/qemu-aarch64-static kali-${architecture}/usr/bin/

LANG=C systemd-nspawn -M ${machine} -D kali-${architecture} /debootstrap/debootstrap --second-stage

mkdir -p kali-${architecture}/etc/apt/
cat << EOF > kali-${architecture}/etc/apt/sources.list
deb http://${mirror}/kali ${suite} main contrib non-free
EOF

echo "${hostname}" > kali-${architecture}/etc/hostname

cat << EOF > kali-${architecture}/etc/hosts
127.0.0.1       ${hostname}    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

# No built in ethernet, so don't add eth0 here otherwise the
# networking.service will fail to start, despite it not being an actual
# issue.
mkdir -p kali-${architecture}/etc/network/
cat << EOF > kali-${architecture}/etc/network/interfaces
auto lo
iface lo inet loopback
EOF

cat << EOF > kali-${architecture}/etc/resolv.conf
nameserver 8.8.8.8
EOF

export MALLOC_CHECK_=0 # workaround for LP: #520465
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

#mount -t proc proc kali-${architecture}/proc
#mount -o bind /dev/ kali-${architecture}/dev/
#mount -o bind /dev/pts kali-${architecture}/dev/pts

cat << EOF > kali-${architecture}/debconf.set
console-common console-data/keymap/policy select Select keymap from full list
console-common console-data/keymap/full select en-latin1-nodeadkeys
EOF

mkdir -p kali-${architecture}/usr/lib/systemd/system/
cat << 'EOF' > kali-${architecture}/usr/lib/systemd/system/regenerate_ssh_host_keys.service
[Unit]
Description=Regenerate SSH host keys
Before=ssh.service
[Service]
Type=oneshot
ExecStartPre=-/bin/dd if=/dev/hwrng of=/dev/urandom count=1 bs=4096
ExecStartPre=-/bin/sh -c "/bin/rm -f -v /etc/ssh/ssh_host_*_key*"
ExecStart=/usr/bin/ssh-keygen -A -v
ExecStartPost=/bin/sh -c "for i in /etc/ssh/ssh_host_*_key*; do actualsize=$(wc -c <\"$i\") ;if [ $actualsize -eq 0 ]; then echo size is 0 bytes ; exit 1 ; fi ; done ; /bin/systemctl disable regenerate_ssh_host_keys"
[Install]
WantedBy=multi-user.target
EOF
chmod 644 kali-${architecture}/usr/lib/systemd/system/regenerate_ssh_host_keys.service

cat << EOF > kali-${architecture}/usr/lib/systemd/system/smi-hack.service
[Unit]
Description=shared-mime-info update hack
Before=regenerate_ssh_host_keys.service
[Service]
Type=oneshot
Environment=DEBIAN_FRONTEND=noninteractive
ExecStart=/bin/sh -c "rm -rf /etc/ssl/certs/*.pem && dpkg -i /root/ca-certificates_20190110_all.deb /root/fontconfig_2.13.1-2_arm64.deb /root/libgdk-pixbuf2.0-0_2.38.1+dfsg-1_arm64.deb"
ExecStart=/bin/sh -c "dpkg-reconfigure shared-mime-info"
ExecStart=/bin/sh -c "rm -f /root/*.deb"
ExecStartPost=/bin/systemctl disable smi-hack

[Install]
WantedBy=multi-user.target
EOF
chmod 644 kali-${architecture}/usr/lib/systemd/system/smi-hack.service

cat << EOF > kali-${architecture}/usr/lib/systemd/system/pinebook-wifi-dkms.service
[Unit]
Description=Compile wifi driver on first boot.
Before=regenerate_ssh_host_keys.service
[Service]
Type=oneshot
ExecStart=/bin/sh -c "cd /usr/src/rtl8723cs && dkms install ."
ExecStartPost=/bin/systemctl disable pinebook-wifi-dkms.service
EOF
chmod 644 kali-${architecture}/usr/lib/systemd/system/pinebook-wifi-dkms.service

# Disable RESUME (suspend/resume is currently broken anyway!) which speeds up boot massively.
mkdir -p kali-${architecture}/etc/initramfs-tools/conf.d/
cat << EOF > kali-${architecture}/etc/initramfs-tools/conf.d/resume
RESUME=none
EOF

cat << EOF > kali-${architecture}/third-stage
#!/bin/bash
set -e
dpkg-divert --add --local --divert /usr/sbin/invoke-rc.d.chroot --rename /usr/sbin/invoke-rc.d
cp /bin/true /usr/sbin/invoke-rc.d
echo -e "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d

apt-get update
apt-get --yes --allow-change-held-packages install locales-all

debconf-set-selections /debconf.set
rm -f /debconf.set
apt-get update
apt-get -y install git-core binutils ca-certificates cryptsetup-bin initramfs-tools u-boot-tools
apt-get -y install locales console-common less nano git
echo "root:toor" | chpasswd
rm -f /etc/udev/rules.d/70-persistent-net.rules
export DEBIAN_FRONTEND=noninteractive
# This looks weird, but we do it twice because every so often, there's a failure to download from the mirror
# So to workaround it, we attempt to install them twice.
apt-get --yes --allow-change-held-packages install ${packages} || apt-get --yes --fix-broken install
apt-get --yes --allow-change-held-packages install ${packages} || apt-get --yes --fix-broken install
apt-get --yes --allow-change-held-packages install ${desktop} ${extras} ${tools} || apt-get --yes --fix-broken install
apt-get --yes --allow-change-held-packages install ${desktop} ${extras} ${tools} || apt-get --yes --fix-broken install
apt-get --yes --allow-change-held-packages dist-upgrade
apt-get --yes --allow-change-held-packages  autoremove

# Regenerated the shared-mime-info database on the first boot
# since it fails to do so properly in a chroot.
systemctl enable smi-hack
# Compile the wifi driver on first boot
systemctl enable pinebook-wifi-dkms

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys
systemctl enable ssh

# Copy bashrc
cp  /etc/skel/.bashrc /root/.bashrc

cd /root
apt download ca-certificates
apt download libgdk-pixbuf2.0-0
apt download fontconfig

# We replace the u-boot menu defaults here so we can make sure the build system doesn't poison it.
# We use _EOF_ so that the third-stage script doesn't end prematurely.
cat << '_EOF_' > /etc/default/u-boot
U_BOOT_PARAMETERS="console=ttyS0,115200 console=tty1 root=/dev/mmcblk0p1 rootwait panic=10 rw rootfstype=ext4 net.ifnames=0"
_EOF_

rm -f /usr/sbin/policy-rc.d
rm -f /usr/sbin/invoke-rc.d
dpkg-divert --remove --rename /usr/sbin/invoke-rc.d

rm -f /third-stage
EOF

chmod 755 kali-${architecture}/third-stage
LANG=C systemd-nspawn -M ${machine} -D kali-${architecture} /third-stage

cat << EOF > kali-${architecture}/cleanup
#!/bin/bash
rm -rf /root/.bash_history
apt-get update
apt-get clean
rm -f /0
rm -f /hs_err*
rm -f cleanup
rm -f /usr/bin/qemu*
EOF

chmod 755 kali-${architecture}/cleanup
LANG=C systemd-nspawn -M ${machine} -D kali-${architecture} /cleanup

#umount kali-${architecture}/proc/sys/fs/binfmt_misc
#umount kali-${architecture}/dev/pts
#umount kali-${architecture}/dev/
#umount kali-${architecture}/proc

# Enable serial console
echo 'T1:12345:respawn:/sbin/agetty 115200 ttymxc0 vt100' >> \
    "${basedir}"/kali-${architecture}/etc/inittab

cat << EOF > "${basedir}"/kali-${architecture}/etc/apt/sources.list
deb http://http.kali.org/kali kali-rolling main non-free contrib
deb-src http://http.kali.org/kali kali-rolling main non-free contrib
EOF

mkdir -p "${basedir}"/kali-${architecture}/etc/X11/xorg.conf.d/
cat << EOF > "${basedir}"/kali-${architecture}/etc/X11/xorg.conf.d/50-pine64-pinebook.touchpad.conf
Section "InputClass"
    Identifier "HAILUCK CO.,LTD USB KEYBOARD"
    MatchIsPointer "1"
    MatchDevicePath "/dev/input/event*"

    Option "AccelerationProfile" "2"
    Option "AdaptiveDeceleration" "1"
    #Option "ConstantDeceleration" "2.5" # Pinebook 14
    Option "ConstantDeceleration" "1.2" # Pinebook 11
EndSection
EOF

# Set up some defaults for chromium, if the user ever installs it
mkdir -p "${basedir}"/kali-${architecture}/etc/chromium/
cat << EOF > "${basedir}"/kali-${architecture}/etc/chromium/default
#Options to pass to chromium
CHROMIUM_FLAGS="\
--disable-smooth-scrolling \
--disable-low-res-tiling \
--enable-low-end-device-mode \
--num-raster-threads=\$(nproc) \
--profiler-timing=0 \
--disable-composited-antialiasing \
"
EOF

# Uncomment this if you use apt-cacher-ng otherwise git clones will fail.
#unset http_proxy

cd "${basedir}"

# Pull in the wifi and bluetooth firmware from anarsoul's git repository.
git clone https://github.com/anarsoul/rtl8723bt-firmware
cd rtl8723bt-firmware
cp -a "${basedir}"/rtl8723bt-firmware/rtl_bt "${basedir}"/kali-${architecture}/lib/firmware/
cd "${basedir}"

# Need to package up the wifi driver (it's a Realtek 8723cs, with the usual
# Realtek driver quality) still, so for now, we clone it and then build it
# inside the chroot.
cd "${basedir}"/kali-${architecture}/usr/src/
git clone https://github.com/icenowy/rtl8723cs
cat << EOF > "${basedir}"/kali-${architecture}/usr/src/rtl8723cs/dkms.conf
PACKAGE_NAME="rtl8723cs"
PACKAGE_VERSION="2018.11.07"

AUTOINSTALL="yes"

CLEAN[0]="make clean"

MAKE[0]="'make' -j4 ARCH=arm64 KVER=\${kernelver} KSRC=/lib/modules/\${kernelver}/build/"

BUILT_MODULE_NAME[0]="8723cs"

BUILT_MODULE_LOCATION[0]=""

DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless"
EOF
cd ${basedir}

cp "${basedir}"/../misc/zram "${basedir}"/kali-${architecture}/etc/init.d/zram
chmod 755 "${basedir}"/kali-${architecture}/etc/init.d/zram

sed -i -e 's/^#PermitRootLogin.*/PermitRootLogin yes/' "${basedir}"/kali-${architecture}/etc/ssh/sshd_config

# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot.
sed -i -e 's/append.*/append root=\/dev\/mmcblk0p1 rootfstype=ext4 console=ttyS0,115200 console=tty1 consoleblank=0 rw rootwait/g' "${basedir}"/kali-${architecture}/boot/extlinux/extlinux.conf

echo "Creating image file for ${imagename}.img"
dd if=/dev/zero of="${basedir}"/${imagename}.img bs=1M count=${size}
parted ${imagename}.img --script -- mklabel msdos
parted ${imagename}.img --script -- mkpart primary ext4 2048s 100%

# Set the partition variables
loopdevice=`losetup -f --show "${basedir}"/${imagename}.img`
device=`kpartx -va ${loopdevice} | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1`
sleep 5
device="/dev/mapper/${device}"
rootp=${device}p1

# Create file systems
mkfs.ext4 ${rootp}

# Create the dirs for the partitions and mount them
mkdir -p "${basedir}"/root
mount ${rootp} "${basedir}"/root

# We do this down here to get rid of the build system's resolv.conf after running through the build.
cat << EOF > kali-${architecture}/etc/resolv.conf
nameserver 8.8.8.8
EOF

echo "Rsyncing rootfs into image file"
rsync -HPavz -q "${basedir}"/kali-${architecture}/ "${basedir}"/root/

# Do some wiggle work because we need to prep the u-boot bits for writing to the
# sdcard.
# Somewhat adapted from the u-boot-install-sunxi64 script

cd "${basedir}"
mkdir -p u-boot-itb
cd u-boot-itb
cp "${basedir}"/root/usr/lib/arm-trusted-firmware/sun50i_a64/bl31.bin .
cp "${basedir}"/root/usr/lib/u-boot/pinebook/* .
BL31=bl31.bin "${basedir}"/root/usr/bin/mksunxi_fit_atf *.dtb > u-boot.its
mkimage -f u-boot.its u-boot.itb

dd conv=fsync,notrunc if=sunxi-spl.bin of=${loopdevice} bs=8k seek=1
dd conv=notrunc if=u-boot.itb of=${loopdevice} bs=8k seek=5

# Unmount partitions
sync
umount ${rootp}

kpartx -dv ${loopdevice}
losetup -d ${loopdevice}


# Don't pixz on 32bit, there isn't enough memory to compress the images.
MACHINE_TYPE=`uname -m`
if [ ${MACHINE_TYPE} == 'x86_64' ]; then
echo "Compressing ${imagename}.img"
pixz "${basedir}"/${imagename}.img "${basedir}"/../${imagename}.img.xz
rm "${basedir}"/${imagename}.img
fi

# Clean up all the temporary build stuff and remove the directories.
# Comment this out to keep things around if you want to see what may have gone
# wrong.
echo "Removing temporary build files"
rm -rf "${basedir}"

#!/bin/bash
set -e

# This is for the Gateworks Ventana (Freescale based).

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ $# -eq 0 ]] ; then
    echo "Please pass version number, e.g. $0 2.0"
    exit 0
fi

basedir=`pwd`/ventana-$1

# Custom hostname variable
hostname=${2:-kali}
# Custom image file name variable - MUST NOT include .img at the end.
imagename=${3:-kali-linux-$1-ventana}
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
export CROSS_COMPILE=arm-linux-gnueabihf-
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
base="apt-utils e2fsprogs ifupdown initramfs-tools kali-defaults parted sudo usbutils firmware-linux firmware-atheros firmware-libertas firmware-realtek u-boot-menu firmware-linux-nonfree bash-completion isc-dhcp-server iw man-db mlocate netcat netcat-traditional net-tools psmisc rfkill tmux"
desktop="kali-menu fonts-croscore fonts-crosextra-caladea fonts-crosextra-carlito gnome-theme-kali gtk3-engines-xfce kali-desktop-xfce kali-root-login lightdm network-manager network-manager-gnome xfce4 xserver-xorg-video-fbdev"
tools="aircrack-ng ethtool hydra john libnfc-bin mfoc nmap passing-the-hash pciutils sqlmap usbutils winexe wireshark"
services="apache2 openssh-server can-utils i2c-tools"
extras="firefox-esr xfce4-terminal wpasupplicant"

packages="${arm} ${base} ${services}"
architecture="armhf"
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

cp /usr/bin/qemu-arm-static kali-${architecture}/usr/bin/

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

mkdir -p kali-${architecture}/etc/network/
cat << EOF > kali-${architecture}/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

allow-hotplug usb0
iface usb0 inet static
    address 10.10.10.1
    netmask 255.255.255.0
    network 10.10.10.0
    broadcast 10.10.10.255
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
ExecStart=/bin/sh -c "rm -rf /etc/ssl/certs/*.pem && dpkg -i /root/ca-certificates_20190110_all.deb /root/fontconfig_2.13.1-2_armhf.deb /root/libgdk-pixbuf2.0-0_2.38.1+dfsg-1_armhf.deb"
ExecStart=/bin/sh -c "dpkg-reconfigure shared-mime-info"
ExecStart=/bin/sh -c "rm -f /root/*.deb"
ExecStartPost=/bin/systemctl disable smi-hack

[Install]
WantedBy=multi-user.target
EOF
chmod 644 kali-${architecture}/usr/lib/systemd/system/smi-hack.service

cat << EOF > kali-${architecture}/third-stage
#!/bin/bash
set -e
dpkg-divert --add --local --divert /usr/sbin/invoke-rc.d.chroot --rename /usr/sbin/invoke-rc.d
cp /bin/true /usr/sbin/invoke-rc.d
echo -e "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get --yes --allow-change-held-packages install locales-all

debconf-set-selections /debconf.set
rm -f /debconf.set
apt-get update
apt-get -y install git-core binutils ca-certificates cryptsetup-bin initramfs-tools u-boot-tools
apt-get -y install locales console-common less nano git
echo "root:toor" | chpasswd
rm -f /etc/udev/rules.d/70-persistent-net.rules
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

cat << EOF > kali-${architecture}/etc/dhcp/dhcpd.conf
ddns-update-style none;
default-lease-time 600;
max-lease-time 7200;
log-facility local7;

subnet 10.10.10.0 netmask 255.255.255.0 {
        range 10.10.10.10 10.10.10.20;
        option subnet-mask 255.255.255.0;
        option domain-name-servers 8.8.8.8;
        option routers 10.10.10.1;
        default-lease-time 600;
        max-lease-time 7200;
}
EOF

cat << EOF > kali-${architecture}/usb-gadget-setup
#Setup Serial Port
#echo 'g_cdc' >> /etc/modules
#echo '\n# USB Gadget Serial console port\nttyGS0' >> /etc/securetty
#systemctl enable getty@ttyGS0.service
#Setup Ethernet Port
echo 'g_ether' >> /etc/modules
sed -i 's/INTERFACESv4=""/INTERFACESv4="usb0"/g' /etc/default/isc-dhcp-server
systemctl enable isc-dhcp-server
rm -rf /usb-gadget-setup
EOF

chmod 755 kali-${architecture}/usb-gadget-setup
LANG=C systemd-nspawn -M ${machine} -D kali-${architecture} /usb-gadget-setup

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
echo 'T1:12345:respawn:/sbin/getty -L ttymxc1 115200 vt100' >> \
    "${basedir}"/kali-${architecture}/etc/inittab

cat << EOF > "${basedir}"/kali-${architecture}/etc/apt/sources.list
deb http://http.kali.org/kali kali-rolling main non-free contrib
deb-src http://http.kali.org/kali kali-rolling main non-free contrib
EOF

# Uncomment this if you use apt-cacher-ng otherwise git clones will fail.
#unset http_proxy

cd "${basedir}"

# Do the kernel stuff...
mkdir -p "${basedir}"/kali-${architecture}/usr/src/
git clone --depth 1 -b gateworks_4.20.7 https://github.com/gateworks/linux-imx6 "${basedir}"/kali-${architecture}/usr/src/kernel
cd "${basedir}"/kali-${architecture}/usr/src/kernel
# Don't change the version because of our patches.
touch .scmversion
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
patch -p1 < "${basedir}"/../patches/veyron/4.19/kali-wifi-injection.patch
patch -p1 < "${basedir}"/../patches/veyron/4.19/wireless-carl9170-Enable-sniffer-mode-promisc-flag-t.patch
cp "${basedir}"/../kernel-configs/gateworks_ventana-4.20.7.config .config
cp "${basedir}"/../kernel-configs/gateworks_ventana-4.20.7.config "${basedir}"/kali-${architecture}/usr/src/gateworks_ventana-4.20.7.config
make -j $(grep -c processor /proc/cpuinfo)
make uImage LOADADDR=0x10008000
make modules_install INSTALL_MOD_PATH="${basedir}"/kali-${architecture}
cp arch/arm/boot/dts/imx6*-gw*.dtb "${basedir}"/kali-${architecture}/boot/
cp arch/arm/boot/uImage "${basedir}"/kali-${architecture}/boot/
make mrproper
cd "${basedir}"

# Pull in imx6 smda/vpu firmware for vpu.
cd  "${basedir}"
mkdir -p "${basedir}"/kali-${architecture}/lib/firmware/vpu
mkdir -p "${basedir}"/kali-${architecture}/lib/firmware/imx/sdma
wget 'https://github.com/armbian/firmware/blob/master/vpu/v4l-coda960-imx6dl.bin?raw=true' -O "${basedir}"/kali-${architecture}/lib/firmware/vpu/v4l-coda960-imx6dl.bin
wget 'https://github.com/armbian/firmware/blob/master/vpu/v4l-coda960-imx6q.bin?raw=true' -O "${basedir}"/kali-${architecture}/lib/firmware/vpu/v4l-coda960-imx6q.bin
wget 'https://github.com/armbian/firmware/blob/master/vpu/vpu_fw_imx6d.bin?raw=true' -O "${basedir}"/kali-${architecture}/lib/firmware/vpu_fw_imx6d.bin
wget 'https://github.com/armbian/firmware/blob/master/vpu/vpu_fw_imx6q.bin?raw=true' -O "${basedir}"/kali-${architecture}/lib/firmware/vpu_fw_imx6q.bin
wget 'https://github.com/armbian/firmware/blob/master/imx/sdma/sdma-imx6q.bin?raw=true' -O "${basedir}"/kali-${architecture}/lib/firmware/imx/sdma/sdma-imx6q.bin

# Allow root login
sed -i -e 's/^#PermitRootLogin.*/PermitRootLogin yes/' "${basedir}"/kali-${architecture}/etc/ssh/sshd_config

# Not using extlinux.conf just yet...
# Ensure we don't have root=/dev/sda3 in the extlinux.conf which comes from running u-boot-menu in a cross chroot.
#sed -i -e 's/append.*/append root=\/dev\/mmcblk0p1 rootfstype=ext4 video=mxcfb0:dev=hdmi,1920x1080M@60,if=RGB24,bpp=32 console=ttymxc0,115200n8 console=tty1 consoleblank=0 rw rootwait/g' "${basedir}"/kali-${architecture}/boot/extlinux/extlinux.conf

# Create the boot script that is expected for the ventana machine
cat << '__EOF__' > "${basedir}"/kali-${architecture}/boot/6x_bootscript-ventana.script
# the following U-Boot env vars are assumed to be set:
#  - automatically by the bootloader:
#    dtype - nand|usb|mmc|sata
#    mem_mb - Mib's of memory (ie 1024)
#    loadaddr - memory address for loading blobs
#  - optionally by the user:
#    mem - optional kernel cmdline args intended for mem allocation
#    video - optional kernel cmdline args intended for display
#    extra - optional kernel cmdline args
#    fixfdt - optional script to execute prior to bootm
#
# if 'video' is not set, it will be determined by detecting a connected
# HDMI monitor and LVDS touchscreen displays with I2C touch controlellers.
#
# if 'mem' is not set, it will be automatically allocated
#

echo "Gateworks Ubuntu Bootscript v1.20"

# calculate load addresses based off of loadaddr as the base
# and allow 128KB for FDT and 64MB for kernel
setexpr fdt_addr $loadaddr
setexpr linux_addr $fdt_addr + 0x20000 # allow 128KB for FDT
setexpr rd_addr $linux_addr + 0x4000000 # allow 64MB for kernel

# CMA (memory allocation)
if test -z "${mem}" ; then
  # CMA used by etnaviv display driver and coda VPU driver
  # specific requirements depend on display res and encode/decode res
  setenv mem "cma=64M"
  echo "Detected ${mem_mb}MB DRAM: $mem"
fi
if itest.s "x${mem}" == "xNA" ; then
  echo "Leaving CMA alone..."
else
  setenv extra "${extra}" "${mem}"
  echo "Memory configuration used from env mem: $mem"
fi

# Display output
if test -z "${video}" ; then
  # locally used variables
  setenv lvds_flag
  setenv hdmi_flag

  # Default displays to display if displays is empty
  if test -z "${displays}"; then
    setenv displays "${display}"
  fi

  # Detect HDMI if displays is empty (HDMI)
  if test -z "${displays}" ; then
    i2c dev 2
    if hdmidet ; then # HDMI
      setenv displays "HDMI"
      echo "HDMI Detected"
    fi
  fi

  # Configure displays
  echo "Display(s) to configure: ${displays}"
  for disp in ${displays} ; do
    if itest.s "x${disp}" == "xHDMI" ; then
      if test -z "${hdmi_flag}" ; then # Only allow one HDMI display
        setenv hdmi_flag 1
        test -n "${hdmi}" || hdmi=1080p
        if itest.s "x${hdmi}" == "x1080p" ; then
          setenv hdmi "1920x1080M@60"
        elif itest.s "x${hdmi}" == "x720p" ; then
          setenv hdmi "1280x720M@60"
        elif itest.s "x${hdmi}" == "x480p" ; then
          setenv hdmi "720x480M@60"
        fi
        setenv video "${video}" "video=HDMI-A-1:${hdmi}"
     fi

     # Freescale MCIMX-LVDS1 10" XGA Touchscreen Display
     elif itest.s "x${disp}" == "xHannstar-XGA" ; then
       if test -z "${lvds_flag}" ; then # Only allow one LVDS display
         setenv lvds_flag 1
         setenv video "${video}" "video=LVDS-1:1024x768@65M"
         setenv display "Hannstar-XGA"
       fi

     # GW17029 DLC700JMGT4 7" WSVGA Touchscreen Display
     elif itest.s "x${disp}" == "xDLC700JMGT4" ; then
       if test -z "${lvds_flag}" ; then # Only allow one LVDS display
         setenv lvds_flag 1
         setenv video "${video}" "video=LVDS-1:1024x600@65M"
         setenv display "DLC700JMGT4"
       fi

     # GW17030 DLC800FIGT3 8" XGA Touchscreen Display"
     elif itest.s "x${disp}" == "xDLC800FIGT3" ; then
       if test -z "${lvds_flag}" ; then # Only allow one LVDS display
         setenv lvds_flag 1
         setenv video "${video}" "video=LVDS-1:1024x768@65M"
         setenv display "DLC800FIGT3"
       fi

     elif itest.s "x${disp}" != "none" ; then
       echo "${disp} is an unsupported display type"
       echo "Valid Displays: HDMI|Hannstar-XGA|DLC700JMGT4|DLC800FIGT3"
     fi
  done

  # disable unused connectors
  if test -z "${hdmi_flag}" ; then
    setenv video "${video}" "video=HDMI-A-1:d"
  fi
  if test -z "${lvds_flag}" ; then
    setenv video "${video}" "video=LVDS-1:d"
  fi

  # Set only if video is set
  if test -n "${video}" ; then
    setenv video "${video}"
  fi
  echo "Video configuration: ${video}"
else
  echo "Video configuration used from env video: ${video}"
fi

# setup root and load options based on dev type
if itest.s "x${dtype}" == "xnand" ; then
  echo "Booting from NAND/ubifs..."
  setenv root "root=ubi0:rootfs ubi.mtd=2 rootfstype=ubifs rw rootwait"
  setenv fsload "ubifsload"
elif itest.s "x${dtype}" == "xmmc" ; then
  echo "Booting from MMC..."
  setenv root "root=/dev/mmcblk0p1 rw rootfstype=ext4 rootwait init=/lib/systemd/systemd"
  setenv fsload "ext4load $dtype 0:1"
  setenv rd_addr # ramdisk not needed for IMX6 MMC
elif itest.s "x${dtype}" == "xusb" ; then
  echo "Booting from USB Mass Storage..."
  setenv root "root=/dev/sda1 rootwait"
  setenv fsload "ext4load $dtype 0:1"
elif itest.s "x${dtype}" == "xsata" ; then
  echo "Booting from SATA..."
  setenv root "root=/dev/sda1 rootwait"
  setenv fsload "ext4load $dtype 0:1"
  setenv rd_addr # ramdisk not needed for IMX6 AHCI SATA
fi

# setup bootargs
setenv bootargs "console=${console},${baudrate} ${root} ${video} ${extra}"

# additional bootargs
setenv bootargs "${bootargs} pci=nomsi" # MSI+legacy IRQs do not work on IMX6

# Gateworks kernels do not need ramdisk
setenv rd_addr

# load fdt/kernel/ramdisk
echo "Loading FDT..."
$fsload $fdt_addr boot/$fdt_file ||
$fsload $fdt_addr boot/$fdt_file1 ||
$fsload $fdt_addr boot/$fdt_file2
echo "Loading Kernel..."
$fsload $linux_addr boot/uImage
if itest.s "x${rd_addr}" != "x" ; then
  echo "Loading Ramdisk..."
  $fsload $rd_addr boot/uramdisk
fi
if itest.s "x${dtype}" == "xnand" ; then
  ubifsumount
fi

# fdt fixup
test -n "$fixfdt" && run fixfdt

# boot
if itest.s "x${rd_addr}" != "x" ; then
  echo "Booting ramdisk with "$bootargs"..."
  bootm $linux_addr $rd_addr $fdt_addr
else
  echo "Booting with "$bootargs"..."
  bootm $linux_addr - $fdt_addr
fi
__EOF__
mkimage -A arm -T script -C none -d "${basedir}"/kali-${architecture}/boot/6x_bootscript-ventana.script "${basedir}"/kali-${architecture}/boot/6x_bootscript-ventana

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
mkfs.ext4 -O ^64bit -O ^flex_bg -O ^metadata_csum ${rootp}

# Create the dirs for the partitions and mount them
mkdir -p "${basedir}"/root
mount ${rootp} "${basedir}"/root

# We do this down here to get rid of the build system's resolv.conf after running through the build.
cat << EOF > kali-${architecture}/etc/resolv.conf
nameserver 8.8.8.8
EOF

echo "Rsyncing rootfs into image file"
rsync -HPavz -q "${basedir}"/kali-${architecture}/ "${basedir}"/root/


#wget http://dev.gateworks.com/ventana/images/SPL -O "${basedir}"/root/usr/lib/u-boot/gateworks/SPL
#wget http://dev.gateworks.com/ventana/images/u-boot.img -O "${basedir}"/root/usr/lib/u-boot/gateworks/u-boot.img
#dd conv=fsync,notrunc if="${basedir}"/root/usr/lib/u-boot/gateworks/SPL of=${loopdevice} bs=1k seek=1
#dd conv=fsync,notrunc if="${basedir}"/root/usr/lib/u-boot/gateworks/u-boot.img of=${loopdevice} bs=1k seek=69

# Unmount partitions
sync
umount ${rootp}

# We need an older cross compiler for compiling u-boot so check out the 4.7
# cross compiler.
#git clone https://github.com/offensive-security/gcc-arm-linux-gnueabihf-4.7

#git clone https://github.com/Gateworks/u-boot-imx6.git
#cd "${basedir}"/u-boot-imx6
#make CROSS_COMPILE="${basedir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf- gwventana_defconfig
#make CROSS_COMPILE="${basedir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf-

#dd if=SPL of=${loopdevice} bs=1K seek=1
#dd if=u-boot.img of=${loopdevice} bs=1K seek=42

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

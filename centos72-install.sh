#!/bin/bash

export LANG=C
echo "*** begin installation job ***"

# ----------------------------------------------------------
# Parameters
# ----------------------------------------------------------

#-- Guest Name (Domain Name)
DOM=centos72
#-- Guest Image File
IMG=/var/lib/libvirt/images/${DOM}.qcow2
#-- Kickstart file
KSF=${DOM}-ks.cfg

#-- num of vCPUs --
VCPUS=1
#VCPUS=2
#-- Guest Memory Size (MB)
RAM=1024
#RAM=2048
#-- Guest Disk Size (GB)
SIZE=16.0
#SIZE=20.0
# -- Virtual NETWORK
#VIRTUALNETWORK=bridge:virbr0
VIRTUALNETWORK=network:default

#-- root password
PASSWORD=password
#-- Hostname
HOSTNAME=centos72.example.com
#-- IP Address
IP=192.168.122.110
#-- Netmask
NETMASK=255.255.255.0
#-- Gateway
GATEWAY=192.168.122.1
#-- DNS server
NAMESERVER=8.8.8.8,8.8.4.4
#NAMESERVER=192.168.100.1,192.168.122.1
#-- NTP server
NTPSERVERS=0.centos.pool.ntp.org,1.centos.pool.ntp.org,2.centos.pool.ntp.org,3.centos.pool.ntp.org
#NTPSERVERS=ntp1.jst.mfeed.ad.jp,ntp2.jst.mfeed.ad.jp,ntp3.jst.mfeed.ad.jp


#-- Install Media (ISO)  full path
DVD1=/var/lib/libvirt/images/CentOS-7-x86_64-DVD-1511.iso
#DVD1=/var/lib/libvirt/images//CentOS-7-x86_64-Everything-1511.iso
#-- dvd basename   ex. "CentOS-7-x86_64-DVD-1511.iso"
DVD1_ISO=$(basename ${DVD1})
#-- dvd mount point name  ex. "CentOS-7-x86_64-DVD-1511"
DVD1_MNT=${DVD1_ISO%.*}

# ----------------------------------------------------------
# Initial Check
# ----------------------------------------------------------

CNT=0
# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
    ((CNT++))
    echo "ERROR${CNT}: This script must be run as root." 1>&2
fi
# Make sure dvd image file exists under /var/lib/libvirt/images dir
if [ ! -f ${DVD1} ]; then
    ((CNT++))
    echo "ERROR${CNT}: DVD install media [${DVD1_ISO}] must be copied under \"/var/lib/libvirt/images\" dir." 1>&2
fi
# exit if error
if [ $CNT -gt 0 ]; then
    echo "*** exit job ***" 1>&2
    exit 1
fi
echo "*** initial check OK ***"

# ----------------------------------------------------------
# erase previous vm & snapshot if existing
# ----------------------------------------------------------

echo "*** erase previous vm & snapshot ***"

# stop domain forcefully
virsh destroy ${DOM} >/dev/null 2>&1
# delete all snapshot of domain
virsh snapshot-list ${DOM} --name 2>/dev/null | xargs -I% sh -c "virsh snapshot-delete ${DOM} --snapshotname % >/dev/null 2>&1;"
# undefine domain
virsh undefine ${DOM} --remove-all-storage --delete-snapshots >/dev/null 2>&1
# remove domain image file
rm -f ${IMG} >/dev/null 2>&1

# ----------------------------------------------------------
# create kickstart file
# ----------------------------------------------------------

echo "*** kickstart file creating ***"

cat << _EOF_ > ${KSF}
#-- Install OS instead of upgrade
install
#-- Use CDROM installation media
cdrom
#-- graphical or text install
text
#-- shutdown after installation
shutdown
#poweroff
#halt
#reboot

#-- System language
lang en_US.UTF-8
#lang ja_JP.UTF-8
#-- Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'
#keyboard --vckeymap=jp --xlayouts='jp'
#-- System authorization information
auth --enableshadow --passalgo=sha512
#-- Root password
rootpw --plaintext ${PASSWORD}
#-- Run the Setup Agent on first boot
firstboot --disable
#-- SELinux configuration --
#selinux --enforcing
#selinux --permissive
selinux --disabled
## selinux must be disabled before installation to avoid some error.
#-- Network information
network \
--device=eth0 \
--bootproto=static \
--ip=${IP} \
--netmask=${NETMASK} \
--gateway=${GATEWAY} \
--nameserver=${NAMESERVER} \
--noipv6 \
--activate \
--hostname=${HOSTNAME%%.*}
#-- Firewall configuration
firewall --enabled --ssh
#firewall --enabled --ssh --http
#-- System services
services --enabled="chronyd"
#-- System timezone
timezone America/New_York --isUtc --ntpservers=${NTPSERVERS}
#timezone Asia/Tokyo --isUtc --ntpservers=${NTPSERVERS}

#-- System bootloader configuration
bootloader --location=mbr --boot-drive=vda --append=" crashkernel=auto" 

#-- use /dev/vda for install destination
ignoredisk --only-use=vda
#-- Partition clearing information
clearpart --none --initlabel 
#-- Disk partitioning information
part /boot --fstype="xfs" --ondisk=vda --size=500
part pv.2 --fstype="lvmpv" --ondisk=vda --size=8192 --grow
volgroup centos --pesize=4096 pv.2
logvol / --fstype="xfs" --grow --maxsize=51200 --size=1024 --name=root --vgname=centos
logvol swap --fstype="swap" --size=1024 --name=swap --vgname=centos

#-- Packages Section --
%packages
@^minimal
@core
chrony

#-- skip installing Adaptec SAS firmware
-aic94xx-firmware*
#-- skip installing firmware for wi-fi
-iwl*firmware
#-- skip installing firmware for WinTV Hauppauge PVR
-ivtv-firmware

%end

#-- Post Section --
%post

%end

_EOF_

echo "*** kickstart file created ***"

# ----------------------------------------------------------
# guest install using virt-install command
# ----------------------------------------------------------

echo "*** virt-install starting ***"

virt-install \
--name="${DOM}" \
--ram=${RAM} \
--vcpus=${VCPUS} \
--cpu host \
--os-type=linux \
--os-variant=centos7.0 \
--file="${IMG}" \
--file-size=${SIZE} \
--location="${DVD1}" \
--network="${VIRTUALNETWORK}" \
--initrd-inject="${KSF}" \
--extra-args="ks=file:/${KSF} console=tty0 console=ttyS0 net.ifnames=0 biosdevname=0" \
--noautoconsole

if [ $? -ne 0 ]; then
  # something error happened before guest install
  exit
fi

# Display Console
virsh console ${DOM}

# wait until guest installation is completed
while true; do
  DOMSTATE=`virsh domstate ${DOM}`
  if [ "${DOMSTATE}" = "shut off" ]; then
    sleep 5
    break
  fi
  sleep 5
done

echo "*** virt-install finished ***"

# ----------------------------------------------------------
# begin customize guest
# ----------------------------------------------------------

echo "*** begin customize guest ***"

# --------------------------------------
# import gpg key
# --------------------------------------

echo "*** import gpg key ***"

guestfish -d ${DOM} -i << _EOF_
  # import RPM GPG KEY
  command "rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7"
_EOF_

# --------------------------------------
# upload dvd to guest
# --------------------------------------

echo "*** uploading DVD to guest ***"

echo "*** begin uploading ***"
guestfish -d ${DOM} -i << _EOF_
  #== copy ISO in guest
  copy-in ${DVD1} /media
_EOF_
echo "*** end uploading ***"

# --------------------------------------
# disable all existing repos 
# --------------------------------------

echo "*** disable all existing repos  ***"

guestfish -d ${DOM} -i << _EOF_
  #== before package installation, we need to mount iso
  mkdir-p /media/${DVD1_MNT}
  mount-loop /media/${DVD1_ISO} /media/${DVD1_MNT}

  #== install yum-utils by rpm command
  command "rpm -Uvh /media/${DVD1_MNT}/Packages/yum-utils-1.1.31-34.el7.noarch.rpm /media/${DVD1_MNT}/Packages/python-kitchen-1.1.1-5.el7.noarch.rpm /media/${DVD1_MNT}/Packages/python-chardet-2.2.1-1.el7_1.noarch.rpm /media/${DVD1_MNT}/Packages/libxml2-python-2.9.1-5.el7_1.2.x86_64.rpm"

  #== disable all existing repos
  command "yum-config-manager --disable base"
  command "yum-config-manager --disable updates"
  command "yum-config-manager --disable extras"
  command "yum-config-manager --disable centosplus"
_EOF_

# --------------------------------------
# setup dvd yum repos
# --------------------------------------

echo "*** setup dvd yum repository ***"

F1R=/etc/yum.repos.d/${DVD1_MNT}.repo
F1L=$(mktemp)
cat << _EOF_ > ${F1L}
[${DVD1_MNT}]
name=${DVD1_MNT}
baseurl=file:///media/${DVD1_MNT}/
gpgcheck=1
enabled=1
gpgkey=file:///media/${DVD1_MNT}/RPM-GPG-KEY-CentOS-7
_EOF_

F2R=/etc/rc.d/isomount
F2L=$(mktemp)
cat << _EOF_ > ${F2L}
#
# isomount
#
isomount () {
  local DVD_ISO="\$1"
  local DVD_MNT=\${DVD_ISO%.*}

  if [ -f /media/\${DVD_ISO} ]; then
    mkdir -p /media/\${DVD_MNT}
    mount -t iso9660 -o ro,loop /media/\${DVD_ISO} /media/\${DVD_MNT} &&
      logger "isomount - [/media/\${DVD_MNT}] is mounted at [/media/\${DVD_ISO}]"
  fi
}

# -- iso loop mount #1 --
isomount ${DVD1_ISO}

_EOF_

F3R=/etc/rc.d/rc.local
guestfish -d ${DOM} -i << _EOF_
  #-- upload .repo file
  upload ${F1L} ${F1R}

  #-- upload /etc/rc.d/isomount
  upload ${F2L} ${F2R}

  #-- backup original file
  cp-a ${F3R} ${F3R}-ORG
  #-- update rc.local
  write-append ${F3R} "\n"
  write-append ${F3R} "# centos72 dvd iso mount\n"
  write-append ${F3R} "source /etc/rc.d/isomount\n"
  #-- enable rc.local service
  command "chmod 755 ${F3R}"

_EOF_

# ----------------------------------------------------------
# install packages
# ----------------------------------------------------------

echo "*** install packages ***"

guestfish -d ${DOM} -i << _EOF_
  #-- before package installation, we need to mount iso
  mkdir-p /media/${DVD1_MNT}
  mount-loop /media/${DVD1_ISO} /media/${DVD1_MNT}

  #-- you can install packages here
  #-- install sos
  command "yum install sos -y"
  #-- install httpd
  command "yum install httpd -y"
_EOF_

# --------------------------------------
# grub timeout settings
# --------------------------------------

echo "*** grub timeout settings ***"

F4R=/etc/default/grub
F4L=$(mktemp)
guestfish -d ${DOM} -i << _EOF_
  #-- backup original
  cp-a ${F4R} ${F4R}-ORG
  #-- copy from guest to local
  download ${F4R} ${F4L}
  #-- edit on local
  ! sed -i -e 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' ${F4L}
  ! sed -i -e '/GRUB_CMDLINE_LINUX=/s/ rhgb//g' ${F4L}
  ! sed -i -e '/GRUB_CMDLINE_LINUX=/s/ quiet//g' ${F4L}
  ! sed -i -e '/GRUB_CMDLINE_LINUX=/s/ console=[a-zA-Z0-9,]*//g' ${F4L}
  ! sed -i -e '/GRUB_CMDLINE_LINUX=/s/\"\$/ console=tty0 console=ttyS0\"/' ${F4L}
  ! echo ${F4L}
  ! cat ${F4L}
  #-- copy from local to guest
  upload ${F4L} ${F4R}
  #-- run grub2-mkconfig
  command "grub2-mkconfig -o /boot/grub2/grub.cfg"
_EOF_

# --------------------------------------
# swappiness settings
# --------------------------------------

echo "*** swappiness settings ***"

# swapiness settings file
F5R=/etc/sysctl.d/swappiness.conf

# suppress swappiness
guestfish -d ${DOM} -i << _EOF_
  # "tuned" must be disabled on centos7.2 for changing swappiness
  command "systemctl disable tuned.service"
  write ${F5R} "vm.swappiness = 0\n"
_EOF_

# --------------------------------------
# disable ipv6
# --------------------------------------

echo "*** disable ipv6 ***"

# ipv6 settings file
F6R=/etc/sysctl.d/disable_ipv6.conf

# disable ipv6
guestfish -d ${DOM} -i << _EOF_
  write        ${F6R} "net.ipv6.conf.all.disable_ipv6 = 1\n"
  write-append ${F6R} "net.ipv6.conf.default.disable_ipv6 = 1\n"
_EOF_

# if ipv6 is disabled, postfix is failed to start. this is the workaround.
F7R=/etc/postfix/main.cf
F7L=$(mktemp)
guestfish -d ${DOM} -i << _EOF_
  #-- backup original
  cp-a ${F7R} ${F7R}-ORG
  #-- copy from guest to local
  download ${F7R} ${F7L}
  #-- edit on local
  ! sed -i -e '/^inet_protocols =/s/all/ipv4/g' ${F7L}
  #-- copy from local to guest
  upload ${F7L} ${F7R}
_EOF_

# --------------------------------------
# enable sshd, httpd services
# --------------------------------------

echo "*** enable sshd, httpd services ***"

guestfish -d ${DOM} -i << _EOF_
  command "systemctl enable sshd"
  command "systemctl enable httpd"
_EOF_

# --------------------------------------
# firewall settings
# --------------------------------------

echo "*** firewall settings ***"

guestfish -d ${DOM} -i << _EOF_
  command "systemctl enable firewalld"
  command "firewall-offline-cmd --remove-service=dhcpv6-client"
  command "firewall-offline-cmd --zone=public --add-service=ssh"
  command "firewall-offline-cmd --zone=public --add-service=http"
  command "firewall-offline-cmd --zone=public --add-service=https"
_EOF_

# ----------------------------
# selinux enabled at next reboot
# ----------------------------

echo "*** selinux enabled ***"

F9R=/etc/selinux/config
F9L=$(mktemp)
guestfish -d ${DOM} -i << _EOF_
  touch /.autorelabel
  #-- backup original file
  #cp-a ${F9R} ${F9R}-ORG
  #-- copy file from guest to local
  download ${F9R} ${F9L}
  #-- edit file on local
  ! sed -i 's/^SELINUX=.*/SELINUX=enforcing/' ${F9L}
  ! echo ${F9L}
  ! cat ${F9L}
  #-- copy file from local to guest
  upload ${F9L} ${F9R}
_EOF_

# ----------------------------
# /etc/hosts
# ----------------------------

echo "*** editing /etc/hosts ***"

F11R=/etc/hosts
guestfish -d ${DOM} -i << _EOF_
  #-- backup original file
  cp-a ${F11R} ${F11R}-ORG
  #-- update
  write-append ${F11R} "\n"
  write-append ${F11R} "${IP} ${HOSTNAME} ${HOSTNAME%%.*}\n"

_EOF_

# ----------------------------------------------------------
# end customize guest
# ----------------------------------------------------------

echo "*** finish all job ***"

# ----------------------------------------------------------
# EOJ
# ----------------------------------------------------------

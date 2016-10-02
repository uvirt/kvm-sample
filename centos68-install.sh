#!/bin/bash

export LANG=C
echo "*** begin installation job ***"

# ----------------------------------------------------------
# Parameters
# ----------------------------------------------------------

#-- Guest Name (Domain Name)
DOM=centos68
#-- Guest Image File
IMG=/var/lib/libvirt/images/${DOM}.qcow2
#-- Kickstart file
KSF=${DOM}-ks.cfg

#-- Guest Memory Size (MB)
RAM=1024
#RAM=2048
#-- Guest Disk Size (GB)
SIZE=16.0
#SIZE=20.0

#-- Install Media (ISO)  full path
DVD1=/var/lib/libvirt/images/CentOS-6.8-x86_64-bin-DVD1.iso
DVD2=/var/lib/libvirt/images/CentOS-6.8-x86_64-bin-DVD2.iso
#-- dvd basename   ex. "CentOS-6.8-x86_64-bin-DVD1.iso"
DVD1_ISO=$(basename $DVD1)
DVD2_ISO=$(basename $DVD2)
#-- dvd mount point name  ex. "CentOS-6.8-x86_64-bin-DVD1"
DVD1_MNT=${DVD1_ISO%.*}
DVD2_MNT=${DVD2_ISO%.*}

#-- root password
PASSWORD=password
#-- Hostname
HOSTNAME=centos68.example.com
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
# clear old vm if existing
# ----------------------------------------------------------

echo "*** clear old vm ***"

# stop domain forcefully
virsh destroy ${DOM} >/dev/null 2>&1
# undefine domain
virsh undefine ${DOM} --remove-all-storage >/dev/null 2>&1
# remove domain image file
rm -f ${IMG} >/dev/null 2>&1

# ----------------------------------------------------------
# create kickstart file
# ----------------------------------------------------------

echo "*** kickstart file creating ***"

cat << _EOF_ > ${KSF}
#-- Install OS instead of upgrade --
install
#-- Use CDROM installation media --
cdrom
#-- graphical or text install --
text
#-- poweroff after installation --
poweroff
#halt
#reboot

#-- System language --
lang en_US.UTF-8
#lang ja_JP.UTF-8
#-- Keyboard layouts --
keyboard us
#keyboard jp106
#-- System authorization --
auth --enableshadow --passalgo=sha512
#-- Root password --
rootpw --plaintext ${PASSWORD}
#-- Run the Setup Agent on first boot --
firstboot --disable
#-- SELinux configuration --
#selinux --enforcing
#selinux --permissive
selinux --disabled
## at beginning, it's better to set selinux disabled to avoid some error
#-- Network information --
network \
--onboot yes \
--device eth0 \
--bootproto static \
--ip ${IP} \
--netmask ${NETMASK} \
--gateway ${GATEWAY} \
--nameserver ${NAMESERVER} \
--noipv6 \
--hostname ${HOSTNAME}
#-- Services  --
services --enabled ntpd,ntpdate
#-- Firewall configuration --
firewall --enabled --ssh
#-- System timezone --
timezone America/New_York
#timezone Asia/Tokyo
#-- System bootloader configuration --
bootloader --location=mbr

#-- Disk partitioning --
zerombr
clearpart --all --initlabel
part /boot --fstype="ext4" --size=500
part pv.2 --size=8192 --grow
volgroup VolGroup --pesize=4096 pv.2
logvol / --fstype="ext4" --name=lv_root --vgname=VolGroup --size=1024 --maxsize=51200 --grow
logvol swap --fstype="swap" --name=lv_swap --vgname=VolGroup --size=1024

#-- Packages Section --
%packages
@core
yum-utils
%end

#-- Post Section --
%post
#-- NTP setting --
cp -np /etc/ntp.conf{,-ORG}
NTPSORG=\$(grep -n -e '^server\s.*' /etc/ntp.conf)
NTPSORG_LAST=\$(echo "\${NTPSORG}" | tail -n1)
NTPSORG_LASTPOS=\${NTPSORG_LAST%%:*}
NTPSERVERS=${NTPSERVERS}
IFS=', ' read -r -a NTPSERVER <<< "\${NTPSERVERS}"
NTPSNEW=""
for x in "\${NTPSERVER[@]}"; do NTPSNEW=\${NTPSNEW}"server \${x} iburst\n"; done
NTPSNEW="\$(echo "\${NTPSNEW}" | sed -e 's/\\n\$//')"
sed -i -e '/^server\s/s/^server/#server/' /etc/ntp.conf
sed -i -e "\${NTPSORG_LASTPOS}a\${NTPSNEW}" /etc/ntp.conf
sed -i -e '/^#server\s/d' /etc/ntp.conf

%end

_EOF_

echo "*** kickstart file created ***"

# ----------------------------------------------------------
# guest install using virt-install command
# ----------------------------------------------------------

echo "*** virt-install starting ***"

virt-install \
--name=${DOM} \
--ram=${RAM} \
--vcpus=1 \
--os-type=linux \
--os-variant=centos6.0 \
--file=${IMG} \
--file-size=${SIZE} \
--location=${DVD1} \
--network=bridge:virbr0 \
--initrd-inject=${KSF} \
--extra-args="ks=file:/${KSF} console=tty0 console=ttyS0" \
--noautoconsole

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
  #-- import RPM GPG KEY --
  command "rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6"
  command "rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Debug-6"
  command "rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Security-6"
  command "rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Testing-6"
_EOF_

# --------------------------------------
# disable all existing repos 
# --------------------------------------

echo "*** disable all existing repos  ***"

guestfish -d ${DOM} -i << _EOF_
  #-- disable all existing repos --
  command "yum-config-manager --disable base"
  command "yum-config-manager --disable updates"
  command "yum-config-manager --disable extras"
  command "yum-config-manager --disable centosplus"
_EOF_

# --------------------------------------
# setup dvd yum repos
# --------------------------------------

echo "*** setup dvd yum repository ***"

FR1=/etc/yum.repos.d/${DVD1_MNT}.repo
FL1=$(mktemp)
cat << _EOF_ > ${FL1}
[${DVD1_MNT}]
name=${DVD1_MNT}
baseurl=file:///media/${DVD1_MNT}/
        file:///media/${DVD2_MNT}/
gpgcheck=1
enabled=1
gpgkey=file:///media/${DVD1_MNT}/RPM-GPG-KEY-CentOS-6
       file:///media/${DVD1_MNT}/RPM-GPG-KEY-CentOS-Debug-6
       file:///media/${DVD1_MNT}/RPM-GPG-KEY-CentOS-Security-6
       file:///media/${DVD1_MNT}/RPM-GPG-KEY-CentOS-Testing-6
_EOF_

FR2=/etc/rc.d/isomount
FL2=$(mktemp)
cat << _EOF_ > ${FL2}
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

# -- iso loop mount #2 --
isomount ${DVD2_ISO}

_EOF_

FR3=/etc/rc.d/rc.local
guestfish -d ${DOM} -i << _EOF_
  #-- upload .repo file --
  upload ${FL1} ${FR1}

  #-- upload /etc/rc.d/isomount --
  upload ${FL2} ${FR2}

  #-- backup original file --
  cp-a ${FR3} ${FR3}-ORG
  #-- update /etc/rc.d/rc.local --
  write-append ${FR3} "\n"
  write-append ${FR3} "# centos68 dvd iso mount\n"
  write-append ${FR3} "source /etc/rc.d/isomount\n"

  #-- enable rc.local service --
  command "chmod 755 ${FR3}"

_EOF_

if [ -f ${DVD1} ]; then
  echo "*** uploading DVD1 ***"
  guestfish -d ${DOM} -i << _EOF_
  #-- copy ISO in guest --
  copy-in ${DVD1} /media
_EOF_
fi

if [ -f ${DVD2} ]; then
  echo "*** uploading DVD2 ***"
  guestfish -d ${DOM} -i << _EOF_
  #-- copy ISO in guest --
  copy-in ${DVD2} /media
_EOF_
fi

# ----------------------------------------------------------
# install packages
# ----------------------------------------------------------

echo "*** install packages ***"

guestfish -d ${DOM} -i << _EOF_
  #-- first we need to mount iso --
  mkdir-p /media/${DVD1_MNT}
  mount-loop /media/${DVD1_ISO} /media/${DVD1_MNT}

  #-- you can install packages here --
  #-- install sos --
  command "yum install sos -y"
  #-- install ntpdate --
  command "yum install ntpdate -y"
  #-- install httpd --
  command "yum install httpd -y"
_EOF_

# --------------------------------------
# grub timeout settings
# --------------------------------------

echo "*** grub timeout settings ***"

FR4=/boot/grub/grub.conf
FL4=$(mktemp)
guestfish -d ${DOM} -i << _EOF_
  #-- backup original file --
  cp-a ${FR4} ${FR4}-ORG
  #-- copy file from guest to local --
  download ${FR4} ${FL4}
  #-- edit file on local --
  ! sed -i -e 's/^timeout=.*/timeout=0/' ${FL4}
  ! sed -i -e '/kernel/s/ rhgb//g' ${FL4}
  ! sed -i -e '/kernel/s/ quiet//g' ${FL4}
  ! sed -i -e '/kernel/s/ console=[a-zA-Z0-9,]*//g' ${FL4}
  ! sed -i -e '/kernel/s/\$/ console=tty0 console=ttyS0/' ${FL4}
  ! echo ${FL4}
  ! cat ${FL4}
  #-- copy file from local to guest --
  upload ${FL4} ${FR4}
_EOF_

# --------------------------------------
# swappiness settings
# --------------------------------------

echo "*** swappiness settings ***"

#-- swapiness settings file --
FR5=/etc/sysctl.d/swappiness.conf

#-- suppress swappiness --
guestfish -d ${DOM} -i << _EOF_
  write ${FR5} "vm.swappiness = 0\n"
_EOF_

# --------------------------------------
# disable ipv6
# --------------------------------------

echo "*** disable ipv6 ***"

#-- ipv6 settings file --
FR6=/etc/sysctl.d/disable_ipv6.conf

#-- disable ipv6 --
guestfish -d ${DOM} -i << _EOF_
  write        ${FR6} "net.ipv6.conf.all.disable_ipv6 = 1\n"
  write-append ${FR6} "net.ipv6.conf.default.disable_ipv6 = 1\n"
_EOF_

# --------------------------------------
# enable sshd, httpd services
# --------------------------------------

echo "*** enable sshd, httpd services ***"

guestfish -d ${DOM} -i << _EOF_
  command "chkconfig sshd on"
  command "chkconfig httpd on"
_EOF_

# --------------------------------------
# firewall settings
# --------------------------------------

echo "*** firewall settings ***"

FR7=/etc/sysconfig/system-config-firewall
FR8=/etc/sysconfig/iptables
guestfish -d ${DOM} -i << _EOF_
  #-- backup original file --
  cp-a ${FR7} ${FR7}-ORG
  cp-a ${FR8} ${FR8}-ORG

  #-- open firewall port --
  command "lokkit --service=ssh --nostart"
  command "lokkit --service=http --nostart"
  command "lokkit --service=https --nostart"
_EOF_

# --------------------------------------
# selinux enabled at next reboot
# --------------------------------------

echo "*** selinux enabled ***"

FR9=/etc/selinux/config
FL9=$(mktemp)
guestfish -d ${DOM} -i << _EOF_
  touch /.autorelabel
  #-- backup original file --
  cp-a ${FR9} ${FR9}-ORG
  #-- copy file from guest to local --
  download ${FR9} ${FL9}
  #-- edit file on local --
  ! sed -i 's/^SELINUX=.*/SELINUX=enforcing/' ${FL9}
  ! echo ${FL9}
  ! cat ${FL9}
  #-- copy file from local to guest --
  upload ${FL9} ${FR9}
_EOF_

# ----------------------------------------------------------
# end customize guest
# ----------------------------------------------------------

echo "*** finish all job ***"

# ----------------------------------------------------------
# EOJ
# ----------------------------------------------------------


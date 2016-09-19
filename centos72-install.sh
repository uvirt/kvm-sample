#!/bin/sh

echo "*** begin installation job ***"

# ----------------------------------------------------------
# Parameters
# ----------------------------------------------------------

# Guest Name (Domain Name)
DOM=centos72
# Guest Image File
IMG=/var/lib/libvirt/images/${DOM}.qcow2
# Kickstart file
KSF=${DOM}-ks.cfg

# Guest Memory Size (MB)
RAM=2048
# Guest Disk Size (GB)
SIZE=16

# Install Media (ISO)  full path
DVD=/var/lib/libvirt/images/CentOS-7-x86_64-DVD-1511.iso
###DVD=/var/lib/libvirt/images//CentOS-7-x86_64-Everything-1511.iso
# dvd basename   ex. "CentOS-7-x86_64-DVD-1511.iso"
DVD_ISO=$(basename $DVD)
# dvd mount point name  ex. "CentOS-7-x86_64-DVD-1511"
DVD_MNT=${DVD_ISO%.*}

# root password
PASSWORD=password
# Hostname
HOSTNAME=centos72.example.com
# IP Address
IP=192.168.122.110
# Netmask
NETMASK=255.255.255.0
# Gateway
GATEWAY=192.168.122.1
# DNS server
NAMESERVER=8.8.8.8,8.8.4.4
# NTP server
NTPSERVERS=0.centos.pool.ntp.org,1.centos.pool.ntp.org,2.centos.pool.ntp.org,3.centos.pool.ntp.org

# ----------------------------------------------------------
# Initial Check
# ----------------------------------------------------------

errcnt=0

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
    ((errcnt++))
    echo "ERROR${errcnt}: This script must be run as root." 1>&2
fi

# Make sure dvd image file exists under /var/lib/libvirt/images dir
if [ ! -f ${DVD} ]; then
    ((errcnt++))
    echo "ERROR${errcnt}: DVD install media [${DVD_ISO}] must be copied under \"/var/lib/libvirt/images\" dir." 1>&2
fi

# exit if error
if [ $errcnt -gt 0 ]; then
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
# Install OS instead of upgrade
install
# shutdown after installation
shutdown
# System authorization information
auth --enableshadow --passalgo=sha512
# Use CDROM installation media
cdrom
# graphical or text install
text
# Run the Setup Agent on first boot
firstboot --disable
# use /dev/vda for install destination
ignoredisk --only-use=vda
# SELinux configuration
selinux --enforcing
# Keyboard layouts
##keyboard --vckeymap=jp --xlayouts='jp'
keyboard --vckeymap=us --xlayouts='us'
# System language
##lang ja_JP.UTF-8
lang en_US.UTF-8
# Network information
network \
--device=eth0 \
--bootproto=static \
--ip=${IP} \
--netmask=${NETMASK} \
--gateway=${GATEWAY} \
--nameserver=${NAMESERVER} \
--noipv6 \
--activate
network --hostname=${HOSTNAME}
# Firewall configuration
##firewall --enabled --ssh --http
firewall --enabled --ssh
# Root password
rootpw --plaintext ${PASSWORD}
# System services
services --enabled="chronyd"
# System timezone
##timezone Asia/Tokyo --isUtc --ntpservers=${NTPSERVERS}
timezone America/New_York --isUtc --ntpservers=${NTPSERVERS}
# System bootloader configuration
bootloader --location=mbr --boot-drive=vda --append=" crashkernel=auto" 
# Partition clearing information
clearpart --none --initlabel 
# Disk partitioning information
part /boot --fstype="xfs" --ondisk=vda --size=500
part pv.20 --fstype="lvmpv" --ondisk=vda --size=8192 --grow
volgroup centos --pesize=4096 pv.20
logvol swap --fstype="swap" --size=921 --name=swap --vgname=centos
logvol / --fstype="xfs" --grow --maxsize=51200 --size=1024 --name=root --vgname=centos

### Packages Section ###
%packages
@core
kexec-tools
yum-utils

%end

### Post Section ###
%post

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
--os-variant=centos7.0 \
--file=${IMG} \
--file-size=${SIZE} \
--location=${DVD} \
--network=bridge:virbr0 \
--initrd-inject=${KSF} \
--extra-args="ks=file:/${KSF} console=tty0 console=ttyS0" \
--noautoconsole

# wait until guest installation is completed
finished="0";
while [ "${finished}" = "0" ]; do
  sleep 5
  domstate=`virsh domstate ${DOM}`
  if [ "${domstate}" = "shut off" ]; then
    finished=1;
  fi
done
sleep 5

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
  command "rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Debug-7"
  command "rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Testing-7"
_EOF_

# --------------------------------------
# disable all existing repos 
# --------------------------------------

echo "*** disable all existing repos  ***"

guestfish -d ${DOM} -i << _EOF_
  # disable all existing repos 
  command "yum-config-manager --disable base"
  command "yum-config-manager --disable updates"
  command "yum-config-manager --disable extras"
  command "yum-config-manager --disable centosplus"
_EOF_

# --------------------------------------
# setup dvd yum repos
# --------------------------------------

echo "*** setup dvd yum repository ***"

F1R=/etc/yum.repos.d/${DVD_MNT}.repo
F1L=$(mktemp)
cat << _EOF_ > ${F1L}
[${DVD_MNT}]
name=${DVD_MNT}
baseurl=file:///media/${DVD_MNT}/
gpgcheck=1
enabled=1
gpgkey=file:///media/${DVD_MNT}/RPM-GPG-KEY-CentOS-7
       file:///media/${DVD_MNT}/RPM-GPG-KEY-CentOS-Testing-7
_EOF_

F2R=/etc/rc.d/isomount
F2L=$(mktemp)
cat << "_EOF_" > ${F2L}
#
# isomount
#
isomount () {
  local DVD_ISO="$1"
  local DVD_MNT=${DVD_ISO%.*}

  if [ -f /media/${DVD_ISO} ]; then
    mkdir -p /media/${DVD_MNT}
    mount -t iso9660 -o ro,loop /media/${DVD_ISO} /media/${DVD_MNT} &&
      logger "isomount - [/media/${DVD_MNT}] is mounted at [/media/${DVD_ISO}]"
  fi
}

# -- iso loop mount #1 --
isomount CentOS-7-x86_64-DVD-1511.iso

### -- iso loop mount #2 --
##isomount CentOS-7-x86_64-Everything-1511.iso

_EOF_

F3R=/etc/rc.d/rc.local
guestfish -d ${DOM} -i << _EOF_
  # copy ISO in guest
  copy-in ${DVD} /media

  # upload /etc/rc.d/isomount
  upload ${F2L} ${F2R}

  # backup /etc/rc.d/rc.local original
  cp-a ${F3R} ${F3R}-ORG
  # update /etc/rc.d/rc.local
  write-append ${F3R} "\n"
  write-append ${F3R} "# centos72 dvd iso mount\n"
  write-append ${F3R} "source /etc/rc.d/isomount\n"
  # enable rc.local service
  command "chmod 755 ${F3R}"
  command "systemctl restart rc-local.service"
  command "systemctl status rc-local.service"

  # upload *.repo file
  upload ${F1L} ${F1R}
_EOF_


# ----------------------------------------------------------
# install sos package
# ----------------------------------------------------------

echo "*** install sos package ***"

guestfish -d ${DOM} -i << _EOF_
  # mount iso
  command "/etc/rc.d/rc.local"
  # install sos
  command "yum install sos -y"
_EOF_

# --------------------------------------
# grub timeout settings
# --------------------------------------

echo "*** grub timeout settings ***"

F1R=/etc/default/grub
F1L=$(mktemp)
guestfish -d ${DOM} -i << _EOF_
  # backup original /etc/default/grub
  cp-a ${F1R} ${F1R}-ORG
  # copy from guest to local
  download ${F1R} ${F1L}
  # edit /etc/default/grub on local
  ! sed -i -e 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' ${F1L}
  ! sed -i -e '/GRUB_CMDLINE_LINUX=/s/ rhgb//g' ${F1L}
  ! sed -i -e '/GRUB_CMDLINE_LINUX=/s/ quiet//g' ${F1L}
  ! sed -i -e '/GRUB_CMDLINE_LINUX=/s/ console=[a-zA-Z0-9,]*//g' ${F1L}
  ! sed -i -e '/GRUB_CMDLINE_LINUX=/s/\"\$/ console=tty0 console=ttyS0\"/' ${F1L}
  ! echo ${F1L}
  ! cat ${F1L}
  # copy from local to guest
  upload ${F1L} ${F1R}
  # run grub2-mkconfig
  command "grub2-mkconfig -o /boot/grub2/grub.cfg"
_EOF_

# --------------------------------------
# swappiness settings
# --------------------------------------

echo "*** swappiness settings ***"

# swapiness settings file
F1R=/etc/sysctl.d/swappiness.conf

# suppress swappiness
guestfish -d ${DOM} -i << _EOF_
  write ${F1R} "vm.swappiness = 0\n"
_EOF_

# --------------------------------------
# disable ipv6
# --------------------------------------

echo "*** disable ipv6 ***"

# ipv6 settings file
F1R=/etc/sysctl.d/disable_ipv6.conf

# disable ipv6
guestfish -d ${DOM} -i << _EOF_
  write        ${F1R} "net.ipv6.conf.all.disable_ipv6 = 1\n"
  write-append ${F1R} "net.ipv6.conf.default.disable_ipv6 = 1\n"
_EOF_

# --------------------------------------
# enable sshd, httpd services
# --------------------------------------

echo "*** enable sshd, httpd services ***"

guestfish -d ${DOM} -i << _EOF_
  command "systemctl enable sshd"
  #command "systemctl enable httpd"
_EOF_

# --------------------------------------
# firewall settings
# --------------------------------------

echo "*** firewall settings ***"

guestfish -d ${DOM} -i << _EOF_
  command "systemctl enable firewalld"
  command "firewall-offline-cmd --remove-service=dhcpv6-client"
  command "firewall-offline-cmd --zone=public --add-service=ssh"
  #command "firewall-offline-cmd --zone=public --add-service=http"
  #command "firewall-offline-cmd --zone=public --add-service=https"
_EOF_

# ----------------------------------------------------------
# end customize guest
# ----------------------------------------------------------

echo "*** finish all job ***"

# ----------------------------------------------------------
# EOJ
# ----------------------------------------------------------

# kvm-sample
Unattended install of CentOS 6.8 and CentOS 7.x vm on KVM host

## Envinronment

Fedora 25 Workstation 64 bit KVM host.

## How to install KVM software on Fedora 25 workstation

    dnf groupinstall virtualization --setopt=group_package_types=mandatory,default,optional -y
    dnf install qemu libvirt-client virt-manager virt-viewer libguestfs libguestfs-tools virt-top -y

## Enable nested virtualization in KVM

    echo "options kvm_intel nested=1" > /etc/modprobe.d/kvm_intel.conf
    echo "options kvm_amd nested=1" > /etc/modprobe.d/kvm_amd.conf

## Download Guest OS ISO Media under /var/lib/libvirt/images dir

### CentOS 6.8
Before executing the script, you need to copy CentOS 6.8 install media under the "/var/lib/libvirt/images" directory on KVM host. DVD2 is optional.

    cd /var/lib/libvirt/images
    wget http://ftp.riken.jp/Linux/centos/6.8/isos/x86_64/CentOS-6.8-x86_64-bin-DVD1.iso
    wget http://ftp.riken.jp/Linux/centos/6.8/isos/x86_64/CentOS-6.8-x86_64-bin-DVD2.iso

### CentOS 7.3
Before executing the script, you need to copy CentOS 7.3 install media under the "/var/lib/libvirt/images" directory on KVM host.

    cd /var/lib/libvirt/images
    wget http://ftp.riken.jp/Linux/centos/7.3.1611/isos/x86_64/CentOS-7-x86_64-DVD-1611.iso

## How to run this script

### CentOS 6.8
    wget https://raw.githubusercontent.com/uvirt/kvm-sample/master/centos68-install.sh
    sh centos68-install.sh

### CentOS 7.3
    wget https://raw.githubusercontent.com/uvirt/kvm-sample/master/centos73-install.sh
    sh centos73-install.sh

And wait until the message "finish all job" is displayed.
It takes approximately 15 minutes.

## How to start the guest and connect via ssh

### CentOS 6.8
    virsh list --all
    virsh start centos68
    virsh console centos68
    login as root.
    password is 'password'

    You can connect via ssh:
    ssh-keygen -R 192.168.122.110
    ssh root@192.168.122.110
    password is 'password'

### CentOS 7.3
    virsh list --all
    virsh start centos73
    virsh console centos73
    login as root.
    password is 'password'

    You can connect via ssh:
    ssh-keygen -R 192.168.122.110
    ssh root@192.168.122.110
    password is 'password'

## How to use yum repository on internet

    yum-config-manager --enable base
    yum-config-manager --enable updates
    yum-config-manager --enable extras
    yum-config-manager --enable centosplus





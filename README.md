# kvm-sample
Unattended install of CentOS 6.8 and CentOS 7.2 vm on KVM host

https://www.uvirt.com/wp1/20160307-1601

## Envinronment

Fedora 24 Workstation 64 bit KVM host.

## How to install kvm software on Fedora 24 workstation

    dnf groupinstall virtualization --setopt=group_package_types=mandatory,default,optional -y
    dnf install libguestfs libguestfs-tools -y

## Download Guest OS ISO Media under /var/lib/libvirt/images dir

### CentOS 6.8
Before executing the script, you need to copy CentOS 6.8 install media under the "/var/lib/libvirt/images" directory on KVM host. DVD2 is optional.

    cd /var/lib/libvirt/images
    wget http://ftp.riken.jp/Linux/centos/6.8/isos/x86_64/CentOS-6.8-x86_64-bin-DVD1.iso
    wget http://ftp.riken.jp/Linux/centos/6.8/isos/x86_64/CentOS-6.8-x86_64-bin-DVD2.iso

### CentOS 7.2
Before executing the script, you need to copy CentOS 7.2 install media under the "/var/lib/libvirt/images" directory on KVM host.

    cd /var/lib/libvirt/images
    wget http://ftp.riken.jp/Linux/centos/7.2.1511/isos/x86_64/CentOS-7-x86_64-DVD-1511.iso

## How to run this script

### CentOS 6.8
    wget https://raw.githubusercontent.com/uvirt/kvm-sample/master/centos68-install.sh
    sh centos68-install.sh

### CentOS 7.2
    wget https://raw.githubusercontent.com/uvirt/kvm-sample/master/centos72-install.sh
    sh centos72-install.sh

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

### CentOS 7.2
    virsh list --all
    virsh start centos72
    virsh console centos72
    login as root.
    password is 'password'

    You can connect via ssh:
    ssh-keygen -R 192.168.122.110
    ssh root@192.168.122.110
    password is 'password'





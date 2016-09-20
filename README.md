# kvm-sample
sample script - Unattended install of CentOS 7.2 guest

For details, please see following.
https://www.uvirt.com/wp1/20160307-1601

## Envinronment

Fedora 24 Workstation 64 bit KVM host.

## How to install kvm software on Fedora 24 workstation

    dnf groupinstall virtualization --setopt=group_package_types=mandatory,default,optional -y
    dnf install libguestfs libguestfs-tools -y

## Copy Guest OS ISO Media

Before executing the script, you need to copy CentOS 7.2 install media to /var/lib/libvirt/images directory on KVM host.

    cd /var/lib/libvirt/images
    wget http://ftp.riken.jp/Linux/centos/7/isos/x86_64/CentOS-7-x86_64-DVD-1511.iso

## How to run this script

    wget https://raw.githubusercontent.com/uvirt/kvm-sample/master/centos72-install.sh
    sh centos72-install.sh

And wait until "finish all job" message is displayed.
It takes approximately 15 minutes.



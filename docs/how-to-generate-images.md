**How to use the module**

Download latest RHCOS image from [https://releases-redhat-coreos.cloud.paas.upshift.redhat.com/](https://releases-redhat-coreos.cloud.paas.upshift.redhat.com/) . For example: [https://releases-redhat-coreos.cloud.paas.upshift.redhat.com/storage/releases/maipo/47.206/redhat-coreos-maipo-47.206-qemu.qcow2.gz](https://releases-redhat-coreos.cloud.paas.upshift.redhat.com/storage/releases/maipo/47.206/redhat-coreos-maipo-47.206-qemu.qcow2.gz)

Uncompress it: gunzip redhat-coreos-maipo-47.206-qemu.qcow2.gz

You need to be inside a vm running that image. So you need to create a vm with that qcow2 base image, and inject ssh keys using an ignition file.

The ignition file would look something like this:

    {
       "ignition":{
          "config":{
          },
          "security":{
             "tls":{
                "certificateAuthorities":[
                   {
                      "source":"<some source hash>",
                      "verification":{
                      }
                   }
                ]
             }
          },
          "timeouts":{
          },
          "version":"2.2.0"
       },
       ...
       "passwd":{
          "users":[
             {
                "name":"core",
                "sshAuthorizedKeys":[
                   "<public key>"
                ]
             }
          ]
       },
       ...
    }


Add something like this to your libvirt domain XML:

    <qemu:commandline>
    <qemu:arg value='-fw_cfg'/>
    <qemu:arg value='name=opt/com.coreos/config,file=<path_to_ign_file>'/>
    </qemu:commandline>

Once you have the VM up and running, you need to ssh into it:

    ssh core@<ip_of_vm>

And start entering the following commands:

    sudo su
    rpm-ostree usroverlay
    toolbox
This will take you to a container where you can install the needed dependencies, that has the root filesystem installed inside /media/root. So you can start installing packages on the container, and move the needed dependencies to the root filesystem. We will start by copying the coreos-dracut project:

    yum -y install git
    cd /tmp
    git clone https://github.com/yrobla/coreos-dracut.git
    cp -R /tmp/coreos-dracut /media/root/tmp/
    exit

Once you are in the root filesystem as well, you need to move the needed files to the dracut directories:

    mkdir /usr/lib/dracut/modules.d/90coreos
    cp -R /tmp/coreos-dracut/dracut-module/* /usr/lib/dracut/modules.d/90coreos/

Time to install dependencies again. So we will start the toolbox container, and continue installing packages:

    podman start toolbox-root
    toolbox
    yum install -y wget kbd dialog bc pv
    yum -y install /usr/share/syslinux/isolinux.bin
    yum -y install genisoimage

Then copy the binary into root path:

    cp /usr/bin/wget /media/root/usr/bin/
    cp /usr/bin/dialog /media/root/usr/bin/
    cp /usr/bin/chvt /media/root/usr/bin/
    cp /usr/bin/dc /media/root/usr/bin/
    cp /usr/bin/pv /media/root/usr/bin/
    cp -R /usr/share/syslinux /media/root/usr/share/
    cp /usr/lib64/libdialog.so.15* /media/root/usr/lib64/
    cp /usr/lib64/libncurses* /media/root/usr/lib64/
    cp /usr/lib64/libtinfo.so.6* /media/root/usr/lib64/
    cp /usr/bin/mkisofs /media/root/usr/bin
    exit

To generate the image, we need to have the vmlinuz of the ostree in the right /boot path:

    cp /boot/ostree/redhat-coreos-maipo-<id_ostree>/vmlinuz-3.10.0-957.1.3.el7.x86_64 /boot/

Before executing mkisofs we need to download some specific dependencies. So execute the following commands:

    cd /tmp/
    curl https://rpmfind.net/linux/fedora/linux/releases/27/Everything/x86_64/os/Packages/l/libusal-1.1.11-37.fc27.x86_64.rpm -o libusal.rpm
    rpm2cpio ./libusal.rpm | cpio -idmv
    cp usr/lib64/libusal.so.0 /usr/lib64/
    cp usr/lib64/librols.so.0* /usr/lib64

And now switch to build directory, and execute the make commands:

    make clean && make x86_64

Images are created on:
- build/x86_64/coreos.iso
- build/x86_64/isolinux/vmlinuz
- build/x86_64/isolinux/initrd.img

Extract and publish them to start using, either for PXE boot or for virtual media.


#!/bin/bash

SILENT=false
MRPROPER=false
NICE_CMD="nice -n 19 ionice -c2"
CONFIG_FILE=/proc/config.gz

[ -f /etc/gentoo-upgrade.conf ] && source /etc/gentoo-upgrade.conf

# available parameters
eval set -- "`getopt -o hsc: --long help,silent,mrproper,config: -- \"$@\"`"

while true ; do
        case "$1" in
                -h|--help)
                        echo "Usage: kernel-rebuild.sh [keys]..."
                        echo "Keys:"
                        echo -e "-h, --help\t\tShow this help and exit."
                        echo -e "-s, --silent\t\tMake with silentoldconfig."
                        echo -e "--mrproper\t\tClean kernel sources before rebuild."
                        echo -e "-c, --config [CONFIG]\tPath to custom kernel config."
                        echo
                        echo -e "This program works on any GNU/Linux with GNU Baurne's shell"
                        echo -e "Report bugs to <mecareful@gmail.com>"
                        exit 0
                        ;;
                -s|--silent) SILENT=true ; shift ;;
                --mrproper) MRPROPER=true ; shift ;;
                -c|--config) CONFIG_FILE=$2 ; shift 2 ;;
	--) shift ; break ;;
	*) echo "Internal error!" ; exit -1 ;;
        esac
done

# remounting file systems ro->rw
for fs in $RW_REMOUNT; do
	if [[ "$fs" =~ ^/+usr/*$ || "$fs" =~ ^/+boot/*$ ]]; then
		echo "remounting $fs -> rw"
		mount -o remount,rw $fs
		[ 0 -ne $? ] && echo "mount -o remount,rw $fs failed ;-( =======" && exit -1
	fi
done

cd /usr/src/linux
[ "$?" != "0" ] && echo /usr/src/linux doesn\'t exist && exit -1

if [ true == "$MRPROPER" ]; then
        make clean && make mrproper
        [ 0 -ne $? ] && echo "make clean && make mrproper failed ;-( =======" && exit -1
fi
echo CONFIG_FILE=$CONFIG_FILE
zcat $CONFIG_FILE >.config 2>/dev/null || cat $CONFIG_FILE >.config
[ "$?" != "0" ] && echo "$CONFIG_FILE doesn't exist or /usr mounted as read-only" && exit -1

if [ true == "$SILENT" ]; then
        yes "" | make silentoldconfig
        [ "$?" != "0" ] && echo "======= yes \"\" | make silentoldconfig failed ;-( =======" && exit -1
else
        make MENUCONFIG_MODE=single_menu MENUCONFIG_COLOR=mono menuconfig
        [ "$?" != "0" ] && echo "======= make menuconfig failed ;-( =======" && exit -1
fi

# aufs3 patches
if [[ `qlist -IC sys-fs/aufs3 | wc -l` != 0 ]]; then
	make modules_prepare
	[ 0 -ne $? ] && echo "make modules_prepare failed ;-(" && exit -1
	emerge -1 sys-fs/aufs3
	[ 0 -ne $? ] && echo "emerge -1 sys-fs/aufs3 failed ;-(" && exit -1
fi

# disable distcc for -march=native -mtune=native

grep 'CONFIG_X86_MARCH_NATIVE=y' .config &>/dev/null
jobs=$((`getconf _NPROCESSORS_ONLN`+1))
if [[ "$?" == 0 ]]; then
	$NICE_CMD make -j$jobs
	[ 0 -ne $? ] && echo "Kernel build failed ;-(" && exit -1
else
	# pump make -j$((jobs*3)) || make -j$jobs
	$NICE_CMD make -j$jobs
	[ 0 -ne $? ] && echo "Kernel build failed ;-(" && exit -1
fi

$NICE_CMD make install
$NICE_CMD make modules_install

REVISION=`cat /usr/src/linux/include/config/kernel.release`

which dracut &>/dev/null && $NICE_CMD dracut --hostonly --force /boot/initramfs-$REVISION.img $REVISION

[ -f /boot/grub/grub.conf ] && \
sed -i "s~\/boot\/vmlinuz-[0-9][^ ]*~\/boot\/vmlinuz-$REVISION~g;
        s~\/boot\/initramfs-[0-9][^ ]*~\/boot\/initramfs-$REVISION.img~g" \
        /boot/grub/grub.conf

[ -f /boot/grub2/grub.cfg ] && grub2-mkconfig -o /boot/grub2/grub.cfg

echo "--------- Rebuilding kernel modules ---------"
emerge -1qv @module-rebuild
[ 0 -ne $? ] && echo "Upgrading kernel modules failed ;-(" && exit -1

cd $pwdtmp 

# remounting file systems rw->ro
for fs in $RO_REMOUNT; do
	if [[ "$fs" =~ ^/+usr/*$ || "$fs" =~ ^/+boot/*$ ]]; then
		echo "remounting $fs -> ro"
		mount -f -o remount,ro $fs
		[ 0 -ne $? ] && echo "mount -f -o remount,ro $fs failed ;-( =======" && exit -1
	fi
done

exit 0


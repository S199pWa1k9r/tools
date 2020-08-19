#!/bin/sh

# Copyright (c) 2017-2020 Sleep Walker <s199p.wa1k9r@gmail.com>
# Copyright (c) 2015-2017 The FreeBSD Foundation
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

set -e

SELF=image

. ./common.sh

if [ ${PRODUCT_ARCH} != armv6 -a ${PRODUCT_ARCH} != armv7 -a ${PRODUCT_ARCH} != aarch64 ]; then
	echo ">>> Cannot build arm image with arch ${PRODUCT_ARCH}"
	exit 1
fi

check_image ${SELF} ${@}

ARMSIZE="3G"

if [ -n "${1}" ]; then
	ARMSIZE=${1}
fi

ARMIMG="${IMAGESDIR}/${PRODUCT_RELEASE}-mmc-${PRODUCT_ARCH}-${PRODUCT_DEVICE}.img"
ARMLABEL="${PRODUCT_NAME}"

sh ./clean.sh ${SELF}

setup_stage ${STAGEDIR}

truncate -s ${ARMSIZE} ${ARMIMG}

DEV=$(mdconfig -a -t vnode -f ${ARMIMG} -x 63 -y 255)

echo ">>> Building MMC image..."

gpart create -s GPT ${DEV}
gpart add -t efi -l efi -a 512k -s 50m -b 16m ${DEV}
gpart add -t freebsd-ufs -l ${ARMLABEL} -a 64k /dev/${DEV}
newfs_msdos -L efi      /dev/${DEV}p1
newfs -U -L ${ARMLABEL} /dev/${DEV}p2

mount /dev/${DEV}p2 ${STAGEDIR}

setup_base ${STAGEDIR}
setup_kernel ${STAGEDIR}
setup_packages ${STAGEDIR}
setup_extras ${STAGEDIR} ${SELF}
setup_entropy ${STAGEDIR}

cat > ${STAGEDIR}/etc/fstab << EOF
# Device		Mountpoint	FStype	Options		Dump	Pass#
/dev/gpt/${ARMLABEL}	/		ufs	rw		1	1
/dev/gpt/efi		/boot/efi	msdosfs	rw,noauto	0	0
EOF

mkdir -p ${STAGEDIR}/boot/efi
mount -t msdosfs /dev/${DEV}p1 ${STAGEDIR}/boot/efi

if [ -f ${STAGEDIR}/boot/loader.efi ] ; then
	echo ">>> Install loader CONF"
	mmc_install_loader

	echo ">>> Install loader EFI"
	mkdir -p ${STAGEDIR}/boot/efi/EFI/BOOT
	cp ${STAGEDIR}/boot/loader.efi ${STAGEDIR}/boot/efi/EFI/BOOT/bootaa64.efi
	echo ">>> Install DTB"
	cp -r ${STAGEDIR}/boot/dtb ${STAGEDIR}/boot/efi
fi

mmc_mount()
{
	mount /dev/${DEV}p1 ${STAGEDIR}
	mount_msdosfs /dev/${DEV}p1 ${STAGEDIR}/boot/efi
}

mmc_unmount()
{
	sync
	umount ${STAGEDIR}/boot/efi
	umount ${STAGEDIR}
}

mmc_unmount

echo -n ">>> Install U-Boot ... "
mmc_install_uboot

mdconfig -d -u ${DEV}

echo "done"

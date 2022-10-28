#!/bin/bash

set -e

export PATH=../../../../prebuilts/clang/ohos/linux-x86_64/llvm/bin/:$PATH
export PRODUCT_PATH=vendor/hihope/rk3568
IMAGE_SIZE=64  # 64M
IMAGE_BLOCKS=4096
export DEVICE_NAME=rk3568
CPUs=`sed -n "N;/processor/p" /proc/cpuinfo|wc -l`
MAKE="make CROSS_COMPILE=/home/eternal/1_eternal/ohos_code/3.2_beta2/prebuilts/gcc/linux-x86/aarch64/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-"
BUILD_PATH=boot_linux
EXTLINUX_PATH=${BUILD_PATH}/extlinux
EXTLINUX_CONF=${EXTLINUX_PATH}/extlinux.conf
TOYBRICK_DTB=toybrick.dtb

ID_MODEL=1
ID_ARCH=2
ID_UART=3
ID_DTB=4
ID_IMAGE=5
ID_CONF=6
model_list=(
	"rock_5b  arm64 0xfe660000 rk3588-rock-5b_lyh  Image rockchip_linux_defconfig"
	"rock_5b_ohos  arm64 0xfe660000 rk3588-rock-5b_lyh  Image rk3588_ohos_defconfig"
)
#rock_3a_defconfig  firefly_3399_linux_defconfig

function help()
{
	echo "Usage: ./make-kernel.sh {BOARD_NAME}"
	echo "e.g."
	for i in "${model_list[@]}"; do
		echo "  ./make-kernel.sh $(echo $i | awk '{print $1}')"
	done
}


function make_extlinux_conf()
{
	dtb_path=$1
	uart=$2
	image=$3
	
	echo "label kernel-5.10" > ${EXTLINUX_CONF}
	echo "	kernel /extlinux/${image}" >> ${EXTLINUX_CONF}
	echo "	fdt /extlinux/${TOYBRICK_DTB}" >> ${EXTLINUX_CONF}
	if [ "enable_ramdisk" == "${ramdisk_flag}" ]; then
		echo "	initrd /extlinux/ramdisk.img" >> ${EXTLINUX_CONF}
	fi   
	cmdline="append earlyprintk mem=3800M rw root=PARTUUID=614e0000-00 loglevel=8 rw rootwait rootfstype=ext4 irqchip.gicv3_pseudo_nmi=0 hardware=rk3568"
	echo "  ${cmdline}" >> ${EXTLINUX_CONF}
}

function make_kernel_image()
{
	arch=$1
	conf=$2
	dtb=$3
	
	#${MAKE} ARCH=${arch} ${conf}
	if [ $? -ne 0 ]; then
		echo "FAIL: ${MAKE} ARCH=${arch} ${conf}"
		return -1
	fi
	#${MAKE} ARCH=${arch} menuconfig
	#${MAKE} ARCH=${arch} ${dtb}.img -j${CPUs}
	#make ARCH=arm64 savedefconfig
	#exit 
	${MAKE} ARCH=${arch} -j${CPUs}
	if [ $? -ne 0 ]; then
		echo "FAIL: ${MAKE} ARCH=${arch} ${dtb}.img"
		return -2
	fi

	return 0
}

function make_ext2_image()
{
	blocks=${IMAGE_BLOCKS}
	block_size=$((${IMAGE_SIZE} * 1024 * 1024 / ${blocks}))

	if [ "`uname -m`" == "aarch64" ]; then
		echo y | sudo mke2fs -b ${block_size} -d boot_linux -i 8192 -t ext2 boot_linux.img ${blocks}
	else
		genext2fs -B ${blocks} -b ${block_size} -d boot_linux -i 8192 -U boot_linux.img
	fi

	return $?
}

function make_boot_linux()
{
	arch=${!ID_ARCH}
	uart=${!ID_UART}
	dtb=${!ID_DTB}
	image=${!ID_IMAGE}
	conf=${!ID_CONF}
	if [ ${arch} == "arm" ]; then
		dtb_path=arch/arm/boot/dts
	else
		dtb_path=arch/arm64/boot/dts/rockchip
	fi

	rm -rf ${BUILD_PATH}
	mkdir -p ${EXTLINUX_PATH}

	make_kernel_image ${arch} ${conf} ${dtb}
	if [ $? -ne 0 ]; then
		exit 1
	fi
	make_extlinux_conf ${dtb_path} ${uart} ${image}
	cp -f arch/${arch}/boot/${image} ${EXTLINUX_PATH}/
	cp -f ${dtb_path}/${dtb}.dtb ${EXTLINUX_PATH}/${TOYBRICK_DTB}
	#cp -f logo*.bmp ${BUILD_PATH}/
	if [ "enable_ramdisk" = "${ramdisk_flag}" ]; then
		cp -f ./ramdisk.img ${EXTLINUX_PATH}/
	fi
	make_ext2_image
}

ramdisk_flag=$2
found=0
for i in "${model_list[@]}"; do
	if [ "$(echo $i | awk '{print $1}')" == "$1" ]; then
		make_boot_linux $i
		found=1
	fi
done

if [ $1 == "clean" ]; then
	echo "---Clearing Other Mirrors---"
	rm ./boot_linux.img -rf
	rm ./boot_linux -rf
	exit 1
fi

if [ ${found} -eq 0 ]; then
	help
fi

#!/bin/bash

RDIR=$(pwd)
export MODEL=$1
export KBUILD_BUILD_USER="@ravindu644"

#OEM variabls
export ARCH=arm64
export PLATFORM_VERSION=12
export ANDROID_MAJOR_VERSION=s

#init ksu next
git submodule init && git submodule update

#proton-12
if [ ! -d "${RDIR}/proton" ]; then
    mkdir -p "${RDIR}/proton"
    git clone --depth=1 https://github.com/ravindu644/proton-12.git -b main --single-branch proton
fi

#export toolchain paths
export BUILD_CROSS_COMPILE="${RDIR}/proton/bin/aarch64-linux-gnu-"
export BUILD_CROSS_COMPILE_ARM32="${RDIR}/proton/bin/arm-linux-gnueabi-"
export BUILD_CC="${RDIR}/proton/bin/clang"
export PATH=$PATH:"${RDIR}/proton/bin"

#build options
export ARGS="
-j$(nproc) \
ARCH=arm64 \
CROSS_COMPILE=${BUILD_CROSS_COMPILE} \
CROSS_COMPILE_ARM32=${BUILD_CROSS_COMPILE_ARM32} \
CC=${BUILD_CC} \
CLANG_TRIPLE=${BUILD_CROSS_COMPILE} \
LLVM=1 \
LLVM_IAS=1 \
AR=${RDIR}/proton/bin/llvm-ar \
NM=${RDIR}/proton/bin/llvm-nm \
LD=${RDIR}/proton/bin/ld.lld \
STRIP=${RDIR}/proton/bin/llvm-strip \
OBJCOPY=${RDIR}/proton/bin/llvm-objcopy \
OBJDUMP=${RDIR}/proton/bin/llvm-objdump \
READELF=${RDIR}/proton/bin/llvm-readelf \
HOSTCC=${RDIR}/proton/bin/clang \
HOSTCXX=${RDIR}/proton/bin/clang++ \
"

# Device configuration
declare -A DEVICES=(
    [beyond2]="exynos9820-beyond2lte_defconfig 9820 SRPRI17C014KU S"
    [beyond1]="exynos9820-beyond1lte_defconfig 9820 SRPRI28B014KU S"
    [beyond0]="exynos9820-beyond0lte_defconfig 9820 SRPRI28A014KU S"
    [beyondxks]="exynos9820-beyondx_defconfig 9820 SRPSC04B011KU S"
    [d1]="exynos9820-d1_defconfig 9825 SRPSD26B009KU N"
    [d2s]="exynos9820-d2s_defconfig 9825 SRPSC14B009KU N"
    [d1x]="exynos9820-d1xks_defconfig 9825 SRPSD23A002KU N"
    [d2x]="exynos9820-d2x_defconfig 9825 SRPSC14C007KU N"
)

# Set device-specific variables
if [[ -v DEVICES[$MODEL] ]]; then
    read KERNEL_DEFCONFIG SOC BOARD PHONE <<< "${DEVICES[$MODEL]}"
    echo -e "[!] Building a KernelSU enabled kernel for ${MODEL}...\n"
else
    echo "Unknown device: $MODEL, setting to beyondxks"
    export MODEL="beyondxks"
    read KERNEL_DEFCONFIG SOC BOARD PHONE <<< "${DEVICES[beyondxks]}"
fi

# tzdev
rm -rf "${RDIR}/drivers/misc/tzdev"

if [ "$PHONE" = "S" ]; then
    echo "Using S tzdev driver"
    cp -ar "${RDIR}/prebuilts/S/tzdev" "${RDIR}/drivers/misc/tzdev"

elif [ "$PHONE" = "N" ]; then
    echo "Using N tzdev driver"
    cp -ar "${RDIR}/prebuilts/N/tzdev" "${RDIR}/drivers/misc/tzdev"

fi

#dev
if [ -z "$LPOS_KERNEL_VERSION" ]; then
    export LPOS_KERNEL_VERSION="dev"
fi

#setting up localversion
echo -e "CONFIG_LOCALVERSION_AUTO=n\nCONFIG_LOCALVERSION=\"-LPoS-x-Eternity-${LPOS_KERNEL_VERSION}\"\n" > "${RDIR}/arch/arm64/configs/version.config"

build_kernel() {
    local config=$1
    echo "Starting a kernel build using $KERNEL_DEFCONFIG"

    make ${ARGS} $KERNEL_DEFCONFIG eternity.config ksu.config version.config || exit 1
    make ${ARGS} menuconfig || true
    make ${ARGS} || exit 1

    ${RDIR}/toolchains/mkdtimg cfg_create build/dtb_$SOC.img $RDIR/toolchains/configs/exynos$SOC.cfg -d $RDIR/arch/arm64/boot/dts/exynos
    echo "Finished kernel build"
}

build_dtbo()
{
    # Build for international variant
    "${RDIR}/toolchains/mkdtimg" cfg_create "build/dtbo_${MODEL}.img" \
        "${RDIR}/toolchains/configs/${MODEL}.cfg" \
        -d "${RDIR}/arch/arm64/boot/dts/samsung"
    
    # Build for Korean variant only if the cfg file exists
    if [ -f "${RDIR}/toolchains/configs/${MODEL}ks.cfg" ]; then
        "${RDIR}/toolchains/mkdtimg" cfg_create "build/dtbo_${MODEL}ks.img" \
            "${RDIR}/toolchains/configs/${MODEL}ks.cfg" \
            -d "${RDIR}/arch/arm64/boot/dts/samsung"
        echo "Korean DTBO image built successfully"
    else
        echo "Info: ${MODEL}ks.cfg not found. Skipping Korean DTBO build."
    fi
}

build_ramdisk() {
    rm -f $RDIR/ramdisk/split_img/boot.img-kernel
    cp $RDIR/arch/arm64/boot/Image $RDIR/ramdisk/split_img/boot.img-kernel
    echo $BOARD > ramdisk/split_img/boot.img-board
    mkdir -p $RDIR/ramdisk/ramdisk/{debug_ramdisk,dev,mnt,proc,sys}

    rm -rf "${RDIR}/ramdisk/ramdisk"/fstab*

    cp $RDIR/ramdisk/fstab.exynos9820 $RDIR/ramdisk/ramdisk/fstab.exynos$SOC

    cd $RDIR/ramdisk/
    sudo bash repackimg.sh
}

build_zip() {
    cd $RDIR/build
    rm -rf $MODEL-boot-ramdisk.img
    mv $RDIR/ramdisk/image-new.img $RDIR/build/$MODEL-boot-ramdisk.img

    # Make recovery flashable package
    rm -rf $RDIR/build/zip
    mkdir -p $RDIR/build/zip
    cp $RDIR/build/$MODEL-boot-ramdisk.img $RDIR/build/zip/boot.img
    cp $RDIR/build/dtb_$SOC.img $RDIR/build/zip/dt.img

    #INTL DTBO
    cp "${RDIR}/build/dtbo_${MODEL}.img" "${RDIR}/build/zip/dtbo.img"

    #KOR DTBO if exsits..
    if [ -f "${RDIR}/build/dtbo_${MODEL}ks.img" ]; then
        cp "${RDIR}/build/dtbo_${MODEL}ks.img" "${RDIR}/build/zip/dtbo_ks.img"
    fi
    
    cp -r "${RDIR}/toolchains/twrp_zip/"* "${RDIR}/build/zip/"
    cd $RDIR/build/zip
    zip -r ../LPoS-x-Eternity-${LPOS_KERNEL_VERSION}-${MODEL}-${KSU}-universal.zip .
    rm -rf $RDIR/build/zip
    cd $RDIR/build
}

# Main execution

START_TIME=$(date +%s)

build_kernel
build_dtbo
build_ramdisk
build_zip

END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))
echo "Total compile time was $ELAPSED_TIME seconds"
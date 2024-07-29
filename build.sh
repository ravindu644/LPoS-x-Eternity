#!/bin/bash
RDIR=$(pwd)
export MODEL=$1
export KSU=$2
export KBUILD_BUILD_USER="@ravindu644"

#proton-12
if [ ! -d "${RDIR}/proton" ]; then
    mkdir -p "${RDIR}/proton"
    git clone --depth=1 https://github.com/ravindu644/proton-12.git -b main --single-branch proton
fi

export PATH=$PWD/proton/bin:$PATH
export READELF=$PWD/proton/bin/aarch64-linux-gnu-readelf
export LLVM=1
export ARGS="
CC=clang
LD=ld.lld
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-
CROSS_COMPILE_ARM32=arm-linux-gnueabi-
CLANG_TRIPLE=aarch64-linux-gnu-
AR=llvm-ar
NM=llvm-nm
AS=llvm-as
OBJCOPY=llvm-objcopy
OBJDUMP=llvm-objdump
OBJSIZE=llvm-size
STRIP=llvm-strip
LLVM_AR=llvm-ar
LLVM_DIS=llvm-dis
LLVM_NM=llvm-nm
LLVM=1
"
#symlinking python2
if [ ! -f "$HOME/python" ]; then
    ln -s /usr/bin/python2.7 "$HOME/python"
fi 

# Device configuration
declare -A DEVICES=(
    [beyond2lte]="exynos9820-beyond2lte_defconfig 9820 SRPRI17C014KU"
    [beyond1lte]="exynos9820-beyond1lte_defconfig 9820 SRPRI28B014KU"
    [beyond0lte]="exynos9820-beyond0lte_defconfig 9820 SRPRI28A014KU"
    [beyondx]="exynos9820-beyondx_defconfig 9820 SRPSC04B011KU"
)

# Set device-specific variables
if [[ -v DEVICES[$MODEL] ]]; then
    read KERNEL_DEFCONFIG SOC BOARD <<< "${DEVICES[$MODEL]}"
else
    echo "Unknown device: $MODEL, setting to beyond2lte"
    read KERNEL_DEFCONFIG SOC BOARD <<< "${DEVICES[beyond2lte]}"
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
    export PLATFORM_VERSION=11
    export ANDROID_MAJOR_VERSION=r

    make -j$(nproc) ARCH=arm64 ${ARGS} $KERNEL_DEFCONFIG $config || exit -1
    make -j$(nproc) ARCH=arm64 ${ARGS} menuconfig || true
    make -j$(nproc) ARCH=arm64 ${ARGS} || exit -1

    $RDIR/toolchains/mkdtimg cfg_create build/dtb_$SOC.img $RDIR/toolchains/configs/exynos$SOC.cfg -d $RDIR/arch/arm64/boot/dts/exynos
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

    rm -rf $RDIR/ramdisk/ramdisk/fstab.exynos9820
    rm -rf $RDIR/ramdisk/ramdisk/fstab.exynos9825

    cp $RDIR/ramdisk/fstab.exynos9820 $RDIR/ramdisk/ramdisk/fstab.exynos$SOC

    cd $RDIR/ramdisk/
    ./repackimg.sh --nosudo
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
rm -rf ./build.log
(
    START_TIME=$(date +%s)

    if [ "$KSU" = "non-ksu" ]; then
        echo "CONFIG_KSU=n" > "${RDIR}/arch/arm64/configs/ksu.config"
        build_kernel "eternity.config ksu.config version.config"
    elif [ "$KSU" = "ksu" ]; then
        echo "CONFIG_KSU=y" > "${RDIR}/arch/arm64/configs/ksu.config"
        build_kernel "eternity.config ksu.config version.config"
    else
        echo "Error: Invalid input. Please enter 'ksu' or 'non-ksu' as the 2nd parameter"
        exit 1
    fi

    build_dtbo
    build_ramdisk
    build_zip

    END_TIME=$(date +%s)
    ELAPSED_TIME=$((END_TIME - START_TIME))
    echo "Total compile time was $ELAPSED_TIME seconds"

) 2>&1 | tee -a ./build.log
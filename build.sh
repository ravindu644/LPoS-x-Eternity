#!/bin/bash

export MODEL=$1
export KSU=$2
export BUILD_CROSS_COMPILE=$(pwd)/toolchains/aarch64-linux-android-4.9/bin/aarch64-linux-androidkernel-
export BUILD_JOB_NUMBER=$(grep -c ^processor /proc/cpuinfo)
RDIR=$(pwd)

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

    make -j$BUILD_JOB_NUMBER ARCH=arm64 CROSS_COMPILE=$BUILD_CROSS_COMPILE $KERNEL_DEFCONFIG $config || exit -1
    make -j$BUILD_JOB_NUMBER ARCH=arm64 CROSS_COMPILE=$BUILD_CROSS_COMPILE menuconfig || true
    make -j$BUILD_JOB_NUMBER ARCH=arm64 CROSS_COMPILE=$BUILD_CROSS_COMPILE || exit -1

    $RDIR/toolchains/mkdtimg cfg_create build/dtb_$SOC.img $RDIR/toolchains/configs/exynos$SOC.cfg -d $RDIR/arch/arm64/boot/dts/exynos
    echo "Finished kernel build"
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
    cp $RDIR/build/dtb_$SOC.img $RDIR/build/zip/dtb.img
    mkdir -p $RDIR/build/zip/META-INF/com/google/android/
    cp $RDIR/toolchains/updater-script $RDIR/build/zip/META-INF/com/google/android/
    cp $RDIR/toolchains/update-binary $RDIR/build/zip/META-INF/com/google/android/
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

    build_ramdisk
    build_zip

    END_TIME=$(date +%s)
    ELAPSED_TIME=$((END_TIME - START_TIME))
    echo "Total compile time was $ELAPSED_TIME seconds"

) 2>&1 | tee -a ./build.log
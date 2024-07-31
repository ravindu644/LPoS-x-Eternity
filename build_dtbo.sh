#!/bin/bash

set -e

RDIR=$(pwd)

#proton12
if [ ! -d "${RDIR}/proton" ]; then
    mkdir -p "${RDIR}/proton"
    git clone --depth=1 https://github.com/ravindu644/proton-12.git -b main --single-branch proton
fi

#variables
export PATH=$PWD/proton/bin:$PATH
export READELF=$PWD/proton/bin/aarch64-linux-gnu-readelf
export LLVM=1
export ARGS="CC=clang LD=ld.lld ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- CLANG_TRIPLE=aarch64-linux-gnu- AR=llvm-ar NM=llvm-nm AS=llvm-as OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump OBJSIZE=llvm-size STRIP=llvm-strip LLVM_AR=llvm-ar LLVM_DIS=llvm-dis LLVM_NM=llvm-nm LLVM=1"

MODELS=("beyond2lte" "beyond1lte" "beyond0lte" "beyondx")

build_dtbo() {
    local MODEL=$1
    local SUFFIX=$2
    echo "Building DTBO for ${MODEL}${SUFFIX}..."
    "${RDIR}/toolchains/mkdtimg" cfg_create "build/dtbo_${MODEL}${SUFFIX}.img" \
        "${RDIR}/toolchains/configs/${MODEL}${SUFFIX}.cfg" \
        -d "${RDIR}/arch/arm64/boot/dts/samsung"
}

#build DTBO for all models
for MODEL in "${MODELS[@]}"; do
    echo "Configuring for ${MODEL}..."
    make ${ARGS} "exynos9820-${MODEL}_defconfig"
    make ${ARGS} dtbs
    build_dtbo "$MODEL" ""  #INTL
    build_dtbo "${MODEL}ks"  #KOR
done

cd "${RDIR}/build" && zip -r "DTBO S10.zip" dtbo_*.img
echo "All DTBO images have been built and zipped."

cd "${RDIR}"
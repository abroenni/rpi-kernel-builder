#!/bin/bash


# raspbian or mainline
kernel_variant="raspbian"
#kernel_variant="mainline"

# if raspbian kernel: master or next
kernel_version="5.8"

## USE "3" for Raspberry Pi 2, Pi 3, Pi 3+, and CM3
## USE "4" for Raspberry Pi 4
rpi_version="4"

echo "Building ${kernel_variant} ${kernel_version} kernel for Raspberrypi ${rpi-version}..."

# Select crosscompile toolchain
# Options: raspberrypi gcc-arm
toolchain="gcc-arm"

[[ "$kernel_variant" == "mainline" ]] && defconfig=multi_v7_custom
#[[ "$kernel_variant" == "mainline" ]] && defconfig=bcm2835
[[ "$kernel_variant" == "raspbian" ]] && [[ "$rpi_version" == "3" ]] && defconfig=bcm2709
### rpi4
[[ "$kernel_variant" == "raspbian" ]] && [[ "$rpi_version" == "4" ]] && defconfig=bcm2711

src_dir=`pwd`
toolchain_dir="tools"
nb_cores=4

# required build deps
builddeps=("build-essential" "git" "bc" "bison" "flex" "libssl-dev" "make" "libc6-dev" "libncurses5-dev"
            "fakeroot" "libncurses-dev" "xz-utils" )

source_toolchain_raspberrypi="https://github.com/raspberrypi/tools"
source_toolchain_gcc="https://developer.arm.com/-/media/Files/downloads/gnu-a/9.2-2019.12/binrel/gcc-arm-9.2-2019.12-x86_64-arm-none-linux-gnueabihf.tar.xz"
source_kernel_raspbian="https://github.com/raspberrypi/linux"
source_kernel_mainline="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"

install_builddep(){
	instdebs=()

	for deb in "${builddeps[@]}"; do
        	dpkg -s ${deb} > /dev/null 2>&1
        	err=$?
        	# 1 not installed, 0 is installed
        	if [ ${err} -eq 1 ]; then
                	echo "[ ] Package ${deb} NOT installed"
                	instdebs=("${instdebs[@]}" "${deb}")
        	else
                	echo "[ii] Package ${deb} found"
        	fi
	done
	# install the build dependencies
	[[ ! -z $instdebs ]] &&	sudo apt install ${instdebs[@]}
}


get_toolchain(){

read -r toolchainid < ${src_dir}/$toolchain_dir/toolchain_id

if [[ "${toolchainid}" == "${toolchain}" ]]; then
    echo "Toolchain ${toolchain} already downloaded, may be updated"
elif [[ "${toolchainid}" != "${toolchain}" ]]; then
    echo "switching toolchains from ${toolchainid} to ${toolchain}"
    cd ${src_dir}
    echo "deleting old toolchain ${toolchainid}"
    sudo rm -rf $toolchain_dir
fi


if [[ "$toolchain" == "raspberrypi" ]];then
    if [ ! -d ${src_dir}/$toolchain_dir ];then
        git clone $source_toolchain_raspberrypi ${src_dir}/${toolchain_dir}
	echo ${toolchain} >> ${src_dir}/$toolchain_dir/toolchain_id
    elif [ -d ${src_dir}/$toolchain_dir ];then
        cd ${src_dir}/$toolchain_dir
        git pull --rebase
    fi
elif [[ "$toolchain" == "gcc-arm" ]];then
    if [ ! -d ${src_dir}/$toolchain_dir ];then
	mkdir ${src_dir}/$toolchain_dir
        [[ ! -f "${src_dir}/gcc-arm.tar-xz" ]] && wget $source_toolchain_gcc -O ${src_dir}/gcc-arm.tar-xz
	tar xf gcc-arm.tar-xz -C ${src_dir}/$toolchain_dir --strip-components=1
	echo ${toolchain} >> ${src_dir}/$toolchain_dir/toolchain_id
    elif [ -d ${src_dir}/$toolchain_dir ];then
	echo "${toolchain} already present"
    fi

else
	echo "Incorrect toolchain selected."
	exit 1
fi

}

get_kernel(){
    linux_dir=${src_dir}/linux-${kernel_variant}-${kernel_version}

    if [ ! -d ${linux_dir} ];then
	if [[ "${kernel_variant}" == "raspbian"  ]];then
	    git clone --depth=1 --branch=rpi-${kernel_version}.y $source_kernel_raspbian ${linux_dir}
	elif [[ "${kernel_variant}" == "mainline"  ]];then
	    git clone --depth=1 --branch=linux-${kernel_version}.y $source_kernel_mainline ${linux_dir}
	fi
    fi

    if [ -d ${linux_dir} ];then
	cd ${linux_dir}
	git pull --rebase
    fi
}


prepare(){

    if [[ "$toolchain" == "raspberrypi" ]];then
    	export TOOLCHAIN_HOME=${src_dir}/${toolchain_dir}/arm-bcm2708/arm-linux-gnueabihf/bin
        crosscompile_prefix="arm-linux-gnueabihf-"
    elif [[ "$toolchain" == "gcc-arm" ]];then
	export TOOLCHAIN_HOME=${src_dir}/${toolchain_dir}/bin
        crosscompile_prefix="arm-none-linux-gnueabihf-"
    fi
    export PATH=$TOOLCHAIN_HOME:$PATH

    if [ -z "$nb_cores" ];then
        nb_cores=$(grep -c '^processor' /proc/cpuinfo)
    fi

    echo "Using ${nb_cores} Cores for compilation"
}

build_kernel(){
    cd ${linux_dir}
    kernel_version_exact=`sed '2,4!d' Makefile | awk '{print $3}' | sed ':a;N;$!ba;s/\n/./g'`
    # Name for rpi 2s and 3s
    [[ "$rpi_version" == "3" ]] && KERNEL=kernel7
    # Name for rpi 4s
    [[ "$rpi_version" == "4" ]] && KERNEL=kernel7l
    # Apply default config
    make ARCH=arm CROSS_COMPILE=${crosscompile_prefix} ${defconfig}_defconfig

    #build kernel
    make -j ${nb_cores} LOCALVERSION=-andromeda ARCH=arm CROSS_COMPILE=${crosscompile_prefix} zImage modules dtbs
}


package(){
    kernel_inst_root=${src_dir}/install_bundle/${kernel_variant}/${kernel_version_exact}
    boot_dir=${kernel_inst_root}/boot_dir
    root_dir=${kernel_inst_root}/root_dir
    mkdir -p ${boot_dir}/overlays
    mkdir -p ${root_dir}

    cd ${linux_dir}
    # echo "env PATH=$PATH make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_MOD_PATH=${root_dir} modules_install" >> ${src_dir}/build.log
    sudo env PATH=$PATH make ARCH=arm CROSS_COMPILE=${crosscompile_prefix} INSTALL_MOD_PATH=${root_dir} modules_install
    sudo env PATH=$PATH make ARCH=arm CROSS_COMPILE=${crosscompile_prefix} INSTALL_MOD_PATH=${root_dir} modules_install
    cp arch/arm/boot/zImage ${boot_dir}/$KERNEL.img
    cp arch/arm/boot/dts/*-rpi-*.dtb ${boot_dir}/

    if [[ "${kernel_variant}" == "raspbian"  ]];then
    	cp arch/arm/boot/dts/overlays/*.dtb* ${boot_dir}/overlays/
    	cp arch/arm/boot/dts/overlays/README ${boot_dir}/overlays/
    fi
}

compress(){
    echo "Creating tar file ..."
    tarfile=rpi-${rpi_version}-${kernel_variant}-${kernel_version_exact}.tar.xz

    # chown to root
    sudo chown -R root:root ${kernel_inst_root}

    # taring
    sudo tar -C ${src_dir}/install_bundle/${kernel_variant}/ -cJf ${src_dir}/${tarfile} ${kernel_version_exact}/

}


clear
install_builddep
get_toolchain
get_kernel
prepare
build_kernel && package && compress

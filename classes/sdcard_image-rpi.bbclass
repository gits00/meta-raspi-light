inherit image_types

#
# Create an image that can be written onto a SD card using dd.
#
# The disk layout used is:
#
#    0                      -> IMAGE_ROOTFS_ALIGNMENT         - reserved for other data
#    IMAGE_ROOTFS_ALIGNMENT -> BOOT_SPACE                     - bootloader and kernel
#    BOOT_SPACE             -> SDIMG_SIZE                     - rootfs
#

#                                                     Default Free space = 1.3x
#                                                     Use IMAGE_OVERHEAD_FACTOR to add more space
#                                                     <--------->
#            4MiB              80MiB           SDIMG_ROOTFS
# <-----------------------> <----------> <---------------------->
#  ------------------------ ------------ ------------------------
# | IMAGE_ROOTFS_ALIGNMENT | BOOT_SPACE | ROOTFS_SIZE            |
#  ------------------------ ------------ ------------------------
# ^                        ^            ^                        ^
# |                        |            |                        |
# 0                      4MiB     4MiB + 80MiB       4MiB + 80Mib + SDIMG_ROOTFS

# This image depends on the rootfs image
IMAGE_TYPEDEP_rpi-sdimg = "${SDIMG_ROOTFS_TYPE}"

# Set kernel and boot loader
IMAGE_BOOTLOADER ?= "bcm2835-bootfiles"

# Boot partition volume id
BOOTDD_VOLUME_ID ?= "${MACHINE}"

# Boot partition size [in KiB] (will be rounded up to IMAGE_ROOTFS_ALIGNMENT)
BOOT_SPACE ?= "80920"

# Set alignment to 4MB [in KiB]
IMAGE_ROOTFS_ALIGNMENT = "4096"

# Use an uncompressed ext4 by default as rootfs
SDIMG_ROOTFS_TYPE ?= "ext4"
SDIMG_ROOTFS = "${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.${SDIMG_ROOTFS_TYPE}"

# For the names of kernel artifacts
inherit kernel-artifact-names

do_image_rpi_sdimg[depends] = " \
    parted-native:do_populate_sysroot \
    mtools-native:do_populate_sysroot \
    dosfstools-native:do_populate_sysroot \
    virtual/kernel:do_deploy \
    ${IMAGE_BOOTLOADER}:do_deploy \
"

do_image_rpi_sdimg[recrdeps] = "do_build"

# SD card image name
SDIMG = "${IMGDEPLOYDIR}/${IMAGE_NAME}.rootfs.rpi-sdimg"

# Compression method to apply to SDIMG after it has been created. Supported
# compression formats are "gzip", "bzip2" or "xz". The original .rpi-sdimg file
# is kept and a new compressed file is created if one of these compression
# formats is chosen. If SDIMG_COMPRESSION is set to any other value it is
# silently ignored.
#SDIMG_COMPRESSION ?= ""

# Additional files and/or directories to be copied into the vfat partition from the IMAGE_ROOTFS.
FATPAYLOAD ?= ""

# SD card vfat partition image name
SDIMG_VFAT = "${IMAGE_NAME}.vfat"
SDIMG_LINK_VFAT = "${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.vfat"

def split_overlays(d, out, ver=None):
    dts = d.getVar("KERNEL_DEVICETREE")
    # Device Tree Overlays are assumed to be suffixed by '-overlay.dtb' (4.1.x) or by '.dtbo' (4.4.9+) string and will be put in a dedicated folder
    if out:
        overlays = oe.utils.str_filter_out('\S+\-overlay\.dtb$', dts, d)
        overlays = oe.utils.str_filter_out('\S+\.dtbo$', overlays, d)
    else:
        overlays = oe.utils.str_filter('\S+\-overlay\.dtb$', dts, d) + \
                   " " + oe.utils.str_filter('\S+\.dtbo$', dts, d)

    return overlays

IMAGE_CMD_rpi-sdimg () {

    # Align partitions
    BOOT_SPACE_ALIGNED=$(expr ${BOOT_SPACE} + ${IMAGE_ROOTFS_ALIGNMENT} - 1)
    BOOT_SPACE_ALIGNED=$(expr ${BOOT_SPACE_ALIGNED} - ${BOOT_SPACE_ALIGNED} % ${IMAGE_ROOTFS_ALIGNMENT})
    SDIMG_SIZE=$(expr ${IMAGE_ROOTFS_ALIGNMENT} + ${BOOT_SPACE_ALIGNED} + $ROOTFS_SIZE)

    echo "Creating filesystem with Boot partition ${BOOT_SPACE_ALIGNED} KiB and RootFS $ROOTFS_SIZE KiB"

    # Check if we are building with device tree support
    DTS="${KERNEL_DEVICETREE}"

    # Initialize sdcard image file
    dd if=/dev/zero of=${SDIMG} bs=1024 count=0 seek=${SDIMG_SIZE}

    # Create partition table
    parted -s ${SDIMG} mklabel msdos
    # Create boot partition and mark it as bootable
    parted -s ${SDIMG} unit KiB mkpart primary fat32 ${IMAGE_ROOTFS_ALIGNMENT} $(expr ${BOOT_SPACE_ALIGNED} \+ ${IMAGE_ROOTFS_ALIGNMENT})
    parted -s ${SDIMG} set 1 boot on
    # Create rootfs partition to the end of disk
    parted -s ${SDIMG} -- unit KiB mkpart primary ext2 $(expr ${BOOT_SPACE_ALIGNED} \+ ${IMAGE_ROOTFS_ALIGNMENT}) -1s
    parted ${SDIMG} print

    # Create a vfat image with boot files
    BOOT_BLOCKS=$(LC_ALL=C parted -s ${SDIMG} unit b print | awk '/ 1 / { print substr($4, 1, length($4 -1)) / 512 /2 }')
    rm -f ${WORKDIR}/boot.img
    mkfs.vfat -F32 -n "${BOOTDD_VOLUME_ID}" -S 512 -C ${WORKDIR}/boot.img $BOOT_BLOCKS
    mcopy -i ${WORKDIR}/boot.img -s ${DEPLOY_DIR_IMAGE}/bcm2835-bootfiles/* ::/
    if test -n "${DTS}"; then
        # Copy board device trees to root folder
        for dtbf in ${@split_overlays(d, True)}; do
            dtb=`basename $dtbf`
            mcopy -i ${WORKDIR}/boot.img -s ${DEPLOY_DIR_IMAGE}/$dtb ::$dtb
        done

        # Copy device tree overlays to dedicated folder
        mmd -i ${WORKDIR}/boot.img overlays
        for dtbf in ${@split_overlays(d, False)}; do
            dtb=`basename $dtbf`
            mcopy -i ${WORKDIR}/boot.img -s ${DEPLOY_DIR_IMAGE}/$dtb ::overlays/$dtb
        done
    fi
    if [ ! -z "${INITRAMFS_IMAGE}" -a "${INITRAMFS_IMAGE_BUNDLE}" = "1" ]; then
        mcopy -i ${WORKDIR}/boot.img -s ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-${INITRAMFS_SYMLINK_NAME}.bin ::${SDIMG_KERNELIMAGE}
    else
        mcopy -i ${WORKDIR}/boot.img -s ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE} ::${SDIMG_KERNELIMAGE}
    fi

    if [ -n ${FATPAYLOAD} ] ; then
        echo "Copying payload into VFAT"
        for entry in ${FATPAYLOAD} ; do
            # add the || true to stop aborting on vfat issues like not supporting .~lock files
            mcopy -i ${WORKDIR}/boot.img -s -v ${IMAGE_ROOTFS}$entry :: || true
        done
    fi

    # Add stamp file
    echo "${IMAGE_NAME}" > ${WORKDIR}/image-version-info
    mcopy -i ${WORKDIR}/boot.img -v ${WORKDIR}/image-version-info ::

    # Burn Partitions
    dd if=${WORKDIR}/boot.img of=${SDIMG} conv=notrunc seek=1 bs=$(expr ${IMAGE_ROOTFS_ALIGNMENT} \* 1024)
    # If SDIMG_ROOTFS_TYPE is a .xz file use xzcat
    if echo "${SDIMG_ROOTFS_TYPE}" | egrep -q "*\.xz"
    then
        xzcat ${SDIMG_ROOTFS} | dd of=${SDIMG} conv=notrunc seek=1 bs=$(expr 1024 \* ${BOOT_SPACE_ALIGNED} + ${IMAGE_ROOTFS_ALIGNMENT} \* 1024)
    else
        dd if=${SDIMG_ROOTFS} of=${SDIMG} conv=notrunc seek=1 bs=$(expr 1024 \* ${BOOT_SPACE_ALIGNED} + ${IMAGE_ROOTFS_ALIGNMENT} \* 1024)
    fi

    # Optionally apply compression
    case "${SDIMG_COMPRESSION}" in
    "gzip")
        gzip -k9 "${SDIMG}"
        ;;
    "bzip2")
        bzip2 -k9 "${SDIMG}"
        ;;
    "xz")
        xz -k "${SDIMG}"
        ;;
    esac
}

ROOTFS_POSTPROCESS_COMMAND += " rpi_generate_sysctl_config ; "

rpi_generate_sysctl_config() {
    # systemd sysctl config
    test -d ${IMAGE_ROOTFS}${sysconfdir}/sysctl.d && \
        echo "vm.min_free_kbytes = 8192" > ${IMAGE_ROOTFS}${sysconfdir}/sysctl.d/rpi-vm.conf

    # sysv sysctl config
    IMAGE_SYSCTL_CONF="${IMAGE_ROOTFS}${sysconfdir}/sysctl.conf"
    test -e ${IMAGE_ROOTFS}${sysconfdir}/sysctl.conf && \
        sed -e "/vm.min_free_kbytes/d" -i ${IMAGE_SYSCTL_CONF}
    echo "" >> ${IMAGE_SYSCTL_CONF} && echo "vm.min_free_kbytes = 8192" >> ${IMAGE_SYSCTL_CONF}
}

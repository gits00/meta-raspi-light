DESCRIPTION = "Closed source binary files to help boot the ARM on the BCM2835."
LICENSE = "Proprietary"

LIC_FILES_CHKSUM = "file://LICENCE.broadcom;md5=4a4d169737c0786fb9482bb6d30401d1"

inherit deploy

PV = "20170427"

SRC_URI = "https://github.com/raspberrypi/firmware/archive/1.${PV}.tar.gz"
#SRC_URI = "https://github.com/schnitzeltony/firmware/archive/schnitzel-${PV}.tar.gz"
SRC_URI[md5sum] = "d7a87af3ffc7ad26c939f01b7ffd561e"
SRC_URI[sha256sum] = "e253084463a0a3ba908396ac383169397d53bc55307d0d8471f2814f2458fa1b"

RDEPENDS_${PN} = "rpi-config"

COMPATIBLE_MACHINE = "raspberrypi"

#S = "${WORKDIR}/firmware-schnitzel-${PV}/boot"
S = "${WORKDIR}/firmware-1.${PV}/boot"

do_deploy() {
    install -d ${DEPLOYDIR}/${PN}

    for i in ${S}/*.elf ; do
        cp $i ${DEPLOYDIR}/${PN}
    done
    for i in ${S}/*.dat ; do
        cp $i ${DEPLOYDIR}/${PN}
    done
    for i in ${S}/*.bin ; do
        cp $i ${DEPLOYDIR}/${PN}
    done

    # Add stamp in deploy directory
    touch ${DEPLOYDIR}/${PN}/${PN}-${PV}.stamp
}

addtask deploy before do_package after do_install
do_deploy[dirs] += "${DEPLOYDIR}/${PN}"

PACKAGE_ARCH = "${MACHINE_ARCH}"


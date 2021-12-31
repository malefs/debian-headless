include Makevars

TMP = tmp
ISOLINUX_CFG_TEMPLATE = isolinux.cfg.template


help:
	@echo
	@echo "Edit 'Makevars' before running any targets."

	@echo
	@echo "Usage:"
	@echo
	@echo "  make config                Edit configuration (Makevars)"
	@echo "  make install-depends       Install dependencies"
	@echo "  make example-preseed.cfg   download preseed.cfg from Debian"
	@echo "  make image                 Build the ISO image"
	@echo "  make qemu                  Boot ISO image in QEMU for testing (optional)"
	@echo "  make usb                   Write ISO to USB device"
	@echo "  make FAT                   Add a FAT partition ot the USB stick (optiona)"
	@echo "  make clean                 Clean up temporary files and folders"
	@echo "  make maintainer-clean      Make clean and remove the output ISO"
	@echo
	@echo "For details consult the README.md file"
	@echo
	@echo "'${ARCH}'"
	@echo "'${ARCHFOLDER}'"
	@echo "'${QEMU}'"
	@echo "'${SOURCE}'"
	@echo "'${TARGET}'"
	@echo "'${LABEL}'"
	@echo "'${RELEASE_NO}'"
	@echo "'${MAJOR}'"
	@echo "'${RELEASE_NAME}'"

.PHONY: install-depends
install-depends:
	sudo apt-get install libarchive-tools syslinux syslinux-utils cpio genisoimage coreutils qemu-system qemu-system-x86 qemu-utils util-linux

example-preseed.cfg:
	wget -O $@ https://www.debian.org/releases/$(RELEASE_NAME)/example-preseed.txt

.PHONY: config
config:
	edit Makevars

.PHONY: image
image: ${TARGET}

# Create ISO and fix MBR for USB boot.
${TARGET}: ${TMP} \
           ${TMP}/isolinux/isolinux.cfg \
           ${TMP}/install.${ARCHFOLDER}/initrd.gz \
           ${TMP}/md5sum.txt
	genisoimage -V ${LABEL} \
		-r -J -b isolinux/isolinux.bin -c isolinux/boot.cat \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		-o $@ ${TMP}
	isohybrid $@

# Unpack the image to the folder and set write permissions.
${TMP}: ${SOURCE}
	mkdir $@
	bsdtar -C $@ -xf $<
	chmod -R +w $@

# Create a minimal isolinux config. no menu, no prompt.
${TMP}/isolinux/isolinux.cfg: ${ISOLINUX_CFG_TEMPLATE}
	sed "s/ARCHFOLDER/${ARCHFOLDER}/" ${ISOLINUX_CFG_TEMPLATE} > $@

# Write the preseed file to initrd.
${TMP}/install.${ARCHFOLDER}/initrd.gz: ${PRESEED}
	gunzip ${TMP}/install.${ARCHFOLDER}/initrd.gz
	cp $< ${TMP}/preseed.cfg
	cd ${TMP}; echo preseed.cfg | cpio -H newc -o -A -F install.${ARCHFOLDER}/initrd
	gzip ${TMP}/install.${ARCHFOLDER}/initrd
	rm ${TMP}/preseed.cfg

# Recreate the MD5 sums of all files.
${TMP}/md5sum.txt: ${TMP} ${TMP}/isolinux/isolinux.cfg ${TMP}/install.${ARCHFOLDER}/initrd.gz
	find ${TMP}/ -type f -exec md5sum {} \; > $@

# Run qemu with forwarded ssh port.
.PHONY: qemu
qemu: ${TARGET} image.qcow
	@echo
	@echo "\nOnce the installer is in network console you can log in:"
	@echo "    ssh installer@localhost -p10022\n"
	${QEMU} -m 1024 \
		-net user,hostfwd=tcp::10022-:22 \
		-net nic \
		-hda image.qcow \
		-cdrom $<

# Create a virtual disk for QEMU.
image.qcow:
	qemu-img create -f qcow2 $@ 10G

# Write the image to usb stick.
.PHONY: usb
usb:
	@echo "This will overwrite all data on ${USBDEV}!"
	@read -p "Type 'yes' if you really want to do this: " proceed; \
	if [ $$proceed = "yes" ] ; then \
		sudo dd if=${TARGET} of=${USBDEV} bs=4k ; \
		sync ; \
	else \
		echo "Aborting" ; \
	fi

# Add a FAT partition in the remaining free space (e.g. for driver files).
.PHONY: FAT
FAT:
	@echo "This will overwrite ${USBDEV}!"
	@read -p "Type 'yes' if you really want to do this: " proceed; \
	if [ $$proceed = "yes" ] ; then \
		echo " , , 0xb" | sudo sfdisk ${USBDEV} -N 2 ;\
		sudo mkfs.vfat ${USBDEV}2 ;\
		sync ;\
	else \
		echo "Aborting" ; \
	fi

.PHONY: clean
clean:
	rm -rf ${TMP}
	rm -f image.qcow
	rm -f example-preseed.cfg

.PHONY: maintainer-clean
maintainer-clean: clean
	rm -f ${TARGET}

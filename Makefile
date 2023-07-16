IMAGE_NAME := flare

.PHONY: all
all: iso hdd ovmf

.PHONY: iso
iso: $(IMAGE_NAME).iso

.PHONY: hdd
hdd: $(IMAGE_NAME).hdd

.PHONY: run-iso
run-iso: $(IMAGE_NAME).iso
	qemu-system-x86_64 -M q35 -m 2G -cdrom $< -boot d -debugcon stdio

.PHONY: run-iso-uefi
run-iso-uefi: $(IMAGE_NAME).iso ovmf
	qemu-system-x86_64 -M q35 -m 2G -bios ovmf/OVMF.fd -cdrom $< -boot d -debugcon stdio

.PHONY: run-hdd
run-hdd: $(IMAGE_NAME).hdd
	qemu-system-x86_64 -M q35 -m 2G -hda $< -debugcon stdio

.PHONY: run-hdd-uefi
run-hdd-uefi: $(IMAGE_NAME).hdd ovmf
	qemu-system-x86_64 -M q35 -m 2G -bios ovmf/OVMF.fd -hda $< -debugcon stdio

ovmf:
	mkdir -p ovmf
	cd ovmf && curl -Lo OVMF.fd https://retrage.github.io/edk2-nightly/bin/RELEASEX64_OVMF.fd

limine:
	git clone https://github.com/limine-bootloader/limine.git --branch=v5.x-branch-binary --depth=1
	$(MAKE) -C limine

.PHONY: kernel
kernel:
	$(MAKE) -C kernel

.PHONY: test
test:
	$(MAKE) -C kernel test

$(IMAGE_NAME).iso: limine kernel
	rm -rf iso_root
	mkdir -p iso_root
	cp -v kernel/kernel.elf limine.cfg limine/limine-bios.sys limine/limine-bios-cd.bin limine/limine-uefi-cd.bin iso_root
	mkdir -p iso_root/EFI/BOOT
	cp -v limine/BOOTX64.EFI iso_root/EFI/BOOT
	cp -v limine/BOOTIA32.EFI iso_root/EFI/BOOT
	xorriso -as mkisofs -b limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table --efi-boot limine-uefi-cd.bin -efi-boot-part --efi-boot-image --protective-msdos-label iso_root -o $@
	./limine/limine bios-install $@
	rm -rf iso_root

$(IMAGE_NAME).hdd: limine kernel
	rm -f $@
	dd if=/dev/zero bs=1M count=0 seek=64 of=$@
	parted -s $@ mklabel gpt
	parted -s $@ mkpart ESP fat32 2048s 100%
	parted -s $@ set 1 esp on
	./limine/limine bios-install $@
	sudo losetup -Pf --show $@ >loopback_dev
	sudo mkfs.fat -F 32 `cat loopback_dev`p1
	mkdir -p img_mount
	sudo mount `cat loopback_dev`p1 img_mount
	sudo mkdir -p img_mount/EFI/BOOT
	sudo cp -v kernel/kernel.elf limine.cfg limine/limine-bios.sys img_mount/
	sudo cp -v limine/BOOTX64.EFI img_mount/EFI/BOOT/
	sudo cp -v limine/BOOTIA32.EFI img_mount/EFI/BOOT/
	sync
	sudo umount img_mount
	sudo losetup -d `cat loopback_dev`
	rm -rf loopback_dev img_mount

.PHONY: clean
clean:
	rm -rf iso_root $(IMAGE_NAME).iso $(IMAGE_NAME).hdd
	rm -rf limine ovmf
	$(MAKE) -C kernel clean

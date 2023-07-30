echo ""
case $ARCH in
    x86_64)
        qemu-system-x86_64 -M q35 -m 2G -cdrom flare.iso -boot d -debugcon stdio
        ;;
esac

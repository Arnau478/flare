.PHONY: kernel
kernel:
	zig build
	cp zig-out/bin/kernel kernel.elf

.PHONY: test
test:
	zig test src/tests.zig

.PHONY: clean
clean:
	rm -rf zig-cache zig-out kernel.elf

# Bootloader

## Install the GCC Cross Compiler
```base
sudo apt update && sudo apt install build-essential bison flex libgmp3-dev libmpc-dev libmpfr-dev texinfo libisl-dev -y

git clone git://sourceware.org/git/binutils-gdb.git
git clone https://gcc.gnu.org/git/gcc.git
mkdir src
mv binutils-gdb gcc src
cd src
mkdir build-binutils
cd build-binutils

../binutils-gdb/configure --target=$TARGET --prefix="$PREFIX" --with-sysroot --disable-nls --disable-werror
make
make install

which -- $TARGET-as || echo $TARGET-as is not in the PATH
mkdir build-gcc
cd build-gcc

../gcc/configure --target=$TARGET --prefix="$PREFIX" --disable-nls --enable-languages=c,c++ --without-headers --disable-hosted-libstdcxx
make all-gcc
make all-target-libgcc
make all-target-libstdc++-v3
make install-gcc
make install-target-libgcc
make install-target-libstdc++-v3

$HOME/opt/cross/bin/$TARGET-gcc --version
export PATH="$HOME/opt/cross/bin:$PATH"
```

## Format the disk
```bash
sudo fdisk /dev/sda <<EOF
o
n
p
1

7816704
t
06
a
n
p
2

15633408
t
2
06
a
2
w
EOF
```

## Assemble and write the MBR
```bash
nasm -f bin boot.asm -o boot.bin
sudo dd if=boot.bin of=/dev/sda conv=notrunc bs=446 count=1
sudo dd if=boot.bin of=/dev/sda conv=notrunc bs=1 count=2 skip=510 seek=510
```

## Assemble and write the VBR for both partitions
```bash
nasm -f bin vbr.asm -o vbr.bin
sudo dd if=vbr.bin of=/dev/sda1 conv=notrunc bs=512 count=1
sudo dd if=vbr.bin of=/dev/sda2 conv=notrunc bs=512 count=1
```

## Assemble the entrypoint for kernels
```bash
i686-elf-as entry.s -o entry.o
```

## Compile, link and write kernel 1
```bash
i686-elf-gcc -c kernel.c -o kernel.o -std=gnu99 -ffreestanding -fno-builtin -O2 -Wall -Wextra
i686-elf-gcc -T linker.ld -o myos.elf -ffreestanding -O2 -nostdlib entry.o kernel.o
sudo dd if=myos.elf of=/dev/sda1 conv=notrunc bs=512 count=40 seek=1
```

## Compile, link and write kernel 2
```bash
i686-elf-gcc -c kernel2.c -o kernel2.o -std=gnu99 -ffreestanding -fno-builtin -O2 -Wall -Wextra
i686-elf-gcc -T linker.ld -o myos2.elf -ffreestanding -O2 -nostdlib entry.o kernel2.o
sudo dd if=myos2.elf of=/dev/sda2 conv=notrunc bs=512 count=40 seek=1
```

## Boot
```bash
sudo qemu-system-i386 -hda /dev/sda -no-reboot -no-shutdown
```

.section .text
.global _start
.type _start, @function

_start:
    call kernel_main

    cli
.hang:
    hlt
    jmp .hang

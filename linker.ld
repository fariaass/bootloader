ENTRY(_start)

SECTIONS
{
	.text 0x10000 : {
        *(.text .text*)
    }

    /* Put all initialized data sections */
    .data : {
        *(.data .data*)
    }

    /* Put all uninitialized data (BSS) sections */
    .bss : {
        *(COMMON)
        *(.bss .bss*)
    }

    /* Discard useless sections */
    /DISCARD/ : {
        *(.note*)
        *(.comment)
    }
}
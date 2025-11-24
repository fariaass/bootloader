[bits 16]
[org 0x7C00]

jmp short start
nop

GDT_Start:
  GDT_Null:
    dd 0x00                             ; First 4 bytes
    dd 0x00                             ; Second 4 bytes (8 bytes total)
  GDT_Code:           
    dw 0xFFFF                           ; Limit 0-15
    dw 0x0000                           ; Base 0-15
    db 0x00                             ; Base 16-23
    db 0x9A                             ; Access byte (0x9A or 10011010b)
    db 0xCF                             ; Limit 16-19 | Flags (0xCF or 11001111b)
    db 0x00                             ; Base 24-31
  GDT_Data:           
    dw 0xFFFF                           ; Limit 0-15
    dw 0x0000                           ; Base 0-15
    db 0x00                             ; Base 16-23
    db 0x92                             ; Access byte (0x96 or 10010110b)
    db 0xCF                             ; Limit 16-19 | Flags (0xCF or 11001111b)
    db 0x00                             ; Base 24-31
  GDT_Stack:            
    dw 0xFFFF                           ; Limit 0-15
    dw 0x0000                           ; Base 0-15
    db 0x00                             ; Base 16-23
    db 0x96                             ; Access byte (0x96 or 10010110b)
    db 0xCF                             ; Limit 16-19 | Flags (0xCF or 11001111b)
    db 0x00                             ; Base 24-31
GDT_End:

GDT_Descriptor:
  dw GDT_End - GDT_Start - 1            ; GDT Size (Limit is size-1)
  dd GDT_Start

CODE_SEG equ GDT_Code - GDT_Start
DATA_SEG equ GDT_Data - GDT_Start
STACK_SEG equ GDT_Stack - GDT_Start

DAP:                                    ; define the disk address packet
	db	0x10                              ; size of packet (16 bytes)
	db	0x00                              ; always 0
blkcnt:	dw	0x40 	                      ; number of sectors to write/read
	dw	0x8000		                        ; memory buffer destination address (0:8000) (offset)
	dw	0x00		                          ; memory buffer destination address (0:8000) (segment)
	dd	0x00000000 			                  ; lower bits, start of LBA
	dd	0x00000000		                    ; upper bits, start of LBA (for systems with LBA > 4 bytes)

EntryAddress:
  dd 0x00

ProgramHeaderTableOffset:
  dd 0x00

ProgramHeaderEntrySize:
  dw 0x00

ProgramHeaderEntriesNumber:
  dw 0x00

bootDrive: db 0

ERROR:
  mov ah, 0xE
  mov al, 0x45
  int 0x10
.hang:
  jmp .hang

start:
  cli
  mov [bootDrive], dl
  xor ax, ax
  mov ds, ax
  mov ss, ax         
  mov sp, 0x7B00
  sti           

  add ebx, 1
  call ReadSectors
  call ParseELFHeader
  call EnterProtectedMode

ReadSectors:
  mov dl, [bootDrive]
  mov [DAP + 0x08], ebx
	mov si, DAP		                        ; address of "disk address packet"
	mov ah, 0x42		                      ; interrupt instruction to read from a hdd in LBA mode
	int 0x13
	jc ERROR
  ret

ParseProgramHeaderTable:
  ; save program header offset in bx
  xor ebx, ebx
  mov bx, WORD [DAP + 0x04]
  add bx, WORD [ProgramHeaderTableOffset]

  ; save number of entrix in cx
  mov cx, WORD [ProgramHeaderEntriesNumber]
  parse_loop:
    ; if cx is 0, there is no more entries to load, return
    cmp cx, 0x00
    je .end 
    dec cx

    ; test if the entry is loadable, if not, try the next one
    mov eax, DWORD [bx]                 ; segment type
    cmp eax, 0x01
    jne parse_loop

    ; clear the memory space where the program will run
    push cx
    mov edi, DWORD [bx + 0x08]          ; p_vaddr
    mov ecx, DWORD [bx + 0x14]          ; p_memsz
    xor eax, eax
    db 0x67
    rep stosb

    ; copy the program entry to location
    mov ecx, DWORD [bx + 0x10]          ; p_filesz
    xor eax, eax
    mov ax, WORD [DAP + 0x04]           ; address where elf was loaded
    add eax, DWORD [bx + 0x04]          ; elf address + p_offset
    mov esi, eax                         
    mov edi, DWORD [bx + 0x08]          ; p_vaddr
    db 0x67                             ; tell nasm to use rep movsb 32 bit instruction, to handle addresses > 16 bit
    rep movsb

    pop cx
    add bx, [ProgramHeaderEntrySize]
    jmp parse_loop
  .end:
    ret

ParseELFHeader:
  ; save memory offset where elf program was loaded
  xor ebx, ebx
  mov bx, WORD [DAP + 0x04]
  
  ; verify if first 4 bytes are ".ELF"
  cmp DWORD [ebx], 0x464C457F
  jne ERROR

  ; fail boot if elf program is not 32 bit
  cmp BYTE [ebx + 0x04], 0x01
  jne ERROR

  ; fail if elf program type is not executable
  cmp WORD [ebx + 0x10], 0x0002
  jne ERROR

  ; fail if elf program instruction set is not x86
  cmp WORD [ebx + 0x12], 0x0003
  jne ERROR

  ; save program entry address
  mov eax, DWORD [ebx + 0x18]
  mov [EntryAddress], eax

  ; save program header information
  mov eax, DWORD [ebx + 0x1C]
  mov [ProgramHeaderTableOffset], eax

  mov ax, WORD [ebx + 0x2A]
  mov [ProgramHeaderEntrySize], ax

  mov ax, WORD [ebx + 0x2C]
  mov [ProgramHeaderEntriesNumber], ax

  call ParseProgramHeaderTable
  ret

EnterProtectedMode:
  cli                                   ; disable interrupts
  
  in al, 0x92                           ; enable A20 line (Fast A20 Gate)
  test al, 2
  jnz after
  or al, 2
  out 0x92, al
after:

  lgdt [GDT_Descriptor]                 ; load GDT register with start address of Global Descriptor Table

  mov eax, cr0 
  or al, 1                              ; set PE (Protection Enable) bit in CR0 (Control Register 0)
  mov cr0, eax

  jmp .flush
.flush:
  
  jmp dword CODE_SEG:ProtectedModeInit

[bits 32]
ProtectedModeInit:
  mov ax, DATA_SEG
  mov ds, ax
  mov es, ax
  mov fs, ax
  mov gs, ax

  mov ax, STACK_SEG
  mov ebp, 0x200000
  mov ss, ax
  mov esp, ebp

  call [EntryAddress]
  hlt

times (510 - ($-$$)) db 0

dw 0xAA55

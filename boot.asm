[bits 16]
[org 0x0600]

start:
  cli
  xor ax, ax
  mov ds, ax
  mov es, ax
  .CopyLower:
    mov cx, 0x0100
    mov si, 0x7C00
    mov di, 0x0600
    rep movsw
  jmp 0:LowStart

CheckEdd:
  mov ah, 0x41
  mov bx, 0x55AA
  mov dl, BYTE [bootDrive]
  int 0x13                      ; checking for EDD presence
  jc ERROR
  cmp bx, 0xAA55
	jne ERROR                     ; BX must have had its bytes swapped
	test cx, 1                    ; check support for the "fixed disk access subset"
	jz ERROR
  ret

ReadSectors:
  push ebx
  call CheckEdd
  pop ebx
  mov [DAP + 0x08], ebx
	mov si, DAP		                ; address of "disk address packet"
	mov ah, 0x42		              ; interrupt instruction to read from a hdd in LBA mode
	mov dl, BYTE [bootDrive]
	int 0x13
	jc ERROR
  ret

ClearScreen:
  mov ah, 0x00
  mov al, 0x03
  int 0x10
  ret

PrintString:
  mov ah, 0xE
  .print_msg_loop:
    lodsb
    cmp al, 0x00
    je .done
    int 0x10
    jmp .print_msg_loop
  .done:
    ret

PrintActivePartitionMessage:
  call PrintString
  mov al, bl
  add al, 0x30 ; print partition number
  int 0x10
  mov al, 0x0A ; line feed
  int 0x10
  mov al, 0x0D ; carriage return
  int 0x10
  ret

ListActivePartitions:
  mov cx, 0x01 ; start cx in 1, so when cx reachs 5, the func returns
  xor ebx, ebx
  mov ebx, PartitionsOffsets
  .print_loop:
    cmp WORD [ebx], 0x00
    je .next_partition
    push bx
    mov bl, cl
    mov si, messageActivePartition
    call PrintActivePartitionMessage
    pop bx
  .next_partition:
    add ebx, 0x02
    add cx, 0x01
    cmp cx, 0x05
    jne .print_loop ; if cx isn't 5, then didn't read all partitions
  
  ret

ReadUserInput:
  .read_loop:
    mov si, messageAskInput
    call PrintString

    mov ah, 0x00 ; interrupt code to read a key press
    int 0x16 ; BIOS interrupt for keyboard
    xor bx, bx
    mov bl, al ; save in bl the ASCII code of the key pressed

    mov ah, 0xE
    int 0x10 ; al already contains the ASCII value of the key pressed

    mov al, 0x0A ; line feed
    int 0x10
    mov al, 0x0D ; carriage return
    int 0x10

    cmp bl, 0x31
    jl .read_loop
    cmp bl, 0x34
    jg .read_loop ; if key pressed is not a valid number (1 - 4), ask again

    sub bl, 0x30 ; convert ascii to number
    xor eax, eax
    mov al, 0x02 ; set al to 2 which is the size of each offset entry of the offsets table
    mul bl ; multiply al by bl to obtain the offset + 2
    sub al, 0x02 ; subtract 2 to obtain the actual offset

    cmp WORD [PartitionsOffsets + eax], 0x00
    je .read_loop ; if partition is not active, ask again

  mov bx, WORD [PartitionsOffsets + eax] ; save our partition offset
  mov WORD [SelectedPartitionOffset], bx
  ret

SelectPartition:
  call ClearScreen
  call ListActivePartitions
  call ReadUserInput
  ret

LowStart:
  xor ax, ax
  mov ss, ax
  mov sp, 0x7C00
  sti   
  mov BYTE [bootDrive], dl
  .CheckPartitions:          
    mov eax, PartitionsOffsets
    mov bx, PT1              
    mov cx, 4
    .CKPTloop:
      push cx
      mov cl, BYTE [bx]
      test cl, 0x80
      jz .empty_partition ; if partition bit is not set, then ignore it and read the next one
      mov BYTE [FoundPartition], 0x01
      mov [eax], bx
    .empty_partition:
      pop cx
      add bx, 0x10
      add ax, 0x02
      dec cx
      jnz .CKPTloop
    cmp BYTE [FoundPartition], 0x01
    jne ERROR
    
    call SelectPartition
    add bx, 0x08
  .ReadVBR:
    mov ebx, DWORD [bx]
    call ReadSectors

  .jumpToVBR:
    cmp WORD [0x7DFE], 0xAA55
    jne ERROR
    mov si, WORD [SelectedPartitionOffset]
    mov dl, BYTE [bootDrive] 
    jmp 0x7C00

ERROR:
  mov ah, 0xE
  mov al, 0x45
  int 0x10
.hang:
  jmp .hang

DAP:                            ; define the disk address packet
	db	0x10                      ; size of packet (16 bytes)
	db	0x00                      ; always 0
blkcnt:	dw	0x01	              ; number of sectors to write/read
	dw	0x7C00		                ; memory buffer destination address (0:7c00) (offset)
	dw	0x00		                  ; memory buffer destination address (0:7c00) (segment)
	dd	0x00000000 			          ; lower bits, start of LBA
	dd	0x00000000		            ; upper bits, start of LBA (for systems with LBA > 4 bytes)

messageActivePartition db "Found active partition: ", 0
messageAskInput db "Select partition to boot: ", 0

bootDrive db 0x00
FoundPartition db 0x00
PartitionsOffsets:
  dw 0x00
  dw 0x00
  dw 0x00
  dw 0x00

SelectedPartitionOffset:
  dw 0x00

times (436 - ($-$$)) db 0x00

UID times 10 db 0x00
PT1 times 16 db 0x00
PT2 times 16 db 0x00
PT3 times 16 db 0x00
PT4 times 16 db 0x00

dw 0xAA55

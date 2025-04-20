global main

section .text
main:
    sub rsp, 40
    mov eax, 2
    mov ecx, 16
    mov ebx, 1
.powx:
    test ecx, ecx
    jz .powx_done
    imul ebx, eax
    dec ecx
    jmp .powx
.powx_done:
    sub ebx, 1
    add rsp, 40
    mov eax, ebx
    ret

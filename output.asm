extern printf
global main

section .data
    msg0 db `Hello, world!\n`, 0
    msg1 db `Another line.\n`, 0

section .text
main:
    sub rsp, 40
    lea rcx, [rel msg0]
    call printf
    lea rcx, [rel msg1]
    call printf
    add rsp, 40
    xor eax, eax
    ret

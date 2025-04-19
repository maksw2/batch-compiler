section .data
str0 db `Hello, world!\n`, 0
str1 db `Another line.\n`, 0

section .text
global main
extern printf

main:
    sub rsp, 40
    lea rcx, [rel str0]
    call printf
    lea rcx, [rel str1]
    call printf
    xor eax, eax
    add rsp, 40
    ret

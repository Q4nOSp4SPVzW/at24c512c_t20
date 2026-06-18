    .section .init, "ax"
    .global _start
_start:
    la sp, _sp
    call main

1:
    j 1b

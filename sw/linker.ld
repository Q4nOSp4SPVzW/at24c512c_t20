OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  ram (wxai!r) : ORIGIN = 0xF9000000, LENGTH = 16K
}

SECTIONS
{
  __stack_size = 512;

  .init : {
    KEEP(*(.init))
  } >ram

  .text : {
    *(.text .text.*)
    *(.rodata .rodata.*)
  } >ram

  . = ALIGN(4);
  .data : {
    *(.sdata .sdata.*)
    *(.data .data.*)
  } >ram

  . = ALIGN(4);
  __bss_start = .;
  .bss : {
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
  } >ram
  __bss_end = .;

  . = ALIGN(16);
  _end = .;

  /* Stack grows down from the end of RAM. Keep SP 16-byte aligned for RISC-V C code. */
  _sp = ORIGIN(ram) + LENGTH(ram);
  __stack_start = _sp - __stack_size;
}

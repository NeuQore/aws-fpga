OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text : { *(.text.init) *(.text) *(.text.*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) *(.sdata*) }
  .bss : {
    . = ALIGN(8);
    _bss_start = .;
    *(.bss*) *(COMMON)
    . = ALIGN(8);
    _bss_end = .;
  }
  . = ALIGN(16);
  _end = .;
  . = 0x81000000;
  _sp = .;
}

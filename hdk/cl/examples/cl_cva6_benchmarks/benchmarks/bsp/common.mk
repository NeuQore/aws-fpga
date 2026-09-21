PREFIX   ?= riscv64-unknown-elf
CC       := $(PREFIX)-gcc
OBJCOPY  := $(PREFIX)-objcopy
OBJDUMP  := $(PREFIX)-objdump

ROOT     := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BSP      := $(ROOT)/bsp

CFLAGS  ?= -march=rv64imafdc_zicsr -mabi=lp64d -static -mcmodel=medany \
            -fvisibility=hidden -nostdlib -nostartfiles -O2 -Wall -ffreestanding
INCLUDES := -I$(BSP)
LDFLAGS  := -T$(BSP)/link.ld

BSP_SRCS := $(BSP)/crt.S $(BSP)/uart.c

.PHONY: all clean
all: $(NAME).bin

$(NAME).elf: $(SRCS) $(BSP_SRCS) $(BSP)/link.ld
	$(CC) $(CFLAGS) $(INCLUDES) $(LDFLAGS) $(BSP_SRCS) $(SRCS) -o $@
	$(OBJDUMP) -d $@ > $(NAME).dump

$(NAME).bin: $(NAME).elf
	$(OBJCOPY) -O binary $< $@
	@echo "Built $@ (`wc -c < $@` bytes)"

clean:
	rm -f $(NAME).elf $(NAME).bin $(NAME).dump

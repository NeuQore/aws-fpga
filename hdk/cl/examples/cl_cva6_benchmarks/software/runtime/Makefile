SDK_USERSPACE_DIR := $(SDK_DIR)/userspace
SW_INC_DIR := ../include

INCLUDES := -I$(SW_INC_DIR) -I$(SDK_USERSPACE_DIR)/include
LDFLAGS := -L$(SDK_USERSPACE_DIR)/lib/so
LDLIBS := -lfpga_mgmt

CC = gcc
CFLAGS = -DCONFIG_LOGLEVEL=4 -std=gnu11 -g -Wall -Werror $(INCLUDES)

.PHONY: all clean check_env

all: check_env run_cva6_benchmark

run_cva6_benchmark: ../src/run_cva6_benchmark.c check_env
	$(CC) -o $@ $< $(CFLAGS) $(LDFLAGS) $(LDLIBS)

clean:
	$(RM) run_cva6_benchmark hello_cva6_linux

check_env:
ifndef SDK_DIR
	$(error SDK_DIR is undefined. Try "source sdk_setup.sh")
endif

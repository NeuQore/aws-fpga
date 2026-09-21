NAME := coremark
SRCS := core_list_join.c core_main.c core_matrix.c core_state.c core_util.c \
        core_portme.c cvt.c ee_printf.c
include ../../bsp/common.mk
CFLAGS += -DITERATIONS=10 -DFLAGS_STR=\""-O2"\" -DPERFORMANCE_RUN=1 -I.

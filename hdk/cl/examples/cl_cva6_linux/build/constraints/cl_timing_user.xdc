# CVA6 (cv64a6_imafdc_sv39) runs on clk_cpu = clk_main_a0 / 4 (62.5 MHz).
# Same CDC as cl_cva6: xpm_fifo_async (UART) plus 2-flop / toggle synchronizers.
# Treat clk_cpu as asynchronous to clk_main_a0 for STA (post-route WNS was
# -2.685 ns on rst_main_n -> i_uart_fifo when they were timed as related).

create_generated_clock -name clk_cpu \
  -source [get_ports clk_main_a0] \
  -divide_by 4 \
  [get_pins -hierarchical -filter {NAME =~ *i_clk_cpu_buf/O}]

set_clock_groups -asynchronous \
  -group [get_clocks clk_main_a0] \
  -group [get_clocks clk_cpu]

# HBM reference constraints adapted from cl_dram_hbm_dma.
set clk_main_a0 [get_clocks -of_objects [get_ports clk_main_a0]]
set clk_hbm_ref [get_clocks -of_objects [get_ports clk_hbm_ref]]

create_generated_clock -name clk_hbm_axi \
  -master_clock [get_clocks -of_objects \
    [get_pins -hierarchical -regexp {.*CL/clk_hbm_ref}]] \
  [get_pins -hierarchical -regexp \
    {.*/HBM_PRESENT_EQ_1.HBM_WRAPPER_I/HBM_MMCM_I/.*/mmcme4_adv_inst/CLKOUT0}]

set_false_path \
  -from [get_pins -hierarchical -regexp \
    {.*/HBM_PRESENT_EQ_1.HBM_WRAPPER_I/HBM_MMCM_I/inst/seq_reg1_reg.*/C}] \
  -to [get_pins -hierarchical -regexp \
    {.*/HBM_PRESENT_EQ_1.HBM_WRAPPER_I/HBM_MMCM_I/inst/clkout1_buf/CE}]

set_clock_groups -asynchronous \
  -group [get_clocks clk_main_a0] \
  -group [get_clocks clk_hbm_ref] \
  -group [get_clocks clk_hbm_axi]

set_clock_groups -asynchronous \
  -group [get_clocks clk_main_a0] \
  -group [get_clocks -of_objects \
    [get_pins -hierarchical -regexp {.*CL/clk_hbm_ref}]]

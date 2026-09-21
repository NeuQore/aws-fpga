TESTS := \
  bpu_1_loop_branch bpu_2_loop_branch bpu_2_toggle_branch \
  bpu_3_loop_branch bpu_3_loop_branch_regdep \
  bpu_4_recursive_func_branch bpu_5_indirect_branch \
  bpu_6_recursive_func_branch bpu_7_indirect_branch \
  bpu_8_nested_4loop_asc bpu_8_nested_4loop_desc bpu_combined \
  retire_test l1_cache_test_32kb \
  lrsc lrsc_mutex lrsc_mutex_cb \
  test_1_store2load_overlap test_2_store2load_overlap \
  test_3_store2load_overlap test_4_store2load_overlap \
  power_virus ipi uart_baud ncore_mem_access \
  coremark dhrystone hmmer libquantum mcf \
  fp16_dotp_rvv int8_dotp_rvv int8_dotp_imext mxfp4_dotp_imext_ar \
  imext_kernels qspi sdio_sdhc

.PHONY: all clean $(TESTS)

all: $(TESTS)

$(TESTS):
	$(MAKE) -C tests/$@

clean:
	for t in $(TESTS); do $(MAKE) -C tests/$$t clean; done

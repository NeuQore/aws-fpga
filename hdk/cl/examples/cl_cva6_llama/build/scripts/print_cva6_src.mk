# Extra makefile fragment. Invoked as:
#   make -C $CVA6_REPO_DIR -f Makefile -f print_cva6_src.mk print-cva6-src \
#        target=cv64a6_imafdc_sv39 RISCV=/usr OUT=/path/to/cva6_files.f

.PHONY: print-cva6-src
print-cva6-src:
	$(file >$(OUT),)
	$(foreach f,$(ariane_pkg),$(file >>$(OUT),$(f)))
	$(foreach f,$(filter-out $(fpga_filter),$(src_flist)),$(file >>$(OUT),$(f)))
	$(foreach f,$(filter-out $(fpga_filter),$(src)),$(file >>$(OUT),$(f)))
	$(foreach f,$(fpga_src),$(file >>$(OUT),$(f)))
	$(foreach f,$(wildcard $(CVA6_REPO_DIR)/corev_apu/axi_mem_if/src/*.sv),$(file >>$(OUT),$(f)))
	$(foreach f,$(wildcard $(CVA6_REPO_DIR)/corev_apu/fpga/src/axi2apb/src/*.sv),$(file >>$(OUT),$(f)))
	@echo "Wrote $(OUT)"

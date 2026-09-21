# Lightweight parse/elaboration check; does not synthesize or build a DCP.
if {![info exists ::env(CL_DIR)]} {
  error "CL_DIR must point to cl_cva6_linux"
}
if {![info exists ::env(HDK_COMMON_DIR)]} {
  error "HDK_COMMON_DIR must point to hdk/common"
}

set cl_dir $::env(CL_DIR)
set hdk_common $::env(HDK_COMMON_DIR)
set generated /tmp/cl_cva6_linux_sources.tcl

read_verilog -sv ${hdk_common}/lib/interfaces.sv
source ${generated}

set_property include_dirs [concat \
  [get_property include_dirs [current_fileset]] \
  [list \
    ${cl_dir}/design \
    ${hdk_common}/shell_stable/design/interfaces \
  ]] [current_fileset]

set pkg ${cl_dir}/design/cl_dram_dma_pkg.sv
read_verilog -sv ${pkg}
set sources [glob ${cl_dir}/design/*.{s,}v]
set sources [lsearch -all -inline -not -exact ${sources} ${pkg}]
read_verilog -sv ${sources}

set ip_root ${hdk_common}/ip/cl_ip/cl_ip.srcs/sources_1
read_ip [list \
  ${ip_root}/ip/axi_register_slice/axi_register_slice.xci \
  ${ip_root}/ip/axi_register_slice_light/axi_register_slice_light.xci \
  ${ip_root}/ip/cl_axi3_256b_reg_slice/cl_axi3_256b_reg_slice.xci \
  ${ip_root}/ip/cl_hbm_mmcm/cl_hbm_mmcm.xci \
  ${ip_root}/ip/cl_hbm/cl_hbm.xci \
]
add_files ${ip_root}/bd/cl_axi_sc_1x1/cl_axi_sc_1x1.bd
read_verilog ${hdk_common}/ip/cl_ip/cl_ip.gen/sources_1/bd/cl_axi_sc_1x1/hdl/cl_axi_sc_1x1_wrapper.v

synth_design -rtl -top cl_cva6_linux \
  -part xcvu47p-fsvh2892-2-e \
  -verilog_define XSDB_SLV_DIS \
  -verilog_define FPGA_TARGET_XILINX

puts "CVA6 Linux RTL elaboration completed"

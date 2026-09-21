# =============================================================================
# Amazon FPGA Hardware Development Kit
#
# Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Amazon Software License (the "License"). You may not use
# this file except in compliance with the License. A copy of the License is
# located at
#
#    http://aws.amazon.com/asl/
#
# or in the "license" file accompanying this file. This file is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
# implied. See the License for the specific language governing permissions and
# limitations under the License.
# =============================================================================


# Common header
source ${HDK_SHELL_DIR}/build/scripts/synth_cl_header.tcl


###############################################################################
print "Reading encrypted user source codes"
###############################################################################

#---- User would replace this section -----

if {![info exists ::env(CVA6_REPO_DIR)]} {
  set ::env(CVA6_REPO_DIR) /projects/prj1/sle-wajahat/cva6
}
if {![info exists ::env(TARGET_CFG)]} {
  set ::env(TARGET_CFG) cv64a6_imafdc_sv39
}

print "Generating and reading CVA6 source list"
set gen_py ${CL_DIR}/build/scripts/gen_cva6_sources.py
set cva6_tcl ${CL_DIR}/build/scripts/cva6_sources.tcl

# -ignorestderr: Tcl's exec otherwise errors out on any stderr output from the
# child even when it exits successfully.
if {[catch {exec -ignorestderr python3 ${gen_py} ${cva6_tcl}} gen_log]} {
  puts ${gen_log}
  print "WARNING: gen_cva6_sources.py returned non-zero"
} else {
  puts ${gen_log}
}

if {![file exists ${cva6_tcl}]} {
  error "CVA6 source list generation failed: ${cva6_tcl} was not created"
}
source ${cva6_tcl}

print "Reading CL wrapper sources"
read_verilog -sv [glob ${src_post_enc_dir}/cl_dram_dma_defines.vh]
set_property file_type {Verilog Header} [get_files ${src_post_enc_dir}/cl_dram_dma_defines.vh]
set_property is_global_include true     [get_files ${src_post_enc_dir}/cl_dram_dma_defines.vh]

set cl_axi_pkg ${src_post_enc_dir}/cl_dram_dma_pkg.sv
read_verilog -sv ${cl_axi_pkg}
set cl_trace_pkg ${src_post_enc_dir}/cva6_trace_pkg.sv
read_verilog -sv ${cl_trace_pkg}
set cl_wrapper_sources [glob ${src_post_enc_dir}/*.{s,}v]
set cl_wrapper_sources [lsearch -all -inline -not -exact ${cl_wrapper_sources} ${cl_axi_pkg}]
set cl_wrapper_sources [lsearch -all -inline -not -exact ${cl_wrapper_sources} ${cl_trace_pkg}]
read_verilog -sv ${cl_wrapper_sources}

#---- End of section replaced by User ----

###############################################################################
print "Reading CL IP blocks"
###############################################################################

#---- User would uncomment and/or list IPs required in their design ----

## DDR IP
# read_ip ${HDK_IP_SRC_DIR}/cl_ddr4_32g/cl_ddr4_32g.xci

## HBM IPs
read_ip [list \
  ${HDK_IP_SRC_DIR}/cl_hbm_mmcm/cl_hbm_mmcm.xci \
  ${HDK_IP_SRC_DIR}/cl_hbm/cl_hbm.xci
]

## Clocking IP's
# read_ip ${HDK_SHELL_DESIGN_DIR}/../../ip/cl_ip/cl_ip.srcs/sources_1/ip/clk_mmcm_a/clk_mmcm_a.xci
# read_ip ${HDK_SHELL_DESIGN_DIR}/../../ip/cl_ip/cl_ip.srcs/sources_1/ip/clk_mmcm_b/clk_mmcm_b.xci
# read_ip ${HDK_SHELL_DESIGN_DIR}/../../ip/cl_ip/cl_ip.srcs/sources_1/ip/clk_mmcm_c/clk_mmcm_c.xci
# read_ip ${HDK_SHELL_DESIGN_DIR}/../../ip/cl_ip/cl_ip.srcs/sources_1/ip/clk_mmcm_hbm/clk_mmcm_hbm.xci
# read_ip ${HDK_SHELL_DESIGN_DIR}/../../ip/cl_ip/cl_ip.srcs/sources_1/ip/cl_clk_axil_xbar/cl_clk_axil_xbar.xci
# read_ip ${HDK_SHELL_DESIGN_DIR}/../../ip/cl_ip/cl_ip.srcs/sources_1/ip/cl_sda_axil_xbar/cl_sda_axil_xbar.xci

## AXI register slices used by OCL and the HBM reference bridge
read_ip [list \
  ${HDK_IP_SRC_DIR}/axi_register_slice/axi_register_slice.xci \
  ${HDK_IP_SRC_DIR}/axi_register_slice_light/axi_register_slice_light.xci \
  ${HDK_IP_SRC_DIR}/cl_axi3_256b_reg_slice/cl_axi3_256b_reg_slice.xci
]

## AXI Conversion IP's
read_ip ${HDK_IP_SRC_DIR}/cl_axi_clock_converter/cl_axi_clock_converter.xci
# read_ip ${HDK_IP_SRC_DIR}/cl_axi_clock_converter_light/cl_axi_clock_converter_light.xci
# read_ip ${HDK_IP_SRC_DIR}/cl_axi4_to_axi3_conv/cl_axi4_to_axi3_conv.xci
# read_ip ${HDK_IP_SRC_DIR}/cl_axi_clock_converter_256b/cl_axi_clock_converter_256b.xci
# read_ip ${HDK_IP_SRC_DIR}/cl_axi_width_cnv_512_to_256/cl_axi_width_cnv_512_to_256.xci
# read_ip ${HDK_IP_SRC_DIR}/axi_clock_converter_0/axi_clock_converter_0.xci

## AXI Utility IP's
# read_ip ${HDK_IP_SRC_DIR}/cl_axi_interconnect/cl_axi_interconnect.xci
# read_ip ${HDK_IP_SRC_DIR}/cl_axi_interconnect_64G_ddr/cl_axi_interconnect_64G_ddr.xci

## Reference SmartConnect performs AXI4 512b/250MHz to AXI3 256b/450MHz
## conversion and safely remaps the 16-bit shell IDs to the 6-bit HBM port.
add_files [list \
  ${HDK_BD_SRC_DIR}/cl_axi_sc_1x1/cl_axi_sc_1x1.bd
]
read_verilog [list \
  ${HDK_BD_GEN_DIR}/cl_axi_sc_1x1/hdl/cl_axi_sc_1x1_wrapper.v
]

## Read IP for virtual jtag / ILA/VIO
# read_ip ${HDK_IP_SRC_DIR}/cl_debug_bridge/cl_debug_bridge.xci
# read_ip ${HDK_IP_SRC_DIR}/ila_1/ila_1.xci
# read_ip ${HDK_IP_SRC_DIR}/ila_vio_counter/ila_vio_counter.xci
# read_ip ${HDK_IP_SRC_DIR}/vio_0/vio_0.xci

#---- End of section uncommented by the User ----

###############################################################################
print "Reading user constraints"
###############################################################################

#---- User would replace this section -----

read_xdc [ list \
  ${constraints_dir}/cl_synth_user.xdc \
  ${constraints_dir}/cl_timing_user.xdc
]

set_property PROCESSING_ORDER LATE [get_files cl_synth_user.xdc]
set_property PROCESSING_ORDER LATE [get_files cl_timing_user.xdc]

#---- End of section replaced by User ----


###############################################################################
print "Starting synthesizing customer design ${CL}"
###############################################################################
update_compile_order -fileset sources_1

synth_design -mode out_of_context \
             -top ${CL} \
             -verilog_define XSDB_SLV_DIS \
             -verilog_define FPGA_TARGET_XILINX \
             -part ${DEVICE_TYPE} \
             -keep_equivalent_registers

###############################################################################
print "Connecting debug network"
###############################################################################

#---- User would replace this section -----

# set cl_ila_cells [get_cells -hier *ILA*]
# if {$cl_ila_cells != ""} {
#   connect_debug_cores -master [get_cells [get_debug_cores -filter {NAME=~*CL_DEBUG_BRIDGE*}]] \
#                       -slaves $cl_ila_cells
# }

#---- End of section replaced by User ----


# Common footer
source ${HDK_SHELL_DIR}/build/scripts/synth_cl_footer.tcl

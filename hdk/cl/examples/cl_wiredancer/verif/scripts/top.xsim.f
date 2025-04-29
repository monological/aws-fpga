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


-define CL_NAME=cl_wiredancer
-define DISABLE_VJTAG_DEBUG

-include $CL_DIR/verif/tests
-f ${HDK_COMMON_DIR}/verif/tb/filelists/tb.${SIMULATOR}.f
${TEST_NAME}

# ---------------------------------------------------------------------------
# CL-WIREDANCER RTL
# ---------------------------------------------------------------------------

-include $CL_DIR/design
${CL_DIR}/design/cl_wiredancer_defines.vh
${CL_DIR}/design/cl_axi_ctl.sv
${CL_DIR}/design/cl_kernel_ctl.sv
${CL_DIR}/design/cl_kernel_regs.sv
${CL_DIR}/design/cl_kernel_req.sv
${CL_DIR}/design/cl_clk_freq.sv
${CL_DIR}/design/cl_hbm_perf_kernel.sv
${CL_DIR}/design/cl_mem_hbm_axi4.sv
${CL_DIR}/design/cl_mem_hbm_wrapper.sv
${CL_DIR}/design/cl_mem_ocl_dec.sv
${CL_DIR}/design/cl_mem_pcis_dec.sv
${CL_DIR}/design/wd_pkg.sv
${CL_DIR}/design/cl_wiredancer.sv

# --- NEWLY-ADDED FILES -------------------------------------------------------
${CL_DIR}/design/areset_sync.sv
${CL_DIR}/design/axil_slave.sv
#${CL_DIR}/design/cl_dma_pcis_slv.sv
#${CL_DIR}/design/cl_dram_dma.sv
${CL_DIR}/design/cl_id_defines.vh
#${CL_DIR}/design/cl_mem_perf_defines.vh
#${CL_DIR}/design/cl_mem_perf.sv
${CL_DIR}/design/cl_ocl_slv.sv
${CL_DIR}/design/dual_clock_showahead_fifo.sv
${CL_DIR}/design/dma_result.sv
${CL_DIR}/design/ed25519_add_modp.sv
${CL_DIR}/design/ed25519_mul_modp.sv
${CL_DIR}/design/ed25519_point_add.sv
${CL_DIR}/design/ed25519_point_dbl.sv
${CL_DIR}/design/ed25519_sigverify_0.sv
${CL_DIR}/design/ed25519_sigverify_1.sv
${CL_DIR}/design/ed25519_sigverify_2.sv
${CL_DIR}/design/ed25519_sigverify_dsdp_mul.sv
${CL_DIR}/design/ed25519_sigverify_ecc.sv
${CL_DIR}/design/ed25519_sub_modp.sv
${CL_DIR}/design/key_store.sv
#${CL_DIR}/design/mul_const_ED25519_L0_6.svh
#${CL_DIR}/design/mul_const_ED25519_L0_133.svh
#${CL_DIR}/design/mul_const_ED25519_L0_260.svh
#${CL_DIR}/design/mul_wide_17nx26_dsp48e2.svh
${CL_DIR}/design/mul_wide.sv
${CL_DIR}/design/pcie_inorder.sv
${CL_DIR}/design/pcie_tr_ext.sv
${CL_DIR}/design/schl_cpu.sv
${CL_DIR}/design/schl_cpu_instr_rom.sv
${CL_DIR}/design/sha512_block.sv
${CL_DIR}/design/sha512_modq.sv
${CL_DIR}/design/sha512_modq_meta.sv
${CL_DIR}/design/sha512_msgseq.sv
${CL_DIR}/design/sha512_pre.sv
${CL_DIR}/design/sha512_round.sv
${CL_DIR}/design/sha512_sch.sv
${CL_DIR}/design/showahead_fifo.sv
${CL_DIR}/design/simple_dual_port_ram.sv
${CL_DIR}/design/tid_inorder.sv
${CL_DIR}/design/top_f2.sv

#
# RTL source from CL_DRAM_HBM_DMA
#
-include $CL_DIR/../cl_dram_hbm_dma
${CL_DIR}/../cl_dram_hbm_dma/design/axil_slave.sv
${CL_DIR}/../cl_dram_hbm_dma/design/cl_tst_scrb.sv
${CL_DIR}/../cl_dram_hbm_dma/design/cl_tst.sv
${CL_DIR}/../cl_dram_hbm_dma/design/cl_int_tst.sv
${CL_DIR}/../cl_dram_hbm_dma/design/cl_dram_dma_pkg.sv
${CL_DIR}/../cl_dram_hbm_dma/design/cl_pcim_mstr.sv
${CL_DIR}/../cl_dram_hbm_dma/design/cl_ila.sv
${CL_DIR}/../cl_dram_hbm_dma/design/cl_vio.sv
${CL_DIR}/../cl_dram_hbm_dma/design/cl_int_slv.sv
${CL_DIR}/../cl_dram_hbm_dma/design/cl_sda_slv.sv
${CL_DIR}/../cl_dram_hbm_dma/design/cl_dram_dma_axi_mstr.sv
${CL_DIR}/../cl_dram_hbm_dma/design/mem_scrb.sv

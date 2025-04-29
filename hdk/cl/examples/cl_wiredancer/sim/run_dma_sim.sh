#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run_dma_sim.sh  —  Compile & run dma_result testbench with Vivado XSIM
# -----------------------------------------------------------------------------
set -euo pipefail

###############################################################################
# 1. Vivado executables
###############################################################################
VIVADO_VER=$(vivado -version | awk 'NR==1{sub(/^v/, "", $2); print $2}')
VIVADO_ROOT="/opt/Xilinx/Vivado/${VIVADO_VER}"
XVLOG="${VIVADO_ROOT}/bin/xvlog"
XELAB="${VIVADO_ROOT}/bin/xelab"
XSIM="${VIVADO_ROOT}/bin/xsim"

###############################################################################
# 2. Directory layout
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DESIGN_ROOT="${SCRIPT_DIR}/../design"          # wd_pkg.sv etc.
TB_FILE="${SCRIPT_DIR}/test_dma_result_tb.sv"
SIM_DIR="${SCRIPT_DIR}/sim_dma_result"; mkdir -p "${SIM_DIR}"
cd "${SIM_DIR}"

###############################################################################
# 3. Pre-compiled primitive libs (unisim / unimacro)
###############################################################################
COMPLIB_DIR="$HOME/xsim_lib_${VIVADO_VER}"

if [[ ! -d "${COMPLIB_DIR}/unisim" ]]; then
  echo "[INFO] compile_simlib → ${COMPLIB_DIR}"
  vivado -mode batch -nolog -nojournal -notrace -source /dev/stdin <<TCL
compile_simlib -simulator xsim -language all -family virtexuplus \
               -dir ${COMPLIB_DIR} -force
quit
TCL
fi

# Put library map where the tools will see it
ln -sf "${COMPLIB_DIR}/xsim.ini" "${SIM_DIR}/xsim.ini"

###############################################################################
# 4. XPM sources → local 'xpm' library  (only if not done yet)
###############################################################################
if ! grep -q xpm_fifo_sync "${SIM_DIR}/xsim.ini"; then
  echo "[INFO] Compiling XPM source into local 'xpm' library"
  XPM_DIR="${VIVADO_ROOT}/data/ip/xpm"
  "${XVLOG}" -sv -work xpm                                             \
      "${XPM_DIR}/xpm_fifo/hdl/xpm_fifo.sv"                            \
      "${XPM_DIR}/xpm_memory/hdl/xpm_memory.sv"
fi

###############################################################################
# 5. Library list for the design
###############################################################################
LIBS=(-L xpm -L unisims_ver -L unimacro_ver)

###############################################################################
# 6. File list for user design + TB
###############################################################################
cat > filelist.f <<EOF
${DESIGN_ROOT}/cl_wiredancer_defines.vh
${DESIGN_ROOT}/cl_axi_ctl.sv
${DESIGN_ROOT}/cl_kernel_ctl.sv
${DESIGN_ROOT}/cl_kernel_regs.sv
${DESIGN_ROOT}/cl_kernel_req.sv
${DESIGN_ROOT}/cl_clk_freq.sv
${DESIGN_ROOT}/cl_hbm_perf_kernel.sv
${DESIGN_ROOT}/cl_mem_hbm_axi4.sv
${DESIGN_ROOT}/cl_mem_hbm_wrapper.sv
${DESIGN_ROOT}/cl_mem_ocl_dec.sv
${DESIGN_ROOT}/cl_mem_pcis_dec.sv
${DESIGN_ROOT}/wd_pkg.sv
${DESIGN_ROOT}/cl_wiredancer.sv
${DESIGN_ROOT}/areset_sync.sv
${DESIGN_ROOT}/axil_slave.sv
${DESIGN_ROOT}/cl_id_defines.vh
${DESIGN_ROOT}/cl_ocl_slv.sv
${DESIGN_ROOT}/dual_clock_showahead_fifo.sv
${DESIGN_ROOT}/dma_result.sv
${DESIGN_ROOT}/ed25519_add_modp.sv
${DESIGN_ROOT}/ed25519_mul_modp.sv
${DESIGN_ROOT}/ed25519_point_add.sv
${DESIGN_ROOT}/ed25519_point_dbl.sv
${DESIGN_ROOT}/ed25519_sigverify_0.sv
${DESIGN_ROOT}/ed25519_sigverify_1.sv
${DESIGN_ROOT}/ed25519_sigverify_2.sv
${DESIGN_ROOT}/ed25519_sigverify_dsdp_mul.sv
${DESIGN_ROOT}/ed25519_sigverify_ecc.sv
${DESIGN_ROOT}/ed25519_sub_modp.sv
${DESIGN_ROOT}/key_store.sv
${DESIGN_ROOT}/mul_wide.sv
${DESIGN_ROOT}/pcie_inorder.sv
${DESIGN_ROOT}/pcie_tr_ext.sv
${DESIGN_ROOT}/schl_cpu.sv
${DESIGN_ROOT}/schl_cpu_instr_rom.sv
${DESIGN_ROOT}/sha512_block.sv
${DESIGN_ROOT}/sha512_modq.sv
${DESIGN_ROOT}/sha512_modq_meta.sv
${DESIGN_ROOT}/sha512_msgseq.sv
${DESIGN_ROOT}/sha512_pre.sv
${DESIGN_ROOT}/sha512_round.sv
${DESIGN_ROOT}/sha512_sch.sv
${DESIGN_ROOT}/showahead_fifo.sv
${DESIGN_ROOT}/simple_dual_port_ram.sv
${DESIGN_ROOT}/tid_inorder.sv
${DESIGN_ROOT}/top_f2.sv
${TB_FILE}
EOF

###############################################################################
# 7. Compile → Elaborate → Run
###############################################################################
echo "[INFO] Compiling design & TB ..."
"${XVLOG}" -sv -f filelist.f "${LIBS[@]}"

echo "[INFO] Elaborating ..."
"${XELAB}" work.test_dma_result_tb "${LIBS[@]}" -timescale 1ns/1ps -debug typical

echo "[INFO] Running simulation ..."
"${XSIM}" work.test_dma_result_tb -runall

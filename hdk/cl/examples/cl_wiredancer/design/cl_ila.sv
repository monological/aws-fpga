// ============================================================================
// Amazon FPGA Hardware Development Kit
//
// Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Amazon Software License (the "License"). You may not use
// this file except in compliance with the License. A copy of the License is
// located at
//
//    http://aws.amazon.com/asl/
//
// or in the "license" file accompanying this file. This file is distributed on
// an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
// implied. See the License for the specific language governing permissions and
// limitations under the License.
// ============================================================================

// -----------------------------------------------------------------------------
// Simple AXI4 bus definition used by the debug cores
// -----------------------------------------------------------------------------
interface axi_bus_t #(DATA_WIDTH=512, ADDR_WIDTH=64, ID_WIDTH=16, LEN_WIDTH=8);
   logic [ID_WIDTH-1:0]   awid;
   logic [ADDR_WIDTH-1:0] awaddr;
   logic [LEN_WIDTH-1:0]  awlen;
   logic [2:0]            awsize;
   logic                  awvalid;
   logic                  awready;
   logic [1:0]            awburst;

   logic [ID_WIDTH-1:0]   wid;
   logic [DATA_WIDTH-1:0] wdata;
   logic [DATA_WIDTH/8-1:0] wstrb;
   logic                  wlast;
   logic                  wvalid;
   logic                  wready;

   logic [ID_WIDTH-1:0]   bid;
   logic [1:0]            bresp;
   logic                  bvalid;
   logic                  bready;

   logic [ID_WIDTH-1:0]   arid;
   logic [ADDR_WIDTH-1:0] araddr;
   logic [LEN_WIDTH-1:0]  arlen;
   logic [2:0]            arsize;
   logic                  arvalid;
   logic                  arready;
   logic [1:0]            arburst;

   logic [ID_WIDTH-1:0]   rid;
   logic [DATA_WIDTH-1:0] rdata;
   logic [1:0]            rresp;
   logic                  rlast;
   logic                  rvalid;
   logic                  rready;
endinterface


module cl_ila (

   input aclk,

   input drck,
   input shift,
   input tdi,
   input update,
   input sel,
   output logic tdo,
   input tms,
   input tck,
   input runtest,
   input reset,
   input capture,
   input bscanid_en,

   axi_bus_t cl_sh_pcim_bus

);

//----------------------------
// Debug bridge
//----------------------------
 cl_debug_bridge CL_DEBUG_BRIDGE (
      .clk(aclk),
      .S_BSCAN_drck(drck),
      .S_BSCAN_shift(shift),
      .S_BSCAN_tdi(tdi),
      .S_BSCAN_update(update),
      .S_BSCAN_sel(sel),
      .S_BSCAN_tdo(tdo),
      .S_BSCAN_tms(tms),
      .S_BSCAN_tck(tck),
      .S_BSCAN_runtest(runtest),
      .S_BSCAN_reset(reset),
      .S_BSCAN_capture(capture),
      .S_BSCAN_bscanid_en(bscanid_en)
   );


//----------------------------
// Debug Core ILA for dmm pcis AXI4 interface
//----------------------------
   ila_1 CL_DMA_ILA_0 (
                   .clk    (aclk),
                   .probe0 (cl_sh_pcim_bus.awvalid),
                   .probe1 (cl_sh_pcim_bus.awaddr),
                   .probe2 (2'b0),
                   .probe3 (cl_sh_pcim_bus.awready),
                   .probe4 (cl_sh_pcim_bus.wvalid),
                   .probe5 (cl_sh_pcim_bus.wstrb),
                   .probe6 (cl_sh_pcim_bus.wlast),
                   .probe7 (cl_sh_pcim_bus.wready),
                   .probe8 (1'b0),
                   .probe9 (1'b0),
                   .probe10 (cl_sh_pcim_bus.wdata),
                   .probe11 (1'b0),
                   .probe12 (cl_sh_pcim_bus.arready),
                   .probe13 (2'b0),
                   .probe14 (cl_sh_pcim_bus.rdata),
                   .probe15 (cl_sh_pcim_bus.araddr),
                   .probe16 (cl_sh_pcim_bus.arvalid),
                   .probe17 (3'b0),
                   .probe18 (3'b0),
                   .probe19 (cl_sh_pcim_bus.awid),
                   .probe20 (cl_sh_pcim_bus.arid),
                   .probe21 (cl_sh_pcim_bus.awlen),
                   .probe22 (cl_sh_pcim_bus.rlast),
                   .probe23 (3'b0),
                   .probe24 (cl_sh_pcim_bus.rresp),
                   .probe25 (cl_sh_pcim_bus.rid),
                   .probe26 (cl_sh_pcim_bus.rvalid),
                   .probe27 (cl_sh_pcim_bus.arlen),
                   .probe28 (3'b0),
                   .probe29 (cl_sh_pcim_bus.bresp),
                   .probe30 (cl_sh_pcim_bus.rready),
                   .probe31 (4'b0),
                   .probe32 (4'b0),
                   .probe33 (4'b0),
                   .probe34 (4'b0),
                   .probe35 (cl_sh_pcim_bus.bvalid),
                   .probe36 (4'b0),
                   .probe37 (4'b0),
                   .probe38 (cl_sh_pcim_bus.bid),
                   .probe39 (cl_sh_pcim_bus.bready),
                   .probe40 (1'b0),
                   .probe41 (1'b0),
                   .probe42 (1'b0),
                   .probe43 (1'b0)
                   );
endmodule

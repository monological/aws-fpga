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


//=============================================================================
// Top level module file for CL_WIREDANCER
//=============================================================================

module cl_wiredancer
#(
  parameter EN_DDR = 0,
  parameter EN_HBM = 0
)
(
    `include "cl_ports.vh"
);

`include "cl_id_defines.vh"       // Defines for ID0 and ID1 (PCI ID's)
`include "cl_dram_dma_defines.vh"

`include "unused_ddr_template.inc"
`include "unused_cl_sda_template.inc"
`include "unused_apppf_irq_template.inc"

///////////////////////////////////////////////////////////////////////
// Unused signals
///////////////////////////////////////////////////////////////////////

  // Tie off unused signals:
  assign cl_sh_dma_rd_full  = 'b0;
  assign cl_sh_dma_wr_full  = 'b0;

  assign cl_sh_pcim_awuser  = 'b0;
  assign cl_sh_pcim_aruser  = 'b0;
  // The design never issues reads so tie off the entire AR channel
  assign cl_sh_pcim_arid    = 16'b0;
  assign cl_sh_pcim_araddr  = 64'b0;
  assign cl_sh_pcim_arlen   = 8'b0;
  assign cl_sh_pcim_arsize  = 3'b0;
  assign cl_sh_pcim_arburst = 2'b0;
  assign cl_sh_pcim_arcache = 4'b0;
  assign cl_sh_pcim_arlock  = 1'b0;
  assign cl_sh_pcim_arprot  = 3'b0;
  assign cl_sh_pcim_arqos   = 4'b0;
  assign cl_sh_pcim_arvalid = 1'b0;
  assign cl_sh_pcim_rready  = 1'b0;

  assign cl_sh_status0      = 'b0;
  assign cl_sh_status1      = 'b0;
  assign cl_sh_status2      = 'b0;

  assign cl_sh_id0[31:0] = `CL_SH_ID0;
  assign cl_sh_id1[31:0] = `CL_SH_ID1;

  // Because the code references ddr_ready/hbm_ready but never declared them:
  logic ddr_ready, hbm_ready;
  assign ddr_ready = (EN_DDR) ? 1'b1 : 1'b0;
  assign hbm_ready = (EN_HBM) ? 1'b1 : 1'b0;

///////////////////////////////////////////////////////////////////////
// Clock and Reset synchronizers
///////////////////////////////////////////////////////////////////////

logic clk;
(* dont_touch = "true" *) logic pipe_rst_n;
logic pre_sync_rst_n;
(* dont_touch = "true" *) logic sync_rst_n;

assign clk = clk_main_a0;

// Reset synchronizer
lib_pipe #(.WIDTH(1), .STAGES(4)) PIPE_RST_N (
    .clk    (clk),
    .rst_n  (1'b1),
    .in_bus (rst_main_n),
    .out_bus(pipe_rst_n)
);

always_ff @(negedge pipe_rst_n or posedge clk) begin
   if (!pipe_rst_n) begin
      pre_sync_rst_n <= 0;
      sync_rst_n     <= 0;
   end
   else begin
      pre_sync_rst_n <= 1;
      sync_rst_n     <= pre_sync_rst_n;
   end
end

///////////////////////////////////////////////////////////////////////
// Local reset for code
///////////////////////////////////////////////////////////////////////

logic rst;
always_ff @(posedge clk_main_a0) begin
    rst <= ~sync_rst_n;
end

///////////////////////////////////////////////////////////////////////
///////////////// FLR resposne ////////////////////////////////////////
///////////////////////////////////////////////////////////////////////

  logic sh_cl_flr_assert_q = 'b0;

  // Auto FLR response
  always_ff @(posedge clk)
    if (!rst) begin
      sh_cl_flr_assert_q <= 0;
      cl_sh_flr_done     <= 0;
    end else begin
      sh_cl_flr_assert_q <= sh_cl_flr_assert;
      cl_sh_flr_done     <= sh_cl_flr_assert_q && !cl_sh_flr_done;
    end


///////////////////////////////////////////////////////////////////////
// WIREDANCER main logic
///////////////////////////////////////////////////////////////////////

// The top-level includes are parameterizable.  For brevity, we keep the code:
localparam DMA_N         = 1;
localparam NO_AVMM_MASTERS = 1;
localparam NO_BASE_ENGINES = 1;
localparam NO_DBG_TAPS     = 1;
localparam DBG_WIDTH       = 1024*2;
localparam DDR_SIM         = 0;

// Debug wires for demonstration
logic [NO_DBG_TAPS-1:0][DBG_WIDTH-1:0]  dbg_wires;

// Simple AVMM stubs
logic [NO_AVMM_MASTERS-1:0] avmm_fh_read;
logic [NO_AVMM_MASTERS-1:0] avmm_fh_write;
logic [NO_AVMM_MASTERS-1:0][32-1:0] avmm_fh_address;
logic [NO_AVMM_MASTERS-1:0][32-1:0] avmm_fh_writedata;
logic [NO_AVMM_MASTERS-1:0][32-1:0] avmm_fh_readdata;
logic [NO_AVMM_MASTERS-1:0]         avmm_fh_readdatavalid;
logic [NO_AVMM_MASTERS-1:0]         avmm_fh_waitrequest;

// Drive them to 0 by default
initial begin
  avmm_fh_read         = '0;
  avmm_fh_write        = '0;
  avmm_fh_address      = '0;
  avmm_fh_writedata    = '0;
end

////////////////////////////////////////////////////////////////////////
// AXI‐Lite (sh_ocl*) minimal state machine
////////////////////////////////////////////////////////////////////////

logic [2:0] st_ocl;
logic [2:0] ocl_mi;

always_comb begin
    // Default
    cl_ocl_arready = (st_ocl == 3'b000);
    cl_ocl_awready = (st_ocl == 3'b000) & ~ocl_cl_arvalid;
    cl_ocl_wready  = (st_ocl == 3'b011);
    cl_ocl_rresp   = 2'b00;
    cl_ocl_bresp   = 2'b00;
end

always_ff @(posedge clk) begin
    integer i;

    case (st_ocl)
        0: begin
            if (ocl_cl_arvalid) begin
                ocl_mi <= ocl_cl_araddr[10+:3];
                for (i = 0; i < NO_AVMM_MASTERS; i ++) begin
                    avmm_fh_address[i] <= ocl_cl_araddr[0+:10];
                    if (ocl_cl_araddr[10+:3] == i)
                        avmm_fh_read[i] <= ocl_cl_arvalid;
                end
                st_ocl <= 1;
            end
            else if (ocl_cl_awvalid) begin
                ocl_mi <= ocl_cl_awaddr[10+:3];
                for (i = 0; i < NO_AVMM_MASTERS; i ++) begin
                    avmm_fh_address[i] <= ocl_cl_awaddr[0+:10];
                end
                st_ocl <= 3;
            end
        end

        1: begin
            // Wait for read data
            if (~avmm_fh_waitrequest[ocl_mi])
                avmm_fh_read[ocl_mi] <= 1'b0;

            if (avmm_fh_readdatavalid[ocl_mi]) begin
                cl_ocl_rvalid <= 1'b1;
                cl_ocl_rdata  <= avmm_fh_readdata[ocl_mi];
                st_ocl        <= 2;
            end
        end

        2: begin
            if (ocl_cl_rready) begin
                cl_ocl_rvalid <= 1'b0;
                st_ocl        <= 0;
            end
        end

        3: begin
            // Prepare for write
            avmm_fh_write    [ocl_mi] <= ocl_cl_wvalid;
            avmm_fh_writedata[ocl_mi] <= ocl_cl_wdata;

            if (ocl_cl_wvalid) begin
                st_ocl <= 4;
            end
        end

        4: begin
            if (~avmm_fh_waitrequest[ocl_mi]) begin
                avmm_fh_write[ocl_mi] <= 1'b0;
                cl_ocl_bvalid         <= 1'b1;
                st_ocl                <= 5;
            end
        end

        5: begin
            if (ocl_cl_bready) begin
                cl_ocl_bvalid <= 1'b0;
                st_ocl        <= 0;
            end
        end

        default: st_ocl <= 0;
    endcase

    if (rst) begin
        st_ocl        <= 0;
        cl_ocl_rvalid <= 1'b0;
        cl_ocl_bvalid <= 1'b0;
        avmm_fh_read  <= '0;
        avmm_fh_write <= '0;
    end
end


////////////////////////////////////////////////////////////////////////
// vdip, vled
////////////////////////////////////////////////////////////////////////

logic [7:0] bresp_status;

always_ff @(posedge clk) begin
    if (sh_cl_pcim_bvalid && sh_cl_pcim_bresp != 2'b00) begin
        bresp_status <= {6'b0, sh_cl_pcim_bresp};  // Show BRESP[1:0] in LED
    end
    if (rst) begin
        bresp_status <= 8'h00;
    end
end

logic [3:0] vdip_func;
logic [3:0] vdip_sel;
logic [7:0] vdip_byte;
logic [15:0][7:0] vdip_bytes; // 16-entry array, each 8 bits

assign {vdip_byte, vdip_sel, vdip_func} = sh_cl_status_vdip;

always_ff @(posedge clk_main_a0) begin
    if (vdip_func == 4'hF) begin
        vdip_bytes[vdip_sel] <= vdip_byte;
    end

    cl_sh_status_vled <= { vdip_bytes[vdip_sel], vdip_sel, vdip_func };
    vdip_bytes[15] <= bresp_status;
end


////////////////////////////////////////////////////////////////////////
// Minimal AXI handling for DMA PCIS writes
////////////////////////////////////////////////////////////////////////

logic [1-1:0]                                st_addr_v;
logic [3-1:0]                                st_data_v;
logic [2-1:0]                                st_v;
logic [1-1:0]                                st_p;
logic [64-1:0]                               st_addr;
logic [2-1:0][256-1:0]                        st_data;

assign cl_sh_dma_pcis_awready                   = 1'b1;
assign cl_sh_dma_pcis_wready                    = 1'b1;
assign cl_sh_dma_pcis_bresp                     = '0;

always_ff @(posedge clk) cl_sh_dma_pcis_bvalid   <= sh_cl_dma_pcis_wvalid & sh_cl_dma_pcis_wlast;
always_ff @(posedge clk) cl_sh_dma_pcis_bid      <= sh_cl_dma_pcis_awid;

showahead_fifo #(
    .WIDTH                              ($bits(sh_cl_dma_pcis_awaddr)),
    .DEPTH                              (32)
) st_in_addr_fifo_inst (
    .aclr                               (rst),

    .wr_clk                             (clk),
    .wr_req                             (sh_cl_dma_pcis_awvalid & cl_sh_dma_pcis_awready),
    .wr_full                            (),
    .wr_data                            ({sh_cl_dma_pcis_awaddr[64-1:6], 6'h0}),

    .rd_clk                             (clk),
    .rd_req                             (st_p),
    .rd_empty                           (),
    .rd_not_empty                       (st_addr_v),
    .rd_count                           (),
    .rd_data                            ({st_addr})
);

showahead_fifo #(
    .WIDTH                              ($bits({sh_cl_dma_pcis_wdata, sh_cl_dma_pcis_wstrb[32], sh_cl_dma_pcis_wstrb[0]})),
    .DEPTH                              (32)
) st_in_data_fifo_inst (
    .aclr                               (rst),

    .wr_clk                             (clk),
    .wr_req                             (sh_cl_dma_pcis_wvalid & cl_sh_dma_pcis_wready),
    .wr_full                            (),
    .wr_data                            ({sh_cl_dma_pcis_wdata, sh_cl_dma_pcis_wstrb[32], sh_cl_dma_pcis_wstrb[0]}),

    .rd_clk                             (clk),
    .rd_req                             (st_p),
    .rd_empty                           (),
    .rd_not_empty                       (st_data_v[2]),
    .rd_count                           (),
    .rd_data                            ({st_data, st_data_v[0+:2]})
);

assign st_p                             = st_addr_v & st_data_v[2];
assign st_v[0]                          = st_addr_v & st_data_v[2] & st_data_v[0];
assign st_v[1]                          = st_addr_v & st_data_v[2] & st_data_v[1];

////////////////////////////////////////////////////////////////////////
// Minimal bridging to PCIM master interface
////////////////////////////////////////////////////////////////////////

logic        dma_push_valid;
logic        dma_push_ready;
logic        dma_addr_fifo_full, dma_data_fifo_full;
logic [63:0] dma_push_addr;   // addresses
logic [63:0] dma_push_wstrb;  // unused (WSTRB not needed now)
logic [255:0] dma_push_data;  // 256-bit data chunk

// --------------------------------------------------------------------
// FIFO Handshake Logic
// --------------------------------------------------------------------
logic        pcim_awvalid, pcim_wvalid;
logic        pcim_fifo_dequeue;
logic [63:0] pcim_awaddr;
logic [255:0] pcim_wdata_half;

// --------------------------------------------------------------------
// AXI4 Master Interface (static fields)
assign cl_sh_pcim_awid    = 4'b0000;
assign cl_sh_pcim_awlen   = 8'b0;
assign cl_sh_pcim_awsize  = 3'b110;
assign cl_sh_pcim_awburst = 2'b01;   // Incrementing burst
assign cl_sh_pcim_awcache = 4'b0;
assign cl_sh_pcim_awlock  = 1'b0;
assign cl_sh_pcim_awprot  = 3'b0;
assign cl_sh_pcim_awqos   = 4'b0;
assign cl_sh_pcim_wid     = 16'b0;
assign cl_sh_pcim_wlast   = 1'b1;
assign cl_sh_pcim_bready  = 1'b1;  // Always ready to accept BRESP
assign cl_sh_pcim_wdata   = {2{pcim_wdata_half}};  // Duplicate 256b to 512b
assign cl_sh_pcim_wstrb   = 64'hFFFFFFFFFFFFFFFF;  // Required: full 512-bit write

// --------------------------------------------------------------------
// FIFO Instances
// --------------------------------------------------------------------
showahead_fifo #(
    .WIDTH(64),
    .FULL_THRESH(512-64),
    .DEPTH(512)
) dma_addr_fifo_inst (
    .aclr          (rst),
    .wr_clk        (clk),
    .wr_req        (dma_push_valid & dma_push_ready),
    .wr_full       (dma_addr_fifo_full),
    .wr_data       (dma_push_addr),
    .rd_clk        (clk),
    .rd_req        (pcim_fifo_dequeue),
    .rd_empty      (),
    .rd_not_empty  (pcim_awvalid),
    .rd_count      (),
    .rd_data       (pcim_awaddr)
);

showahead_fifo #(
    .WIDTH(256),
    .FULL_THRESH(512-64),
    .DEPTH(512)
) dma_data_fifo_inst (
    .aclr          (rst),
    .wr_clk        (clk),
    .wr_req        (dma_push_valid & dma_push_ready),
    .wr_full       (dma_data_fifo_full),
    .wr_full_b     (),
    .wr_count      (),
    .wr_data       (dma_push_data),
    .rd_clk        (clk),
    .rd_req        (pcim_fifo_dequeue),
    .rd_empty      (),
    .rd_not_empty  (pcim_wvalid),
    .rd_count      (),
    .rd_data       (pcim_wdata_half)
);

// --------------------------------------------------------------------
// Push logic from staging FIFO to PCIM write pipeline
// --------------------------------------------------------------------
assign dma_push_ready     = ~dma_addr_fifo_full & ~dma_data_fifo_full;

// Dequeue only when both AW and W channels are ready
assign pcim_fifo_dequeue = pcim_awvalid && pcim_wvalid &&
                           sh_cl_pcim_awready && sh_cl_pcim_wready;

// Drive PCIM AXI4 valid signals
assign cl_sh_pcim_awvalid = pcim_awvalid;
assign cl_sh_pcim_awaddr  = pcim_awaddr;
assign cl_sh_pcim_wvalid  = pcim_wvalid;


////////////////////////////////////////////////////////////////////////
// Example “top_f2” instance (from your snippet)
////////////////////////////////////////////////////////////////////////

`ifndef TOP_NAME
`define TOP_NAME top_f2
`endif

`TOP_NAME #(
  .DBG_WIDTH(DBG_WIDTH),
  .DMA_N     (DMA_N)
) top_inst (
    .avmm_read         (avmm_fh_read [0]),
    .avmm_write        (avmm_fh_write[0]),
    .avmm_address      (avmm_fh_address[0]),
    .avmm_writedata    (avmm_fh_writedata[0]),
    .avmm_readdata     (avmm_fh_readdata[0]),
    .avmm_readdatavalid(avmm_fh_readdatavalid[0]),
    .avmm_waitrequest  (avmm_fh_waitrequest[0]),

    .priv_bytes        (vdip_bytes),

    // PCIE bridging (input side)
    .pcie_v(st_v),
    .pcie_a(st_addr),
    .pcie_d(st_data),

    // Example DMA push
    .dma_push_ready    (dma_push_ready),
    .dma_push_valid    (dma_push_valid),
    .dma_push_addr     (dma_push_addr),
    .dma_push_wstrb    (dma_push_wstrb),
    .dma_fifo_full     (dma_addr_fifo_full | dma_data_fifo_full),
    .dma_push_data     (dma_push_data),

    .dbg_wire          (dbg_wires[0]),

    // Used to clock SV. Change to faster clock domain for
    // higher throughput. 
    .clk_f             (clk),
    .rst_f             (rst),

    .clk               (clk),
    .rst               (rst)
);


endmodule // cl_wiredancer

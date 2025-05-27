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
// Tie off the application PF interrupt request signals. Including the template
// caused a syntax issue when compiling with XSIM, so perform the assignment
// directly here instead of relying on the include file.
assign cl_sh_apppf_irq_req = 16'b0;

///////////////////////////////////////////////////////////////////////
// Unused signals
///////////////////////////////////////////////////////////////////////

  // Tie off unused signals:
  assign cl_sh_dma_rd_full  = 'b0;
  assign cl_sh_dma_wr_full  = 'b0;

  assign cl_sh_pcim_awuser  = 'b0;
  assign cl_sh_pcim_aruser  = 'b0;

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

assign cl_sh_dma_pcis_awready = 1'b1;
assign cl_sh_dma_pcis_wready  = 1'b1;
assign cl_sh_dma_pcis_bresp   = 2'b00;

// We ack the write once we see wlast
always_ff @(posedge clk) begin
  cl_sh_dma_pcis_bvalid <= sh_cl_dma_pcis_wvalid & sh_cl_dma_pcis_wlast;
  cl_sh_dma_pcis_bid    <= sh_cl_dma_pcis_awid;
  if (rst) begin
    cl_sh_dma_pcis_bvalid <= 1'b0;
    cl_sh_dma_pcis_bid    <= 4'b0;
  end
end

 // FIFO that holds AW address and length for incoming bursts
 logic aw_fifo_v;
 logic aw_fifo_pop;
 logic [63:0] aw_addr_q;
 logic [7:0]  aw_len_q;

 showahead_fifo #(
     .WIDTH(72),
     .DEPTH(32)
) aw_fifo_inst (
     .aclr      (rst),
     .wr_clk    (clk),
     .wr_req    (sh_cl_dma_pcis_awvalid & cl_sh_dma_pcis_awready),
     .wr_full   (),
     .wr_data   ({sh_cl_dma_pcis_awaddr, sh_cl_dma_pcis_awlen}),

     .rd_clk    (clk),
     .rd_req    (aw_fifo_pop),
     .rd_empty  (),
     .rd_not_empty(aw_fifo_v),
     .rd_count  (),
     .rd_data   ({aw_addr_q, aw_len_q})
 );

 // FIFO that holds W channel data and strobe
wire        st_p;          // dequeue signal for data FIFO
logic       st_data_v;
logic [255:0] st_data;
logic [31:0]  st_data_strb;
logic         st_data_fifo_wr_full;
logic [5:0]   st_data_fifo_rd_count;

showahead_fifo #(
    .WIDTH(288),
    .DEPTH(32)
) st_in_data_fifo_inst (
    .aclr        (rst),
    .wr_clk      (clk),
    .wr_req      (sh_cl_dma_pcis_wvalid & cl_sh_dma_pcis_wready),
    .wr_full     (st_data_fifo_wr_full),
    .wr_data     ({sh_cl_dma_pcis_wdata[255:0], sh_cl_dma_pcis_wstrb[31:0]}),

    .rd_clk      (clk),
    .rd_req      (st_p),
    .rd_empty    (),  // optional dummy if unused
    .rd_not_empty(st_data_v),
    .rd_count    (st_data_fifo_rd_count),
    .rd_data     ({st_data, st_data_strb})
);

////////////////////////////////////////////////////////////////////////
// Minimal bridging to PCIM master interface
////////////////////////////////////////////////////////////////////////

logic        dma_push;
logic        dma_r;
logic        dma_full_a, dma_full_d;
logic [63:0] dma_push_a;   // addresses
logic [255:0] dma_push_d;  // 256-bit data chunk

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
    .wr_req        (dma_push & dma_r),
    .wr_full       (dma_full_a),
    .wr_data       (dma_push_a),
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
    .wr_req        (dma_push & dma_r),
    .wr_full       (dma_full_d),
    .wr_full_b     (),
    .wr_count      (),
    .wr_data       (dma_push_d),
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
assign dma_r = ~dma_full_a & ~dma_full_d;

// Read from the PCIS FIFOs only when there is an active burst or a new AW entry
assign st_p = (aw_active || aw_fifo_v) & st_data_v & dma_r;

// Dequeue only when both AW and W channels are ready
assign pcim_fifo_dequeue = pcim_awvalid && pcim_wvalid &&
                           sh_cl_pcim_awready && sh_cl_pcim_wready;

// Drive PCIM AXI4 valid signals
assign cl_sh_pcim_awvalid = pcim_awvalid;
assign cl_sh_pcim_awaddr  = pcim_awaddr;
assign cl_sh_pcim_wvalid  = pcim_wvalid;

////////////////////////////////////////////////////////////////////////
// Simple PCIS to PCIM loopback with burst address handling
////////////////////////////////////////////////////////////////////////

logic        aw_active;
logic [63:0] cur_addr;
logic [7:0]  beats_left;

always_ff @(posedge clk) begin
    dma_push       <= 1'b0;
    aw_fifo_pop    <= 1'b0;

    if (rst) begin
        aw_active   <= 1'b0;
        cur_addr    <= 64'd0;
        beats_left  <= 8'd0;
    end else begin
        if (st_p) begin
            dma_push   <= 1'b1;
            dma_push_d <= st_data;

            if (!aw_active) begin
                // start of a new burst
                aw_fifo_pop <= 1'b1;
                dma_push_a  <= aw_addr_q;
                cur_addr    <= aw_addr_q + 64;
                beats_left  <= aw_len_q;
                aw_active   <= (aw_len_q != 0);
            end else begin
                dma_push_a  <= cur_addr;
                cur_addr    <= cur_addr + 64;
                if (beats_left != 0) begin
                    beats_left <= beats_left - 1;
                    // After the decrement, aw_active should deassert when no
                    // beats remain. Without this check, aw_active could stay
                    // high after the last beat which causes the next burst to
                    // reuse the previous address.
                    aw_active  <= (beats_left != 1);
                end else begin
                    aw_active  <= 1'b0;
                end
            end
        end
    end
end


endmodule // cl_wiredancer

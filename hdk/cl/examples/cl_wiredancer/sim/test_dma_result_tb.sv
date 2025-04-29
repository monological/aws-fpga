// ============================================================================
// test_dma_result_tb.sv  –  round-trip bench for CL_WIREDANCER
// ============================================================================

`timescale 1ns/1ps

module test_cl_wiredancer_tb;

//----------------------------------------------------------------------------
// 1. clocks & resets
//----------------------------------------------------------------------------
logic clk   = 0;  always #1     clk   = ~clk;     // 1 GHz
logic clk_f = 0;  always #0.9   clk_f = ~clk_f;   // 1.11 GHz

logic rst   = 1, rst_f = 1;
initial begin
  repeat (32) @(posedge clk ); rst   = 0;
  repeat (32) @(posedge clk_f); rst_f = 0;
end

//----------------------------------------------------------------------------
// 2. SH-CL interface signals we really use
//----------------------------------------------------------------------------
logic clk_main_a0 = clk;
logic rst_main_n  = ~rst;

/* DMA-PCIS host→CL */
logic [63:0]  sh_cl_dma_pcis_awaddr  = 0;
logic [2:0]   sh_cl_dma_pcis_awsize  = 0;
logic [1:0]   sh_cl_dma_pcis_awburst = 0;
logic         sh_cl_dma_pcis_awvalid = 0;
wire          cl_sh_dma_pcis_awready;

logic [511:0] sh_cl_dma_pcis_wdata  = 0;
logic [63:0]  sh_cl_dma_pcis_wstrb  = 0;
logic         sh_cl_dma_pcis_wlast  = 0;
logic         sh_cl_dma_pcis_wvalid = 0;
wire          cl_sh_dma_pcis_wready;

wire          cl_sh_dma_pcis_bvalid;
logic         sh_cl_dma_pcis_bready = 0;

/* PCIM CL→host */
wire  [63:0] cl_sh_pcim_awaddr;
wire         cl_sh_pcim_awvalid;
logic        sh_cl_pcim_awready = 1;

wire [511:0] cl_sh_pcim_wdata;
wire         cl_sh_pcim_wvalid, cl_sh_pcim_wlast;
logic        sh_cl_pcim_wready  = 1;

logic  [1:0] sh_cl_pcim_bresp  = 2'b00;
logic        sh_cl_pcim_bvalid = 0;
wire         cl_sh_pcim_bready;

/* quick taps */
wire [3:0] pcie_il = dut.top_inst.pcie_il;
wire       dma_v   = dut.dma_push;
wire       dma_r   = dut.dma_r;
wire [63:0] dma_b  = dut.dma_push_b;
wire [255:0] dma_d = dut.dma_push_d;

//----------------------------------------------------------------------------
// 3. instantiate DUT
//----------------------------------------------------------------------------
cl_wiredancer dut (.*);

//----------------------------------------------------------------------------
// 4. startup forces from original python bench
//----------------------------------------------------------------------------
initial begin
  force dut.top_inst.avmm_read  = 0;
  force dut.top_inst.avmm_write = 0;
  force dut.top_inst.dma_f      = 0;
  force dut.top_inst.pcie_v     = 0;
  force dut.top_inst.send_fails = 1;
end

//----------------------------------------------------------------------------
// 5. random dma_r pulses
//----------------------------------------------------------------------------
initial forever begin
  @(posedge clk);
  if ($urandom_range(0,49)==0) begin
    force dut.dma_r = 1;
    @(posedge clk);
    force dut.dma_r = 0;
  end
end

// ============================================================================
// 6. helpers – compact versions of the python functions
// ============================================================================
localparam int PCIE_MAGIC = 32'hACE0_FBAC;

function longint unsigned rnd (input int w);
  longint unsigned n=0; for (int i=0;i<w;i++) n=(n<<1)|$urandom_range(0,1);
  return n;
endfunction

function longint unsigned bits (input longint unsigned v,input int b,input int s);
  return (v>>s)&((64'h1<<b)-1);
endfunction

typedef struct packed { // packed – no arrays
  longint unsigned src, tid;
  longint unsigned sig_l, sig_h, pub;
  int              msg_sz;
  int              dma_ctrl, dma_size, dma_chunk;
  longint unsigned dma_addr, dma_seq;
  bit              sigverify;
} tr_hdr_t;

//----------------------------------------------------------------------------
// 7. AXI DMA-PCIS single-beat writer
//----------------------------------------------------------------------------
task dma_write64 (input logic [63:0] addr,
                  input logic [511:0] data);
  /* AW */
  sh_cl_dma_pcis_awaddr  <= addr;
  sh_cl_dma_pcis_awsize  <= 3'b110;
  sh_cl_dma_pcis_awburst <= 2'b01;
  sh_cl_dma_pcis_awvalid <= 1;
  @(posedge clk);  wait (cl_sh_dma_pcis_awready);
  sh_cl_dma_pcis_awvalid <= 0;

  /* W */
  sh_cl_dma_pcis_wdata  <= data;
  sh_cl_dma_pcis_wstrb  <= '1;
  sh_cl_dma_pcis_wlast  <= 1;
  sh_cl_dma_pcis_wvalid <= 1;
  @(posedge clk);  wait (cl_sh_dma_pcis_wready);
  sh_cl_dma_pcis_wvalid <= 0;
  sh_cl_dma_pcis_wlast  <= 0;

  /* B */
  sh_cl_dma_pcis_bready <= 1;
  wait (cl_sh_dma_pcis_bvalid);
  sh_cl_dma_pcis_bready <= 0;
endtask

// ============================================================================
// 8. scoreboard queues
// ============================================================================
typedef struct {logic [63:0] addr; logic [511:0] data;} beat_t;
beat_t exp_q[$], aw_q[$], w_q[$];
int    mismatches = 0;

// PCIM back-pressure
always @(posedge clk) begin
  sh_cl_pcim_awready <= ($urandom_range(0,3)!=0);
  sh_cl_pcim_wready  <= ($urandom_range(0,3)!=0);
end
assign cl_sh_pcim_bready = 1'b1;

// capture PCIM transactions
always @(posedge clk)
  if (cl_sh_pcim_awvalid && sh_cl_pcim_awready)
    aw_q.push_back('{addr:cl_sh_pcim_awaddr, data:'0});

always @(posedge clk)
  if (cl_sh_pcim_wvalid && sh_cl_pcim_wready && cl_sh_pcim_wlast)
    w_q.push_back('{addr:'0, data:cl_sh_pcim_wdata});

// compare when both present
always @(posedge clk) begin
  if (aw_q.size() && w_q.size()) begin
    beat_t g_aw = aw_q.pop_front();
    beat_t g_w  = w_q .pop_front();
    beat_t ex   = exp_q.pop_front();
    if (g_aw.addr!==ex.addr || g_w.data!==ex.data) mismatches++;
    sh_cl_pcim_bvalid <= 1;
  end else
    sh_cl_pcim_bvalid <= 0;
end

//----------------------------------------------------------------------------
// 9. simple dma_push checker
//----------------------------------------------------------------------------
int dma_err = 0;
always @(posedge clk)
  if (dma_v && dma_r) begin
    bit ok = dma_d[2] == ~dma_b[0];
    if (!ok) dma_err++;
  end

// ============================================================================
// 10. main stimulus
// ============================================================================
initial begin
  int unsigned tid     = 32'hABCD0000 - 1;
  longint unsigned pcie_a = 0;
  longint unsigned pcie_b = 64'h1_0000_0000;

  @(negedge rst);  repeat (2048) @(posedge clk);

  for (int t=0; t<20; t++) begin
    repeat ($urandom_range(10,250)) @(posedge clk);
    while (pcie_il[0] > 2) @(posedge clk);

    //------------------------------------------------------------
    // build minimal transaction header (payload later)
    //------------------------------------------------------------
    tr_hdr_t h;
    h.src        = rnd(12)<<4;
    h.tid        = ++tid;
    h.sig_l      = rnd(256);
    h.sig_h      = rnd(256);
    h.pub        = rnd(256);
    h.msg_sz     = $urandom_range(32,1280);
    h.dma_ctrl   = 0;  h.dma_size = 0;  h.dma_chunk = $urandom;
    h.dma_addr   = rnd(59)<<5;
    h.dma_seq    = $urandom;
    h.sigverify  = 1;

    // header beat
    logic [511:0] header = '0;
    header[ 31: 0] = PCIE_MAGIC;
    header[ 47:32] = h.src;
    header[ 63:48] = h.msg_sz + 64;
    header[ 79:64] = h.dma_size;
    header[ 95:80] = h.dma_ctrl;
    header[159:96] = h.dma_addr;
    header[223:160]= h.dma_seq;
    header[287:224]= h.dma_chunk;

    // sig/pub beats
    logic [511:0] blk_sig = {h.sig_h, h.sig_l};
    logic [511:0] blk_pub = {h.pub  , 256'd0};

    // push header + sig + pub
    beat_t tmp;
    tmp='{addr:pcie_b|pcie_a, data:header}; exp_q.push_back(tmp);
    dma_write64(pcie_b|pcie_a, header);  pcie_a += 64;

    tmp='{addr:pcie_b|pcie_a, data:blk_sig}; exp_q.push_back(tmp);
    dma_write64(pcie_b|pcie_a, blk_sig); pcie_a += 64;

    tmp='{addr:pcie_b|pcie_a, data:blk_pub}; exp_q.push_back(tmp);
    dma_write64(pcie_b|pcie_a, blk_pub); pcie_a += 64;

    // message beats
    int blks_msg = (h.msg_sz+63)/64;
    for (int m=0; m<blks_msg; m++) begin
      logic [511:0] msgb = '0;
      for (int i=0; i<64; i++) begin
        int idx = m*64+i;
        if (idx < h.msg_sz)
          msgb[i*8 +:8] = $urandom_range(0,255);
      end
      tmp='{addr:pcie_b|pcie_a, data:msgb}; exp_q.push_back(tmp);
      dma_write64(pcie_b|pcie_a, msgb); pcie_a += 64;
    end
    pcie_a &= (64'h1<<34)-1;
  end

  // drain
  repeat (4096) @(posedge clk);

  if (mismatches==0 && exp_q.size()==0 && dma_err==0)
    $display("✅  PASS – all 20 transactions round-tripped correctly");
  else
    $error("❌  FAIL  mism=%0d  pending=%0d  dma_err=%0d",
           mismatches, exp_q.size(), dma_err);

  $finish;
end

endmodule

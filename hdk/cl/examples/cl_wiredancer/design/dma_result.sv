`default_nettype none

import wd_sigverify::*;

module dma_result #(
    PCIE_N                                              = 2
) (
    input wire [1-1:0]                                  dma_push_ready,
    output logic [1-1:0]                                dma_push_valid,
    output logic [64-1:0]                               dma_push_addr,
    output logic [64-1:0]                               dma_push_wstrb,
    input wire [1-1:0]                                  dma_fifo_full,
    output logic [256-1:0]                              dma_push_data,

    input wire [PCIE_N-1:0][1-1:0]                      ext_valid,
    input wire [PCIE_N-1:0][1-1:0]                      ext_ready,
    input wire [PCIE_N-1:0][1-1:0]                      ext_eop,
    input wire [PCIE_N-1:0][$bits(pcie_meta_t)-1:0]     ext_meta,

    input wire [PCIE_N-1:0][1-1:0]                      result_valid,
    input wire [PCIE_N-1:0][64-1:0]                     result_tid,
    input wire [PCIE_N-1:0][1-1:0]                      result_data,
    output logic [PCIE_N-1:0][16-1:0]                   result_count,
    output logic [PCIE_N-1:0][1-1:0]                    result_full,
    output logic [PCIE_N-1:0][1-1:0]                    result_push,

    input wire [64-1:0]                                 priv_base,
    input wire [64-1:0]                                 priv_mask,

    input wire [1-1:0]                                  send_fails,

    input wire clk,
    input wire rst
);

logic [PCIE_N-1:0][1-1:0]               dma_port_ready;
logic [PCIE_N-1:0][1-1:0]               dma_port_valid;
mcache_pcim_t [PCIE_N-1:0]              dma_port_desc;

logic [64-1:0]                          dma_aa;

assign dma_push_addr                    = {dma_aa[64-1:6], 6'h0};

generate

    for (genvar g_i = 0; g_i < PCIE_N; g_i ++) begin: P_IN

        logic [1-1:0]                       ext_pipe_valid, ext_pipe_valid2;
        pcie_meta_t                         ext_pipe_meta, ext_pipe_meta2;

        logic [1-1:0]                       dma_meta_valid;
        logic [16-1:0]                      dma_meta_ctrl;
        logic [1-1:0]                       result_out_valid;
        logic [1-1:0]                       result_out_data;

        assign dma_port_valid[g_i]                 = result_out_valid & dma_meta_valid & (|dma_port_desc[g_i].pcim_addr) & (send_fails | result_out_data);
        assign dma_port_desc[g_i].pcim_strb     = dma_port_desc[g_i].pcim_addr[5] ? 64'hFFFF_FFFF_0000_0000 : 64'h0000_0000_FFFF_FFFF;
        assign dma_port_desc[g_i].ctrl[1:0]     = dma_meta_ctrl[1:0];
        assign dma_port_desc[g_i].ctrl[2]       = ~result_out_data;
        assign dma_port_desc[g_i].ctrl[15:3]    = dma_meta_ctrl[15:3];
        assign dma_port_desc[g_i].tsorig        = '0;
        assign dma_port_desc[g_i].tspub         = '0;

        always_ff@(posedge clk) res_p [g_i] <= dma_port_ready[g_i] & dma_port_valid[g_i];

        (* dont_touch = "yes" *) piped_wire #(
            .WIDTH                      ($bits({ext_meta[g_i], ext_valid[g_i] & ext_ready[g_i] & ext_eop[g_i]})),
            .DEPTH                      (2)
        ) ext_pipe_inst (
            .in                         ({ext_meta[g_i], ext_valid[g_i] & ext_ready[g_i] & ext_eop[g_i]}),
            .out                        ({ext_pipe_meta, ext_pipe_valid}),

            .clk                        (clk),
            .reset                      (rst)
        );

        always_ff@(posedge clk) begin
            ext_pipe_valid2             <= ext_pipe_valid;
            ext_pipe_meta2              <= ext_pipe_meta;
            ext_pipe_meta2.dma_addr     <= (ext_pipe_meta.dma_addr & priv_mask) + priv_base;
        end

        showahead_fifo #(
            .WIDTH                      ($bits({ext_pp_m.sig_l[0+:64], ext_pp_m.dma_chunk, ext_pp_m.dma_seq, ext_pp_m.dma_addr, ext_pp_m.dma_ctrl, ext_pp_m.dma_size})),
            .DEPTH                      (512)
        ) dma_m_fifo_inst (
            .aclr                       (rst),

            .wr_clk                     (clk),
            .wr_req                     (ext_pp_v),
            .wr_full                    (),
            .wr_full_b                  (),
            .wr_count                   (),
            .wr_data                    ({ext_pipe_meta2.sig_l[0+:64], ext_pipe_meta2.dma_chunk, ext_pipe_meta2.dma_seq, ext_pipe_meta2.dma_addr, ext_pipe_meta2.dma_ctrl, ext_pipe_meta2.dma_size}),

            .rd_clk                     (clk),
            .rd_req                     (dma_meta_valid & result_out_valid & dma_port_ready[g_i]),
            .rd_empty                   (),
            .rd_not_empty               (dma_meta_valid),
            .rd_count                   (),
            .rd_data                    ({dma_port_desc[g_i].sig, dma_port_desc[g_i].chunk, dma_port_desc[g_i].seq, dma_port_desc[g_i].pcim_addr, dma_meta_ctrl, dma_port_desc[g_i].sz})
        );

        tid_inorder #(
            .W                          ($bits({res_d[g_i]})),
            .D                          (2048)
        ) tid_inorder_inst (
            .in_valid                   (result_valid      [g_i]),
            .in_addr                    (result_tid        [g_i][0+:11]),
            .in_full                    (result_full       [g_i]),
            .in_count                   (result_count      [g_i]),
            .in_data                    (result_data       [g_i]),

            .out_ready                  (dma_meta_valid & result_out_valid & dma_port_ready[g_i]),
            .out_valid                  (result_out_valid),
            .out_data                   (result_out_data),

            .clk                        (clk),
            .rst                        (rst)
        );

    end
endgenerate

rrb_merge #(
    .W                                  ($bits({dma_port_desc[0]})),
    .N                                  (PCIE_N)
) dma_merge_inst (
    .i_r                                (dma_port_ready),
    .i_v                                (dma_port_valid),
    .i_e                                ({PCIE_N{1'b1}}),
    .i_m                                (dma_port_desc),

    .o_r                                (dma_push_ready),
    .o_v                                (dma_push_valid),
    .o_e                                (),
    .o_m                                ({dma_push_data, dma_push_wstrb, dma_aa}),

    .clk                                (clk),
    .rst                                (rst)
);

always_ff@(posedge clk)
if (|dma_port_valid)
$display("%t: %m: %b %b - %b %b", $time
, dma_port_ready
, dma_port_valid
, dma_push_ready
, dma_push_valid
);
endmodule


`default_nettype wire

`default_nettype none

module sha512_modq_meta #(
    parameter integer KEY_D                 = 512,
    parameter integer KEY_D_L               = $clog2(KEY_D)
) (
    output logic [1-1:0]                    in_ready, // backpressure is only applied for the first block (in_meta.f)
    input wire [1-1:0]                      in_wait, // wait
    input wire [1-1:0]                      in_valid, // valid
    input wire [1-1:0]                      in_last, // last blk
    input wire [$bits(sv_meta3_t)-1:0]      in_meta, // meta data

    output logic  [1-1:0]                   out_valid,
    output logic  [1-1:0]                   out_last,
    output logic  [$bits(sv_meta4_t)-1:0]   out_meta,

    input wire [1-1:0] clk,
    input wire [1-1:0] rst
);

sv_meta3_t                                  in_meta_reg;
sv_meta4_t                                  out_meta_reg;

logic [1-1:0]                               sha_i_r;
logic [1-1:0]                               sha_i_v;
logic [KEY_D_L-1:0]                         sha_i_k;

logic [1-1:0]                               key_i_r;
logic [1-1:0]                               key_i_v;

logic [1-1:0]                               sha_o_v;
logic [KEY_D_L-1:0]                         sha_o_k;
logic [256-1:0]                             sha_o_d;

assign in_ready                             = (in_meta_reg.f & sha_i_r & key_i_r & ~in_wait) | (sha_i_r & ~in_meta_reg.f);
assign in_meta_reg                          = in_meta;

assign key_i_v                              = in_meta_reg.f & sha_i_r & in_valid & ~in_wait;
assign sha_i_v                              = (in_meta_reg.f & key_i_r & in_valid & ~in_wait) | (in_valid & ~in_meta_reg.f);

assign out_last                             = 1;
assign out_meta                             = out_meta_reg;

always_ff@(posedge clk) begin
    out_valid                               <= sha_o_v;
    out_meta_reg.h                          <= sha_o_d;
    if (rst)
        out_valid <= 0;
end

key_store #(
    .D                                      (KEY_D),
    .W                                      ($bits({in_meta}))
) keystore_inst (
    .i_r                                    (key_i_r),
    .i_v                                    (key_i_v),
    .i_k                                    (sha_i_k),
    .i_d                                    ({in_meta}),

    .o_r                                    (sha_o_v),
    .o_k                                    (sha_o_k),
    .o_d                                    ({out_meta_reg.m}),

    .clk                                    (clk),
    .rst                                    (rst)
);

sha512_modq #(
    .META_W                                 (KEY_D_L)
) sha512_modq_inst (
    .i_p                                    (sha_i_r), // backpressure is only applied for the first block (in_meta.f)
    .i_v                                    (sha_i_v),
    .i_t                                    (sha_i_k), // key
    .i_f                                    (in_meta_reg.f), // first blk
    .i_c                                    (in_meta_reg.c), // number of blocks
    .i_d                                    (in_meta_reg.d), // data

    .o_v                                    (sha_o_v),
    .o_t                                    (sha_o_k),
    .o_d                                    (sha_o_d),

    .clk                                    (clk),
    .rst                                    (rst)
);

endmodule

`default_nettype wire


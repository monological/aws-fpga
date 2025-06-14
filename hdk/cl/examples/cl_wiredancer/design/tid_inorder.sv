
/*

    Transactions belonging to each stream (identified by metadata.src)
    must be published to the host in the same order as they were invoked
    by the host.  Scrambling occurs inside SHA as message length determines
    the number of cycles to perform SHA.

    A 64-bit timestamp (cycle count) is used for time keeping.  At 250MHz
    a 64-bit timestamp will wrap around after ~137 years.

    Transactions are placed into a ram according to the LSBs of the
    transaction ID, along with the current timestamp.

    For every ram location, a last-seen timestamp is also kept in a 
    separate ram, which is only updated when a transaction is deemed
    new.
    
    Output pointer advances only if a transaction has a timestamp newer
    than its corresponding last-seen timestamp.

    The size of the ram is proportional to the span of the reordering
    that occurs.

*/

`default_nettype none

module tid_inorder #(
    W                           = 32,
    D                           = 16,
    D_L                         = $clog2(D),
    W_L                         = $clog2(W)
) (
    input wire [1-1:0]          in_valid,
    input wire [D_L-1:0]        in_addr,
    input wire [W-1:0]          in_data,
    output logic [1-1:0]        in_full,
    output logic [D_L+1-1:0]    in_count,

    input wire [1-1:0]          out_ready,
    output logic [1-1:0]        out_valid,
    output logic [W-1:0]        out_data,

    input wire [1-1:0]          clk,
    input wire [1-1:0]          rst
);

logic [64-1:0]                  timestamp;
bit   [64-1:0]                  last_ts;
bit   [64-1:0]                  oo_t;
logic [1-1:0]                   oo_r;
logic [1-1:0]                   oo_v;
logic [W-1:0]                   oo_d;
logic [D_L-1:0]                 oo_a;
logic [D_L-1:0]                 oo_a_n;

assign oo_r                     = out_ready | ~out_valid;
assign oo_a_n                   = (oo_v & oo_r) ? oo_a + 1 : oo_a;

assign in_full                  = in_count >= D-1;
assign oo_v                     = (oo_t > last_ts);

simple_dual_port_ram #(
    .WRITE_MODE                                     ("read_first"),
    .CLOCKING_MODE                                  ("common_clock"),
    .ADDRESS_WIDTH                                  (D_L),
    .DATA_WIDTH                                     ($bits({timestamp, in_data}))
) ram_inst (
    .wr_clock                                       (clk),
    .wr_address                                     (in_addr),
    .wr_en                                          (in_valid),
    .wr_byteenable                                  ('1),
    .data                                           ({timestamp, in_data}),

    .rd_clock                                       (clk),
    .rd_address                                     (oo_a_n),
    .q                                              ({oo_t, oo_d}),
    .rd_en                                          (1'b1)
);

simple_dual_port_ram #(
    .WRITE_MODE                                     ("read_first"),
    .CLOCKING_MODE                                  ("common_clock"),
    .ADDRESS_WIDTH                                  (D_L),
    .DATA_WIDTH                                     ($bits({timestamp}))
) ts_ram_inst (
    .wr_clock                                       (clk),
    .wr_address                                     (oo_a),
    .wr_en                                          (oo_v & oo_r),
    .wr_byteenable                                  ('1),
    .data                                           (timestamp),

    .rd_clock                                       (clk),
    .rd_address                                     (oo_a_n),
    .q                                              (last_ts),
    .rd_en                                          (1'b1)
);

always_ff@(posedge clk) begin
    timestamp                   <= timestamp + 1;
    oo_a                        <= oo_a_n;

    if (oo_r) begin
        out_valid               <= oo_v;
        out_data                <= oo_d;
    end

    case({
        in_valid,
        out_valid & out_ready
    })
        2'b10: in_count         <= in_count + 1;
        2'b01: in_count         <= in_count - 1;
    endcase

    if (rst) begin
        in_count                <= 0;
        out_valid               <= 0;
        oo_a                    <= 0;
        timestamp               <= 0;
    end
end

always_ff@(posedge clk) if (in_valid | out_valid) $display("%t: %x %x %b %b %x - %x %x %x", $time
    , in_valid
    , in_addr
    , in_count
    , in_full
    , in_data

    , out_valid
    , out_ready
    , out_data
);

endmodule

`default_nettype wire

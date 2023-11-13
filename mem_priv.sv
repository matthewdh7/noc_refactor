module mem_priv
    import bsg_global_buffer_pkg::*;
            #(parameter data_width_p           = -1
            , parameter bank_els_p             = -1

            , localparam bank_addr_width_lp    = `BSG_SAFE_CLOG2(bank_els_p)
            )

    ( input  logic                                  clk_i
    , input  logic                                  reset_i

    , input logic [bank_addr_width_lp-1:0]          rw_mem_addr
    , input logic [data_width_p-1:0]                rw_mem_data
    , input logic                                   rw_mem_w
    , input logic                                   rw_mem_v

    , input logic [bank_addr_width_lp-1:0]          wo_mem_addr
    , input logic [data_width_p-1:0]                wo_mem_data
    , input logic                                   wo_mem_v

    , input logic [bank_addr_width_lp-1:0]          ro_mem_addr
    , input logic                                   ro_mem_v

    , output logic [data_width_p]                   mem_data_o
    );

    logic rw_mem_yumi, wo_mem_yumi, ro_grant_lo;
    
    bsg_arb_fixed #(.inputs_p(3), .lo_to_hi_p(0))
        fixed_arb
            (.ready_i(1'b1)
            ,.reqs_i({ro_mem_v, wo_mem_v, rw_mem_v})
            ,.grants_o({ro_grant_lo, wo_mem_yumi, rw_mem_yumi})
            );

    wire [bank_addr_width_lp-1:0] mem_addr_li = rw_mem_yumi ? rw_mem_addr
                                              : wo_mem_yumi ? wo_mem_addr
                                              :               ro_mem_addr;

    wire [data_width_p-1:0] mem_data_li = rw_mem_yumi ? rw_mem_data
                                        :               wo_mem_data;

    wire mem_w_li = rw_mem_yumi ? rw_mem_w
                  : wo_mem_yumi ? 1'b1
                  :               1'b0;

    wire mem_v_li = rw_mem_yumi | wo_mem_yumi | ro_grant_lo;

    bsg_mem_1rw_sync #(.width_p(data_width_p), .els_p(bank_els_p))
        memory
            (.clk_i(clk_i)
            ,.reset_i(reset_i)

            ,.addr_i(mem_addr_li)
            ,.data_i(mem_data_li)
            ,.w_i(mem_w_li)
            ,.v_i(mem_v_li)

            ,.data_o(mem_data_o)
            );

endmodule
            
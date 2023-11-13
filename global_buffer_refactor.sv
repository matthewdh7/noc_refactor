`include "bsg_defines.v"
`include "bsg_global_buffer_pkg.vh"

module bsg_global_buffer
import bsg_global_buffer_pkg::*;
        #( parameter data_width_p           = -1
         , parameter rw_addr_width_p        = -1
         , parameter ro_wo_addr_width_p     = -1
         , parameter bank_els_p             = -1
         , parameter num_tiles_x_p          = -1
         , parameter num_tiles_y_p          = -1
         , parameter num_rw_ch_p            = -1
         , parameter max_outstanding_p      = -1

         , parameter fwd_rx_fifo_els_p      =  2

         , localparam id_width_lp           = `BSG_SAFE_CLOG2(max_outstanding_p)
         , localparam x_cord_width_lp       = `BSG_SAFE_CLOG2(num_tiles_x_p)
         , localparam y_cord_width_lp       = `BSG_SAFE_CLOG2(num_tiles_y_p + 1)
         , localparam bank_addr_width_lp    = `BSG_SAFE_CLOG2(bank_els_p)

         , localparam link_sif_width_lp     = `bsg_global_buffer_link_sif_width
         , localparam fwd_packet_width_lp   = `bsg_global_buffer_fwd_packet_width
         , localparam rev_packet_width_lp   = `bsg_global_buffer_rev_packet_width

         , localparam S                     = 32'(bsg_noc_pkg::S)
         , localparam N                     = 32'(bsg_noc_pkg::N)
         , localparam E                     = 32'(bsg_noc_pkg::E)
         , localparam W                     = 32'(bsg_noc_pkg::W)
         , localparam P                     = 32'(bsg_noc_pkg::P)
         )
( input  logic                                              clk_i
, input  logic                                              reset_i

, input  logic [num_rw_ch_p-1:0][rw_addr_width_p-1:0]       rw_addr_i
, input  logic [num_rw_ch_p-1:0][data_width_p-1:0]          rw_data_i
, input  logic [num_rw_ch_p-1:0]                            rw_w_i
, input  logic [num_rw_ch_p-1:0]                            rw_v_i
, output logic [num_rw_ch_p-1:0]                            rw_ready_o

, output logic [num_rw_ch_p-1:0][data_width_p-1:0]          rw_data_o
, output logic [num_rw_ch_p-1:0]                            rw_v_o
, input  logic [num_rw_ch_p-1:0]                            rw_yumi_i

, output logic [num_rw_ch_p-1:0]                            rw_fence_o

, input  logic [num_tiles_y_p-1:0][ro_wo_addr_width_p-1:0]  ro_addr_i
, input  logic [num_tiles_y_p-1:0]                          ro_v_i

, output logic [num_tiles_y_p-1:0][ro_wo_addr_width_p-1:0]  ro_addr_o
, output logic [num_tiles_y_p-1:0][data_width_p-1:0]        ro_data_o
, output logic [num_tiles_y_p-1:0]                          ro_v_o

, input  logic [num_tiles_y_p-1:0][ro_wo_addr_width_p-1:0]  wo_addr_i
, input  logic [num_tiles_y_p-1:0][data_width_p-1:0]        wo_data_i
, input  logic [num_tiles_y_p-1:0]                          wo_v_i
, output logic [num_tiles_y_p-1:0]                          wo_ready_o
);

    `bsg_global_buffer_declare_structs;

    bsg_global_buffer_link_sif_s [num_tiles_y_p-1:0][num_tiles_x_p-1:0][S:W] link_in, link_out;

    logic [E:W][num_tiles_y_p-1:0][link_sif_width_lp-1:0] hor_link_sif_li, hor_link_sif_lo;
    logic [S:N][num_tiles_x_p-1:0][link_sif_width_lp-1:0] ver_link_sif_li, ver_link_sif_lo;

    logic [num_tiles_x_p:0][num_tiles_y_p-1:0][bank_addr_width_lp-1:0] ro_addr_n;
    logic [num_tiles_x_p:0][num_tiles_y_p-1:0][x_cord_width_lp-1:0] ro_dest_x_n;
    logic [num_tiles_x_p:0][num_tiles_y_p-1:0][data_width_p-1:0] ro_data_n;
    logic [num_tiles_x_p:0][num_tiles_y_p-1:0] ro_addr_v_n, ro_data_v_n;

    logic [num_tiles_x_p:0][num_tiles_y_p-1:0][bank_addr_width_lp-1:0] wo_addr_n;
    logic [num_tiles_x_p:0][num_tiles_y_p-1:0][x_cord_width_lp-1:0] wo_dest_x_n;
    logic [num_tiles_x_p:0][num_tiles_y_p-1:0][data_width_p-1:0] wo_data_n;
    logic [num_tiles_x_p:0][num_tiles_y_p-1:0] wo_v_n, wo_ready_n;

    logic [num_tiles_x_p:0][num_tiles_y_p-1:0][bank_addr_width_lp-1:0]  rw_mem_addr_li;
    logic [num_tiles_x_p:0][num_tiles_y_p-1:0][data_width_p-1:0]        rw_mem_data_li, rw_mem_data_lo;
    logic [num_tiles_x_p:0][num_tiles_y_p-1:0]                          rw_mem_w_li;
    logic [num_tiles_x_p:0][num_tiles_y_p-1:0]                          rw_mem_v_li;
    logic [num_tiles_x_p:0][num_tiles_y_p-1:0]                          rw_mem_yumi_lo;


    for (genvar r = 0; r < num_tiles_y_p; r++) begin
        assign ro_addr_n[0][r] = ro_addr_i[r][0+:bank_addr_width_lp];
        assign ro_dest_x_n[0][r] = ro_addr_i[r][bank_addr_width_lp+:x_cord_width_lp];
    end
    assign ro_addr_v_n[0] = ro_v_i;
    assign ro_data_n[0] = '0;
    assign ro_data_v_n[0] = '0;
    assign ro_addr_o = {ro_dest_x_n[num_tiles_x_p], ro_addr_n[num_tiles_x_p]};
    assign ro_data_o = ro_data_n[num_tiles_x_p];
    assign ro_v_o = ro_data_v_n[num_tiles_x_p];

    for (genvar r = 0; r < num_tiles_y_p; r++) begin
        assign wo_addr_n[0][r] = wo_addr_i[r][0+:bank_addr_width_lp];
        assign wo_dest_x_n[0][r] = wo_addr_i[r][bank_addr_width_lp+:x_cord_width_lp];
    end
    assign wo_data_n[0] = wo_data_i;
    assign wo_v_n[0] = wo_v_i;
    assign wo_ready_o = wo_ready_n[0];
    assign wo_ready_n[num_tiles_x_p] = '1;

    for (genvar r = 0; r < num_tiles_y_p; r++) begin: y
        for (genvar c = 0; c < num_tiles_x_p; c++) begin: x
            genvar coord = c + (r * '(num_tiles_x_p));
            bsg_global_buffer_tile #
                (.data_width_p(data_width_p)
                ,.rw_addr_width_p(rw_addr_width_p)
                ,.ro_wo_addr_width_p(ro_wo_addr_width_p)
                ,.bank_els_p(bank_els_p)
                ,.num_tiles_x_p(num_tiles_x_p)
                ,.num_tiles_y_p(num_tiles_y_p)
                ,.num_rw_ch_p(num_rw_ch_p)
                ,.max_outstanding_p(max_outstanding_p)
                ,.fwd_rx_fifo_els_p(fwd_rx_fifo_els_p))
                tile
                    (.clk_i(clk_i)
                    ,.reset_i(reset_i)

                    ,.my_x_i(x_cord_width_lp'(c))
                    ,.my_y_i(y_cord_width_lp'(r+1))

                    ,.links_sif_i(link_in[r][c])
                    ,.links_sif_o(link_out[r][c])

                    ,.ro_addr_i(ro_addr_n[c][r])
                    ,.ro_dest_x_i(ro_dest_x_n[c][r])
                    ,.ro_addr_v_i(ro_addr_v_n[c][r])
                    ,.ro_data_i(ro_data_n[c][r])
                    ,.ro_data_v_i(ro_data_v_n[c][r])

                    ,.ro_addr_o(ro_addr_n[c+1][r])
                    ,.ro_dest_x_o(ro_dest_x_n[c+1][r])
                    ,.ro_addr_v_o(ro_addr_v_n[c+1][r])
                    ,.ro_data_o(ro_data_n[c+1][r])
                    ,.ro_data_v_o(ro_data_v_n[c+1][r])

                    ,.wo_addr_i(wo_addr_n[c][r])
                    ,.wo_dest_x_i(wo_dest_x_n[c][r])
                    ,.wo_data_i(wo_data_n[c][r])
                    ,.wo_v_i(wo_v_n[c][r])
                    ,.wo_ready_o(wo_ready_n[c][r])

                    ,.wo_addr_o(wo_addr_n[c+1][r])
                    ,.wo_dest_x_o(wo_dest_x_n[c+1][r])
                    ,.wo_data_o(wo_data_n[c+1][r])
                    ,.wo_v_o(wo_v_n[c+1][r])
                    ,.wo_ready_i(wo_ready_n[c+1][r])

                    ,.rw_mem_addr_i(rw_mem_addr_li)
                    ,.rw_mem_data_i(rw_mem_data_li)
                    ,.rw_mem_w_i(rw_mem_w_li)
                    ,.rw_mem_v_i(rw_mem_v_li)

                    ,.rw_mem_yumi_o(rw_mem_yumi_lo)
                    ,.rw_mem_data_o(rw_mem_data_lo)
                    );
        end: x
    end: y

    bsg_mesh_stitch #(.width_p(link_sif_width_lp)
                     ,.x_max_p(num_tiles_x_p)
                     ,.y_max_p(num_tiles_y_p))
        link
            (.outs_i(link_out)
            ,.ins_o(link_in)
            ,.hor_i(hor_link_sif_li)
            ,.hor_o(hor_link_sif_lo)
            ,.ver_i(ver_link_sif_li)
            ,.ver_o(ver_link_sif_lo)
            );

    mesh_2d # 
            (.nodes_x_p(num_tiles_x_p)
            ,.nodes_y_p(num_tiles_y_p)
            ,.addr_width_p(rw_addr_width_p)
            ,.data_width_p(data_width_p)
            // ,.req_resp_addr_width_p()
            // ,.local_addr_width_p()
            )
        rw_mesh
            (.clk_i(clk_i)
            ,.reset_i(reset_i)

            ,.req_addr_i(rw_addr_i)
            ,.req_data_i(rw_data_i)
            ,.req_w_i(rw_w_i)
            ,.req_v_i(rw_v_i)
            ,.req_ready_o(rw_ready_o)

            ,.req_data_o(rw_data_o)
            ,.req_v_o(rw_v_o)
            ,.req_yumi_i(rw_yumi_i)
            ,.req_fence_o(rw_fence_o)

            ,.resp_addr_o(rw_mem_addr_li)
            ,.resp_data_o(rw_mem_data_li)
            ,.resp_w_o(rw_mem_w_li)
            ,.resp_v_o(rw_mem_v_li)
            ,.resp_yumi_i(rw_mem_yumi_lo)

            ,.resp_dest_id_i()
            ,.resp_data_i(rw_mem_data_lo)
            ,.resp_v_i(1'b1)
            ,.resp_ready_o(1'b1)
            );



endmodule // bsg_global_buffer
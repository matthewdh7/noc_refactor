`include "bsg_defines.v"
`include "bsg_global_buffer_pkg.vh"

module bsg_network_wo_ro
////////////////////////////////////////////////////////////////////////////////
// PARAMETERS
//
#(parameter nodes_x_p = -1
, parameter nodes_y_p = -1

// , parameter addr_width_p = -1
, parameter local_addr_width_p     = -1
, parameter data_width_p = -1

, parameter ro_wo_addr_width_p     = lg_wo_ro_ports_lp + local_addr_width_lp
, parameter bank_els_p             = -1

, parameter wo_sel = 0 //0=read-only, 1=write-only

//TODO: add param for deciding which bits of addr_i/o are dest vs. addr
    
////////////////////////////////////////////////////////////////////////////////
// LOCAL PARAMETERS
//
, localparam wo_ro_ports_lp = nodes_x_p * nodes_y_p
, localparam lg_wo_ro_ports_lp = 'BSG_SAFE_CLOG2(wo_ro_ports_lp)

, localparam x_cord_width_lp       = `BSG_SAFE_CLOG2(nodes_x_p)
, localparam y_cord_width_lp       = `BSG_SAFE_CLOG2(nodes_y_p + 1) // ?? why + 1
, localparam bank_addr_width_lp    = `BSG_SAFE_CLOG2(bank_els_p)

, localparam link_sif_width_lp     = `bsg_global_buffer_link_sif_width
, localparam fwd_packet_width_lp   = `bsg_global_buffer_fwd_packet_width
, localparam rev_packet_width_lp   = `bsg_global_buffer_rev_packet_width

, localparam local_addr_width_lp = (addr_width_p - x_cord_width_lp)
, localparam fwd_width_lp = (local_addr_width_lp + data_width_p + 1)
, localparam rev_width_lp = (data_width_p + 1)
)

////////////////////////////////////////////////////////////////////////////////
// INPUT/OUTPUT PORTS
//
(  input  logic                                             clk_i
,  input  logic                                             reset_i

,  input  logic [nodes_y_p-1:0][ro_wo_addr_width_p-1:0]     addr_i
,  input  logic [nodes_y_p-1:0][data_width_p-1:0]           data_i
,  input  logic [nodes_y_p-1:0]                             v_i //either wo_v_i or ro_addr_v_i
,  output logic [nodes_y_p-1:0]                             ready_o

,  output logic [nodes_y_p-1:0][ro_wo_addr_width_p-1:0]     addr_o
,  output logic [nodes_y_p-1:0][data_width_p-1:0]           data_o
,  output logic [nodes_y_p-1:0]                             v_o //either wo_v_o or ro_addr_v_o

,  input  logic [nodes_x_p-1:0][nodes_y_p-1:0][data_width_p-1:0]        mem_data_i
,  output logic [nodes_x_p-1:0][nodes_y_p-1:0][local_addr_width_lp-1:0] mem_addr_o
,  output logic [nodes_x_p-1:0][nodes_y_p-1:0][data_width_p-1:0]        mem_data_o
,  output logic [nodes_x_p-1:0][nodes_y_p-1:0]                          mem_v_o
);

    `bsg_global_buffer_declare_structs;
////////////////////////////////////////////////////////////////////////////////
// INTERMEDIATES DEFINITIONS

    logic [nodes_x_p:0][nodes_y_p-1:0][bank_addr_width_lp-1:0]  addr_n;
    logic [nodes_x_p:0][nodes_y_p-1:0][x_cord_width_lp-1:0]     dest_x_n;
    logic [nodes_x_p:0][nodes_y_p-1:0][data_width_p-1:0]        data_n;
    logic [nodes_x_p:0][nodes_y_p-1:0]                          ro_addr_v_n, ro_data_v_n, wo_v_n, wo_ready_n;

    logic [nodes_x_p:0][nodes_y_p-1:0] link_fwd_v_li, link_fwd_v_lo, link_rev_v_li, link_rev_v_lo;
    logic [nodes_x_p:0][nodes_y_p-1:0][fwd_width_lp-1:0] link_fwd_pkt_li, link_fwd_pkt_lo;
    logic [nodes_x_p:0][nodes_y_p-1:0][rev_width_lp-1:0] link_rev_pkt_li, link_rev_pkt_lo;
    
    logic z0, z1, z4, z6;
    logic [data_width_p-1:0] z2, z5;

////////////////////////////////////////////////////////////////////////////////
// NETWORK

    for (genvar r = 0; r < nodes_y_p; r++) begin
        assign addr_n[0][r] = addr_i[r][0+:bank_addr_width_lp];
        assign dest_x_n[0][r] = addr_i[r][bank_addr_width_lp+:x_cord_width_lp];
    end
    assign data_n[0] = wo_sel ? wo_data_i : '0;

    assign addr_o = wo_sel ? '0 : {ro_dest_x_n[num_tiles_x_p], ro_addr_n[num_tiles_x_p]};
    assign data_o = wo_sel ? '0 : data_n[num_tiles_x_p];

    assign v_o = ro_data_v_n[num_tiles_x_p]; //only used for ro
    assign ready_o = wo_ready_n[0];          //only used for wo

    assign ro_addr_v_n[0] = v_i; 
    assign ro_data_v_n[0] = '0;
    assign wo_v_n[0] = v_i;
    assign wo_ready_n[num_tiles_x_p] = '1;

    for (genvar y = 0; y < nodes_y_p; y++) begin: y 
        for (genvar x = 0; x < nodes_x_p; x++) begin: x 
            assign link_fwd_v_li[x][y] = wo_sel ? wo_v_n[x][y] : ro_addr_v_n[x][y];
            assign link_fwd_v_lo[x][y] = wo_sel ? wo_v_n[x+1][y] : ro_addr_v_n[x+1][y];
            assign link_rev_v_li[x][y] = wo_sel ? '0 : ro_data_v_n[x][y];
            assign link_rev_v_lo[x][y] = wo_sel ? '0 : ro_data_v_n[x+1][y];
            assign link_fwd_pkt_li[x][y] = wo_sel ? {addr_n[x][y], data_n[x][y], 1'b1} : {addr_n[x][y], {data_width_p{1'b0}}, 1'b0};
            assign link_fwd_pkt_lo[x][y] = wo_sel ? {addr_n[x+1][y], data_n[x+1][y], z0} : {addr_n[x+1][y], z2, z1};
            assign link_rev_pkt_li[x][y] = wo_sel ? {{data_width_p{1'd0}}, 1'b1} : {data_n[x][y], 1'b0};
            assign link_rev_pkt_lo[x][y] = wo_sel ? {z5, z6} : {data_n[x+1][y], z4};

            bsg_network_ring_sqmp_no_backpressure_endp_resp #(.addr_width_p(x_cord_width_lp + bank_addr_width_lp)
                                                     ,.data_width_p(data_width_p)
                                                     ,.resp_nodes_p(nodes_x_p))
                wo_ro_node
                    (.clk_i(clk_i)
                    ,.reset_i(reset_i)

                    ,.my_id_i(x_cord_width_lp'(x))

                    ,.link_fwd_dest_id_i(dest_x_n[x][y])
                    ,.link_fwd_pkt_i(link_fwd_pkt_li)
                    ,.link_fwd_v_i(link_fwd_v_li)

                    ,.link_fwd_dest_id_o(dest_x_n[x+1][y])
                    ,.link_fwd_pkt_o(link_fwd_pkt_lo)
                    ,.link_fwd_v_o(link_fwd_v_lo)

                    ,.link_rev_pkt_i(link_rev_pkt_li)
                    ,.link_rev_v_i(link_rev_v_li)

                    ,.link_rev_pkt_o(link_rev_pkt_lo)
                    ,.link_rev_v_o(link_rev_v_lo)

                    ,.addr_o(mem_addr_o)
                    ,.data_o(mem_data_o)
                    ,.w_o()
                    ,.v_o(mem_v_o)
                    ,.data_i(mem_data_i)
                    );
        end
    end

endmodule // bsg_network_wo_ro
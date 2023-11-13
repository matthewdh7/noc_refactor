`include "bsg_defines.v"
`include "bsg_global_buffer_pkg.vh"

module mesh_2d
////////////////////////////////////////////////////////////////////////////////
// PARAMETERS
//
#(parameter nodes_x_p = -1
, parameter nodes_y_p = -1

, parameter addr_width_p = -1
, parameter data_width_p = -1

, parameter req_resp_addr_width_p = lg_req_resp_ports_lp + local_addr_width_p
, parameter local_addr_width_p = -1
//TODO: add param for deciding which bits of addr_i/o are dest vs. addr
    
////////////////////////////////////////////////////////////////////////////////
// LOCAL PARAMETERS
//
, localparam req_resp_ports_lp = nodes_x_p * nodes_y_p
, localparam lg_req_resp_ports_lp = 'BSG_SAFE_CLOG2(req_resp_ports_lp)

// , localparam id_width_lp           = `BSG_SAFE_CLOG2(max_outstanding_p)
, localparam x_cord_width_lp       = `BSG_SAFE_CLOG2(num_tiles_x_p)
, localparam y_cord_width_lp       = `BSG_SAFE_CLOG2(num_tiles_y_p + 1) // ?? why + 1
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

////////////////////////////////////////////////////////////////////////////////
// INPUT/OUTPUT PORTS
//
(  input  logic                                           clk_i
,  input  logic                                           reset_i

,  input   logic  [req_resp_ports_lp-1:0][req_resp_addr_width_p-1:0]    req_addr_i
,  input   logic  [req_resp_ports_lp-1:0][data_width_p-1:0]             req_data_i
,  input   logic  [req_resp_ports_lp-1:0]                               req_w_i
,  input   logic  [req_resp_ports_lp-1:0]                               req_v_i
,  output  logic  [req_resp_ports_lp-1:0]                               req_ready_o

,  output  logic  [req_resp_ports_lp-1:0][data_width_p-1:0]             req_data_o
,  output  logic  [req_resp_ports_lp-1:0]                               req_v_o
,  input   logic  [req_resp_ports_lp-1:0]                               req_yumi_i
,  output  logic  [req_resp_ports_lp-1:0]                               req_fence_o //TODO: implement

,  output  logic  [req_resp_ports_lp-1:0][req_resp_addr_width_p-1:0]    resp_addr_o //these go to sram
,  output  logic  [req_resp_ports_lp-1:0][data_width_p-1:0]             resp_data_o
,  output  logic  [req_resp_ports_lp-1:0]                               resp_w_o
,  output  logic  [req_resp_ports_lp-1:0]                               resp_v_o
,  input   logic  [req_resp_ports_lp-1:0]                               resp_yumi_i

,  input   logic  [req_resp_ports_lp-1:0][lg_req_resp_ports_lp-1:0]     resp_dest_id_i //these go back to req
,  input   logic  [req_resp_ports_lp-1:0][data_width_p-1:0]             resp_data_i
,  input   logic  [req_resp_ports_lp-1:0]                               resp_v_i
,  output  logic  [req_resp_ports_lp-1:0]                               resp_ready_o
);

    `bsg_global_buffer_declare_structs;
////////////////////////////////////////////////////////////////////////////////
// LINK/PKT DEFINITIONS
    bsg_global_buffer_link_sif_s [nodes_y_p-1:0][nodes_x_p-1:0][S:W] link_in, link_out; //matrix of links spawned by mesh stitch

    logic [E:W][nodes_y_p-1:0][link_sif_width_lp-1:0] hor_link_sif_li, hor_link_sif_lo; //one hor_link per row
    logic [S:N][nodes_x_p-1:0][link_sif_width_lp-1:0] ver_link_sif_li, ver_link_sif_lo; //one ver_link per column

    bsg_global_buffer_link_sif_s [nodes_y_p-1:0][nodes_x_p-1:0] proc_link_sif_in, proc_link_sif_out; //two links (each with fwd/rev) per node

////////////////////////////////////////////////////////////////////////////////
// MESH STITCH AND NODES
    bsg_mesh_stitch #(.width_p(link_sif_width_lp)
                    ,.x_max_p(nodes_x_p)
                    ,.y_max_p(nodes_y_p))
    link
        (.outs_i(link_out)
        ,.ins_o(link_in)
        ,.hor_i(hor_link_sif_li)
        ,.hor_o(hor_link_sif_lo)
        ,.ver_i(ver_link_sif_li)
        ,.ver_o(ver_link_sif_lo)
        );

    for (genvar m = 0; n < nodes_y_p; n++) begin: y_ch
        for (genvar n = 0; m < nodes_x_p; m++) begin: x_ch
            genvar coord = n + (m*nodes_x_p);
            mesh2_node_priv #
                    (.data_width_p(data_width_p)
                    ,.rw_addr_width_p(rw_addr_width_p)
                    ,.bank_els_p(bank_els_p)
                    ,.num_tiles_x_p(num_tiles_x_p)
                    ,.num_tiles_y_p(num_tiles_y_p)
                    ,.fwd_rx_fifo_els_p(fwd_rx_fifo_els_p))
                inter
                    (.clk_i(clk_i)
                    ,.reset_i(reset_i)

                    ,.my_x_i(x_cord_width_lp'(n))
                    ,.my_y_i(y_cord_width_lp'(m))

                    ,.link_sif_i(link_in[m][n])
                    ,.link_sif_o(link_out[m][n])

                    // ,.proc_link_sif_i(proc_link_sif_in[m][n]) //from req_src, from resp_src
                    // ,.proc_link_sif_o(proc_link_sif_out[m][n]) //to req_sink, to resp_sink

                    ,.req_addr_i(req_addr_i[coord])
                    ,.req_data_i(req_data_i[coord])
                    ,.req_w_i(req_w_i[coord])
                    ,.req_v_i(req_v_i[coord])
                    ,.req_ready_o(req_ready_o[coord])

                    ,.req_data_o(req_data_o[coord])
                    ,.req_v_o(req_v_o[coord])
                    ,.req_yumi_i(req_yumi_i[coord])
                    ,.req_fence_o(req_fenco_o[coord])

                    ,.resp_addr_o(resp_addr_o[coord])
                    ,.resp_data_o(resp_data_o[coord])
                    ,.resp_w_o(resp_w_o[coord])
                    ,.resp_v_o(resp_v_o[coord])
                    ,.resp_yumi_i(resp_yumi_i[coord])

                    ,.resp_dest_id_i(resp_dest_id_i[coord])
                    ,.resp_data_i(resp_data_i[coord])
                    ,.resp_v_i(resp_v_i[coord])
                    ,.resp_ready_o(resp_ready_o[coord])
                    );
        end: x_ch
    end: y_ch

    //tie off rest of north/south links
    for (genvar n = 0; n < nodes_x_p; n++) begin
        assign ver_link_sif_li[N][n] = '0;
        assign ver_link_sif_li[S][n] = '0;
    end

    //tie off rest of east/west links
    for (genvar m = 0; m < nodes_y_p; m++) begin
        assign hor_link_sif_li[E][m] = '0;
        assign hor_link_sif_li[W][m] = '0;
    end

endmodule // mesh_2d
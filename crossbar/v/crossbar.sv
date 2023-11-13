`include "bsg_defines.v"
`include "noc_interfaces.sv"

////////////////////////////////////////////////////////////////////////////////
//
module bsg_noc_crossbar_network_unmanaged_hop
//
// Description:
//    This module implements a simple request/response crossbar network.
//    Requests are generated from the req_* ports and responses are generated
//    from the resp_* ports. This module is "unmanaged" which means that
//    responders attached on the resp ports must keep track of who sent the
//    request and include the response destination infromation when enqueue a
//    response. This eliminates the fifo used in the managed crossbar networks
//    to keep track of this information.
//
////////////////////////////////////////////////////////////////////////////////
// PARAMETERS
//
#(parameter req_ports_p = -1
, parameter req_i_fifo_els_p = 2

, parameter resp_ports_p = -1
, parameter resp_i_fifo_els_p = 2

, parameter addr_width_p = -1
, parameter data_width_p = -1

, parameter req_addr_width_p = lg_req_ports_lp + local_addr_width_p
, parameter resp_addr_width_p = lg_resp_ports_lp + local_addr_width_p
, parameter local_addr_width_p = -1
//TODO: add param for deciding which bits of addr_i/o are dest vs. addr

////////////////////////////////////////////////////////////////////////////////
// LOCAL PARAMETERS
//
, localparam lg_req_ports_lp = `BSG_SAFE_CLOG2(req_ports_p)
, localparam lg_resp_ports_lp = `BSG_SAFE_CLOG2(resp_ports_p)
)

////////////////////////////////////////////////////////////////////////////////
// INPUT/OUTPUT PORTS
//
(  input  logic                                           clk_i
,  input  logic                                           reset_i

//MSB: dest_id    LSB: addr
,  input   logic  [req_ports_p-1:0][req_addr_width_p-1:0]     req_addr_i
,  input   logic  [req_ports_p-1:0][data_width_p-1:0]         req_data_i
,  input   logic  [req_ports_p-1:0]                           req_w_i
,  input   logic  [req_ports_p-1:0]                           req_v_i
,  output  logic  [req_ports_p-1:0]                           req_ready_o

,  output  logic  [req_ports_p-1:0][data_width_p-1:0]         req_data_o
,  output  logic  [req_ports_p-1:0]                           req_v_o
,  input   logic  [req_ports_p-1:0]                           req_yumi_i
,  output  logic  [req_ports_p-1:0]                           req_fence_o //TODO: implement

,  output  logic  [resp_ports_p-1:0][resp_addr_width_p-1:0]   resp_addr_o
,  output  logic  [resp_ports_p-1:0][data_width_p-1:0]        resp_data_o
,  output  logic  [resp_ports_p-1:0]                          resp_w_o
,  output  logic  [resp_ports_p-1:0]                          resp_v_o
,  input   logic  [resp_ports_p-1:0]                          resp_yumi_i

,  input   logic  [resp_ports_p-1:0][lg_req_ports_lp-1:0]     resp_dest_id_i
,  input   logic  [resp_ports_p-1:0][data_width_p-1:0]        resp_data_i
,  input   logic  [resp_ports_p-1:0]                          resp_v_i
,  output  logic  [resp_ports_p-1:0]                          resp_ready_o
);

////////////////////////////////////////////////////////////////////////////////
// HARDWARE DESCRIPTION
//

  typedef struct packed {
      logic [lg_req_ports_lp-1:0] src;
      logic [data_width_p-1:0]   data;
      logic                      wen;
      logic [addr_width_p-1:0]   addr;
      logic [lg_resp_ports_lp-1:0] dest;
  } req_src_pkt_s;

  typedef struct packed {
      logic [lg_req_ports_lp-1:0] src;
      logic [data_width_p-1:0]   data;
      logic                      wen;
      logic [addr_width_p-1:0]   addr;
  } req_sink_pkt_s;

  typedef struct packed {
      logic [data_width_p-1:0]   data;
      logic [lg_req_ports_lp-1:0] dest;
  } resp_src_pkt_s;

  typedef struct packed {
      logic [data_width_p-1:0]   data;
  } resp_sink_pkt_s;

  req_src_pkt_s       [req_ports_p-1:0]   req_li;
  req_sink_pkt_s      [resp_ports_p-1:0]  req_lo;
  resp_src_pkt_s      [resp_ports_p-1:0]  resp_li;
  resp_sink_pkt_s     [req_ports_p-1:0]   resp_lo;

  logic [resp_ports_p-1:0] resp_v_lo;

  //requester-side packets
  for (genvar i = 0; i < req_ports_p; i++) begin //req_src_pkt assignment
    assign req_li[i] = '{
      src  : lg_req_ports_lp'(i),
      data : req_data_i[i],
      wen  : req_w_i[i],
      addr : req_addr_i[i][addr_width_p-1:0],
      dest : req_addr_i[i][lg_resp_ports_lp-1:addr_width_p]
    };

    assign req_data_o[i] = resp_lo[i].data; //resp_sink_pkt assignment
    assign req_fence_o[i] = '0; //TODO: implement fence for crossbar
  end

  //responder-side packets
  for (genvar i = 0; i < resp_ports_p; i++) begin //req_sink_pkt assignment
    assign resp_addr_o[i]   = {req_lo[i].src, req_lo[i].addr};
    assign resp_data_o[i]   = req_lo[i].data;
    assign resp_w_o[i]      = req_lo[i].wen;
    assign resp_v_o[i]      = resp_v_lo[i];

    assign resp_li[i] = '{  //resp_src_pkt assignment
      data : resp_data_i[i],
      dest : resp_dest_id_i[i]
    };
  end

  localparam int req_i_fifo_els_p_arr [req_ports_p-1:0] = '{default:req_i_fifo_els_p};
  localparam int resp_i_fifo_els_p_arr [resp_ports_p-1:0] = '{default:resp_i_fifo_els_p};

  bsg_router_crossbar_o_by_i #
    (.i_els_p(req_ports_p)
    ,.i_width_p($bits(req_src_pkt_s))
    ,.i_use_credits_p({req_ports_p{1'b0}})
    ,.i_fifo_els_p(req_i_fifo_els_p_arr)
    ,.o_els_p(resp_ports_p)
    ,.drop_header_p(1))
  req_xbar
    (.clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.data_i(req_li)
    ,.valid_i(req_v_i)
    ,.credit_ready_and_o(req_ready_o)

    ,.data_o(req_lo)
    ,.valid_o(resp_v_lo)
    ,.ready_and_i(resp_yumi_i)
    );

  bsg_router_crossbar_o_by_i #
    (.i_els_p(resp_ports_p)
    ,.i_width_p($bits(resp_src_pkt_s))
    ,.i_use_credits_p({resp_ports_p{1'b0}})
    ,.i_fifo_els_p(resp_i_fifo_els_p_arr)
    ,.o_els_p(req_ports_p)
    ,.drop_header_p(1))
  resp_xbar
    (.clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.data_i(resp_li)
    ,.valid_i(resp_v_i)
    ,.credit_ready_and_o(resp_ready_o)

    ,.data_o(resp_lo)
    ,.valid_o(req_v_o)
    ,.ready_and_i(req_yumi_i)
    );

endmodule // bsg_noc_crossbar_network_unmanaged_hop_refactor
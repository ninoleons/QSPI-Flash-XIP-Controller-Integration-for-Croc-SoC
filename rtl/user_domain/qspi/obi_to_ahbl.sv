// added by Jan Häussermann and Nino Singer for QSPI-XIP

// Simple read-only OBI-to-AHB-Lite adapter for EF_QSPI_XIP_CTRL_AHBL.
//
// Croc side:
//   OBI request / response
//
// Efabless QSPI side:
//   Minimal AHB-Lite signals:
//   HSEL, HADDR, HTRANS, HWRITE, HREADY, HREADYOUT, HRDATA
//
// Important:
//   EF_QSPI_XIP_CTRL_AHBL has no HWDATA and no HRESP.
//   Therefore this bridge supports reads only.
//   OBI writes return an error response.


`include "common_cells/assertions.svh"

module obi_to_ahbl #(
parameter obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
parameter type obi_req_t = logic,
parameter type obi_rsp_t = logic,
parameter logic [ObiCfg.AddrWidth-1:0] AddrOffset = '0
) (
input  logic clk_i,
input  logic rst_ni,

input  obi_req_t obi_req_i,
output obi_rsp_t obi_rsp_o,

output logic [31:0] haddr_o,
output logic [1:0]  htrans_o,
output logic        hwrite_o,
output logic        hsel_o,
output logic        hready_o,

input  logic        hreadyout_i,
input  logic [31:0] hrdata_i
);

localparam logic [1:0] HTRANS_IDLE   = 2'b00;
localparam logic [1:0] HTRANS_NONSEQ = 2'b10;

typedef enum logic [1:0] {
Idle,
AhbWait,
ObiResp
} state_e;

state_e state_q, state_d;

logic [ObiCfg.IdWidth-1:0]   aid_q, aid_d;
logic [ObiCfg.AddrWidth-1:0] addr_q, addr_d;
logic [31:0]                 rdata_q, rdata_d;
logic                        err_q, err_d;

always_ff @(posedge clk_i or negedge rst_ni) begin
if (!rst_ni) begin
state_q <= Idle;
aid_q   <= '0;
addr_q  <= '0;
rdata_q <= '0;
err_q   <= 1'b0;
end else begin
state_q <= state_d;
aid_q   <= aid_d;
addr_q  <= addr_d;
rdata_q <= rdata_d;
err_q   <= err_d;
end
end

always_comb begin
state_d = state_q;
aid_d   = aid_q;
addr_d  = addr_q;
rdata_d = rdata_q;
err_d   = err_q;

obi_rsp_o.gnt              = 1'b0;
obi_rsp_o.rvalid           = 1'b0;
obi_rsp_o.r.rid            = aid_q;
obi_rsp_o.r.rdata          = rdata_q;
obi_rsp_o.r.err            = err_q;
obi_rsp_o.r.r_optional     = '0;

hsel_o   = 1'b0;
htrans_o = HTRANS_IDLE;
haddr_o  = 32'(addr_q - AddrOffset);
hwrite_o = 1'b0;

/*
 * For this direct single-slave AHB-Lite connection, use HREADYOUT as the
 * global HREADY input. This stalls the AHB address/control phase while the
 * Efabless QSPI controller is busy.
 */
hready_o = hreadyout_i;

case (state_q)

  Idle: begin
    obi_rsp_o.gnt = hreadyout_i;

    if (obi_req_i.req && obi_rsp_o.gnt) begin
      aid_d  = obi_req_i.a.aid;
      addr_d = obi_req_i.a.addr;

      if (obi_req_i.a.we) begin
        rdata_d = '0;
        err_d   = 1'b1;
        state_d = ObiResp;
      end else begin
        err_d = 1'b0;

        hsel_o   = 1'b1;
        htrans_o = HTRANS_NONSEQ;
        haddr_o  = 32'(obi_req_i.a.addr - AddrOffset);
        hwrite_o = 1'b0;

        state_d = AhbWait;
      end
    end
  end

  AhbWait: begin
    hsel_o   = 1'b1;
    htrans_o = HTRANS_NONSEQ;
    haddr_o  = 32'(addr_q - AddrOffset);
    hwrite_o = 1'b0;

    if (hreadyout_i) begin
      rdata_d = hrdata_i;
      err_d   = 1'b0;
      state_d = ObiResp;
    end
  end

  ObiResp: begin
    obi_rsp_o.rvalid           = 1'b1;
    obi_rsp_o.r.rid            = aid_q;
    obi_rsp_o.r.rdata          = rdata_q;
    obi_rsp_o.r.err            = err_q;
    obi_rsp_o.r.r_optional     = '0;

    state_d = Idle;
  end

  default: begin
    state_d = Idle;
  end

endcase

end

`ifdef QSPI_OBI_AHB_DEBUG
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (state_q != Idle || obi_req_i.req || obi_rsp_o.rvalid || hsel_o) begin
        $display("@%t | [OBI2AHB] state=%0d req=%0b gnt=%0b rvalid=%0b addr=0x%08h haddr=0x%08h hsel=%0b htrans=%b hready=%0b hreadyout=%0b hrdata=0x%08h rdata=0x%08h err=%0b",
                 $time,
                 state_q,
                 obi_req_i.req,
                 obi_rsp_o.gnt,
                 obi_rsp_o.rvalid,
                 obi_req_i.a.addr,
                 haddr_o,
                 hsel_o,
                 htrans_o,
                 hready_o,
                 hreadyout_i,
                 hrdata_i,
                 obi_rsp_o.r.rdata,
                 obi_rsp_o.r.err);
      end
    end
  end
`endif

`ASSERT_INIT(no_rready, ObiCfg.UseRReady == 0,
"RReady not supported in OBI to AHBL conversion")

`ASSERT_INIT(no_atop, ObiCfg.OptionalCfg.UseAtop == 0,
"ATOP not supported in OBI to AHBL conversion")

`ASSERT_INIT(no_memtype, ObiCfg.OptionalCfg.UseMemtype == 0,
"Memtype not supported in OBI to AHBL conversion")

`ASSERT_INIT(no_debug, ObiCfg.OptionalCfg.UseDbg == 0,
"Debug not supported in OBI to AHBL conversion")

`ASSERT_INIT(no_integrity, !ObiCfg.Integrity,
"Integrity not supported in OBI to AHBL conversion")

`ASSERT_INIT(no_achk, ObiCfg.OptionalCfg.AChkWidth == 0,
"ACHK field not supported in OBI to AHBL conversion")

`ASSERT_INIT(data_width_32, ObiCfg.DataWidth == 32,
"This OBI to AHBL bridge assumes 32-bit OBI data width")

endmodule

// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

// changed by Jan Häussermann and Nino Singer for QSPI-XIP
// Accesses to 0x2000_0000..0x2000_0FFF return a small user ROM string.
// Accesses to 0x2000_1000..0x2100_0FFF are connected to the QSPI/XIP controller.

module user_domain import user_pkg::*; import croc_pkg::*; #(
  parameter int unsigned GpioCount = 16,
  parameter int unsigned NumExternalIrqs = 4
) (
  input  logic      clk_i,
  input  logic      ref_clk_i,
  input  logic      rst_ni,
  input  logic      testmode_i,

  input  sbr_obi_req_t user_sbr_obi_req_i, // User Sbr (rsp_o), Croc Mgr (req_i)
  output sbr_obi_rsp_t user_sbr_obi_rsp_o,

  output mgr_obi_req_t user_mgr_obi_req_o, // User Mgr (req_o), Croc Sbr (rsp_i)
  input  mgr_obi_rsp_t user_mgr_obi_rsp_i,

  input  logic [      GpioCount-1:0] gpio_in_sync_i, // synchronized GPIO inputs
  output logic [NumExternalIrqs-1:0] interrupts_o,    // interrupts to core

  // QSPI external pins @nino @jan
  output logic qspi_sck_o, 
  output logic qspi_ce_n_o,
  input logic [3:0] qspi_din_i,
  output logic [3:0] qspi_dout_o,
  output logic [3:0] qspi_douten_o
);

  assign interrupts_o = '0;


  //////////////////////
  // User Manager MUX //
  /////////////////////

  // No manager so we don't need a obi_mux module and just terminate the request properly
  assign user_mgr_obi_req_o = '0;


  ////////////////////////////
  // User Subordinate DEMUX // @nino @jan
  ////////////////////////////

  // ----------------------------------------------------------------------------------------------
  // User Subordinate Buses
  // ----------------------------------------------------------------------------------------------

  // Collection of signals from the demultiplexer
  sbr_obi_req_t [NumDemuxSbr-1:0] all_user_sbr_obi_req;
  sbr_obi_rsp_t [NumDemuxSbr-1:0] all_user_sbr_obi_rsp;

  // Error Subordinate Bus
  sbr_obi_req_t user_error_obi_req;
  sbr_obi_rsp_t user_error_obi_rsp;

  // OBI bus to hardcoded user ROM string
  sbr_obi_req_t user_rom_obi_req;
  sbr_obi_rsp_t user_rom_obi_rsp;

  // OBI bus to QSPI/XIP controller
  sbr_obi_req_t user_qspi_obi_req;
  sbr_obi_rsp_t user_qspi_obi_rsp;

  // Fanout into more readable signals
  assign user_error_obi_req              = all_user_sbr_obi_req[UserError];
  assign all_user_sbr_obi_rsp[UserError] = user_error_obi_rsp;

  assign user_rom_obi_req                = all_user_sbr_obi_req[UserRom];
  assign all_user_sbr_obi_rsp[UserRom]   = user_rom_obi_rsp;

  assign user_qspi_obi_req               = all_user_sbr_obi_req[UserQspi];
  assign all_user_sbr_obi_rsp[UserQspi]  = user_qspi_obi_rsp;

  //-----------------------------------------------------------------------------------------------
  // Demultiplex to User Subordinates according to address map
  //-----------------------------------------------------------------------------------------------

  logic [cf_math_pkg::idx_width(NumDemuxSbr)-1:0] user_idx;

  addr_decode #(
    .NoIndices ( NumDemuxSbr                    ),
    .NoRules   ( $size(UserAddrMap)             ),
    .addr_t    ( logic[SbrObiCfg.DataWidth-1:0] ),
    .rule_t    ( addr_map_rule_t                ),
    .Napot     ( 1'b0                           )
  ) i_addr_decode_periphs (
    .addr_i           ( user_sbr_obi_req_i.a.addr ),
    .addr_map_i       ( UserAddrMap               ),
    .idx_o            ( user_idx                  ),
    .dec_valid_o      (),
    .dec_error_o      (),
    .en_default_idx_i ( 1'b1      ),
    .default_idx_i    ( UserError )
  );

  obi_demux #(
    .ObiCfg      ( SbrObiCfg     ),
    .obi_req_t   ( sbr_obi_req_t ),
    .obi_rsp_t   ( sbr_obi_rsp_t ),
    .NumMgrPorts ( NumDemuxSbr   ),
    .NumMaxTrans ( 2             )
  ) i_obi_demux (
    .clk_i,
    .rst_ni,

    .sbr_port_select_i ( user_idx             ),
    .sbr_port_req_i    ( user_sbr_obi_req_i   ),
    .sbr_port_rsp_o    ( user_sbr_obi_rsp_o   ),

    .mgr_ports_req_o   ( all_user_sbr_obi_req ),
    .mgr_ports_rsp_i   ( all_user_sbr_obi_rsp )
  );


//-------------------------------------------------------------------------------------------------
// User Subordinates
//-------------------------------------------------------------------------------------------------

  ///////////////////////////////////
  // Replace this with your Design // @nino @jan
  ///////////////////////////////////

  // --------------------------------------------------------------------------
  // Hardcoded User ROM
  // --------------------------------------------------------------------------
  // The automatic checker reads from 0x2000_0000 and expects a zero-terminated
  // ASCII string with the group members' names.

  function automatic logic [31:0] user_rom_word(input logic [9:0] word_addr);
    unique case (word_addr)
      // "Jan Haeussermann, Nino Singer\0"
      10'd0: user_rom_word = 32'h206E614A; // "Jan "
      10'd1: user_rom_word = 32'h75656148; // "Haeu"
      10'd2: user_rom_word = 32'h72657373; // "sser"
      10'd3: user_rom_word = 32'h6E6E616D; // "mann"
      10'd4: user_rom_word = 32'h694E202C; // ", Ni"
      10'd5: user_rom_word = 32'h53206F6E; // "no S"
      10'd6: user_rom_word = 32'h65676E69; // "inge"
      10'd7: user_rom_word = 32'h00000072; // "r\0\0\0"
      default: user_rom_word = 32'h00000000;
    endcase
  endfunction

  logic                         user_rom_req_q;
  logic                         user_rom_we_q;
  logic [SbrObiCfg.IdWidth-1:0] user_rom_id_q;
  logic [9:0]                   user_rom_word_addr_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      user_rom_req_q       <= 1'b0;
      user_rom_we_q        <= 1'b0;
      user_rom_id_q        <= '0;
      user_rom_word_addr_q <= '0;
    end else begin
      user_rom_req_q       <= user_rom_obi_req.req;
      user_rom_we_q        <= user_rom_obi_req.a.we;
      user_rom_id_q        <= user_rom_obi_req.a.aid;
      user_rom_word_addr_q <= user_rom_obi_req.a.addr[11:2];
    end
  end

  always_comb begin
    user_rom_obi_rsp             = '0;
    user_rom_obi_rsp.gnt         = 1'b1;
    user_rom_obi_rsp.rvalid      = user_rom_req_q;
    user_rom_obi_rsp.r.rid       = user_rom_id_q;
    user_rom_obi_rsp.r.rdata     = user_rom_we_q ? 32'hBADCAB1E
                                                 : user_rom_word(user_rom_word_addr_q);
    user_rom_obi_rsp.r.err       = user_rom_we_q;
    user_rom_obi_rsp.r.r_optional = '0;
  end

  // QSPI AHB-Lite signals between OBI-to-AHBL bridge and Efabless QSPI controller
  logic        qspi_hsel;
  logic [31:0] qspi_haddr;
  logic [1:0]  qspi_htrans;
  logic        qspi_hwrite;
  logic        qspi_hready;
  logic        qspi_hreadyout;
  logic [31:0] qspi_hrdata;

  ///////////////////////////
  // QSPI Flash Controller //
  ///////////////////////////

  // Bridge from Croc OBI to the Efabless AHB-Lite QSPI interface.
  obi_to_ahbl #(
    .ObiCfg     ( SbrObiCfg             ),
    .obi_req_t  ( sbr_obi_req_t         ),
    .obi_rsp_t  ( sbr_obi_rsp_t         ),
    .AddrOffset ( 32'h2000_1000 )
  ) i_obi_to_ahbl_qspi (
    .clk_i,
    .rst_ni,

    .obi_req_i ( user_qspi_obi_req ),
    .obi_rsp_o ( user_qspi_obi_rsp ),
    .haddr_o      ( qspi_haddr      ),
    .htrans_o     ( qspi_htrans     ),
    .hwrite_o     ( qspi_hwrite     ),
    .hsel_o       ( qspi_hsel       ),
    .hready_o     ( qspi_hready     ),
    .hreadyout_i  ( qspi_hreadyout  ),
    .hrdata_i     ( qspi_hrdata     )
  );

  // Efabless QSPI XIP controller with AHB-Lite wrapper.
  EF_QSPI_XIP_CTRL_AHBL #(
    .NUM_LINES    ( 16  ),
    .LINE_SIZE    ( 32  ),
    .RESET_CYCLES ( 999 )
  ) i_qspi_ahbl (
    // AHB-Lite Slave Interface
    .HCLK      ( clk_i          ),
    .HRESETn   ( rst_ni         ),
    .HSEL      ( qspi_hsel      ),
    .HADDR     ( qspi_haddr     ),
    .HTRANS    ( qspi_htrans    ),
    .HWRITE    ( qspi_hwrite    ),
    .HREADY    ( qspi_hready    ),
    .HREADYOUT ( qspi_hreadyout ),
    .HRDATA    ( qspi_hrdata    ),

    // External Interface to Quad I/O
    .sck       ( qspi_sck_o    ),
    .ce_n      ( qspi_ce_n_o   ),
    .din       ( qspi_din_i    ),
    .dout      ( qspi_dout_o   ),
    .douten    ( qspi_douten_o )
  );

  ///////////////////////////////////

  // Error Subordinate
  obi_err_sbr #(
    .ObiCfg      ( SbrObiCfg     ),
    .obi_req_t   ( sbr_obi_req_t ),
    .obi_rsp_t   ( sbr_obi_rsp_t ),
    .NumMaxTrans ( 1             ),
    .RspData     ( 32'hBADCAB1E  )
  ) i_user_err (
    .clk_i,
    .rst_ni,
    .testmode_i ( testmode_i         ),
    .obi_req_i  ( user_error_obi_req ),
    .obi_rsp_o  ( user_error_obi_rsp )
  );

endmodule

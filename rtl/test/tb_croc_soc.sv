// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>
// - Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

// changed by Jan Häussermann and Nino Singer for QSPI-XIP

`define TRACE_WAVE

module tb_croc_soc #(
  parameter int unsigned GpioCount = 32
);

  import tb_croc_pkg::*;

  // Signals fully controlled by the VIP
  // use VIP functions/tasks to manipulate these signals
  logic rst_n;
  logic sys_clk;
  logic ref_clk;

  logic jtag_tck;
  logic jtag_trst_n;
  logic jtag_tms;
  logic jtag_tdi;
  logic jtag_tdo;

  logic uart_rx;
  logic uart_tx;

  // Signals partially controlled by the VIP
  logic [GpioCount-1:0] gpio_in;
  logic [GpioCount-1:0] gpio_out;
  logic [GpioCount-1:0] gpio_out_en;

  // QSPI signals from the DUT @nino @jan
  logic       qspi_sck;
  logic       qspi_ce_n;
  logic [3:0] qspi_din;
  logic [3:0] qspi_dout;
  logic [3:0] qspi_douten;

  // QSPI flash model. The c code will be automatically
  // compiled and loaded with ....flash.hex file in here.
  qspi_flash_model i_qspi_flash_model (
    .sck_i    ( qspi_sck    ),
    .ce_ni    ( qspi_ce_n   ),
    .dout_i   ( qspi_dout   ),
    .douten_i ( qspi_douten ),
    .din_o    ( qspi_din    )
  );

  // Print transaction boundaries for QSPI debug.
  //always @(negedge qspi_ce_n) begin
  //  $display("@%t | [QSPI_TB] CE low, transaction start", $time);
  //end
  //always @(posedge qspi_ce_n) begin
  //  $display("@%t | [QSPI_TB] CE high, transaction end", $time);
  //end

  // Signals controlled by the testbench

  /////////////////////////////
  //  Command Line Arguments //
  /////////////////////////////

  string binary_path;

  initial begin
    $display("Running QSPI/XIP boot test. Program image is passed with +flash=...");
  end

  ////////////
  //  VIP   //
  ////////////
  // Verification IP
  // - drives clocks and resets
  // - provides helper tasks and functions for JTAG, namely:
  //   - jtag_load_hex: loads a hex file into the DUT's memory
  //   - jtag_write_reg32: write 32-bit value to DUT
  //   - jtag_read_reg32: read 32-bit value from DUT
  //   - jtag_halt / jtag_resume: control core execution
  //   - jtag_wait_for_eoc: wait for end of code execution (core writes non-zero to status register)
  // - prints UART output to console (you can also write via uart_write_byte)
  // - internal GPIO loopback for helloworld test

  croc_vip #(
    .GpioCount ( GpioCount )
  ) i_vip (
    .rst_no        ( rst_n       ),
    .sys_clk_o     ( sys_clk     ),
    .ref_clk_o     ( ref_clk     ),
    .jtag_tck_o    ( jtag_tck    ),
    .jtag_trst_no  ( jtag_trst_n ),
    .jtag_tms_o    ( jtag_tms    ),
    .jtag_tdi_o    ( jtag_tdi    ),
    .jtag_tdo_i    ( jtag_tdo    ),
    .uart_rx_o     ( uart_rx     ),
    .uart_tx_i     ( uart_tx     ),
    .gpio_out_en_i ( gpio_out_en ),
    .gpio_out_i    ( gpio_out    ),
    .gpio_in_o     ( gpio_in     )
  );

  ////////////
  //  DUT   //
  ////////////

  `ifdef TARGET_NETLIST_YOSYS
  \croc_soc$croc_chip.i_croc_soc i_croc_soc (
  `else
  croc_soc #(
    .GpioCount ( GpioCount )
  ) i_croc_soc (
  `endif
    .clk_i         ( sys_clk     ),
    .rst_ni        ( rst_n       ),
    .ref_clk_i     ( ref_clk     ),
    .testmode_i    ( 1'b0        ),
    .status_o      (             ),
    .jtag_tck_i    ( jtag_tck    ),
    .jtag_tdi_i    ( jtag_tdi    ),
    .jtag_tdo_o    ( jtag_tdo    ),
    .jtag_tms_i    ( jtag_tms    ),
    .jtag_trst_ni  ( jtag_trst_n ),
    .uart_rx_i     ( uart_rx     ),
    .uart_tx_o     ( uart_tx     ),
    .gpio_i        ( gpio_in     ),
    .gpio_o        ( gpio_out    ),
    .gpio_out_en_o ( gpio_out_en ),

    //@nino @jan
    .qspi_sck_o    ( qspi_sck    ),
    .qspi_ce_n_o   ( qspi_ce_n   ),
    .qspi_din_i    ( qspi_din    ),
    .qspi_dout_o   ( qspi_dout   ),
    .qspi_douten_o ( qspi_douten )
  );

  /////////////////
  //  Testbench  //
  /////////////////

  logic [31:0] tb_data;

  initial begin
  $timeformat(-9, 0, "ns", 12);

  // Wait for reset
  #ClkPeriodSys;

  // Initialize JTAG/debug interface
  // The program is NOT loaded through JTAG anymore
  i_vip.jtag_init();

  // Wake the core
  // bootrom will jump and executecode from QSPI (user_address space)
  $display("@%t | [CORE] Waking core via CLINT msip", $time);
  i_vip.jtag_write_reg32(ClintBaseAddr, 32'h1);

  // same halt/resume sequence as in the original testbench
  i_vip.jtag_halt();
  i_vip.jtag_resume();

  // Wait until the program returns
  $display("@%t | [CORE] Wait for end of code...", $time);
  i_vip.jtag_wait_for_eoc(tb_data);

  // Finish simulation
  repeat (50) @(posedge sys_clk);
  $finish();
  end


  ////////////////
  //  Waveform  //
  ////////////////
  // start waveform dump at time 0, independent of stimuli
  initial begin
    `ifdef TRACE_WAVE
      `ifdef VERILATOR
        $dumpfile("croc.fst");
        $dumpvars(0, i_croc_soc);
        $dumpvars(0, i_qspi_flash_model);
      `else
        $dumpfile("croc.vcd");
        $dumpvars(0, i_croc_soc);
        $dumpvars(0, i_qspi_flash_model);
      `endif
    `endif
  end

  // flush waveform dump when simulation ends
  final begin
    `ifdef TRACE_WAVE
      $dumpflush;
    `endif
  end

endmodule
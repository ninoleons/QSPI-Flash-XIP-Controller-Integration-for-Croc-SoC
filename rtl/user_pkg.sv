// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

`include "obi/typedef.svh"

package user_pkg;

  //////////////////
  // User Manager //
  //////////////////

  // None


  ///////////////////////
  // User Subordinates //
  ///////////////////////

  // The base address of the user domain can be retrived from `croc_pkg::UserBaseAddr`
  // Recommended: place subordinates at 4KB boundaries (32'hXXXX_X000)

  /// Enum with user domain demultiplexer subordinate idxs
  /// changed by @nino @jan
  typedef enum bit [4:0]  {
    UserError = 0,
    UserRom   = 1,
    UserQspi  = 2
  } user_demux_outputs_e;

  /// Address rules given to user domain demultiplexer (see croc_pkg.sv for examples)
  /// changed by @nino @jan
  localparam croc_pkg::addr_map_rule_t [1:0] UserAddrMap = '{
    '{
      idx:        UserRom,
      start_addr: croc_pkg::UserBaseAddr,
      end_addr:   croc_pkg::UserBaseAddr + 32'h0000_1000
    },
    '{
      idx:        UserQspi,
      start_addr: croc_pkg::UserBaseAddr + 32'h0000_1000,
      end_addr:   croc_pkg::UserBaseAddr + 32'h0100_1000
    }
  };
  // All addresses outside the defined address rules go to the error subordinate

  // +1 for additional OBI error
  localparam int unsigned NumDemuxSbr = $size(UserAddrMap) + 1;

endpackage

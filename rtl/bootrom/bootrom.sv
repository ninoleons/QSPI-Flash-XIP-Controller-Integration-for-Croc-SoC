// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

/// Bootrom containing WFI trampoline, register init, trap handlers, and EOC.
/// After reset the core fetches from here:
/// 1. Enables MSIE, executes WFI, waits until woken by CLINT msip
/// 2. Clears msip, disables interrupts, clears registers x1/x3-x15
/// 3. Sets mtvec to bootrom trap handler

/// 5. On main() return: _eoc packs retval, writes CORESTATUS, halts
/// Trap handler dispatches to QSPI/XIP function pointer table at 0x2000_1000.
/// Source: bootrom.S

/// changed by Jan Häussermann and Nino Singer for QSPI-XIP
/// 4. directly jump to QSPI code start address 0x2000_1000 instead of reading BOOTADDR from soc_ctrl

module bootrom #(
    /// The OBI configuration for all ports.
    parameter obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
    /// OBI request type
    parameter type obi_req_t = logic,
    /// OBI response type
    parameter type obi_rsp_t = logic
) (
    input  logic     clk_i,
    input  logic     rst_ni,
    input  obi_req_t obi_req_i,
    output obi_rsp_t obi_rsp_o
);

    //-----------------------------------------------------------------------------------
    // Bootrom divided into blocks per contiguous label
    //-----------------------------------------------------------------------------------
    // Contiguous block starting at 0x02000000: _start
    // changed by @nino @jan for XIP
    localparam int unsigned StartRomWords = 24;
    localparam logic [31:0] StartRom [StartRomWords] = '{
        32'h30445073, // 0x02000000
        32'h10500073, // 0x02000004
        32'h020402B7, // 0x02000008
        32'h0002A023, // 0x0200000C
        32'h30405073, // 0x02000010
        32'h00000193, // 0x02000014
        32'h00000213, // 0x02000018
        32'h00000313, // 0x0200001C
        32'h00000393, // 0x02000020
        32'h00000413, // 0x02000024
        32'h00000493, // 0x02000028
        32'h00000513, // 0x0200002C
        32'h00000593, // 0x02000030
        32'h00000613, // 0x02000034
        32'h00000693, // 0x02000038
        32'h00000713, // 0x0200003C
        32'h00000793, // 0x02000040
        32'h00000297, // 0x02000044
        32'h1BC28293, // 0x02000048
        32'h30529073, // 0x0200004C
        32'h00000097, // 0x02000050
        32'h0B008093, // 0x02000054
        32'h200012B7, // 0x02000058
        32'h00028067 // 0x0200005C
    };


    // Contiguous block starting at 0x02000100: _eoc
    // changed by @nino @jan for XIP
    localparam int unsigned EocRomWords = 5;
    localparam logic [31:0] EocRom [EocRomWords] = '{
        32'h00151293, // 0x02000100
        32'h0012E293, // 0x02000104
        32'h03000337, // 0x02000108
        32'h00532423, // 0x0200010C
        32'h10500073 // 0x02000110
    };

    // Contiguous block starting at 0x02000200: _trap_handler_wrapper
    // changed by @nino @jan for XIP
    localparam int unsigned TrapHandlerRomWords = 22;
    localparam logic [31:0] TrapHandlerRom [TrapHandlerRomWords] = '{
        32'hFB010113, // 0x02000200
        32'h04112423, // 0x02000204
        32'h04512023, // 0x02000208
        32'h02612C23, // 0x0200020C
        32'h02712823, // 0x02000210
        32'h02A12423, // 0x02000214
        32'h02B12023, // 0x02000218
        32'h00C12C23, // 0x0200021C
        32'h00D12823, // 0x02000220
        32'h00E12423, // 0x02000224
        32'h00F12023, // 0x02000228
        32'h200012B7, // 0x0200022C
        32'h34202573, // 0x02000230
        32'h00054863, // 0x02000234
        32'h0042A303, // 0x02000238
        32'h000300E7, // 0x0200023C
        32'h0C00006F, // 0x02000240
        32'h00151513, // 0x02000244
        32'h00155513, // 0x02000248
        32'h0082A303, // 0x0200024C
        32'h000300E7, // 0x02000250
        32'h0AC0006F // 0x02000254
    };

    // Contiguous block starting at 0x02000300: _trap_exit
    // changed by @nino @jan for XIP
    localparam int unsigned TrapExitRomWords = 12;
    localparam logic [31:0] TrapExitRom [TrapExitRomWords] = '{
        32'h04812083, // 0x02000300
        32'h04012283, // 0x02000304
        32'h03812303, // 0x02000308
        32'h03012383, // 0x0200030C
        32'h02812503, // 0x02000310
        32'h02012583, // 0x02000314
        32'h01812603, // 0x02000318
        32'h01012683, // 0x0200031C
        32'h00812703, // 0x02000320
        32'h00012783, // 0x02000324
        32'h05010113, // 0x02000328
        32'h30200073 // 0x0200032C
    };

    // --------------------------------------------------------------------------
    // Handle OBI requests
    // --------------------------------------------------------------------------
    localparam int unsigned WordAddressWidth = 10; // 12-bit byte address

    logic                        we_d, we_q;
    logic                        req_d, req_q;
    logic [ObiCfg.IdWidth-1:0]   id_d, id_q;
    logic [WordAddressWidth-1:0] word_addr_d, word_addr_q;

    assign req_d       = obi_req_i.req;
    assign we_d        = obi_req_i.a.we;
    assign id_d        = obi_req_i.a.aid;
    assign word_addr_d = obi_req_i.a.addr[WordAddressWidth+2-1:2];

    // Latch request for one-cycle response
    `FF(req_q, req_d, '0, clk_i, rst_ni)
    `FF(we_q, we_d, '0, clk_i, rst_ni)
    `FF(id_q, id_d, '0, clk_i, rst_ni)
    `FF(word_addr_q, word_addr_d, '0, clk_i, rst_ni)

    // --------------------------------------------------------------------------
    // Mask-based ROM decode:
    // - upper 4 bits of the *word address* select the ROM block
    // - lower 6 bits index the word within that block
    // --------------------------------------------------------------------------
    logic        rom_req;
    logic [ 3:0] rom_select;
    logic [ 5:0] rom_idx, rom_size;
    logic        rom_error;
    logic [31:0] rom_rdata;

    assign rom_req    = req_q && !we_q;
    assign rom_select = word_addr_q[WordAddressWidth-1 -: 4];
    assign rom_idx    = word_addr_q[5:0];

    always_comb begin
        rom_rdata = 32'h0000_0000;
        rom_error = 1'b1;

        case (rom_select)
            4'b0000: rom_size  = StartRomWords;
            4'b0001: rom_size  = EocRomWords;
            4'b0010: rom_size  = TrapHandlerRomWords;
            4'b0011: rom_size  = TrapExitRomWords;
            default: rom_size = 6'h00;
        endcase

        rom_error = (rom_idx >= rom_size);

        if (!rom_error && rom_req) begin
            case (rom_select)
                4'b0000: rom_rdata = StartRom[rom_idx];
                4'b0001: rom_rdata = EocRom[rom_idx];
                4'b0010: rom_rdata = TrapHandlerRom[rom_idx];
                4'b0011: rom_rdata = TrapExitRom[rom_idx];
                default: rom_rdata = 32'h0000_0000;
            endcase
        end
    end

    always_comb begin
        obi_rsp_o         = '0;
        obi_rsp_o.gnt     = 1'b1; // always grant
        obi_rsp_o.rvalid  = req_q;
        obi_rsp_o.r.rid   = id_q;
        if (we_q) begin
            // write request
            obi_rsp_o.r.rdata = 32'hBADCAB1E;
            obi_rsp_o.r.err   = 1'b1;
        end else begin
            obi_rsp_o.r.rdata = rom_rdata;
            obi_rsp_o.r.err   = rom_error;
        end
    end

endmodule

// added by Jan Häussermann and Nino Singer for QSPI-XIP

// This file was added as a simulation model for an external QSPI flash.
// It contains an internal byte-addressed memory
// logic [7:0] mem [0:BYTES-1];
// The flash contents are loaded with $readmemh
// A +flash=<path> plusarg was added, so the testbench can select which .flash.hex image to load

module qspi_flash_model #(
    parameter int unsigned BYTES = 16 * 1024 * 1024
) (
    input logic sck_i,
    input logic ce_ni,

    input logic [3:0] dout_i,
    input logic [3:0] douten_i,

    output logic [3:0] din_o
);

    logic [7:0] mem [0:BYTES-1];

    int unsigned edge_cnt_q;

    logic [7:0]  cmd_q;
    logic [23:0] addr_q;

    logic continuous_mode_q;
    logic continuous_xfer_q;

    string flash_path;

    initial begin
        $display("@%t | [QSPI_FLASH] instance path = %m", $time);

        for (int i = 0; i < BYTES; i++) begin
            mem[i] = 8'h00;
        end

        flash_path = "../sw/bin/helloworld.flash.hex";

        if ($value$plusargs("flash=%s", flash_path)) begin
            $display("@%t | [QSPI_FLASH] Loading flash image from plusarg: %s",
                    $time, flash_path);
        end else begin
            $display("@%t | [QSPI_FLASH] Loading default flash image: %s",
                    $time, flash_path);
        end

        $readmemh(flash_path, mem);

        edge_cnt_q        = 0;
        cmd_q             = 8'h00;
        addr_q            = 24'h000000;
        continuous_mode_q = 1'b0;
        continuous_xfer_q = 1'b0;
    end

    always_ff @(posedge sck_i or posedge ce_ni) begin
        if (ce_ni) begin
            edge_cnt_q        <= 0;
            cmd_q             <= 8'h00;
            addr_q            <= 24'h000000;
            continuous_xfer_q <= continuous_mode_q;
        end else begin
            if (!continuous_xfer_q) begin
                if (edge_cnt_q < 8) begin
                    cmd_q <= {cmd_q[6:0], dout_i[0]};

                    if (edge_cnt_q == 7) begin
                        if ({cmd_q[6:0], dout_i[0]} == 8'hEB) begin
                            continuous_mode_q <= 1'b1;
                        end
                    end
                end else if (edge_cnt_q < 14) begin
                    addr_q <= {addr_q[19:0], dout_i};
                end
            end else begin
                if (edge_cnt_q < 6) begin
                    addr_q <= {addr_q[19:0], dout_i};
                end
            end

            edge_cnt_q <= edge_cnt_q + 1;
        end
    end

    always_comb begin
        int unsigned data_start;
        int unsigned nibble_idx;
        int unsigned byte_addr;

        /*
         * Full 0xEB transaction:
         *   command 8 + address 6 + mode 2 + dummy 4 = 20
         *
         * Continuous transaction:
         *   address 6 + mode 2 + dummy 4 = 12
         *
         * The Efabless reader samples one nibble after this boundary,
         * so use edge_cnt_q > data_start and subtract one.
         */
        din_o       = 4'h0;
        data_start  = continuous_xfer_q ? 12 : 20;
        nibble_idx  = 0;
        byte_addr   = 0;
        
        if (!ce_ni && edge_cnt_q > data_start) begin
            nibble_idx = edge_cnt_q - data_start - 1;
            byte_addr  = addr_q + (nibble_idx >> 1);

            if (byte_addr < BYTES) begin
                // Low nibble first, then high nibble.
                if (nibble_idx[0] == 1'b0) begin
                    din_o = mem[byte_addr][7:4];
                end else begin
                    din_o = mem[byte_addr][3:0];
                end
            end
        end
    end

endmodule

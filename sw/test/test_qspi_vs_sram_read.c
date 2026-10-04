#include <stdint.h>
#include "uart.h"
#include "print.h"

#define QSPI_XIP_BASE_ADDR 0x20001000u
#define SRAM_BASE_ADDR     0x10000000u

// an example to run a test is  -->  ./run_verilator.sh --run ../sw/bin/test/test_qspi_vs_sram_read.flash.hex

// This test shows:
// 1. The user ROM at 0x2000_0000 contains the group name string.
// 2. The executable code is located in QSPI/XIP starting at 0x2000_1000.
// To check. Compare the first QSPI/XIP words at 0x20001000 with the beginning of the .flash.hex file.
// 3. SRAM is used for data/stack and no longer contains the program text.

int main(void) {
    uart_init();

    printf("Hello from QSPI XIP!\n");

    volatile char     *user_rom = (volatile char *)USER_ROM_BASE_ADDR;
    volatile uint32_t *user_rom_words = (volatile uint32_t *)USER_ROM_BASE_ADDR;
    volatile uint32_t *xip  = (volatile uint32_t *)QSPI_XIP_BASE_ADDR;
    volatile uint32_t *sram = (volatile uint32_t *)SRAM_BASE_ADDR;

    printf("User ROM at 0x20000000:\n");
    printf("String: ");

    for (int i = 0; i < 128; i++) {
        char c = user_rom[i];

        if (c == '\0') {
            break;
        }

        printf("%c", c);
    }
    printf("\n");

    printf("  USER_ROM[0x20000000] = %x\n", user_rom_words[0]);
    printf("  USER_ROM[0x20000004] = %x\n", user_rom_words[1]);
    printf("  USER_ROM[0x20000008] = %x\n", user_rom_words[2]);
    printf("  USER_ROM[0x2000000c] = %x\n", user_rom_words[3]);

    printf("First words from QSPI/XIP:\n");
    printf("  XIP[0x20001000] = %x\n", xip[0]);
    printf("  XIP[0x20001004] = %x\n", xip[1]);
    printf("  XIP[0x20001008] = %x\n", xip[2]);
    printf("  XIP[0x2000100c] = %x\n", xip[3]);

    printf("First words from SRAM:\n");
    printf("  SRAM[0x10000000] = %x\n", sram[0]);
    printf("  SRAM[0x10000004] = %x\n", sram[1]);
    printf("  SRAM[0x10000008] = %x\n", sram[2]);
    printf("  SRAM[0x1000000c] = %x\n", sram[3]);

    printf("Compare QSPI/XIP words with .flash.hex file to verify!\n");
    printf("The code is no longer located at SRAM 0x10000000!\n");

    uart_write_flush();

    return 0;
}
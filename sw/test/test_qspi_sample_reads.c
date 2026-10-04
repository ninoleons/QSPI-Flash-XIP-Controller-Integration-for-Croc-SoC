#include <stdint.h>

#include "uart.h"
#include "print.h"

#define QSPI_XIP_BASE_ADDR 0x20001000u

// 24-bit QSPI address space = 16 MiB
#define QSPI_SIZE_BYTES    0x01000000u
#define QSPI_LAST_OFFSET   (QSPI_SIZE_BYTES - 4u)

static char hex_digit(uint32_t x)
{
    x &= 0xfu;
    return (x < 10u) ? (char)('0' + x) : (char)('a' + x - 10u);
}

static void print_hex32(uint32_t value)
{
    for (int shift = 28; shift >= 0; shift -= 4) {
        printf("%c", hex_digit(value >> shift));
    }
}

static void read_word(const char *label, uint32_t addr)
{
    volatile uint32_t *ptr = (volatile uint32_t *)addr;
    uint32_t value = *ptr;

    printf("  ");
    printf(label);
    printf("[0x");
    print_hex32(addr);
    printf("] = 0x");
    print_hex32(value);
    printf("\n");
}

static void read_qspi_offset(uint32_t offset)
{
    read_word("QSPI", QSPI_XIP_BASE_ADDR + offset);
}

int main(void)
{
    uart_init();

    printf("QSPI sample read test\n");
    printf("Group: Jan Haeussermann, Nino Singer\n");

    printf("Memory map:\n");
    printf("  User ROM : 0x20000000 .. 0x20000fff\n");
    printf("  QSPI/XIP : 0x20001000 .. 0x21000fff\n");

    printf("User ROM check:\n");
    read_word("USER_ROM", USER_ROM_BASE_ADDR + 0x0000u);
    read_word("USER_ROM", USER_ROM_BASE_ADDR + 0x0004u);

    printf("QSPI sample reads:\n");
    read_qspi_offset(0x000000u);         // first QSPI word
    read_qspi_offset(0x000004u);
    read_qspi_offset(0x000010u);
    read_qspi_offset(0x000100u);
    read_qspi_offset(0x001000u);
    read_qspi_offset(0x010000u);
    read_qspi_offset(0x100000u);         // 1 MiB
    read_qspi_offset(0x400000u);         // 4 MiB
    read_qspi_offset(0x800000u);         // 8 MiB
    read_qspi_offset(0xc00000u);         // 12 MiB
    read_qspi_offset(QSPI_LAST_OFFSET);  // last valid QSPI word

    printf("Expected last QSPI address: 0x");
    print_hex32(QSPI_XIP_BASE_ADDR + QSPI_LAST_OFFSET);
    printf("\n");

    printf("QSPI sample read test finished.\n");

    uart_write_flush();

    return 0;
}
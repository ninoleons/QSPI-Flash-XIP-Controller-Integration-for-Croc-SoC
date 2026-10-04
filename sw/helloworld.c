#include "uart.h"
#include "print.h"

// This program was used as a simple first test to verify 
// that the core can boot and execute code directly from 0x20000000. (QSPI FLASH/XIP)

int main(void) {
    uart_init();
    printf("Hello from QSPI boot!\n");
    printf("Group: Jan Haeussermann, Nino Singer\n");
    uart_write_flush();
    return 0;
}
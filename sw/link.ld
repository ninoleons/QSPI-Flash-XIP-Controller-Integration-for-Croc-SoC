/* Copyright (c) 2024 ETH Zurich and University of Bologna.
 * Licensed under the Apache License, Version 2.0, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0
 *
 * Authors:
 * - Paul Scheffler <paulsc@iis.ee.ethz.ch>
 * - Philippe Sauter <phsauter@iis.ee.ethz.ch> 
 */

/* changed by Jan Häussermann and Nino Singer for QSPI-XIP
 * Executable and read-only sections are now placed into the QSPI/XIP region:
 * .vectors
 * .text._start
 * .text
 * .rodata
 * Runtime data remains in SRAM:
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
	/* QSPI XIP window used for code and read-only data max 16 MiB @nino @jan*/
	FLASH (rxail)  : ORIGIN = 0x20001000, LENGTH = 0x01000000

	/* on-chip SRAM used for writable data and stack @nino @jan*/
	SRAM  (rwxail) : ORIGIN = 0x10000000, LENGTH = 4K
}

PHDRS
{
	text PT_LOAD FLAGS(5); /* tag as: Read + Execute */
	data PT_LOAD FLAGS(6); /* tag as: Read + Write */
}

SECTIONS
{
    /* Drop metadata/debug sections, not needed */
	/DISCARD/ :
	{
	*(.riscv.attributes)
	*(.comment)
	}

	/* Start placing executable sections at the QSPI XIP base address @nino @jan*/
	. = ORIGIN(FLASH);

    /* Interrupt vector table @nino @jan*/
	.vectors : ALIGN(4)
	{
		*(.vectors)
		KEEP(*(.vectors))
	} > FLASH :text

    /* Startup entry (first instructions executed after bootrom) @nino @jan*/
	.text._start : ALIGN(4)
	{
		*(.text._start)
	} > FLASH :text

    /* Main code (text) and read-only data (rodata) @nino @jan*/
	.text : ALIGN(4)
	{
		*(.text)
		*(.text.*)
		*(.rodata)
		*(.rodata.*)
	} > FLASH :text

    /* Writable data (what people colloquially call RAM) @nino @jan*/
	.misc (NOLOAD) : ALIGN(4)
	{
	*(.sdata)
	*(.sdata.*)
	*(.data)
	*(.data.*)
	*(.sbss)
	*(.sbss.*)
	*(.bss)
	*(.bss.*)
	*(COMMON)
	} > SRAM :data
}

/* Global absolute symbols */

/* Place GP near the middle for efficient GP-relative access */
PROVIDE(__global_pointer$ = ADDR(.misc) + SIZEOF(.misc) / 2);
/* Initial stack pointer at the end of SRAM */
PROVIDE(__stack_pointer$ = ORIGIN(SRAM) + LENGTH(SRAM));

/* Bootrom symbols (fixed addresses) */
PROVIDE(_eoc = 0x02000100);
PROVIDE(_trap_handler_wrapper = 0x02000200);
PROVIDE(_trap_exit = 0x02000300);

/* SoC register symbols */
PROVIDE(corestatus = 0x03000008);

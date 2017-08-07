// SK6812RGBW Signal Generation PRU Program Template using r30 based I/O
//
// Drives up to 8 strips using a single PRU with ultra-precise (nanosecond!) timing.. LEDscape (in userspace) writes rendered frames into shared DDR memory
// and sets a flag to indicate how many pixels are to be written.  The PRU then bit bangs the signal out the
// 8 special GPIO pins and sets a "complete" flag.
//
// To stop, the ARM can write a 0xFF to the command, which will cause the PRU code to exit.
//
// At 800 KHz the SK6812RGBW signal is:
//  ____
// |  | |______|
// 0  250 600  1250 offset
//    250 350   650 delta
//
// each pixel is stored in 4 bytes in the order RGBW
//
// while len > 0:
//    for bit# = 32 down to 0:
//        write out bits
//    increment address by 32
//

// This code is extremely similar to the ws281x code except 32 bits are output per pixel 
//

// Mapping lookup

.origin 0
.entrypoint START

#include "common.p.h"

#define CHECK_TIMEOUT WAIT_TIMEOUT 3000, FRAME_DONE

START:
	// Enable OCP master port
	// clear the STANDBY_INIT bit in the SYSCFG register,
	// otherwise the PRU will not be able to write outside the
	// PRU memory space and to the BeagleBon's pins.
	LBCO	r0, C4, 4, 4
	CLR		r0, r0, 4
	SBCO	r0, C4, 4, 4

	// Configure the programmable pointer register for PRU0 by setting
	// c28_pointer[15:0] field to 0x0120.  This will make C28 point to
	// 0x00012000 (PRU shared RAM).
	MOV		r0, 0x00000120
	MOV		r1, CTPPR_0
	ST32	r0, r1

	// Configure the programmable pointer register for PRU0 by setting
	// c31_pointer[15:0] field to 0x0010.  This will make C31 point to
	// 0x80001000 (DDR memory).
	MOV		r0, 0x00100000
	MOV		r1, CTPPR_1
	ST32	r0, r1

	// Write a 0x1 into the response field so that they know we have started
	MOV r2, #0x1
	SBCO r2, CONST_PRUDRAM, 12, 4


	MOV r20, 0xFFFFFFFF

	// Wait for the start condition from the main program to indicate
	// that we have a rendered frame ready to clock out.  This also
	// handles the exit case if an invalid value is written to the start
	// start position.
_LOOP:
	// Let ledscape know that we're starting the loop again. It waits for this
	// interrupt before sending another frame
	RAISE_ARM_INTERRUPT

	// Load the pointer to the buffer from PRU DRAM into r0 and the
	// length (in bytes-bit words) into r1.
	// start command into r2
	LBCO      r_data_addr, CONST_PRUDRAM, 0, 12

	// Wait for a non-zero command
	QBEQ _LOOP, r2, #0

	// Reset the sleep timer
	RESET_COUNTER

	// Zero out the start command so that they know we have received it
	// This allows maximum speed frame drawing since they know that they
	// can now swap the frame buffer pointer and write a new start command.
	MOV r3, 0
	SBCO r3, CONST_PRUDRAM, 8, 4

	// Command of 0xFF is the signal to exit
	QBEQ EXIT, r2, #0xFF

l_word_loop:
	// for bit in 32 to 0
	MOV r_bit_num, 32

	l_bit_loop:
		DECREMENT r_bit_num

		// Load 6 registers of data, starting at r10
		LOAD_CHANNEL_DATA(6, 0, 6)

		WAITNS 500, wait_one_time
		// Clear previous output
		XOR r30, r30, r30

		// Zero out the ones registers
		RESET_GPIO_ONES()

		// Test the channel data and compute the value of the ones register
		TEST_BIT_ONE_NREMAP(r_data0,  0)
		TEST_BIT_ONE_NREMAP(r_data1,  1)
		TEST_BIT_ONE_NREMAP(r_data2,  2)
		TEST_BIT_ONE_NREMAP(r_data3,  3)
		TEST_BIT_ONE_NREMAP(r_data4,  4)
		TEST_BIT_ONE_NREMAP(r_data5,  5)

		// Wait until the end of the frame (including the time it takes to reset the counter)
		WAITNS 1150, wait_frame_spacing_time
		CHECK_TIMEOUT
		RESET_COUNTER

		// Send all the start bits
		GPIO_APPLY_MASK_TO_OUTREG()

		WAITNS 350, wait_zero_time
		CHECK_TIMEOUT

		// Lower the zero bit lines
		GPIO_APPLY_ONES_TO_OUTREG()

		// The one bits are lowered in the next iteration of the loop
		QBNE l_bit_loop, r_bit_num, 0

	// The RGB streams have been clocked out
	// Move to the next pixel on each row
	ADD r_data_addr, r_data_addr, 48 * 4
	DECREMENT r_data_len
	QBNE l_word_loop, r_data_len, #0

FRAME_DONE:

	WAITNS 1200, end_of_frame_clear_wait
	XOR r30, r30, r30

	// Delay at least 50 usec; this is the required reset
	// time for the LED strip to update with the new pixels.
	SLEEPNS 50000, 1, reset_time

	// Write out that we are done!
	// Store a non-zero response in the buffer so that they know that we are done
	// aso a quick hack, we write the counter so that we know how
	// long it took to write out.
	MOV r8, PRU_CONTROL_ADDRESS // control register
	LBBO r2, r8, 0xC, 4
	SBCO r2, CONST_PRUDRAM, 12, 4

	// Go back to waiting for the next frame buffer
	QBA _LOOP

EXIT:
	// Write a 0xFF into the response field so that they know we're done
	MOV r2, #0xFF
	SBCO r2, CONST_PRUDRAM, 12, 4

	RAISE_ARM_INTERRUPT

	HALT

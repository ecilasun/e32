# E32

E32 is a minimal RISC-V SoC implementation which contains:
- A single RV32IZicsr HART
- An internal UART fixed at 115200 bauds
- 64 Kbytes of block RAM

The project is built using an Arty A7-100T board but is small enough to fit onto any smaller board.

The CPU takes 5 stages to execute most instruction, with the exception of LOAD and WFI instructions, which have additional wait stages. At 100Mhz, this yields a peak of 20MIPS and an average of 16.67MIPS depending on memory read patterns.

## State machine flow
The stages will always follow the following sequence from startup time, where the curly braces is the looping part, and Reset happens once:

```
Initialization: 2 clocks
Reset -> { Retire -> ... }

LOAD instruction: 6 clocks
{ Fetch -> Decode -> Execute -> LoadWait -> Writeback -> Retire -> ... }

WFI instruction: 6 clocks
{ Fetch -> Decode -> Execute -> InterruptWait -> Writeback -> Retire -> ... }

All other instructions: 5 clocks
{ Fetch -> Decode -> Execute -> Writeback -> Retire -> ... }
```

## Fetch Stage
This stage is an instruction load wait slot, and caches internal CSR register representations to be used on later stages, such as interrupt enable flags.

## Decode Stage
This stage will latch the read word from memory to instruction register, and enable the instruction decoder so that we have something to process on the execute stage. After this stage, on next clock, the instruction parts will be available for use, including the values read from the register file for source registers 1 and 2.

## Execute Stage
This stage handles bus read request for LOAD and memory address generation for LOAD/STORE instructions. It will also turn on the ALU for the writeback stage, where the aluout result is used, and pipelines the result of the branch decision output from the BLU. In addition, it caches the CSR value from currently selected CSR register for later modification, and detects ecall/ebreak/wfi/mret instructions.

## Load Wait Stage
This stage is the data load delay slot. Since the writeback stage needs the data from memory to pass into a register, we need to wait here for loads to complete. It's also a placeholder stage for future, delayed devices where loads do not complete in a single clock cycle.

## Interrupt Wait Stage
This stage is entered only when the WFI instruction is executed, to serve as a sleep/wait for interrupt stage. On any external hardware interrupt or timer interrupt, this stage will resume execution of the HART. One exception is the software illegal instruction interrupts which will be ignored, since obviously the HART is already asleep and can't be producing those.

## Writeback Stage
This stage handles the write enable mask generation for the STORE instruction, and will set up the writeback value to the register file based on instruction type, for both the integer register file and the CSRs. The next instruction pointer is calculated here as well, including handling of traps and branches. This stage will handle mret by clearing the currently handled interrupt pending bit to allow further traps of the same type execute.

## Retire Stage
This stage generates the bus address and enable signal for instruction load, and sets up the mip/mepc/mtval/mcause registers for any hardware or software interrupt detected during this instruction.

# Default ROM behavior

After the board is programmed with this SoC's bin or bit file, you can connect to the Arty board using a terminal program such as PuTTY. By default, the Arty board serial device comes up on the device list as COM4 (on USB). Set your terminal program to use 115200 baud / 1 stop bit / no parity and you should be able to see messages displayed by the board.

The default ROM image that ships with this SoC will display startup message when the reset button is pressed (if the SoC image is in the persistent memory), or when programmed in dynamic mode. The ROM code will then sit at a WFI instruction, waiting for any external interrupts to be triggered. The interrupt handler, upon receiving a UART input or a timer interrupt, will execute the proper action (trap and echo back any character sent to it or show the one-time timer test message). During this process, if at any time an uppercase 'c' character (C) is caught, the main loop is alerted via a volatile which will in turn trigger a deliberate illegal instruction exception, which is also handled by the same interrupt service routine. In this case a detailed exception message will be displayed and the HART will be put to sleep via an infinite loop around a WFI instruction, from which a single HART can't escape until reset or reprogram.

One could modify this behavior to for example load programs from an SDCard (or over USB) and run them, or simply act as a dummy device responding to simple UART commands. It's left up to the user to decide how to use or extend this design.

# Changing the ROM image

To use a different ROM image, you'll need to head over to https://github.com/ecilasun/riscvtool and sync the depot.
After that, you'll need to install the RISC-V toolchain (as instructed in the README.md file).
Once you have a working RISC-V toolchain, you can then go to e32/ROMs/ directory in the project root, make changes to the ROM.cpp file, type 'make' and you'll have a .coe file generated for you. You can then replace the contents of the ROM.coe file found in the source/ip folder with the contents of this file. Once that is done, you'll need to remove the generated files for the block RAM 'SRAMBOOTRAMDevice' in the project by right clicking and selecting 'Reset Output Products'. Next step is to synthesize/implement the design which will now have your own ROM image embedded in it.

Note that this SoC doesn't support loading programs from an external source as-is, since it's made for static devices which will do only one thing. Therefore, you'll need to place the programs onto the 'ROM' area, which will have to fit into the 64K RAM region.

The memory addresses for the ROM (which is also your RAM) start from 0x10000000 and reach up to 0x1000FFFF, which are hard-coded. You could expand the address range by using more block ram and increasing the bit counts fed to the block ram (S-RAM) device in the design. This would also require changes to the linker script to adjust the 'max size' of your programs, and a few more changes to the rvcrt0.h file in the ROMs directory to move the stack pointer accordingly.

The default stack address is set to 0x1000FFF0 by the startup code in rvcrt0.h file in the ROMs directory, and the default heap_start/heap_end are set to 0x00008000 and 0x0000F000 respectively, which live in the core.cpp file in the SDK directory.

# About the UART / UART FIFO

The SoC uses the built-in USB/UART pins to communicate with the outside world. The problem here is that there are only two pins exposed to the FPGA (TX/RX) and no flow control pins are taken into account. Therefore, the device will currently simply drop the incoming data if the input FIFO is full, as it doesn't have any means to stop the data flow from sender. However, future ROM versions will implement XON/XOFF flow control so that the software layer might tell the remote device to stop before the FIFO is filled up.

# CSR registers

E32 currently has a minimal set of CSR registers supported to do basic exception / interrupt / timer handling, and only machine level versions.
The 15 CSR registers currently in the design (all read/write access for now) are:

```
MSTATUS : Machine status
MIE : Machine interrupt enable
MTVEC : Machine trap vector
MEPC : Machine return program counter
MCAUSE : Machine cause (cause of trap)
MTVAL : Machine trap value (exception specific information)
MIP : Machine interrupt pending
CYCLELO / CYCLEHI : HART cycle counter
RETILO / RETIHI : HART retired instruction counter 
TIMELO / TIMEHI : Wall clock timer
TIMECMPLO / TIMECMPHI : Time compare value against wall clock timer (custom CSR register)
```

# TODO

- Expose FPGA pins connected to the GPIO / PMOD / LED / BUTTON peripherals as memory mapped devices.
- Work on a bus arbiter to support more than one HART (ideally one director and several worker harts)
- Add back the simple GPU design

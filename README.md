# E32

E32 is a minimal RISC-V SoC implementation which contains:
- A single RV32IZicsr HART
- An internal UART fixed at 115200 bauds
- 64 Kbytes of block RAM

The project is built using an Arty A7-100T board but is small enough to fit onto any smaller board.

The CPU consists of only 5 stages in this SoC, apart from the initial Reset stage. Note that at the beginning of every stage, register writes, bus writes, bus reads, instruction decoder and ALU are all turned off, to be turned on for only the stages they're required in. This ensures a well balanced device with all possible paths taken for all driven registers. This excludes the 'dout' register, as the data has to be held and not change in case of a bus stall.

## Fetch Stage
This stage is an instruction load wait slot, and is reserved space for future CSR loads to internal registers such as timecmp.

## Decode Stage
This stage will latch the read word from memory to instruction register, and enable the instruction decoder so that we have something to process on the execute stage. After this stage, on next clock, the instruction will be available as individual, decoded segments.

## Execute Stage
This stage handles bus read request for LOAD and memory address generation for LOAD/STORE instructions. This stage will turn on the ALU for the writeback stage, where the aluout result is used, and also pipelines the result of the branch decision output from the BLU.

## Writeback Stage
This stage handles the write enable mask generation for the STORE instruction, and will set up the writeback value to the register file based on instruction type. This is also the wait stage for any LOAD instruction started in the execute stage. The instruction pointer is calculated here as well.

## Retire Stage
This stage generates the bus address for next instruction, enables register writes for any pending writes, and will handle the masking/sign extension of register output value from previous started LOAD instruction.

The stages will always follow the following sequence from startup time, where the curly braces is the looping part, and Reset happens once:

Reset ->{ Retire -> Fetch -> Decode -> Execute -> Writeback -> Retire -> Fetch -> Execute -> Writeback -> ... }

# Default ROM image

To use a different ROM image, you'll need to head over to https://github.com/ecilasun/riscvtool and sync the depot.
After that, you'll need to install the RISC-V toolchain (as instructed in the README.md file).
Once you have a working RISC-V toolchain, you can then go to e32/ROMs/ directory in the project root, make changes to the ROM.cpp file, type 'make' and you'll have a .coe file generated for you. You can then replace the contents of the ROM.coe file found in the source/ip folder with the contents of this file. Once that is done, you'll need to remove the generated files for the block RAM 'SRAMBOOTRAMDevice' in the project by right clicking and selecting 'Reset Output Products'. Next step is to synthesize/implement the design which will now have your own ROM image embedded in it.

Note that this SoC doesn't support loading programs from an external source as-is, since it's made for static devices which will do only one thing. Therefore, you'll need to place the programs onto the 'ROM' area, which will have to fit into the 64K RAM region.

The memory addresses for the ROM (which is also your RAM) start from 0x10000000 and reach up to 0x1000FFFF, which are hard-coded. You could expand the address range by using more block ram and increasing the bit counts fed to the block ram (S-RAM) device in the design. This would also require changes to the linker script to adjust the 'max size' of your programs, and a few more changes to the rvcrt0.h file in the ROMs directory to move the stack pointer accordingly.

The default stack address is set to 0x1000FFF0 by the startup code in rvcrt0.h file in the ROMs directory, and the default heap_start/heap_end are set to 0x00008000 and 0x0000F000 respectively, which live in the core.cpp file in the SDK directory.

# Default ROM behavior

After the board is programmed with this SoC's bin or bit file, you can connect to the Arty board using a terminal program such as PuTTY. By default, the Arty board serial device comes up on the device list as COM4 (on USB). Set your terminal program to use 115200 baud / 1 stop bit / no parity and you should be able to see messages displayed by the board.

The default ROM image that ships with this SoC will display a copyright message when the reset button is pressed (if the SoC image is in the persistent memory). The ROM code will then sit in an infinite loop, and echo back any character sent to it.

One could modify this behavior to either accept external programs from an SDCard or over USB and run them, or simply act as a dummy terminal device running simple commands.

# About the UART

The SoC uses the built-in USB/UART pins to communicate with the outside world. The problem here is that there are only two pins exposed to the FPGA (TX/RX) and no flow control pins are taken into account. Therefore, the device will currently simply drop the incoming data if the input FIFO is full, as it doesn't have any means to stop the data flow from sender. However, future ROM versions might implement XON/XOFF flow control so that the software layer might tell the remote device to slow down before the FIFO is filled up, though this will be very tricky to do with a very small FIFO as used on the current system, which has only 512 entries.

Other means of optimizing this are available, both on hardware and software side, but these solutions will add more hardware and the design goal of this SoC is to be initially be as small as possible.

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

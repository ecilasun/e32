# E32

E32 is a minimal RISC-V SoC implementation which contains:
- A single RV32I core
- An internal UART fixed at 115200 bauds
- 64 Kbytes of block RAM

The project is built using an Arty A7-100T board but is small enough to fit onto any smaller board.

The CPU consists of only 4 stages in this SoC, apart from the initial Reset stage. Note that at the beginning of every stage, register writes, bus writes, bus reads, data out, instruction decoder and ALU are all turned off, to be turned on for only the stages they're required in.

## Fetch Stage
This stage is an instruction load wait slot, and is reserved space for handling interrupt triggers. It will also enable the instruction decoder so that we have something to process on the execute stage.

## Execute Stage
This is where the next instruction pointer is calculated. It also handles bus read request / address are generated for LOAD and STORE instructions. This stage will turn on the ALU for the writeback stage, where the aluout result is used.

## Writeback Stage
This stage handles the write enable mask generation for the STORE instruction, and will set up the writeback value to the register file based on instruction type. This is also the wait stage for any LOAD instruction started in the execute stage.

## Retire Stage
This stage generates the bus address for next instruction, enables register writes for any pending writes, and will handle the masking/sign extension of register output value from previous started LOAD instruction.

The stages will always follow the following sequence from startup time, where the curly braces is the looping part, and Reset happens once:

Reset ->{ Retire -> Fetch -> Execute -> Writeback -> Retire -> Fetch -> Execute -> Writeback -> ... }

# ROM

To use a different ROM image, you'll need to head over to https://github.com/ecilasun/riscvtool and sync the depot.
After that, you'll need to install the RISC-V toolchain (as instructed in the README.md file).
Once you have a working RISC-V toolchain, you can then go to e32/ROMs/ directory in the project root, make changes to the ROM.cpp file, type 'make' and you'll have a .coe file generated for you. You can then replace the contents of the ROM.coe file found in the source/ip folder with the contents of this file. Once that is done, you'll need to remove the generated files for the block RAM in the project, and synthesize/implement the design which will now have your own ROM image embedded in it.

Note that this SoC doesn't support loading programs from an external source as-is, since it's made for static devices which will do only one thing. Therefore, you'll need to place the programs onto the 'ROM' area, which will have to fit into the 64K RAM region.

The memory addresses for the ROM (which is also your RAM) start from 0x10000000 and reach up to 0x1000FFFF, which are hard-coded. You could expand the address range by using more block ram and increasing the bit counts fed to the block ram (S-RAM) device in the design. This would also require changes to the linker script to adjust the 'max size' of your programs, and a few more changes to the rvcrt0.h file in the ROMs directory to move the stack pointer accordingly.

The default stack address is set to 0x1000FFF0 by the startup code in rvcrt0.h file in the ROMs directory, and the default heap_start/heap_end are set to 0x00008000 and 0x0000F000 respectively, which live in the core.cpp file in the SDK directory.

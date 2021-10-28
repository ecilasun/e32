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

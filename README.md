# MOS-6502

This is my personal project implementing a cycle-oriented MOS 6502 CPU core written in Verilog. This repo includes a self-checking testbench built around the classic NES **nestest** program. The CPU was tested using behavioral simulation and exposes a simple memory bus plus IRQ/NMI support. It has been implemented on hardware to run games on the NES(Sipeed Tang Nano 9K FPGA Dev Board, used peripherals from https://github.com/sipeed/TangNano-20K-example), but other applications like Apple II and Atari 2600 are possible. 

<img width="1676" height="802" alt="image" src="https://github.com/user-attachments/assets/535933af-6ce1-4e0a-96d9-168e6db037e2" />


## Features
- Implements 100% of documented 6502 opcodes, binary arithmetic only
- 100% byte and cycle accurate cycles, per the 6502 datasheet
- Opcodes selected through instructions in mem file.

## To implement
- Decimal mode is not implemented; ADC/SBC run in binary.
- Only official opcodes are supported (undocumented instructions and known hardawre glitches are not implemented).
- Bus interface is single-cycle with no wait-state insertion; integrate with synchronous memory or add external wait logic if needed.

## Program Files
- [cpu.v](cpu.v) — 6502 core
- [tb.v](tb.v) — testbench that loads the nestest program into  RAM and checks every instruction against the expected log.
- [nestest_instructions.mem](nestest_instructions.mem) — hex image of the nestest program
- [nestest_verification.mem](nestest_verification.mem) — expected CPU state per instruction (A, X, Y, P, SP, CYC) used by the self-checking testbench.

## License
Released under the MIT License. See [LICENSE](LICENSE).

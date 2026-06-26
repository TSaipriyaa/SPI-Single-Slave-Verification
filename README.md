# SPI-Single-Slave-Verification
SystemVerilog-based verification of an SPI Master communicating with a single SPI Slave using a self-checking testbench and SystemVerilog Assertions (SVA).

# SPI Single Slave Verification using SystemVerilog

## Overview

This project implements and verifies a configurable SPI (Serial Peripheral Interface) Master communicating with a single SPI Slave using SystemVerilog. The SPI Master supports all four standard SPI modes through configurable Clock Polarity (CPOL) and Clock Phase (CPHA), along with selectable clock division for different SPI frequencies.

A self-checking verification environment is developed using a behavioral SPI slave model, automatic result checking, and SystemVerilog Assertions (SVA) to validate correct protocol operation under multiple test scenarios.

---

## Features

### SPI Master
- Configurable data width (default: 8 bits)
- Supports all four SPI modes
  - Mode 0 (CPOL=0, CPHA=0)
  - Mode 1 (CPOL=0, CPHA=1)
  - Mode 2 (CPOL=1, CPHA=0)
  - Mode 3 (CPOL=1, CPHA=1)
- Programmable SPI clock divider
  - System Clock ÷2
  - System Clock ÷4
  - System Clock ÷8
  - System Clock ÷16
- Finite State Machine based implementation
  - IDLE
  - LOAD
  - TRANSFER
  - DONE
- Registered SPI clock generation
- Full-duplex SPI communication
- Configurable transmit and receive data paths

---

## Verification Features

- Self-checking testbench
- Behavioral SPI Slave model
- Automatic PASS/FAIL reporting
- SystemVerilog Assertions (SVA)
- Functional verification of all SPI modes
- Multiple clock divider verification
- Timeout detection
- Bidirectional data integrity checking

---

## Project Structure

```
SPI-Single-Slave-Verification
│
├── spi_master_cfg.sv          # SPI Master RTL
├── spi_master_cfg_tb.sv       # Self-checking Testbench
├── README.md
```

---

## Verification Methodology

The verification environment consists of:

- Configurable SPI Master (DUT)
- Behavioral SPI Slave Model
- Clock Generator
- Reset Generator
- Self-checking scoreboard logic
- SystemVerilog Assertions
- Automated test execution

The testbench automatically compares:

- Data received by the master
- Data received by the slave

against the expected values and reports PASS or FAIL without manual waveform inspection.

---

## Test Coverage

The project verifies:

 Reset functionality
 SPI Mode 0
 SPI Mode 1
 SPI Mode 2
 SPI Mode 3
 Clock Divider (/2)
 Clock Divider (/4)
 Clock Divider (/8)
 Clock Divider (/16)
 Master-to-Slave data transfer
 Slave-to-Master data transfer
 Simultaneous full-duplex communication
 DONE signal generation
 Busy signal behavior
 Chip Select (SS) operation
 SCK idle polarity
 Timeout handling

---

## SystemVerilog Assertions

The verification environment includes assertions for protocol correctness, including:

- DONE signal must be a single-cycle pulse.
- Slave Select (SS) remains active during data transfer.
- SPI Clock returns to the configured idle polarity when idle.

These assertions help detect protocol violations automatically during simulation.

---

## Test Cases

The project executes sixteen verification test cases covering:

- Four SPI Modes
- Four Clock Divider settings
- Various transmit and receive data patterns

Each test automatically verifies:

- Master received data
- Slave received data
- Protocol correctness
- PASS/FAIL status

---

## Simulation Output

The simulation generates:

- PASS/FAIL report for every test case
- Overall verification summary
- VCD waveform file (`spi_master_cfg.vcd`) for waveform analysis

---

## Tools Used

- SystemVerilog
- ModelSim / QuestaSim
- GTKWave (for VCD waveform viewing)

---

## Learning Outcomes

This project demonstrates:

- SPI protocol implementation
- Finite State Machine design
- Configurable serial communication
- Self-checking verification methodology
- Behavioral modeling
- SystemVerilog Assertions (SVA)
- Functional verification techniques

---

## Future Enhancements

- Support for multiple SPI slaves
- Functional Coverage
- Constrained Random Verification
- UVM-based verification environment
- Coverage-driven verification
- Parameterizable frame sizes

---

## Author

**Saipriyaa Thiagarajan**

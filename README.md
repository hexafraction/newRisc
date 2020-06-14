# NewRISC: a Really Insecure Speculative Computer

NewRISC is a personal project of mine, where I aim to create a 32-bit processor with an unusual design goal: **an environment to easily explore side-channel and microarchitectural sampling exploits**. 

In the initial revision, the design will be targeted toward enabling a variety of attacks via memory caches. The design is extensible to allow multicore operation, as well as simple privilege levels (i.e. user/supervisor mode) in the future.

## The core

The processor has a pipelined core capable of issuing one instruction per cycle, and retiring two writes per cycle. One of each execution unit is planned:

 - 32-bit ALU
     - Branch operations use ALU flags and are executed as an extension of the ALU pipe.
 - Wide-function unit (shifts and multiplies)
 - Memory unit (loads, stores, exchanges)
 - SFR unit (handles reads and writes to my equivalent of model-specific and special-function registers)
 - Address generator (calculates `base + stride * offset`)
 - Deliberate pipeline delay unit (used to make speculative execution attacks easier)
 
In order to speed development, the ALU and memory unit will be developed first, and the remaining functional units will be developed at the end. 

Serializing instructions and a timestamp counter will be available.



### Registers

The processor provides sixteen general purpose architectural registers, backed by 32 physical registers. Through a simple form of register renaming, each architectural register can be backed by one of its two corresponding physical registers.

The register file is banked; on each cycle, one odd register (i.e. r1, r3, ...) and one even register may be written.

On a branch misprediction, the register mapping is rolled back to preserve architectural state. 

### Writeback (subject to change)

As mentioned above, one register can be written back per bank, per clock cycle (i.e. one even and one odd register per cycle). There are two writeback queues, one for each bank, holding up to two pending writebacks. When executing speculatively, the queues may fill while waiting for the branch to resolve; they subsequently empty since banks are not utilized at 100% in typical programs.

### Speculative execution

For simplicity, only one branch instruction may be in the pipeline at any time. Once it enters the pipeline, all following instructions are marked as speculative: they will not be allowed to reach the writeback phase until the branch resolves successfully, and must wait in the writeback queues. However, register values *will* be forwarded to speculative instructions being issued.

Non-architectural side effects will remain in place on mispredictions. At present, this includes only effects on the L1D and L2 unified caches.

> "Nooo! you can't just update microarchitectural state on a speculated instruction!"
> 
> "Haha, cache line fill go brrrrrrrrrrr"

### Delay unit

To assist in constructing deep speculative paths, there will be a "pipeline delay" unit. This unit can be used to create a slow dependency for a conditional branch:

```
SLOWMOV r7, r8;
CMP r7, r5;
BEQ someLabel;
... instructions to be executed speculatively follow here 
```

The CMP enters the pipeline with pending operands, and remains for a long time while the SLOWMOV resolves. Note that the speculative instructions which follow cannot include ALU ops, since they would stall until just before the branch clears.

# Memory hierarchy

 - 4 KiB L1i cache, one per core, simple prefetching, custom design.
 - 4 KiB L1d cache, one per core. Write-through policy; reads can be forced to fill from main memory even if cache line is available. Custom design.
 - 32 KiB unified L2 cache, shared between cores, off-the-shelf Xilinx IP.
 - No coherency between L1i and L1d, or between L1 caches on different cores
     - Volatile reads must force L1 cache bypass (writes always bypass)
 - DRAM accessed via Zynq PS's HP AXI port
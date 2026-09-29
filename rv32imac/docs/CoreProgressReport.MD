# Building a RISC-V CPU: Report

---

## Part 1: What Are We Even Building?

Imagine a very fast, very obedient robot that can only do a small list of chores. It can:
- Add two numbers
- Put a number in a box (memory)
- Take a number out of a box
- Decide "if this is true, skip the next chore(s)"

That's basically what a CPU is. It's a machine that reads a list of tiny instructions and does them, one after another, millions of times per second.

**RISC-V** (said "risk five") is the list of instructions. It's a *standard*, like how "USB" is a standard for plugs. Anyone can build a USB device that plugs into any USB port. Same for RISC-V: anyone can build a CPU that runs any RISC-V program.

**RV32IMAC** is the exact flavour of RISC-V we built. It's a code:
- **RV32** — 32-bit (the numbers are 32 bits wide, from 0 to about 4 billion)
- **I** — the basic set of instructions (the "integer" ones)
- **M** — extra instructions for multiplying and dividing
- **A** — extra instructions for doing things atomically (important for multiple CPUs sharing memory)
- **C** — "compressed" instructions, which are short versions of common instructions to save space

Our CPU runs programs written in RV32IMAC. That's the goal.

---

## Part 2: Choosing Our Tools (The Workshop)

Before building anything, we needed a workbench. Here's what we chose and why.

### The Editor: VSCode + a Verilog plugin

**What it is:** A program for typing code.

**Why this one:** VSCode is free, works on every operating system, and has an enormous library of extensions. The Verilog extension gives us:
- Colour-coded syntax (so keywords pop out)
- Auto-complete for module ports
- Inline error highlighting before we even compile
- Jump-to-definition across files (crucial once you have 20 files)

**Analogy:** VSCode is like a really good notebook. It doesn't do the work for you, but it makes writing and rereading much easier.

### The Simulator: Icarus Verilog (iverilog)

**What it is:** A program that reads your Verilog code and *pretends* to run it, showing you what would happen if you built the circuit for real.

**Why this one:**
- **Free and open source.**
- **Fast enough** for small-to-medium designs. Our core simulates in a few milliseconds per test.
- **No licence** needed — some commercial simulators cost tens of thousands of pounds.

**What it can't do:**
- Timing analysis. It tells you *what* signals do, not how fast the circuit can run.
- Very large designs. Once you have a multicore with caches and coherency, you'll want something faster.

**Analogy:** iverilog is like a flight simulator. You can practice take-off and landing without actually flying a plane. When you're ready, you move to real hardware.

### The Waveform Viewer: GTKWave

**What it is:** A program that draws a picture of what every signal in your design was doing, cycle by cycle.

**Why this one:**
- **Pairs with iverilog.** Iverilog writes a `wave.vcd` file; GTKWave reads it.
- **Free, cross-platform.**

**How we use it:** every testbench ends with two lines:

```verilog
$dumpfile("wave.vcd");
$dumpvars(0, tb_mymodule);
```

`$dumpvars(0, ...)` means "record every signal in this module and all its children, at every clock edge." Then we open the file in GTKWave and can scroll backwards through the exact cycle where something broke.

**Analogy:** if iverilog is a flight simulator, GTKWave is the flight recorder — the little black box that shows what every instrument was reading in the moments before things went wrong.

### Best practice summary for the toolchain

| Aspect | Best practice | Personal spin |
|---|---|---|
| Editor | Any syntax-aware editor | VSCode vs Vim is taste |
| Simulator | Free, open source, standards-compliant | iverilog for small designs; Reassess when you scale up |
| Waveform | VCD-compatible viewer | GTKWave is the standard default |
| Version control | Git | You should use some form of it |

---

## Part 3: Specification: Deciding *What* to Build

Before writing a single line of code, we wrote down what we wanted. This is the *specification*.

### The Big Decisions

**1. Which instructions?**

We chose RV32IMAC + Zicsr + Zifencei. In plain English:
- I: the basic integer instructions
- M: multiply/divide
- A: atomics
- C: compressed
- Zicsr: read/write control registers (needed to run Linux)
- Zifencei: instruction-cache flush

**Why not fewer?** We wanted to eventually run Linux. Linux needs M, A, and the control-register machinery. Skipping them would mean re-doing the architecture later. Better to spec them now.

**Why not more?** We deliberately skipped:
- **F/D** — floating point. Adds a whole register file and 100+ instructions. Not needed for our first goal.
- **RV64** — 64-bit. Doubles every wire in the design. RV32 is easier to get right first.
- **Hypervisor extension** — nobody needs this on an FPGA.

**2. What privilege levels?**

M-mode (Machine), S-mode (Supervisor), U-mode (User).

**Analogy:** think of a company. U-mode is a regular employee, can only do their own job. S-mode is a manager, can set up how the department runs. M-mode is the CEO, can do anything, including things managers aren't allowed to touch. This layering is what makes operating systems possible: the OS runs in S-mode, user programs run in U-mode, and only M-mode can change the deepest settings.

**3. What memory layout?**

We adopted the standard RISC-V memory map:

| Address | Device |
|---|---|
| `0x0000_1000` | Boot ROM |
| `0x0200_0000` | CLINT (timer + inter-core interrupts) |
| `0x0C00_0000` | PLIC (external interrupts) |
| `0x1000_0000` | UART |
| `0x8000_0000` | Main RAM |

**Why these exact numbers?** Because Linux and existing RISC-V software expect them. If you invent your own memory map, you have to patch every bootloader and kernel you use.

**4. What performance target?**

Not measured in megahertz yet. Instead, we specified a *structural* target: a classic 5-stage pipeline. This is the minimum for a "real" CPU (a microcontroller core can do 2 stages; a desktop CPU does 15+).

### Best practice summary for specification

| Aspect | Best practice | Personal spin |
|---|---|---|
| ISA choice | Spec for the eventual goal, not the minimum | We chose Linux-capable; a hobbyist might choose bare-metal RV32I |
| Privilege | Include all levels you'll ever need | Could have done M-only; we did M+S+U |
| Memory map | Follow the standard | Non-negotiable if you want to reuse software |
| Performance | Structural targets, not clock targets | "5-stage" more actionable than "50 MHz" |

**The one rule:** write the spec *before* the RTL. Changing a spec later means changing every module. Changing RTL before the spec is even set means rewriting everything.

---

## Part 4: Architecture: Deciding *How* to Build It

### The 5-Stage Pipeline

Think of a factory assembly line. Each station does one small job, then passes the item to the next station. Every station works on a *different* item at the same time. That's how you get throughput.

Our factory has five stations:

```
     ┌────┐   ┌────┐   ┌────┐   ┌─────┐   ┌────┐
PC──▶│ IF │──▶│ ID │──▶│ EX │──▶│ MEM │──▶│ WB │──▶ Regfile
     └────┘   └────┘   └────┘   └─────┘   └────┘
```

- **IF (Instruction Fetch):** go get the next instruction from memory.
- **ID (Instruction Decode):** figure out what the instruction means and read its inputs.
- **EX (Execute):** do the math (add, subtract, compare).
- **MEM (Memory):** for load/store instructions, talk to memory.
- **WB (Write Back):** save the result into a register.

**Analogy:** at any moment, one instruction is being fetched, the previous one is being decoded, another is being executed, and so on. When the pipeline is full, five instructions are being worked on at once.

### The Pipeline Registers

Between each station we put a small storage box (a "pipeline register"). At the end of every clock tick, each station drops its result into the box for the next station.

- `if_id` — between IF and ID
- `id_ex` — between ID and EX
- `ex_mem` — between EX and MEM
- `mem_wb` — between MEM and WB

**Why not just combinational logic?** Because then the whole design would be one giant chain of logic, and the clock period would be limited by the longest path. By splitting into stages, each stage's path is short, and the clock can tick faster.

### Hazards, and How We Handle Them

Real programs have nasty cases where the neat assembly line falls apart. These are called *hazards*.

**Hazard 1: Load-use.** Imagine you're decoding an instruction that wants the value `x4`, but `x4` is being loaded *right now* by the instruction one step ahead of you. The load hasn't finished,  the value isn't ready. We must **stall** (pause the pipeline for one cycle) and wait.

**Hazard 2: Data forwarding.** Suppose the previous instruction computed `x1 = x2 + x3`. If the next instruction needs `x1`, it doesn't have to wait for the result to be written back to the register file  we can *forward* it directly from where it was computed. Saves a stall.

**Hazard 3: Branches.** If the previous instruction is `beq x1, x2, label`, we don't know until EX whether to jump. The instructions we fetched in IF and ID might be wrong. We **flush** them (replace with harmless NOPs) and start fetching from the correct address.

**Hazard 4: Read-during-write.** We found this one the hard way (see Part 6). If an instruction reads `x4` at the exact same cycle the WB stage is writing `x4`, does it get the old value or the new one? Answer: **the new one**. This requires a small bypass in the register file.

### The Module Layout

We split the design into small, single-purpose files:

```
rtl/
  riscv_defs.vh              — shared constants (opcodes, CSR addresses, ...)
  core/
    alu.v                    — arithmetic/logic
    decoder.v                — "what does this instruction mean?"
    regfile.v                — the registers
    csr_file.v               — control/status registers
    branch_unit.v            — "should I take this branch?"
    muldiv.v                 — multiply/divide
    amo_unit.v               — atomics
    rvc_expand.v             — decompress compressed instructions
    forward_unit.v           — operand forwarding
    hazard_unit.v            — stall/flush decisions
    if_id.v / id_ex.v / ex_mem.v / mem_wb.v   — pipeline registers
    if_stage.v / id_stage.v / ex_stage.v / mem_stage.v / wb_stage.v
    riscv_core.v             — top-level integration
```

**Why one file per module?** Because:
1. You can test each module in isolation (see Part 5).
2. You can find things. `alu.v` is the ALU. `decoder.v` is the decoder. No mysteries.
3. Synthesis tools can prune unused logic better when the hierarchy is clean.

**Best practice vs personal spin:**
- *Best practice:* one module per file, file name equals module name. Standard across every HDL project.
- *Personal spin:* the specific split (e.g., "should `muldiv` be inside `ex_stage` or separate?") is a judgment call.

### Coding Standard

We froze a small set of rules at the start:

1. **Verilog-2001 only.** Verilog-2001 is universally portable.
2. **Synchronous active-low reset (`rst_n`).** Every flip-flop resets on the same signal at the same clock edge. Async resets are used in some designs; we chose synchronous for simplicity.
3. **No latches.** Every combinational `always @(*)` assigns every output on every path. Prevents accidental latches.
4. **No magic numbers.** Everything comes from `riscv_defs.vh`. If `OP_LOAD` means `7'b0000011`, it's written once, in one place.
5. **Header comment on every module** describing its job, ports, latency, and reset behavior.
6. **`default` in every `case` statement.** A missing default is a latch waiting to happen.

**Best practice vs personal spin:**

| Rule | Verdict |
|---|---|
| Verilog-2001 only | Best practice for portability |
| Sync reset | Both sync and async are legitimate; async is faster, sync is simpler |
| No latches | Non-negotiable |
| No magic numbers | Non-negotiable for anything over 100 lines |
| Header comments | Best practice, occasionally skipped but you always regret it |
| `default` in `case` | Non-negotiable |

---

## Part 5: Verification: Proving It Works

Writing RTL is easy. Writing RTL that *actually works* is hard.

### The Golden Rule: A Testbench for Every Module

For every file we wrote (`alu.v`, `decoder.v`, `regfile.v`, and so on ) we wrote a matching testbench: `tb_alu.v`, `tb_decoder.v`, `tb_regfile.v`.

**What is a testbench?** It's a wrapper module that:
1. Instantiates the module-under-test
2. Drives its inputs with known values
3. Checks that its outputs match what we expect
4. Prints "PASS" or "FAIL" and exits

Testbenches are *not* synthesizable. They're pure simulation. They exist only to catch bugs.

### Self-Checking

Every testbench we wrote follows the same pattern:

```verilog
tests_run = tests_run + 1;
if (got !== expected) begin
    $display("FAIL [%0s] got=%h exp=%h", label, got, expected);
    errors = errors + 1;
end
```

**Why `!==` and not `!=`?** Because `!==` treats X (unknown) and Z (high-impedance) as different from any defined value. If a signal goes X due to a bug, `!=` might accidentally pass; `!==` will fail.

**Why self-checking?** Because a testbench that just prints values and lets a human eyeball them doesn't scale. Once you have 500 tests, you need the testbench to tell you *automatically* if anything is wrong. `$display("TEST PASSED: tb_alu")` or `$display("TEST FAILED: ...")` is the standard convention.

### Directed + Randomized

Every testbench contains two kinds of tests:

**Directed tests** — hand-picked cases that target known corner cases:
- `ADD 0 + 0 = 0`
- `ADD 0xFFFFFFFF + 1 = 0` (overflow wraps)
- `SRA 0x80000000 >> 1 = 0xC0000000` (arithmetic shift keeps sign)

**Randomized tests** — thousands of random values run against a reference model:
```verilog
for (k = 0; k < NUM_RANDOM; k = k + 1) begin
    rand_a = $urandom;
    rand_b = $urandom;
    rand_op = $urandom_range(0, 11);
    check(rand_a, rand_b, rand_op, "RAND");
end
```

**Why both?** Directed tests catch the things you already know are tricky. Randomized tests catch the things you didn't think of. Together they give much better coverage than either alone.

### Deterministic Randomness

We always seed the random generator:

```verilog
rng_seed = SEED;
rng_dummy = $urandom(rng_seed);
```

**Why?** So a failing test can be reproduced. If you get a failure with seed `0xDEADBEEF` on Tuesday, running with the same seed on Wednesday gives the same failure. This is *essential* for debugging.

**Icarus gotcha:** `$urandom` needs an integer variable as its seed. Passing a `localparam` fails. We learned this the hard way.

### Coverage

Every testbench tracks which cases it ran:

```verilog
opcode_hits[op] = 1'b1;
```

At the end, it checks that every opcode was exercised:

```verilog
for (c = 0; c < NUM_OPS; c = c + 1)
    if (!opcode_hits[c]) begin
        $display("FAIL coverage: opcode %0d never exercised", c);
        errors = errors + 1;
    end
```

**Analogy:** imagine testing a car. You could drive it a thousand miles on the motorway and say "it works!" But if you never tested the brakes, you haven't really tested it. Coverage tracking forces you to hit every case.

### The Watchdog

Every testbench has a timeout:

```verilog
always @(posedge clk)
    if (rst_n && cycles > MAX_CYCLES)
        $fatal(1, "timeout after %0d cycles", cycles);
```

**Why?** Some bugs cause infinite loops. Without a watchdog, a broken test hangs forever — annoying in an interactive session, catastrophic in a regression suite. The watchdog ensures every test eventually ends, one way or another.

### Waveforms on Demand

Every testbench calls `$dumpfile`/`$dumpvars`, so every test produces a waveform. If a test fails, you open the waveform and look at the cycle it failed on.

**Rule of thumb:** never debug a failing test by staring at the code. Look at the waveform first. It almost always tells you exactly what's wrong.

### The Integration Testbench

Once every module passed, we wrote `tb_riscv_core.v` — a testbench that instantiates the *whole core* and runs a small program:

```
0x1000:  addi x1, x0, 5      # x1 = 5
0x1004:  addi x2, x0, 7      # x2 = 7
0x1008:  add  x3, x1, x2     # x3 = 12
0x100C:  sw   x3, 0(x0)      # mem[0] = 12
0x1010:  lw   x4, 0(x0)      # x4 = mem[0] = 12
0x1014:  sw   x4, 4(x0)      # mem[4] = 12
0x1018:  jal  x0, 0          # infinite loop
```

The testbench waits for the core to reach the self-loop and then checks that both `mem[0]` and `mem[4]` equal 12.

**Why this matters:** every module passing in isolation doesn't prove the whole thing works. Integration tests are where you catch the wiring bugs that no unit test can find.

### Best practice summary for verification

| Practice | Verdict |
|---|---|
| Self-checking testbenches | Non-negotiable |
| `!==` for comparisons | Non-negotiable |
| Directed + randomized | Standard industry practice |
| Deterministic seeds | Essential |
| Watchdog | Non-negotiable |
| Waveform dump | Standard |
| Coverage tracking | Best practice; often skipped under time pressure |
| One testbench per module | Best practice |

---

## Part 6: Debugging: When Things Break

Three bugs we hit and how we found them. These are teaching moments that recur in every HDL project.

### Bug 1: The missing wire: `F3_JALR` undefined

**Symptom:** Icarus reported "Unable to bind wire/reg/memory `ALU_ADD`" for every ALU opcode in the decoder testbench.

**Cause:** we had moved the opcode constants into a header file (`riscv_defs.vh`) using `` `define `` which creates *macros*. Macros must be referenced with a leading backtick: `` `ALU_ADD ``, not `ALU_ADD`. Without the backtick, the compiler treats the name as a wire and can't find it.

**Fix:** add backticks to every use. Trivial once you know.

**Lesson:** when you move constants into a header, every reference site must change. Do the move in one shot, not piecemeal.

### Bug 2: The wrong sign: `imm_i6` too narrow

**Symptom:** the compressed-instruction expander (`rvc_expand.v`) produced correct results for *positive* immediates and wrong results for *negative* ones.

**Cause:** the 6-bit RVC immediate is a 6-bit value that must be sign-extended into a 12-bit field. We wrote:

```verilog
wire [11:0] imm_i6 = {{6{inst_in[12]}}, inst_in[6:2]};
```

`6 bits of sign + 5 bits of value = 11 bits`, silently zero-extended to 12. Only visible when the sign bit was 1.

**Fix:**

```verilog
wire [11:0] imm_i6 = {{6{inst_in[12]}}, inst_in[12], inst_in[6:2]};
```

Now `6 + 1 + 5 = 12`. Correct.

**Lesson:** always count the bits of a concatenation. Verilog silently zero-extends or truncates; there is no warning. Any time a directed test passes on positive inputs and fails on negative ones, suspect extension width.

### Bug 3: The lost instruction: same-cycle register write

**Symptom:** the integration test passed `mem[0]=12` but failed `mem[1]=0`.

**How we found it:** we added a `$monitor` that printed every register-write and every memory access. The trace showed:

```
T=24 RETIRE pc=00001010 rd=4 data=0000000c    <- load writes x4=12
T=26 DWRITE addr=00000004 data=00000000       <- store writes 0
```

The load wrote `x4=12` at cycle 24. The store read `x4=0` and wrote it at cycle 26. **The store had read the old value of `x4`.**

**Cause:** the store instruction was in ID at the exact cycle the load was writing `x4` in WB. Our register file's read ports reflected the pre-write array contents, so the store saw `x4=0`.

This is a classic *read-during-write hazard*. It's not caught by load-use detection because the consumer is in ID, not EX.

**Fix:** change `regfile.v` to be *write-first*:

```verilog
assign rs1_data = (rs1_addr == 5'd0) ? 32'b0 :
                  (reg_write && (rd_addr == rs1_addr)) ? rd_data :
                  regs[rs1_addr];
```

If a write is happening to the same register you're reading, return the *new* value, not the stored value. 

**Alternative fix:** stall the pipeline for one cycle whenever WB's `rd` matches ID's `rs1`/`rs2`. That works, but it costs you a cycle every time it happens. Since the bypass is cheap, felt bypass was then the better choice.

**Lesson:** every register file either needs a bypass or needs stall logic.

### Best practice for debugging

- **Waveforms first, code second.** Always.
- **Add `$monitor`/`$display` traces** when a failure isn't obvious. Cheap, temporary, and give you exactly the event stream you need.
- **Read the error message twice.** Half the time the message itself tells you the fix. ("Unable to bind `ALU_ADD`" → the macro isn't being expanded → missing backtick.)
- **When something works for positive inputs but fails for negative, suspect sign extension.**
- **When a value is "off by one cycle," suspect a same-cycle read-during-write.**

---

## Part 7: Reflection: Best Practice vs Personal Spin

### Non-negotiable best practices

1. **Testbench per module.**
2. **Self-checking testbenches.**
3. **Standard memory map.**
4. **Standard ISA encoding.**
5. **Synchronous resets.**
6. **No latches, no X propagation, no `case` without `default`.**
7. **Watchdog on every testbench.**
8. **Constants in a shared header.**
9. **Waveform dumps for every test.**
10. **Write-first register file (or equivalent WB-to-ID forwarding).**

### Personal / judgment calls


1. **RV32IMAC over RV32I.**
2. **5-stage pipeline over 3-stage or 7-stage.**
3. **Sync reset over async reset.**
4. **Verilog-2001 over SystemVerilog.**
5. **Native bus interface (our own simple protocol) over Wishbone or AXI directly.**
6. **Two-tier stall network. `stall_up` for load-use and `stall_down` for mem-stall.**
7. **Store = 1 cycle, load = 2+ cycles.**
8. **`csr_addr` deferred to WB.** We carry `csr_addr` through all pipeline registers and do the CSR read in WB. Alternative: read CSR in ID and carry the value. Our way is simpler at the pipeline register level.
9. **`illegal` clears control bits.** On an illegal instruction, we zero everything (not just `reg_write`). Belt-and-suspenders.
10. **Header comment format.**

### What we'd change with hindsight

- **Coverage collection across all testbenches.** Currently each testbench tracks its own coverage. A unified coverage report would show gaps at the suite level.
- **A golden-model regression.** Comparing against Spike or a Python model on randomly generated programs would catch far more than isolated unit tests.
- **Formal verification for the control logic.** Tools like SymbiYosys can prove that `hazard_unit` never asserts contradictory outputs. Not needed for correctness at this stage, but cheap insurance later.

### Where we are now

The core is done and passing:
- Every leaf module has been unit-tested in isolation.
- The integrated core runs a small program correctly.

**Next steps** (each is a new chapter):

1. `sram.v` / `rom.v` — behavioural memory models
2. `mmu_passthrough.v` — MMU stub, replaced later by a real Sv32 MMU
3. Caches (I-cache and D-cache)
4. Bus fabric (arbiter, interconnect)
5. Peripherals (UART, timer, GPIO, CLINT, PLIC)
6. SoC integration with `bootrom.v` and `soc_top.v`
7. A bare-metal test that prints "hello" over UART
8. riscv-tests regression
9. Sv32 MMU
10. Multicore with cache coherency

Each of those is a project in itself. But the foundation ( a correct, well-tested RV32IMAC core ) is done.

---

## Closing thoughts

Building a CPU is a bit like building a house. You can't start with the roof. You need:
1. A plan (the spec)
2. A frame (the architecture)
3. Each room built and inspected before you drywall over it (unit tests)
4. A final walkthrough (integration test)

The temptation is always to skip ahead, to write the whole core in one file, then debug it end-to-end. That approach works for a toy. It fails for anything you want to run Linux on.

The discipline that saved us repeatedly was: **write a testbench before you trust the module**. Every bug we hit was caught by a test we wrote before the bug existed. The three bugs we discussed above ( the missing backtick, the sign-extension width, the read-during-write ) none of them would have been caught by "let's just try running the whole thing." They were caught because a small, focused testbench failed loudly and pointed us straight at the problem.

The essence of good engineering: build small, test each piece, and trust only what you've verified.
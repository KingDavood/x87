// top of decode, produces uop bundles
//pkg
// 0 -> start
// 1 -> end 

// 10, 11, 12, 13,  opcode types


module decode
#( parameter MAX_BYTE_WIDTH = 1,
   parameter MAX_INSTRUCTIONS = 4,
   parameter MAX_OPCODE_LENGTH = 3)
(
  input  logic                                          clk,
  input  logic                                          rst_n,
  input  mode_t                                         mode,
  input  logic [MAX_BYTE_WIDTH*8-1:0]                   bytes, // TODO: Fix sizing eventually
  input  logic [MAX_BYTE_WIDTH*8-1:0][3:0]              bytes_flags,
  input  logic                                          op_cache_hit, //power gate on this
  output uop_metadata_t [MAX_UOPS-1:0]                  uops,    // Need to define this in pkts
  output logic [5:0]                                    pfx_len,
  output logic                                          interrupt_GP,
  output logic [MAX_INSTRUCTIONS-1:0]                   uop_valid,
  output logic [MAX_INSTRUCTIONS-1:0][FETCH_WIDTH-1:0]  instr_len // TODO: Parameter sizing
);

  localparam OPCODE_LENGTH = 8 * MAX_OPCODE_LENGTH;
  logic [5:0] byte_pos;
  logic not_done;
  logic is_modrm;

  // ModRM/SIB fields
  logic [1:0] mod;
  logic [2:0] rm;
  logic       sib;
  logic [2:0] disp;      // TODO: confirm width/encoding against DISP8/DISP16/DISP32 constants
  logic       combined;

  // prefix/mode tracking (not yet driven by the byte-scan loop)
  logic       seen_66, seen_67;
  logic       addr64, addr32;
  logic       REX_W;
  logic [1:0] opSize;    // TODO: confirm encoding against OP16/OP32/OP64 constants
  logic [1:0] addrSize;  // TODO: confirm encoding against ADDR32/ADDR64 constants
  logic       changed_from_66_from_mode_32;

  // immediate sizing
  logic [2:0] imm_type;  // TODO: confirm encoding against ib/iw/iz/io/iw_ib constants
  logic [3:0] imm_size;
  logic [3:0] start_postions;

  assign interrupt_GP = byte_pos > 15;
  
  // https://wiki.osdev.org/X86-64_Instruction_Encoding
  function automatic logic is_legacy_prefix(logic [7:0] byte);
    case (byte)
      PFX_LOCK, PFX_REPNE, PFX_REP, PFX_OPSIZE, PFX_ADDRSIZE,
      PFX_SEG_ES, PFX_SEG_CS, PFX_SEG_SS, PFX_SEG_DS, PFX_SEG_FS, PFX_SEG_GS: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction


  //Some FSM to figure where are what and what we are looking at
  //We don't know what what looking and don't what to clear

  //IDLE
  //FETCH
  //PREFIXES
  //OPCODES
  //MOD-RM
  //DISPLACEMENT
  //IMMEDIATE
      
  
  always_ff @(posedge clk, negedge rst_n) begin
    if(!rst_n) begin
      num <= 0;
      start_positions <= `{default: 0};
    end else begin
      
      for(int i = 0; i < MAX_BYTE_WIDTH; i = i + 1) begin
      
    end
  end


  always_comb begin
    byte_pos = 0;
    not_done = 1;
    pos = 0;
    sib = 0;
    disp = 0;
    combined = 0;
    opSize = OP32;
    addrSize = ADDR32;
    if(mode == MODE64) begin
      opSize = OP32;
      addrSize = ADDR64;
    end

    if(!op_cache_hit) begin
  


      // This is going to be 3
    for(int i = 0; i < MAX_BYTE_WIDTH; i = i + 1) begin

     x[i] = (byte_flags[i][0] & 1) ???? i = i;
     loop by x
        if(!=0 )
      pos 
    if(is_modrm) begin
      if(addr64 || addr32) begin
        case(mod)
          2'b00: begin
            if(rm == 3'b101) begin
              disp = DISP32;
            end
            else if(rm == 3'b100) begin
              sib = 1;
            end
            else if (Sib base something) begin

            end
            else begin
              sib = 0;
              disp = 0;
            end
          end
          2'b01: begin
            disp = DISP_8;
            if(rm==3'b100) sib = 1;
          end
          2'b10: begin
            disp = DISP_32;
            if(rm==3'b100) sib = 1;
          end
          2'b11: begin
            sib = 0;
            disp = 0;
          end
        endcase
      end
      else if(addr16)begin
        case(mod)
          2'b00: begin
            if(rm == 3'b110) begin
              disp = DISP16;
            end else begin
              disp = 0;
              sib = 0;
            end
          end
          2'b01: begin
            disp = DISP8;
          end
          2'b10: begin
            disp = DISP16;
          end
          2'b11: begin
            disp = 0;
          end
        endcase
      end
    end
  end

endmodule
// ### `x87_imm_extract`
// - **Role:** pull the immediate and size it.
// - **In:** bytes (post-disp), `imm_kind`, `operand_size`. **Out:** `imm` (extended), `imm_len`.
// - **Comb.** **Traps:** `iz` size flips with `66`/`REX.W`; `io` (imm64) only for `MOV r64, imm64`.

//some things to add:

// 1. No opcode table — the biggest gap. Nothing in the file reads the opcode byte(s) to determine (a) how many opcode bytes it is (1, or 0F two-byte, or 0F 38/0F 3A three-byte escapes), (b) whether that specific opcode needs a ModRM byte, or (c) what its immediate class is (ib/iw/iz/io/none). is_modrm and imm_type are just floating wires — nothing assigns them. Right now the ModRM/disp block and the immediate-size block are both dead code because their trigger signals are never driven. This needs some kind of case statement or ROM keyed on the opcode bytes (the outer decode module even has a ROM_SIZE parameter, suggesting this was the intent).

// 2. No REX-prefix detection. REX_W is referenced but nothing scans for a 0x40–0x4F byte after the legacy prefixes (64-bit mode only). REX also needs to be excluded from is_legacy_prefix's counting logic and its own byte counted separately, since it sits in a specific position (immediately before the opcode).

// 3. Legacy-prefix scan doesn't classify what it found. is_legacy_prefix only returns "yes/no this byte is a prefix" — it can't tell you which prefix matched. But seen_66/seen_67 (which drive the operand/address-size overrides) need to know specifically whether a 0x66 or 0x67 byte was among the ones scanned. As written there's no path that ever sets seen_66/seen_67/REX_W to anything.

// 4. SIB byte isn't counted. The sib flag gets set in the ModRM case logic, but nothing adds a byte for it, and nothing implements the SIB-specific rule (mod==00 && base==101 → extra disp32) that real x86 requires.

// 5. No final length output at all. This is the one that stands out most given the module's name: length_decode's outputs are op_code, op_code_len, pfx_len, interrupt_GP — nothing sums prefix bytes + REX + opcode bytes + ModRM(1) + SIB(0/1) + displacement + immediate into a total. There's no port here feeding the top-level decode module's instr_len at all. Something needs to combine all the pieces.

// 6. interrupt_GP checks the wrong thing. It's byte_pos > 15, but byte_pos right now only tracks prefix-scan progress, not the running total instruction length. The real check ("instruction exceeds 15 bytes → #GP") needs to happen against the final accumulated length, not just the prefix count.

// 7. is_prefix's mode-based branching is an empty stub. It's presumably meant to decide prefix legality/behavior per mode (e.g., REX only exists in 64-bit mode, segment overrides behave differently pre/post long mode) but every branch is empty — no logic at all yet.

// 8. Default operand-size edge case. The 64-bit-mode default (opSize = OP32 unless REX.W) is roughly right generically, but doesn't account for "default 64-bit operand size" opcodes (push/pop/near call/jmp/ret) that are 64-bit regardless of REX.W — that opcode-dependent behavior also depends on item #1 (the opcode table) existing.

// In short: the ModRM/SIB/displacement/immediate sizing logic is roughly the right shape once its bugs are fixed, but there's no opcode classification driving it, no REX handling, no prefix classification, and no summation step producing an actual length — those all need to be added, not just fixed.


module Decode_FSM(
    input  logic clk, start, has_modrm,
    input  logic rst_n,
    input  logic [7:0] position,
    input  logic [MAX_BYTE_WIDTH*8-1:0]bytes,
    output logic [7:0] instr_pos_start,
    output logic [7:0] instr_pos_end,
    output logic [5:0] bucket_opcode_type,
    output logic done);

    // typedef enum logic [5:0] {LEGACY_PREFIX, PREFIX, OPCODE, DISPLACEMENT, IMMEDIATE} state_t;
    // state_t current_state, next_state;

    // always_ff @(posedge clk, negedge rst_n) begin
    //     if(!rst_n) begin
    //         current_state <= LEGACY_PREFIX;
    //     end else begin
    //         current_state <= next_state;
    //     end
    // end
    
    always_comb begin
        done = 1'd0;
        if(start) begin
          
          // Find the end of the legecay/regular prefix byte chain
          for(int i = 0; i < MAX_LEGACY_PREFIX; i++) begin
            //in prefix lookup
              //if rex increase displacement
              //if 66 || 67 increase other thing 
              //add 1 to end
          end
          // OPCODE:
            // Check for VEX/REX/XOP/EVEX
            // Check for what mode we're in

            // => Which op_map to use

         
          // MOD_RM:
            //Gives displacement size and whether sib folllows
          // DISPLACEMENT:


          // IMMEDIATE:

        end
    end
endmodule


// For length_decode specifically, the table just needs to answer "how many bytes does this opcode occupy, and what comes after it" — it doesn't need the full instruction-identity payload that opcode_rom/cracking wants.

// Input (lookup key):

// escape — none / 0F / 0F 38 / 0F 3A (which map is this in)
// opcode_byte — the byte after the escape
// mand_pfx — mandatory-prefix class (none/66/F2/F3) from the prefix scan, since some SSE-style opcodes change meaning based on it
// optionally modrm.reg for "group" opcodes (ADD/OR/... share one opcode, reg field picks the variant) — doesn't block the length calc since group opcodes always have ModRM by construction
// Output (fields length_decode consumes):

// valid — 0 means unrecognized opcode (#UD), stop here
// opcode_len — 1/2/3, how many bytes the escape+opcode consumed
// has_modrm — feeds the ModRM/SIB/disp sizing block that's currently dead code
// imm_kind — none/ib/iw/iz/io/iw_ib, feeds the immediate-size block
// def64 — whether this opcode forces 64-bit operand size in long mode regardless of prefixes (CALL/PUSH/POP/Jcc-style), needed to size iz/io correctly
// The doc's guidance (§2, x87_ilen_dec) is explicit that this should be the same table opcode_rom uses for cracking — just add the extra fields (uop_template, flags_wr, group_id, etc.) that length_decode ignores — rather than building a second lookup that can drift out of sync with the first.



// ADD/SUB/logic/shift/rotate/MOV/LEA/MUL/DIV/LOAD/STORE/branches/SETcc/CMOVcc covers the "protected-mode integer subset" the doc scopes for first. A few things from that list don't need new uops at all — worth naming so you don't over-build:

// PUSH/POP → crack into existing UOP_SUB/UOP_ADD (rsp adjust) + UOP_LOAD/UOP_STORE, per the doc's own cracking example.
// XCHG reg,reg → two UOP_MOVs through a temp (or move-elimination, see below). XCHG mem,reg is the harder one — it's implicitly locked (atomic) even without a LOCK prefix, so it wants the same atomicity primitive as CMPXCHG, not a bespoke uop.
// LOOP/LOOPE/LOOPNE → decrement + test + UOP_JCC, no new primitive needed.


//1. Read prefxies -> x86 specific not 66, 67, REX
// // i. READ all prefixes carre about 66, 67, REX
//2. Then measure 1 insturction length -> add up everything : prefixes + opcode + modrm + sib + displacement + immediate = a number.
// // i. SIB byte isn't counted. The sib flag gets set in the ModRM case logic, but nothing adds a byte for it, and nothing implements 
// //ii. No final length output at all. This is the one that stands out most given the module's name: length_decode's outputs are op_code, op_code_len, pfx_len, interrupt_GP —  bytes + ModRM(1) + SIB(0/1) + displacement + immediate into a total.
//3. Find when instructions starts -> Koggestone shit do in parallel for all instructions
// // i. 
//3.5 What is going on with each instruciton
// // i. opcode table 

//5ish. Not the other microp path

they are in plain words:

Box A — read the prefixes. Look at the front of an instruction, count the prefix bytes (66, 67, REX, etc.), note what they mean. Small, x86-specific.

Box B — measure one instruction's length. Add up the field sizes: prefixes + opcode + modrm + sib + displacement + immediate = a number. Also x86-specific. Uses A's output. This is NOT the scan. It's just adding widths at one spot.

Box C — find where instructions start. Take the length numbers from B and hop: 0 → 0+len → ... This is the only box that uses Kogge-Stone, and it doesn't know or care that it's x86. It's just numbers.

Box D — actually decode the instruction into uops. Runs only on the real starts that C found.
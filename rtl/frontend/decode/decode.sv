// top of decode, produces uop bundles
module decode #(
  parameter FETCH_WIDTH=4,
  parameter ROM_SIZE=64,
  parameter MAX_UOPS=4
)
(
    input logic                     clk, rst_n,
    input logic [FETCH_W*8-1:0]     bytes,
    input prefix_state_t            prefix,  // need to find this aswell
    input mode_e                    mode,   
    output uop_metadata_t [MAX_UOPS-1:0]     uops,    // Need to define this in pkts
    output logic [MAX_UOPS-1:0]     uop_valid,
    output logic [FETCH_WIDTH-1:0]  instr_len // TODO: Parameter sizing
);

endmodule


module prefix_decode #(
  parameter FETCH_WIDTH=4  
)
(
  input logic                     clk, rst_n,
  input mode_e                    mode,
  output logic [FETCH_WIDTH-1:0]  pfx_len, // TODO: Parameter sizing
  output prefix_state_t           prefix
);


endmodule

module length_decode
#( parameter MAX_BYTE_WIDTH = 32,
   parameter MAX_OPCODE_LENGTH = 3)
(
  input  logic clk,
  input  logic rst_n,
  input  mode_t mode,
  input  logic [MAX_BYTE_WIDTH*8-1:0]bytes, // TODO: Fix sizing eventually
  output logic [MAX_OPCODE_LENGTH*8-1:0] op_code,
  output logic [1:0]                     op_code_len,
  output logic [5:0]                     pfx_len,
  output logic                           interrupt_GP
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
      
  
  

  // find amd thingy
  function automatic logic is_prefix(logic [7:0] byte);
  // need some more inputs
    always_comb begin
      if(mode == REAL)begin
        
      end else if(mode == PROTECTED) begin
        
      end else if(mode == BIT_64)begin
        
      end else if(mode == VIRTUAL8086) begin
        
      end else if(mode == COMPATIBILITY) begin
        
      end
      
    end
  endfunction

  always_comb begin
    byte_pos = 0;
    not_done = 1;
    sib = 0;
    disp = 0;
    combined = 0;
    opSize = OP32;
    addrSize = ADDR32;
    if(mode == MODE64) begin
      opSize = OP32;
      addrSize = ADDR64;
    end

    // Immediate classes (op-size = latched op-size unless mandatory-66):
    // none
    // ib = 1
    // iw = 2
    // iz = 2 if op16, else 4 (also E8/E9 branch rel; iz stays 4 at op64, sign-extended)
    // io = 8, only B8–BF (MOV r64,imm) with REX.W; without REX.W it's iz
    // iw+ib = 3 (ENTER C8)


    //if we are at the end of an instruction could go to different fetch group
    if(imm_type == ib) begin // 1 byte IB
      imm_size = 1;      
    end else if(imm_type == iw) begin
      imm_size = 2;
    end else if (imm_type == iz) begin
      if(OP32) begin
        imm_size = 4;
      end else if(OP16) begin
        imm_size = 2;
      end
    end else if(imm_type ==  io) begin
      if(OP64 && REX_W) begin
        imm_size = 8;
      end else begin
        imm_size = 4;
      end
    end else if(imm_size == iw_ib) begin
      imm_size = 3;
      combined = 1;
    end
      

    for(int i = 0; i < MAX_BYTE_WIDTH; i++) begin
      if(not_done &&
      (is_prefix(bytes[i]) || is_legacy_prefix(bytes[(i+1)*8:i*8]))) begin
        byte_pos += 1;
      end

  


      else begin
        not_done = 0;
      end
    end

    if(mode == MODE32 && seen_66) begin
      opSize = OP16;
      changed_from_66_from_mode_32 = 1;
    end
    else if(mode == MODE32 && seen_67)begin
      addrSize = ADDR32;
    end 

    if(mode == MODE64 && REX_W) begin
      opSize = OP64;
    end 
    else if(mode == MODE64 && seen_66) begin
      addrSize = OP16;
    end
    else if(mode == MODE64 && seen_67) begin
      addrSize = ADDR32;
    end
  
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


// ------------------------------------------------------------------
// escape_t / prefix_t / imm_t -- shared key/result types for opcode_table
// below. escape_t and prefix_t are the lookup KEY (see docs/x87_decode_impl.md
// #3 "Lookup key: {escape, mand_pfx, opcode_byte}"); imm_t is one field of
// the RESULT, transcribed from ref.x86asm.net alongside has_modrm/valid.
// ------------------------------------------------------------------
typedef enum logic [1:0] {
  ESC_NONE,  // no escape -- opcode_byte is the primary one-byte opcode
  ESC_0F,    // 0F xx     -- two-byte map
  ESC_0F38,  // 0F 38 xx  -- three-byte map (not on coder64.html -- #UD until filled in)
  ESC_0F3A   // 0F 3A xx  -- three-byte map (not on coder64.html -- #UD until filled in)
} escape_t;

// mandatory-prefix class -- part of the lookup key per the doc, but not
// consumed by opcode1_attrs/opcode0F_attrs below: distinguishing SSE-style
// mandatory-prefix forms (66/F2/F3 changing an 0F opcode's meaning) is out
// of scope for the protected-mode integer subset. Accepted as an input so
// the port shape matches the eventual shared table; wire it up when SSE
// opcodes are in scope.
typedef enum logic [3:0] {
  IMM_NONE,   // no immediate
  IMM_IB,     // 1 byte  (ib / rel8)
  IMM_IW,     // 2 bytes (iw, fixed)
  IMM_IZ,     // 2 or 4  (iz / rel16-32, follows operand size)
  IMM_IZ_IO,  // iz unless REX.W, then 8 (B8-BF MOV r64,imm only)
  IMM_ID,     // 4 bytes (id, fixed)
  IMM_IO,     // 8 bytes (io, fixed)
  IMM_IW_IB,  // 3 bytes (ENTER: imm16 then imm8)
  IMM_MOFFS,  // addr-sized direct offset (A0-A3)
  IMM_PTR     // far ptr16:16/32 (invalid in 64-bit mode; kept for completeness)
} imm_t;  // moved here from inside the module body -- a port list is elaborated
          // before the module body, so a type used in the ports (imm_kind below)
          // has to be defined at file scope first, same reasoning as escape_t/prefix_t.

typedef enum logic [1:0] {
  MPFX_NONE, MPFX_66, MPFX_F2, MPFX_F3
} prefix_t;

module opcode_table(
  input  logic       clk,
  input  logic       rst_n,
  input  escape_t    escape,
  input  logic [7:0] opcode_byte,  // one byte at a time -- caller already knows escape,
                                    // so there's no need to hand this module two bytes
                                    // at once (the original 16-bit port was dropped)
  input  prefix_t    mand_pfx,     // TODO: not consumed yet, see prefix_t comment above
  output logic        valid,
  output logic [1:0]  opcode_len,  // bytes consumed by escape+opcode (was 1-bit `logic`,
                                    // too narrow to hold 1-3 -- widened to match
                                    // MAX_OPCODE_LENGTH in length_decode)
  output logic        has_modrm,
  output imm_t         imm_kind,
  output logic         def64        // TODO: not derived from the page yet. The 'st'
                                    // column shows a 'D32' footnote on CALL/JMP-near
                                    // (E8/E9) and PUSH/POP (50-5F/58-5F) that looks
                                    // related to "operand size fixed regardless of
                                    // prefixes", but the footnote legend itself wasn't
                                    // fetched/decoded -- don't trust a guess here,
                                    // confirm against the SDM before wiring this up.
);

  // ------------------------------------------------------------------
  // Opcode attribute tables -- transcribed directly from
  // http://ref.x86asm.net/coder64.html (one-byte + two-byte 0F maps,
  // 64-bit/long-mode edition). Deliberately unoptimized: one `if` per
  // opcode byte, in byte order, so each line can be diff'ed against a
  // row on that page. has_modrm/imm_kind come from that page's 'o'
  // (register/opcode field) and operand columns:
  //   o column blank            -> no ModRM byte
  //   o column 'r' or a digit   -> ModRM byte present
  //   operand imm8/rel8         -> IMM_IB   (1 byte)
  //   operand imm16             -> IMM_IW   (2 bytes)
  //   operand imm16/32, rel16/32-> IMM_IZ   (2 or 4, follows opsize)
  //   operand imm16/32/64 (B8-BF only) -> IMM_IZ_IO (IMM_IZ unless REX.W, then 8 bytes)
  //   operand imm32             -> IMM_ID   (4 bytes, fixed)
  //   operand imm64             -> IMM_IO   (8 bytes)
  //   ENTER (C8) imm16+imm8     -> IMM_IW_IB (3 bytes)
  //   moffs*/ptr16:*            -> IMM_MOFFS / IMM_PTR (addr-sized, rare)
  // NOT hand-verified against the SDM beyond what's on the page --
  // e.g. 0F 19-1E ("HINT_NOP") show has_modrm=0 on this page even
  // though the SDM's multi-byte-NOP block (0F 18-1F) documents all of
  // them as taking an r/m operand via ModRM; worth a manual check.
  // Coverage: only what's on this page -- one-byte + two-byte(0F) maps.
  // No 0F 38 / 0F 3A three-byte escapes (not listed on this page).
  // ------------------------------------------------------------------

  function automatic void opcode1_attrs(
    input  logic [7:0] b,
    output logic       valid,
    output logic       has_modrm,
    output imm_t  imm_kind
  );
    if (b == 8'h00) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ADD r/m8,r8
    else if (b == 8'h01) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ADD r/m16/32/64,r16/32/64
    else if (b == 8'h02) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ADD r8,r/m8
    else if (b == 8'h03) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ADD r16/32/64,r/m16/32/64
    else if (b == 8'h04) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // ADD AL,imm8
    else if (b == 8'h05) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // ADD rAX,imm16/32
    else if (b == 8'h08) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // OR r/m8,r8
    else if (b == 8'h09) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // OR r/m16/32/64,r16/32/64
    else if (b == 8'h0A) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // OR r8,r/m8
    else if (b == 8'h0B) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // OR r16/32/64,r/m16/32/64
    else if (b == 8'h0C) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // OR AL,imm8
    else if (b == 8'h0D) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // OR rAX,imm16/32
    else if (b == 8'h0F) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // escape to two-byte (0F) map -- see opcode0F_attrs
    else if (b == 8'h10) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ADC r/m8,r8
    else if (b == 8'h11) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ADC r/m16/32/64,r16/32/64
    else if (b == 8'h12) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ADC r8,r/m8
    else if (b == 8'h13) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ADC r16/32/64,r/m16/32/64
    else if (b == 8'h14) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // ADC AL,imm8
    else if (b == 8'h15) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // ADC rAX,imm16/32
    else if (b == 8'h18) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SBB r/m8,r8
    else if (b == 8'h19) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SBB r/m16/32/64,r16/32/64
    else if (b == 8'h1A) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SBB r8,r/m8
    else if (b == 8'h1B) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SBB r16/32/64,r/m16/32/64
    else if (b == 8'h1C) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // SBB AL,imm8
    else if (b == 8'h1D) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // SBB rAX,imm16/32
    else if (b == 8'h20) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // AND r/m8,r8
    else if (b == 8'h21) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // AND r/m16/32/64,r16/32/64
    else if (b == 8'h22) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // AND r8,r/m8
    else if (b == 8'h23) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // AND r16/32/64,r/m16/32/64
    else if (b == 8'h24) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // AND AL,imm8
    else if (b == 8'h25) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // AND rAX,imm16/32
    else if (b == 8'h26) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (ES override (null in 64-bit mode)) -- consumed by prefix scan, should not reach here
    else if (b == 8'h28) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SUB r/m8,r8
    else if (b == 8'h29) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SUB r/m16/32/64,r16/32/64
    else if (b == 8'h2A) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SUB r8,r/m8
    else if (b == 8'h2B) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SUB r16/32/64,r/m16/32/64
    else if (b == 8'h2C) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // SUB AL,imm8
    else if (b == 8'h2D) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // SUB rAX,imm16/32
    else if (b == 8'h2E) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (CS override (null in 64-bit mode)) -- consumed by prefix scan, should not reach here
    else if (b == 8'h30) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // XOR r/m8,r8
    else if (b == 8'h31) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // XOR r/m16/32/64,r16/32/64
    else if (b == 8'h32) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // XOR r8,r/m8
    else if (b == 8'h33) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // XOR r16/32/64,r/m16/32/64
    else if (b == 8'h34) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // XOR AL,imm8
    else if (b == 8'h35) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // XOR rAX,imm16/32
    else if (b == 8'h36) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (SS override (null in 64-bit mode)) -- consumed by prefix scan, should not reach here
    else if (b == 8'h38) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMP r/m8,r8
    else if (b == 8'h39) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMP r/m16/32/64,r16/32/64
    else if (b == 8'h3A) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMP r8,r/m8
    else if (b == 8'h3B) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMP r16/32/64,r/m16/32/64
    else if (b == 8'h3C) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // CMP AL,imm8
    else if (b == 8'h3D) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // CMP rAX,imm16/32
    else if (b == 8'h3E) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (DS override (null in 64-bit mode)) -- consumed by prefix scan, should not reach here
    else if (b == 8'h40) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h41) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h42) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h43) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h44) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h45) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h46) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h47) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h48) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h49) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h4A) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h4B) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h4C) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h4D) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h4E) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h4F) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REX) -- consumed by prefix scan, should not reach here
    else if (b == 8'h50) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // PUSH r64/16 (+0)
    else if (b == 8'h51) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // PUSH r64/16 (+1)
    else if (b == 8'h52) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // PUSH r64/16 (+2)
    else if (b == 8'h53) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // PUSH r64/16 (+3)
    else if (b == 8'h54) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // PUSH r64/16 (+4)
    else if (b == 8'h55) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // PUSH r64/16 (+5)
    else if (b == 8'h56) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // PUSH r64/16 (+6)
    else if (b == 8'h57) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // PUSH r64/16 (+7)
    else if (b == 8'h58) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // POP r64/16 (+0)
    else if (b == 8'h59) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // POP r64/16 (+1)
    else if (b == 8'h5A) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // POP r64/16 (+2)
    else if (b == 8'h5B) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // POP r64/16 (+3)
    else if (b == 8'h5C) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // POP r64/16 (+4)
    else if (b == 8'h5D) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // POP r64/16 (+5)
    else if (b == 8'h5E) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // POP r64/16 (+6)
    else if (b == 8'h5F) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // POP r64/16 (+7)
    else if (b == 8'h63) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVSXD r32/64,r/m32
    else if (b == 8'h64) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (FS override) -- consumed by prefix scan, should not reach here
    else if (b == 8'h65) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (GS override) -- consumed by prefix scan, should not reach here
    else if (b == 8'h66) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (operand-size override) -- consumed by prefix scan, should not reach here
    else if (b == 8'h67) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (address-size override) -- consumed by prefix scan, should not reach here
    else if (b == 8'h68) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // PUSH imm16/32
    else if (b == 8'h69) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IZ; end // IMUL r16/32/64,r/m16/32/64,imm16/32
    else if (b == 8'h6A) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // PUSH imm8
    else if (b == 8'h6B) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // IMUL r16/32/64,r/m16/32/64,imm8
    else if (b == 8'h6C) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // INS m8,DX
    else if (b == 8'h6D) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // INS m16,DX
    else if (b == 8'h6E) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // OUTS DX,m8
    else if (b == 8'h6F) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // OUTS DX,m16
    else if (b == 8'h70) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JO rel8
    else if (b == 8'h71) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JNO rel8
    else if (b == 8'h72) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JB rel8
    else if (b == 8'h73) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JNB rel8
    else if (b == 8'h74) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JZ rel8
    else if (b == 8'h75) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JNZ rel8
    else if (b == 8'h76) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JBE rel8
    else if (b == 8'h77) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JNBE rel8
    else if (b == 8'h78) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JS rel8
    else if (b == 8'h79) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JNS rel8
    else if (b == 8'h7A) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JP rel8
    else if (b == 8'h7B) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JNP rel8
    else if (b == 8'h7C) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JL rel8
    else if (b == 8'h7D) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JNL rel8
    else if (b == 8'h7E) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JLE rel8
    else if (b == 8'h7F) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JNLE rel8
    else if (b == 8'h80) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // ADD r/m8,imm8
    else if (b == 8'h81) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IZ; end // ADD r/m16/32/64,imm16/32
    else if (b == 8'h83) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // ADD r/m16/32/64,imm8
    else if (b == 8'h84) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // TEST r/m8,r8
    else if (b == 8'h85) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // TEST r/m16/32/64,r16/32/64
    else if (b == 8'h86) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // XCHG r8,r/m8
    else if (b == 8'h87) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // XCHG r16/32/64,r/m16/32/64
    else if (b == 8'h88) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOV r/m8,r8
    else if (b == 8'h89) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOV r/m16/32/64,r16/32/64
    else if (b == 8'h8A) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOV r8,r/m8
    else if (b == 8'h8B) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOV r16/32/64,r/m16/32/64
    else if (b == 8'h8C) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOV m16,Sreg
    else if (b == 8'h8D) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // LEA r16/32/64,m
    else if (b == 8'h8E) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOV Sreg,r/m16
    else if (b == 8'h8F) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // POP r/m16/32
    else if (b == 8'h90) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // XCHG r16/32/64,rAX (+0)
    else if (b == 8'h91) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // XCHG r16/32/64,rAX (+1)
    else if (b == 8'h92) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // XCHG r16/32/64,rAX (+2)
    else if (b == 8'h93) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // XCHG r16/32/64,rAX (+3)
    else if (b == 8'h94) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // XCHG r16/32/64,rAX (+4)
    else if (b == 8'h95) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // XCHG r16/32/64,rAX (+5)
    else if (b == 8'h96) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // XCHG r16/32/64,rAX (+6)
    else if (b == 8'h97) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // XCHG r16/32/64,rAX (+7)
    else if (b == 8'h98) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // CBW AX,AL
    else if (b == 8'h99) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // CWD DX,AX
    else if (b == 8'h9B) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // FWAIT 
    else if (b == 8'h9C) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // PUSHF Flags
    else if (b == 8'h9D) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // POPF Flags
    else if (b == 8'h9E) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // SAHF AH
    else if (b == 8'h9F) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // LAHF AH
    else if (b == 8'hA0) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_MOFFS; end // MOV AL,moffs8
    else if (b == 8'hA1) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_MOFFS; end // MOV rAX,moffs16/32/64
    else if (b == 8'hA2) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_MOFFS; end // MOV moffs8,AL
    else if (b == 8'hA3) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_MOFFS; end // MOV moffs16/32/64,rAX
    else if (b == 8'hA4) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // MOVS m8,m8
    else if (b == 8'hA5) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // MOVS m16/32/64,m16/32/64
    else if (b == 8'hA6) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // CMPS m8,m8
    else if (b == 8'hA7) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // CMPS m16/32/64,m16/32/64
    else if (b == 8'hA8) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // TEST AL,imm8
    else if (b == 8'hA9) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // TEST rAX,imm16/32
    else if (b == 8'hAA) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // STOS m8,AL
    else if (b == 8'hAB) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // STOS m16/32/64,rAX
    else if (b == 8'hAC) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // LODS AL,m8
    else if (b == 8'hAD) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // LODS rAX,m16/32/64
    else if (b == 8'hAE) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // SCAS m8,AL
    else if (b == 8'hAF) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // SCAS m16/32/64,rAX
    else if (b == 8'hB0) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // MOV r8,imm8 (+0)
    else if (b == 8'hB1) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // MOV r8,imm8 (+1)
    else if (b == 8'hB2) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // MOV r8,imm8 (+2)
    else if (b == 8'hB3) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // MOV r8,imm8 (+3)
    else if (b == 8'hB4) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // MOV r8,imm8 (+4)
    else if (b == 8'hB5) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // MOV r8,imm8 (+5)
    else if (b == 8'hB6) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // MOV r8,imm8 (+6)
    else if (b == 8'hB7) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // MOV r8,imm8 (+7)
    else if (b == 8'hB8) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ_IO; end // MOV r16/32/64,imm16/32/64 (+0)
    else if (b == 8'hB9) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ_IO; end // MOV r16/32/64,imm16/32/64 (+1)
    else if (b == 8'hBA) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ_IO; end // MOV r16/32/64,imm16/32/64 (+2)
    else if (b == 8'hBB) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ_IO; end // MOV r16/32/64,imm16/32/64 (+3)
    else if (b == 8'hBC) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ_IO; end // MOV r16/32/64,imm16/32/64 (+4)
    else if (b == 8'hBD) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ_IO; end // MOV r16/32/64,imm16/32/64 (+5)
    else if (b == 8'hBE) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ_IO; end // MOV r16/32/64,imm16/32/64 (+6)
    else if (b == 8'hBF) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ_IO; end // MOV r16/32/64,imm16/32/64 (+7)
    else if (b == 8'hC0) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // ROL r/m8,imm8
    else if (b == 8'hC1) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // ROL r/m16/32/64,imm8
    else if (b == 8'hC2) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IW; end // RETN imm16
    else if (b == 8'hC3) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // RETN 
    else if (b == 8'hC6) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // MOV r/m8,imm8
    else if (b == 8'hC7) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IZ; end // MOV r/m16/32/64,imm16/32
    else if (b == 8'hC8) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IW_IB; end // ENTER rBP,imm16,imm8
    else if (b == 8'hC9) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // LEAVE rBP
    else if (b == 8'hCA) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IW; end // RETF imm16
    else if (b == 8'hCB) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // RETF 
    else if (b == 8'hCC) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // INT 3,eFlags
    else if (b == 8'hCD) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // INT imm8,eFlags
    else if (b == 8'hCE) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // INTO eFlags
    else if (b == 8'hCF) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // IRET Flags
    else if (b == 8'hD0) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ROL r/m8,1
    else if (b == 8'hD1) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ROL r/m16/32/64,1
    else if (b == 8'hD2) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ROL r/m8,CL
    else if (b == 8'hD3) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ROL r/m16/32/64,CL
    else if (b == 8'hD7) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // XLAT AL,m8
    else if (b == 8'hD8) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // FADD ST,m32real
    else if (b == 8'hD9) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // FLD ST,STi/m32real
    else if (b == 8'hDA) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // FIADD ST,m32int
    else if (b == 8'hDB) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // FILD ST,m32int
    else if (b == 8'hDC) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // FADD ST,m64real
    else if (b == 8'hDD) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // FLD ST,m64real
    else if (b == 8'hDE) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // FIADD ST,m16int
    else if (b == 8'hDF) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // FILD ST,m16int
    else if (b == 8'hE0) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // LOOPNZ rCX,rel8
    else if (b == 8'hE1) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // LOOPZ rCX,rel8
    else if (b == 8'hE2) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // LOOP rCX,rel8
    else if (b == 8'hE3) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JECXZ rel8,ECX
    else if (b == 8'hE4) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // IN AL,imm8
    else if (b == 8'hE5) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // IN eAX,imm8
    else if (b == 8'hE6) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // OUT imm8,AL
    else if (b == 8'hE7) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // OUT imm8,eAX
    else if (b == 8'hE8) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // CALL rel16/32
    else if (b == 8'hE9) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JMP rel16/32
    else if (b == 8'hEB) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IB; end // JMP rel8
    else if (b == 8'hEC) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // IN AL,DX
    else if (b == 8'hED) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // IN eAX,DX
    else if (b == 8'hEE) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // OUT DX,AL
    else if (b == 8'hEF) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // OUT DX,eAX
    else if (b == 8'hF0) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (LOCK) -- consumed by prefix scan, should not reach here
    else if (b == 8'hF1) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // undefined undefined,undefined,undefined,undefined
    else if (b == 8'hF2) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REPNZ/REPNE) -- consumed by prefix scan, should not reach here
    else if (b == 8'hF3) begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // prefix byte (REPZ/REPE) -- consumed by prefix scan, should not reach here
    else if (b == 8'hF4) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // HLT 
    else if (b == 8'hF5) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // CMC 
    else if (b == 8'hF6) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // TEST r/m8,imm8
    else if (b == 8'hF7) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IZ; end // TEST r/m16/32/64,imm16/32
    else if (b == 8'hF8) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // CLC 
    else if (b == 8'hF9) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // STC 
    else if (b == 8'hFA) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // CLI 
    else if (b == 8'hFB) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // STI 
    else if (b == 8'hFC) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // CLD 
    else if (b == 8'hFD) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // STD 
    else if (b == 8'hFE) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // INC r/m8
    else if (b == 8'hFF) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // INC r/m16/32/64
    else begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // unreachable
  endfunction

  function automatic void opcode0F_attrs(
    input  logic [7:0] b2,
    output logic       valid,
    output logic       has_modrm,
    output imm_t  imm_kind
  );
    if (b2 == 8'h00) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SLDT m16,LDTR
    else if (b2 == 8'h01) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SGDT m,GDTR
    else if (b2 == 8'h02) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // LAR r16/32/64,m16
    else if (b2 == 8'h03) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // LSL r16/32/64,m16
    else if (b2 == 8'h05) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // SYSCALL RCX,R11,SS,...
    else if (b2 == 8'h06) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // CLTS CR0
    else if (b2 == 8'h07) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // SYSRET SS,EFlags,R11,...
    else if (b2 == 8'h08) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // INVD 
    else if (b2 == 8'h09) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // WBINVD 
    else if (b2 == 8'h0B) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // UD2 
    else if (b2 == 8'h0D) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // NOP r/m16/32
    else if (b2 == 8'h10) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVUPS xmm,xmm/m128
    else if (b2 == 8'h11) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVUPS xmm/m128,xmm
    else if (b2 == 8'h12) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVHLPS xmm,xmm
    else if (b2 == 8'h13) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVLPS m64,xmm
    else if (b2 == 8'h14) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // UNPCKLPS xmm,xmm/m64
    else if (b2 == 8'h15) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // UNPCKHPS xmm,xmm/m64
    else if (b2 == 8'h16) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVLHPS xmm,xmm
    else if (b2 == 8'h17) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVHPS m64,xmm
    else if (b2 == 8'h18) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PREFETCHNTA m8
    else if (b2 == 8'h19) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // HINT_NOP r/m16/32
    else if (b2 == 8'h1A) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // HINT_NOP r/m16/32
    else if (b2 == 8'h1B) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // HINT_NOP r/m16/32
    else if (b2 == 8'h1C) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // HINT_NOP r/m16/32
    else if (b2 == 8'h1D) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // HINT_NOP r/m16/32
    else if (b2 == 8'h1E) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // HINT_NOP r/m16/32
    else if (b2 == 8'h1F) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // NOP r/m16/32
    else if (b2 == 8'h20) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOV r64,CRn
    else if (b2 == 8'h21) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOV r64,DRn
    else if (b2 == 8'h22) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOV CRn,r64
    else if (b2 == 8'h23) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOV DRn,r64
    else if (b2 == 8'h28) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVAPS xmm,xmm/m128
    else if (b2 == 8'h29) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVAPS xmm/m128,xmm
    else if (b2 == 8'h2A) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CVTPI2PS xmm,mm/m64
    else if (b2 == 8'h2B) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVNTPS m128,xmm
    else if (b2 == 8'h2C) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CVTTPS2PI mm,xmm/m64
    else if (b2 == 8'h2D) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CVTPS2PI mm,xmm/m64
    else if (b2 == 8'h2E) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // UCOMISS xmm,xmm/m32
    else if (b2 == 8'h2F) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // COMISS xmm,xmm/m32
    else if (b2 == 8'h30) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // WRMSR MSR,rCX,rAX,rDX
    else if (b2 == 8'h31) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // RDTSC EAX,EDX,IA32_TIME_S…
    else if (b2 == 8'h32) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // RDMSR rAX,rDX,rCX,MSR
    else if (b2 == 8'h33) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // RDPMC EAX,EDX,PMC
    else if (b2 == 8'h34) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // SYSENTER SS,RSP,IA32_SYSENT…,...
    else if (b2 == 8'h35) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // SYSEXIT SS,eSP,IA32_SYSENT…,...
    else if (b2 == 8'h37) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // GETSEC EAX
    else if (b2 == 8'h38) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // INVEPT r64,m128
    else if (b2 == 8'h3A) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // ROUNDPS xmm,xmm/m128,imm8
    else if (b2 == 8'h40) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVO r16/32/64,r/m16/32/64
    else if (b2 == 8'h41) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVNO r16/32/64,r/m16/32/64
    else if (b2 == 8'h42) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVB r16/32/64,r/m16/32/64
    else if (b2 == 8'h43) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVNB r16/32/64,r/m16/32/64
    else if (b2 == 8'h44) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVZ r16/32/64,r/m16/32/64
    else if (b2 == 8'h45) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVNZ r16/32/64,r/m16/32/64
    else if (b2 == 8'h46) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVBE r16/32/64,r/m16/32/64
    else if (b2 == 8'h47) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVNBE r16/32/64,r/m16/32/64
    else if (b2 == 8'h48) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVS r16/32/64,r/m16/32/64
    else if (b2 == 8'h49) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVNS r16/32/64,r/m16/32/64
    else if (b2 == 8'h4A) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVP r16/32/64,r/m16/32/64
    else if (b2 == 8'h4B) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVNP r16/32/64,r/m16/32/64
    else if (b2 == 8'h4C) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVL r16/32/64,r/m16/32/64
    else if (b2 == 8'h4D) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVNL r16/32/64,r/m16/32/64
    else if (b2 == 8'h4E) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVLE r16/32/64,r/m16/32/64
    else if (b2 == 8'h4F) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMOVNLE r16/32/64,r/m16/32/64
    else if (b2 == 8'h50) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVMSKPS r32/64,xmm
    else if (b2 == 8'h51) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SQRTPS xmm,xmm/m128
    else if (b2 == 8'h52) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // RSQRTPS xmm,xmm/m128
    else if (b2 == 8'h53) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // RCPPS xmm,xmm/m128
    else if (b2 == 8'h54) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ANDPS xmm,xmm/m128
    else if (b2 == 8'h55) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ANDNPS xmm,xmm/m128
    else if (b2 == 8'h56) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ORPS xmm,xmm/m128
    else if (b2 == 8'h57) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // XORPS xmm,xmm/m128
    else if (b2 == 8'h58) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ADDPS xmm,xmm/m128
    else if (b2 == 8'h59) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MULPS xmm,xmm/m128
    else if (b2 == 8'h5A) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CVTPS2PD xmm,xmm/m128
    else if (b2 == 8'h5B) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CVTDQ2PS xmm,xmm/m128
    else if (b2 == 8'h5C) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SUBPS xmm,xmm/m128
    else if (b2 == 8'h5D) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MINPS xmm,xmm/m128
    else if (b2 == 8'h5E) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // DIVPS xmm,xmm/m128
    else if (b2 == 8'h5F) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MAXPS xmm,xmm/m128
    else if (b2 == 8'h60) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PUNPCKLBW mm,mm/m64
    else if (b2 == 8'h61) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PUNPCKLWD mm,mm/m64
    else if (b2 == 8'h62) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PUNPCKLDQ mm,mm/m64
    else if (b2 == 8'h63) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PACKSSWB mm,mm/m64
    else if (b2 == 8'h64) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PCMPGTB mm,mm/m64
    else if (b2 == 8'h65) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PCMPGTW mm,mm/m64
    else if (b2 == 8'h66) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PCMPGTD mm,mm/m64
    else if (b2 == 8'h67) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PACKUSWB mm,mm/m64
    else if (b2 == 8'h68) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PUNPCKHBW mm,mm/m64
    else if (b2 == 8'h69) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PUNPCKHWD mm,mm/m64
    else if (b2 == 8'h6A) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PUNPCKHDQ mm,mm/m64
    else if (b2 == 8'h6B) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PACKSSDW mm,mm/m64
    else if (b2 == 8'h6C) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PUNPCKLQDQ xmm,xmm/m128
    else if (b2 == 8'h6D) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PUNPCKHQDQ xmm,xmm/m128
    else if (b2 == 8'h6E) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVD mm,r/m32
    else if (b2 == 8'h6F) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVQ mm,mm/m64
    else if (b2 == 8'h70) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // PSHUFW mm,mm/m64,imm8
    else if (b2 == 8'h71) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // PSRLW mm,imm8
    else if (b2 == 8'h72) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // PSRLD mm,imm8
    else if (b2 == 8'h73) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // PSRLQ mm,imm8
    else if (b2 == 8'h74) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PCMPEQB mm,mm/m64
    else if (b2 == 8'h75) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PCMPEQW mm,mm/m64
    else if (b2 == 8'h76) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PCMPEQD mm,mm/m64
    else if (b2 == 8'h77) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // EMMS 
    else if (b2 == 8'h78) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // VMREAD r/m64,r64
    else if (b2 == 8'h79) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // VMWRITE r64,r/m64
    else if (b2 == 8'h7C) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // HADDPD xmm,xmm/m128
    else if (b2 == 8'h7D) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // HSUBPD xmm,xmm/m128
    else if (b2 == 8'h7E) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVD r/m32,mm
    else if (b2 == 8'h7F) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVQ mm/m64,mm
    else if (b2 == 8'h80) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JO rel16/32
    else if (b2 == 8'h81) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JNO rel16/32
    else if (b2 == 8'h82) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JB rel16/32
    else if (b2 == 8'h83) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JNB rel16/32
    else if (b2 == 8'h84) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JZ rel16/32
    else if (b2 == 8'h85) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JNZ rel16/32
    else if (b2 == 8'h86) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JBE rel16/32
    else if (b2 == 8'h87) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JNBE rel16/32
    else if (b2 == 8'h88) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JS rel16/32
    else if (b2 == 8'h89) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JNS rel16/32
    else if (b2 == 8'h8A) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JP rel16/32
    else if (b2 == 8'h8B) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JNP rel16/32
    else if (b2 == 8'h8C) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JL rel16/32
    else if (b2 == 8'h8D) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JNL rel16/32
    else if (b2 == 8'h8E) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JLE rel16/32
    else if (b2 == 8'h8F) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_IZ; end // JNLE rel16/32
    else if (b2 == 8'h90) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETO r/m8
    else if (b2 == 8'h91) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETNO r/m8
    else if (b2 == 8'h92) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETB r/m8
    else if (b2 == 8'h93) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETNB r/m8
    else if (b2 == 8'h94) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETZ r/m8
    else if (b2 == 8'h95) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETNZ r/m8
    else if (b2 == 8'h96) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETBE r/m8
    else if (b2 == 8'h97) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETNBE r/m8
    else if (b2 == 8'h98) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETS r/m8
    else if (b2 == 8'h99) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETNS r/m8
    else if (b2 == 8'h9A) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETP r/m8
    else if (b2 == 8'h9B) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETNP r/m8
    else if (b2 == 8'h9C) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETL r/m8
    else if (b2 == 8'h9D) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETNL r/m8
    else if (b2 == 8'h9E) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETLE r/m8
    else if (b2 == 8'h9F) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SETNLE r/m8
    else if (b2 == 8'hA0) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // PUSH FS
    else if (b2 == 8'hA1) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // POP FS
    else if (b2 == 8'hA2) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // CPUID IA32_BIOS_SIG…,EAX,ECX,...
    else if (b2 == 8'hA3) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // BT r/m16/32/64,r16/32/64
    else if (b2 == 8'hA4) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // SHLD r/m16/32/64,r16/32/64,imm8
    else if (b2 == 8'hA5) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SHLD r/m16/32/64,r16/32/64,CL
    else if (b2 == 8'hA8) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // PUSH GS
    else if (b2 == 8'hA9) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // POP GS
    else if (b2 == 8'hAA) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // RSM Flags
    else if (b2 == 8'hAB) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // BTS r/m16/32/64,r16/32/64
    else if (b2 == 8'hAC) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // SHRD r/m16/32/64,r16/32/64,imm8
    else if (b2 == 8'hAD) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // SHRD r/m16/32/64,r16/32/64,CL
    else if (b2 == 8'hAE) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // FXSAVE m512,ST,ST1,...
    else if (b2 == 8'hAF) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // IMUL r16/32/64,r/m16/32/64
    else if (b2 == 8'hB0) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMPXCHG r/m8,AL,r8
    else if (b2 == 8'hB1) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMPXCHG r/m16/32/64,rAX,r16/32/64
    else if (b2 == 8'hB2) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // LSS SS,r16/32/64,m16:16/32/64
    else if (b2 == 8'hB3) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // BTR r/m16/32/64,r16/32/64
    else if (b2 == 8'hB4) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // LFS FS,r16/32/64,m16:16/32/64
    else if (b2 == 8'hB5) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // LGS GS,r16/32/64,m16:16/32/64
    else if (b2 == 8'hB6) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVZX r16/32/64,r/m8
    else if (b2 == 8'hB7) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVZX r16/32/64,r/m16
    else if (b2 == 8'hB8) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // POPCNT r16/32/64,r/m16/32/64
    else if (b2 == 8'hB9) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // UD r,r/m
    else if (b2 == 8'hBA) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // BT r/m16/32/64,imm8
    else if (b2 == 8'hBB) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // BTC r/m16/32/64,r16/32/64
    else if (b2 == 8'hBC) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // BSF r16/32/64,r/m16/32/64
    else if (b2 == 8'hBD) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // BSR r16/32/64,r/m16/32/64
    else if (b2 == 8'hBE) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVSX r16/32/64,r/m8
    else if (b2 == 8'hBF) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVSX r16/32/64,r/m16
    else if (b2 == 8'hC0) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // XADD r/m8,r8
    else if (b2 == 8'hC1) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // XADD r/m16/32/64,r16/32/64
    else if (b2 == 8'hC2) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // CMPPS xmm,xmm/m128,imm8
    else if (b2 == 8'hC3) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVNTI m32/64,r32/64
    else if (b2 == 8'hC4) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // PINSRW mm,r32/64,imm8
    else if (b2 == 8'hC5) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // PEXTRW r32/64,mm,imm8
    else if (b2 == 8'hC6) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_IB; end // SHUFPS xmm,xmm/m128,imm8
    else if (b2 == 8'hC7) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CMPXCHG8B m64,EAX,EDX,...
    else if (b2 == 8'hC8) begin valid=1'b1; has_modrm=1'b0; imm_kind=IMM_NONE; end // BSWAP r16/32/64
    else if (b2 == 8'hD0) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // ADDSUBPD xmm,xmm/m128
    else if (b2 == 8'hD1) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSRLW mm,mm/m64
    else if (b2 == 8'hD2) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSRLD mm,mm/m64
    else if (b2 == 8'hD3) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSRLQ mm,mm/m64
    else if (b2 == 8'hD4) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PADDQ mm,mm/m64
    else if (b2 == 8'hD5) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PMULLW mm,mm/m64
    else if (b2 == 8'hD6) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVQ xmm/m64,xmm
    else if (b2 == 8'hD7) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PMOVMSKB r32/64,mm
    else if (b2 == 8'hD8) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSUBUSB mm,mm/m64
    else if (b2 == 8'hD9) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSUBUSW mm,mm/m64
    else if (b2 == 8'hDA) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PMINUB mm,mm/m64
    else if (b2 == 8'hDB) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PAND mm,mm/m64
    else if (b2 == 8'hDC) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PADDUSB mm,mm/m64
    else if (b2 == 8'hDD) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PADDUSW mm,mm/m64
    else if (b2 == 8'hDE) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PMAXUB mm,mm/m64
    else if (b2 == 8'hDF) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PANDN mm,mm/m64
    else if (b2 == 8'hE0) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PAVGB mm,mm/m64
    else if (b2 == 8'hE1) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSRAW mm,mm/m64
    else if (b2 == 8'hE2) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSRAD mm,mm/m64
    else if (b2 == 8'hE3) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PAVGW mm,mm/m64
    else if (b2 == 8'hE4) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PMULHUW mm,mm/m64
    else if (b2 == 8'hE5) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PMULHW mm,mm/m64
    else if (b2 == 8'hE6) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // CVTPD2DQ xmm,xmm/m128
    else if (b2 == 8'hE7) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MOVNTQ m64,mm
    else if (b2 == 8'hE8) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSUBSB mm,mm/m64
    else if (b2 == 8'hE9) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSUBSW mm,mm/m64
    else if (b2 == 8'hEA) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PMINSW mm,mm/m64
    else if (b2 == 8'hEB) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // POR mm,mm/m64
    else if (b2 == 8'hEC) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PADDSB mm,mm/m64
    else if (b2 == 8'hED) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PADDSW mm,mm/m64
    else if (b2 == 8'hEE) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PMAXSW mm,mm/m64
    else if (b2 == 8'hEF) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PXOR mm,mm/m64
    else if (b2 == 8'hF0) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // LDDQU xmm,m128
    else if (b2 == 8'hF1) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSLLW mm,mm/m64
    else if (b2 == 8'hF2) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSLLD mm,mm/m64
    else if (b2 == 8'hF3) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSLLQ mm,mm/m64
    else if (b2 == 8'hF4) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PMULUDQ mm,mm/m64
    else if (b2 == 8'hF5) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PMADDWD mm,mm/m64
    else if (b2 == 8'hF6) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSADBW mm,mm/m64
    else if (b2 == 8'hF7) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // MASKMOVQ m64,mm,mm
    else if (b2 == 8'hF8) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSUBB mm,mm/m64
    else if (b2 == 8'hF9) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSUBW mm,mm/m64
    else if (b2 == 8'hFA) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSUBD mm,mm/m64
    else if (b2 == 8'hFB) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PSUBQ mm,mm/m64
    else if (b2 == 8'hFC) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PADDB mm,mm/m64
    else if (b2 == 8'hFD) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PADDW mm,mm/m64
    else if (b2 == 8'hFE) begin valid=1'b1; has_modrm=1'b1; imm_kind=IMM_NONE; end // PADDD mm,mm/m64
    else begin valid=1'b0; has_modrm=1'b0; imm_kind=IMM_NONE; end // unreachable
  endfunction
  always_comb begin
    def64 = 1'b0;  // TODO: see note on the port above
    unique case (escape)
      ESC_NONE: begin
        opcode1_attrs(opcode_byte, valid, has_modrm, imm_kind);
        opcode_len = valid ? 2'd1 : 2'd0;
      end
      ESC_0F: begin
        opcode0F_attrs(opcode_byte, valid, has_modrm, imm_kind);
        opcode_len = valid ? 2'd2 : 2'd0;  // +1 for the 0F escape byte itself
      end
      default: begin  // ESC_0F38 / ESC_0F3A -- not on coder64.html, not transcribed
        valid      = 1'b0;
        has_modrm  = 1'b0;
        imm_kind   = IMM_NONE;
        opcode_len = 2'd0;
      end
    endcase
  end

endmodule









// ------------------------------------------------------------------
// opcode_invalid_table -- the #UD/reserved-slot check, split out of
// opcode_table so it can be pipelined separately from the (larger)
// has_modrm/imm_kind lookup -- e.g. run as an early cheap reject, or
// put on its own stage; how/when to combine this with opcode_table's
// own `valid` output is left for whoever wires the two together.
// Same source and transcription rules as opcode_table: one `if` per
// byte, straight off http://ref.x86asm.net/coder64.html. Only the
// bytes opcode_table's tables marked "unassigned / #UD" are here --
// prefix bytes (66/67/F0/F2/F3/REX/segment overrides) are NOT included:
// those aren't invalid opcodes, they're valid bytes the prefix scanner
// should already have consumed before anything reaches this table.
// ------------------------------------------------------------------
module opcode_invalid_table(
  input  escape_t    escape,
  input  logic [7:0] opcode_byte,
  output logic       invalid
);

  function automatic logic invalid1(logic [7:0] b);
    if (b == 8'h06) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h07) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h0E) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h16) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h17) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h1E) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h1F) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h27) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h2F) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h37) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h3F) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h60) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h61) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h62) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h82) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'h9A) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'hC4) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'hC5) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'hD4) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'hD5) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'hD6) invalid1 = 1'b1; // unassigned / #UD
    else if (b == 8'hEA) invalid1 = 1'b1; // unassigned / #UD
    else invalid1 = 1'b0;
  endfunction

  function automatic logic invalid0F(logic [7:0] b2);
    if (b2 == 8'h04) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h0A) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h0C) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h0E) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h0F) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h24) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h25) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h26) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h27) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h36) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h39) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h3B) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h3C) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h3D) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h3E) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h3F) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h7A) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'h7B) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'hA6) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'hA7) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'hC9) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'hCA) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'hCB) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'hCC) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'hCD) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'hCE) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'hCF) invalid0F = 1'b1; // unassigned / #UD
    else if (b2 == 8'hFF) invalid0F = 1'b1; // unassigned / #UD
    else invalid0F = 1'b0;
  endfunction

  always_comb begin
    unique case (escape)
      ESC_NONE: invalid = invalid1(opcode_byte);
      ESC_0F:   invalid = invalid0F(opcode_byte);
      default:  invalid = 1'b1;  // ESC_0F38 / ESC_0F3A -- not on coder64.html, not transcribed
    endcase
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
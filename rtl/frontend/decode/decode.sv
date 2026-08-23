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
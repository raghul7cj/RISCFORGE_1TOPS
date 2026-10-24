// =============================================================================
// RISCFORGE 1TOPS — AT24C02 2Kbit I2C EEPROM Slave VIP (i2c_eeprom_at24c02.sv)
// =============================================================================

`timescale 1ns/1ps

module i2c_eeprom_at24c02 #(
  parameter logic [6:0] I2C_ADDR = 7'h50 // 0b1010000
)(
  input  logic scl,
  inout  wire  sda
);

  logic [7:0] memory [0:255];
  logic [7:0] mem_addr;
  logic [7:0] shift_in;
  logic [7:0] shift_out;
  logic       sda_out;
  logic       sda_en;

  assign sda = (sda_en && !sda_out) ? 1'b0 : 1'bz;

  typedef enum logic [2:0] {
    S_IDLE,
    S_DEV_ADDR,
    S_DEV_ACK,
    S_MEM_ADDR,
    S_MEM_ACK,
    S_WRITE_DATA,
    S_WRITE_ACK,
    S_READ_DATA
  } state_e;

  state_e state;
  int bit_idx;
  logic is_read;

  initial begin
    state    = S_IDLE;
    sda_en   = 1'b0;
    sda_out  = 1'b1;
    mem_addr = '0;
    for (int i = 0; i < 256; i++) memory[i] = 8'hA5 ^ i[7:0];
  end

  // START and STOP condition detection
  always @(negedge sda) begin
    if (scl) begin
      // START condition
      state   <= S_DEV_ADDR;
      bit_idx <= 7;
      sda_en  <= 1'b0;
    end
  end

  always @(posedge sda) begin
    if (scl) begin
      // STOP condition
      state  <= S_IDLE;
      sda_en <= 1'b0;
    end
  end

  // State machine clocked on SCL
  always @(posedge scl) begin
    case (state)
      S_DEV_ADDR: begin
        shift_in[bit_idx] <= sda;
      end
      S_MEM_ADDR: begin
        shift_in[bit_idx] <= sda;
      end
      S_WRITE_DATA: begin
        shift_in[bit_idx] <= sda;
      end
      default: ;
    endcase
  end

  always @(negedge scl) begin
    case (state)
      S_DEV_ADDR: begin
        if (bit_idx == 0) begin
          if (shift_in[7:1] == I2C_ADDR) begin
            is_read <= shift_in[0];
            state   <= S_DEV_ACK;
            sda_en  <= 1'b1;
            sda_out <= 1'b0; // Send ACK
          end else begin
            state  <= S_IDLE;
            sda_en <= 1'b0;
          end
        end else begin
          bit_idx <= bit_idx - 1;
        end
      end

      S_DEV_ACK: begin
        sda_en <= 1'b0;
        bit_idx <= 7;
        if (is_read) begin
          state     <= S_READ_DATA;
          shift_out <= memory[mem_addr];
          sda_en    <= 1'b1;
          sda_out   <= memory[mem_addr][7];
        end else begin
          state <= S_MEM_ADDR;
        end
      end

      S_MEM_ADDR: begin
        if (bit_idx == 0) begin
          mem_addr <= shift_in;
          state    <= S_MEM_ACK;
          sda_en   <= 1'b1;
          sda_out  <= 1'b0; // Send ACK
        end else begin
          bit_idx <= bit_idx - 1;
        end
      end

      S_MEM_ACK: begin
        sda_en  <= 1'b0;
        bit_idx <= 7;
        state   <= S_WRITE_DATA;
      end

      S_WRITE_DATA: begin
        if (bit_idx == 0) begin
          memory[mem_addr] <= shift_in;
          mem_addr         <= mem_addr + 1;
          state            <= S_WRITE_ACK;
          sda_en           <= 1'b1;
          sda_out          <= 1'b0; // Send ACK
        end else begin
          bit_idx <= bit_idx - 1;
        end
      end

      S_WRITE_ACK: begin
        sda_en  <= 1'b0;
        bit_idx <= 7;
        state   <= S_WRITE_DATA;
      end

      S_READ_DATA: begin
        if (bit_idx == 0) begin
          sda_en   <= 1'b0; // Wait for Master ACK/NACK
          mem_addr <= mem_addr + 1;
          state    <= S_IDLE;
        end else begin
          bit_idx   <= bit_idx - 1;
          sda_out   <= shift_out[bit_idx - 1];
        end
      end

      default: ;
    endcase
  end

endmodule

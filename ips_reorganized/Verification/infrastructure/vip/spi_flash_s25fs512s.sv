/* =============================================================================
 * RISCFORGE 1TOPS — Lightweight SPI Flash S25FS512S BFM (spi_flash_s25fs512s.sv)
 * Emulates JEDEC ID (0x9F), Read (0x03), Fast Read (0x0B), Write Enable (0x06)
 * ============================================================================= */

`timescale 1ns / 1ps

module spi_flash_s25fs512s #(
    parameter int MEM_SIZE_BYTES = 65536
) (
    input  wire spi_clk,
    input  wire spi_csn,
    input  wire spi_si,
    output wire spi_so
);

    logic [7:0] flash_mem [0:MEM_SIZE_BYTES-1];
    logic [7:0] shift_in;
    logic [7:0] shift_out;
    logic       so_drive;
    int         bit_cnt;
    logic [7:0] opcode;
    logic [23:0] addr;
    logic       wel; // Write enable latch

    task automatic preload_hex(input string hex_file);
        $readmemh(hex_file, flash_mem);
        $display("[SPI_FLASH_BFM] Preloaded memory from %s", hex_file);
    endtask

    wire sck = spi_clk;
    wire csn = spi_csn;
    wire si  = spi_si;
    assign spi_so = (so_drive && !csn) ? shift_out[7] : 1'bz;

    typedef enum logic [2:0] {
        IDLE,
        RECV_CMD,
        RECV_ADDR,
        DUMMY,
        SEND_DATA,
        RECV_DATA
    } state_t;

    state_t state;

    /* Initialize memory */
    initial begin
        for (int i = 0; i < MEM_SIZE_BYTES; i++) begin
            flash_mem[i] = 8'hFF;
        end
        wel = 1'b0;
        state = IDLE;
        bit_cnt = 0;
        so_drive = 1'b0;
    end

    /* SPI SCK Rising Edge: Sample SI */
    always @(posedge sck or posedge csn) begin
        if (csn) begin
            state <= IDLE;
            bit_cnt <= 0;
            so_drive <= 1'b0;
        end else begin
            shift_in <= {shift_in[6:0], si};
            bit_cnt <= bit_cnt + 1;

            case (state)
                IDLE: begin
                    state <= RECV_CMD;
                    bit_cnt <= 1;
                end

                RECV_CMD: begin
                    if (bit_cnt == 8) begin
                        opcode <= {shift_in[6:0], si};
                        bit_cnt <= 0;
                        case ({shift_in[6:0], si})
                            8'h9F: begin /* JEDEC Read ID: Manufacturer=0x01, Device=0x02, Capacity=0x19 */
                                state <= SEND_DATA;
                                shift_out <= 8'h01;
                                so_drive <= 1'b1;
                            end
                            8'h06: begin /* Write Enable */
                                wel <= 1'b1;
                                state <= IDLE;
                            end
                            8'h04: begin /* Write Disable */
                                wel <= 1'b0;
                                state <= IDLE;
                            end
                            8'h05: begin /* Read Status */
                                state <= SEND_DATA;
                                shift_out <= {6'b0, wel, 1'b0};
                                so_drive <= 1'b1;
                            end
                            8'h03: begin /* Read Data */
                                state <= RECV_ADDR;
                            end
                            default: state <= IDLE;
                        endcase
                    end
                end

                RECV_ADDR: begin
                    if (bit_cnt == 24) begin
                        addr <= {shift_in[22:0], si};
                        bit_cnt <= 0;
                        state <= SEND_DATA;
                        shift_out <= flash_mem[{shift_in[22:0], si} % MEM_SIZE_BYTES];
                        so_drive <= 1'b1;
                    end
                end

                SEND_DATA: begin
                    if (bit_cnt == 8) begin
                        bit_cnt <= 0;
                        addr <= addr + 1;
                        if (opcode == 8'h9F) begin
                            shift_out <= 8'h19; /* Next byte of ID */
                        end else begin
                            shift_out <= flash_mem[(addr + 1) % MEM_SIZE_BYTES];
                        end
                    end
                end
            endcase
        end
    end

    /* SPI SCK Falling Edge: Shift OUT */
    always @(negedge sck or posedge csn) begin
        if (csn) begin
            so_drive <= 1'b0;
        end else if (state == SEND_DATA) begin
            if (bit_cnt > 0 && bit_cnt <= 7) begin
                shift_out <= {shift_out[6:0], 1'b0};
            end
        end
    end

endmodule

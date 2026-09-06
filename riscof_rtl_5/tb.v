`timescale 1ns / 1ps

module tb();

    // System signals
    reg clk;
    reg rst;
    wire PCSrcE1; // Debug wire connected to top.v

    // Instantiate the Top Level RISC-V Pipeline Module
    top uut (
        .clk(clk),
        .rst(rst),
        .PCSrcE1(PCSrcE1)
    );

    // Clock Generator: Create a 10ns clock period (100MHz)
    // Flips the clock signal every 5 nanoseconds
    always #5 clk = ~clk;

    initial begin
        // 1. Setup VCD to dump waveform output (can be viewed later in GTKWave)
        $dumpfile("waveform.vcd");
        // Dump all variables in module instances starting downwards from 'tb'
        $dumpvars(0, tb);   

        // 2. Initialize signals
        clk = 0;
        
        // Assert the active-low reset
        rst = 0;           
        
        // Wait 20ns, then release reset to start the processor
        #20;
        rst = 1;       

        // 3. Wait for the program to execute.
        // Longer programs (e.g., bubble sort) need more cycles.
        // 3000ns = 300 cycles at 100MHz.
        #3000;
        
        // 4. Dump all register values
        dump_registers;

        // 5. Finish the simulation manually
        $display("--------------------------------");
        $display("- Simulation Execution Finished-");
        $display("--------------------------------");
        $finish; 
    end

    // ================================================================
    // Task: Dump all 32 registers to console and to reg_dump.txt
    // ================================================================
    task dump_registers;
        integer i;
        integer fd;
        begin
            $display("");
            $display("================================================");
            $display("         REGISTER FILE DUMP  (x0 - x31)         ");
            $display("================================================");
            $display("  Reg   |   Hex Value   |  Decimal (signed)");
            $display("--------+---------------+--------------------");

            fd = $fopen("reg_dump.txt", "w");
            $fwrite(fd, "================================================\n");
            $fwrite(fd, "         REGISTER FILE DUMP  (x0 - x31)         \n");
            $fwrite(fd, "================================================\n");
            $fwrite(fd, "  Reg   |   Hex Value   |  Decimal (signed)\n");
            $fwrite(fd, "--------+---------------+--------------------\n");

            for (i = 0; i < 32; i = i + 1) begin
                $display("  x%-2d   |   0x%08h  |  %0d",
                         i,
                         uut.Decode.rf.Register[i],
                         $signed(uut.Decode.rf.Register[i]));
                $fwrite(fd, "  x%-2d   |   0x%08h  |  %0d\n",
                         i,
                         uut.Decode.rf.Register[i],
                         $signed(uut.Decode.rf.Register[i]));
            end

            $display("================================================");
            $fwrite(fd, "================================================\n");
            $fclose(fd);
            $display("[INFO] Register dump saved to reg_dump.txt");
            $display("");
        end
    endtask

endmodule

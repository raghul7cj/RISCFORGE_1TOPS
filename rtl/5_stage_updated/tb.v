`timescale 1ns/1ps

`timescale 1ns/1ps

module tb;
    reg clk;
    reg rst;

    // Instantiate your 5-stage Core
    top dut (
        .clk(clk),
        .rst(rst)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    integer sig_begin, sig_end;
    integer fd, i;

    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb);

        if (!$value$plusargs("begin_signature=%d", sig_begin)) sig_begin = 0;
        if (!$value$plusargs("end_signature=%d", sig_end)) sig_end = 0;

        $readmemh("test.hex", dut.Fetch.IMEM.mem);
        $readmemh("test.hex", dut.Memory.dmem.mem);

        rst = 0;
        #22;
        rst = 1;
    end

    // ----------------------------------------------------
    // PIPELINE HALT DETECTOR
    // ----------------------------------------------------
    integer halt_counter = 0;
    reg halting = 0;

    always @(posedge clk) begin
        if (rst) begin
            // RVMODEL_HALT uses 'j write_tohost' which jumps back 1 instruction.
            // We detect this inside the EX stage!
            if (dut.PCSrcE1 && (dut.Execute.PCTargetE == dut.Execute.PCE || dut.Execute.PCTargetE == (dut.Execute.PCE - 32'd4)) && dut.Execute.PCE != 0) begin
                halting <= 1;
            end
            
            if (halting) begin
                halt_counter <= halt_counter + 1;
                // Give it 5 clock cycles to let the final 'sw' reach the MEM stage and save!
                if (halt_counter > 5) begin 
                    $display("HALT DETECTED at PC = %h", dut.Execute.PCE);
                    fd = $fopen("signature.txt", "w");
                    for (i = sig_begin/4; i < sig_end/4; i = i + 1) begin
                        // MAGIC FIX: Bitwise AND masks the index safely to physical memory bounds
                        $fdisplay(fd, "%08x", dut.Memory.dmem.mem[i & 18'h3FFFF]);
                    end
                    $fclose(fd);
                    $finish;
                end
            end
        end
    end

    // ----------------------------------------------------
    // FALLBACK EMERGENCY TIMEOUT
    // ----------------------------------------------------
    initial begin
        #50000; // 50,000ns is plenty of time for M-extension tests
        $display("SIMULATION TIMEOUT! Force-dumping signature...");
        fd = $fopen("signature.txt", "w");
        for (i = sig_begin/4; i < sig_end/4; i = i + 1) begin
            // We force a dump even on a crash so RISCOF gets actual data!
            $fdisplay(fd, "%08x", dut.Memory.dmem.mem[i & 18'h3FFFF]);
        end
        $fclose(fd);
        $finish;
    end
endmodule

// module tb;
//     reg clk;
//     reg rst;

//     // Instantiate your 5-stage Core
//     top dut (
//         .clk(clk),
//         .rst(rst)
//     );

//     initial begin
//         clk = 0;
//         forever #5 clk = ~clk;
//     end

//     integer sig_begin, sig_end;
//     integer fd, i;

//     initial begin
//         $dumpfile("waveform.vcd");
//         $dumpvars(0, tb);

//         if (!$value$plusargs("begin_signature=%d", sig_begin)) sig_begin = 0;
//         if (!$value$plusargs("end_signature=%d", sig_end)) sig_end = 0;

//         // FIXED PATHS FOR 5-STAGE PIPELINE
//         $readmemh("test.hex", dut.Fetch.IMEM.mem);
//         $readmemh("test.hex", dut.Memory.dmem.mem);

//         rst = 0;
//         #22;
//         rst = 1;
//     end

//     reg [31:0] last_pc;
//     integer stuck_counter = 0;

//     // always @(posedge clk) begin
//     //     if (rst) begin
//     //         // FIXED PC PATH TO FETCH STAGE
//     //         if (dut.Fetch.PCF == last_pc && dut.Fetch.PCF != 0 && dut.Fetch.PCF !== 32'hx) begin
//     //             stuck_counter <= stuck_counter + 1;
//     //             // Wait 5 cycles to ensure it's not just a pipeline stall
//     //             if (stuck_counter > 5) begin
//     //                 $display("HALT DETECTED at PC = %h", dut.Fetch.PCF);
//     //                 fd = $fopen("signature.txt", "w");
//     //                 for (i = sig_begin/4; i < sig_end/4; i = i + 1) begin
//     //                     $fdisplay(fd, "%08x", dut.Memory.dmem.mem[i]);
//     //                 end
//     //                 $fclose(fd);
//     //                 $finish;
//     //             end
//     //         end else begin
//     //             stuck_counter <= 0;
//     //         end
//     //         last_pc <= dut.Fetch.PCF;
//     //     end
//     // end
//     always @(posedge clk) begin
//         if (rst) begin
//             // FIXED PC PATH TO FETCH STAGE
//             if (dut.Fetch.PCF == last_pc && dut.Fetch.PCF != 0 && dut.Fetch.PCF !== 32'hx) begin
//                 stuck_counter <= stuck_counter + 1;
//                 // Wait 5 cycles to ensure it's not just a pipeline stall
//                 if (stuck_counter > 50) begin
//                     $display("HALT DETECTED at PC = %h", dut.Fetch.PCF);
//                     fd = $fopen("signature.txt", "w");
//                     for (i = sig_begin/4; i < sig_end/4; i = i + 1) begin
//                         // MAGIC FIX: Slice the testbench index to match physical memory!
//                         $fdisplay(fd, "%08x", dut.Memory.dmem.mem[i[17:0]]);
//                     end
//                     $fclose(fd);
//                     $finish;
//                 end
//             end else begin
//                 stuck_counter <= 0;
//             end
//             last_pc <= dut.Fetch.PCF;
//         end
//     end
//     initial begin
//         #100000; 
//         $display("SIMULATION TIMEOUT! Processor stuck at PC = %h", dut.Fetch.PCF);
//         $finish;
//     end
// endmodule
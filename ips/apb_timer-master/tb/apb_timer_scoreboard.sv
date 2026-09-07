class apb_timer_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(apb_timer_scoreboard)

    virtual apb_timer_if vif;

    bit [31:0] timer_ref [2];
    bit [31:0] ctrl_ref [2];
    bit [31:0] cmp_ref [2];
    bit [31:0] cycle_ref [2];

    int compare_irq_seen[2];
    int overflow_irq_seen[2];

    int checks;
    int errors;


    function new(string name = "apb_timer_scoreboard",uvm_component parent = null);
        super.new(name, parent);
    endfunction


    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        if (!uvm_config_db#(virtual apb_timer_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Interface not found")

    endfunction


    function bit [31:0] expected_read(bit [11:0] addr);

        int timer_id;
        bit [1:0] reg_id;

        timer_id = addr[4];
        reg_id   = addr[3:2];

        case (reg_id)

            2'b00:
                return timer_ref[timer_id];

            2'b01:
                return ctrl_ref[timer_id];

            2'b10:
                return cmp_ref[timer_id];

            default:
                return 32'b0;

        endcase

    endfunction


    task run_phase(uvm_phase phase);

        bit [3:0] exp_irq;

        bit [31:0] timer_n [2];
        bit [31:0] ctrl_n  [2];
        bit [31:0] cmp_n   [2];
        bit [31:0] cycle_n [2];

        bit [2:0] prescaler;

        int timer_id;
        bit [1:0] reg_id;
        bit [31:0] exp_data;


        forever begin

            @(posedge vif.HCLK);

            if (!vif.HRESETn) begin

                for (int i = 0; i < 2; i++) begin
                    timer_ref[i] = 0;
                    ctrl_ref[i]  = 0;
                    cmp_ref[i]   = 0;
                    cycle_ref[i] = 0;
                end

                continue;

            end


            if (vif.PREADY !== 1'b1) begin
                `uvm_error("PREADY", "PREADY should always be 1")
                errors++;
            end

            if (vif.PSLVERR !== 1'b0) begin
                `uvm_error("PSLVERR", "PSLVERR should always be 0")
                errors++;
            end


            exp_irq = 4'b0;

            for (int i = 0; i < 2; i++) begin

                prescaler = ctrl_ref[i][5:3];

                if ((timer_ref[i] == 32'hFFFF_FFFF) && (prescaler == cycle_ref[i])) begin
                    exp_irq[2*i] = 1'b1;
                    overflow_irq_seen[i]++;
                end
                if ((cmp_ref[i] != 0) && (timer_ref[i] == cmp_ref[i]) && (prescaler == cycle_ref[i])) begin
                    exp_irq[(2*i)+1] = 1'b1;
                    compare_irq_seen[i]++;
                end
            end


            checks++;

            if (vif.irq_o !== exp_irq) begin
                `uvm_error("IRQ", $sformatf("IRQ mismatch expected=%b actual=%b", exp_irq, vif.irq_o))
                errors++;

            end


            if (vif.PSEL && vif.PENABLE && vif.PREADY && !vif.PWRITE) begin
                exp_data = expected_read(vif.PADDR);
                checks++;
                if (vif.PRDATA !== exp_data) begin
                    `uvm_error("READ", $sformatf("addr=0x%0h expected=0x%08h actual=0x%08h", vif.PADDR, exp_data, vif.PRDATA))
                    errors++;
                end
            end


            for (int i = 0; i < 2; i++) begin

                timer_n[i] = timer_ref[i];
                ctrl_n[i]  = ctrl_ref[i];
                cmp_n[i]   = cmp_ref[i];

                cycle_n[i] = cycle_ref[i] + 1;

                prescaler = ctrl_ref[i][5:3];
                if (exp_irq[2*i] || exp_irq[(2*i)+1])
                    timer_n[i] = 0;
                else if (ctrl_ref[i][0] && prescaler != 0 && prescaler == cycle_ref[i])
                    timer_n[i] = timer_ref[i] + 1;
                else if (ctrl_ref[i][0] && prescaler == 0)
                    timer_n[i] = timer_ref[i] + 1;
                if (cycle_ref[i] >= prescaler)
                    cycle_n[i] = 0;

            end


            if (vif.PSEL && vif.PENABLE && vif.PWRITE && vif.PREADY) begin
                timer_id = vif.PADDR[4];
                reg_id   = vif.PADDR[3:2];
                case (reg_id)
                    2'b00:
                        timer_n[timer_id] = vif.PWDATA;
                    2'b01:
                        ctrl_n[timer_id] = vif.PWDATA;
                    2'b10: begin
                        cmp_n[timer_id]   = vif.PWDATA;
                        timer_n[timer_id] = 0;
                    end
                endcase
            end

            for (int i = 0; i < 2; i++) begin
                timer_ref[i] = timer_n[i];
                ctrl_ref[i]  = ctrl_n[i];
                cmp_ref[i]   = cmp_n[i];
                cycle_ref[i] = cycle_n[i];
            end
        end

    endtask


    function void report_phase(uvm_phase phase);

        `uvm_info("SCB",
            $sformatf(
                "Checks=%0d Errors=%0d T0_CMP_IRQ=%0d T0_OVF_IRQ=%0d T1_CMP_IRQ=%0d T1_OVF_IRQ=%0d",
                checks,
                errors,
                compare_irq_seen[0],
                overflow_irq_seen[0],
                compare_irq_seen[1],
                overflow_irq_seen[1]
            ), UVM_NONE)

    endfunction

endclass

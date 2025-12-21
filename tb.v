module cpu_tb;
    localparam CLK_PERIOD = 10;

    reg clk;
    reg rst;
    wire [15:0] address;
    reg  [7:0] din;
    wire [7:0] dout;
    wire read;
    wire write;
    
    reg ce;
    reg irq;
    reg nmi;
    
    reg [15:0] cyc;

    reg [7:0] ram [0:65535];

    CPU cpu (
        .clk(clk),
        .rst(rst),
        .address(address),
        .din(din),
        .dout(dout),
        .read(read),
        .write(write),
        .ce(ce),
        .irq(irq),
        .nmi(nmi)
    );

    initial begin
        clk = 0;
        cyc = 5;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end
    
    always @(posedge clk) begin
        if (rst == 0) begin
            cyc <= cyc + 1;
        end    
    end    

    always @(negedge clk) begin
        if (write) begin
            ram[address] = dout;
            din = 8'hZZ;
        end
    end

    
    always @(negedge clk) begin
        if (read) begin
            din = ram[address];
        end    
    end

    initial begin
        
        $readmemh("nestest_instructions.mem", ram, 16'h7FF0);
        $readmemh("nestest_instructions.mem", ram, 16'hBFF0);
        
        ram[16'hFFFC] = 8'h00;
        ram[16'hFFFD] = 8'hC0;
        
        ce = 1;
        irq = 0;
        nmi = 0;
        
        rst = 1;
        # (CLK_PERIOD * 2);
        rst = 0;
        
        
    end
    
    integer file;
    integer r;
    reg [15:0] log_PC;
    reg [7:0] log_A, log_X, log_Y, log_P, log_SP;
    reg [15:0] log_CYC;
    
    initial begin
        file = $fopen("nestest_verification.mem", "r");
        if (file == 0) begin
            $display("Cannot open file");
            $finish;
        end

        forever begin
            @(posedge clk);
            
            if (cpu.debug_instr_start) begin
                 r = $fscanf(file, "%h %h %h %h %h %d\n", log_A, log_X, log_Y, log_P, log_SP, log_CYC);
                if (r == -1) begin
                    $display("End of file");
                    $finish;
                end
             
                if (cpu.A  !== log_A)  begin
                    $display("Mismatch A at PC=%h: got %h, expected %h",  cpu.PC, cpu.A, log_A);
                    $stop; // pause simulation
                end else
                if (cpu.X  !== log_X)  begin
                    $display("Mismatch X at PC=%h: got %h, expected %h",  cpu.PC, cpu.X, log_X);
                    $stop;
                end else
                if (cpu.Y  !== log_Y)  begin
                    $display("Mismatch Y at PC=%h: got %h, expected %h",  cpu.PC, cpu.Y, log_Y);
                    $stop;
                end else
                if (cpu.P  !== log_P)  begin
                    $display("Mismatch P at PC=%h: got %h, expected %h",  cpu.PC, cpu.P, log_P);
                    $stop;
                end else
                if (cpu.SP !== log_SP) begin
                    $display("Mismatch SP at PC=%h: got %h, expected %h", cpu.PC, cpu.SP, log_SP);
                    $stop;
                end else
                if (cyc !== log_CYC) begin
                    $display("Mismatch CYC at PC=%h: got %d, expected %d", cpu.PC, cyc, log_CYC);
                    $stop;
                end else begin
                    $display("Instruction at PC = %h and CYC %d passed", cpu.PC, cyc);
                end
            end
        end
    end
endmodule
`timescale 1ns / 1ps

    module CPU (
        input wire clk,
        input wire ce,
        input wire rst,
        input wire [7:0] din,
        input wire irq,
        input wire nmi,
        output reg [7:0] dout,
        output reg [15:0] address,
        output reg read,
        output reg write
    );
    
    // 6502 registers
    reg [7:0] A;
    reg [7:0] X;
    reg [7:0] Y;
    reg [7:0] SP;
    reg [15:0] PC;
    reg [7:0] P;
    
    localparam
        C = 0,  // Carry
        Z = 1,  // Zero
        I = 2,  // Interrupt Disable
        D = 3,  // Decimal
        B = 4,  // Break
        U = 5,  // Unused
        V = 6,  // Overflow
        N = 7;  // Negative

    reg [7:0] IR;

    reg [2:0] cycle;

    reg nmi_prev;
    reg nmi_pending;
    reg nmi_in_progress;
    reg nmi_reset;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            nmi_prev <= 1'b0;
            nmi_pending <= 1'b0;
        end else begin
            if (!loading_vector && !reset_sequence) begin
                nmi_prev <= nmi;
            end

            nmi_pending <= nmi_in_progress;
        end
    end

    always @(*) begin
        if (nmi && !nmi_prev && !loading_vector && !reset_sequence) begin
            nmi_in_progress <= 1'b1;
        end else if (loading_vector && nmi_reset) begin
            nmi_in_progress <= 1'b0;
        end else begin
            nmi_in_progress <= nmi_pending;
        end
    end

    reg [15:0] interrupt_vector;
    reg [1:0] interrupt_type;
    wire in_interrupt;
    reg in_interrupt_continue;
    wire enter_interrupt;
    assign enter_interrupt = (irq & ~P[I]) | nmi_in_progress;
    assign in_interrupt = (cycle == 3'b000) ? enter_interrupt : in_interrupt_continue;

    reg [7:0] din_low;
    reg [7:0] din_high;
    reg [7:0] ind_offset;
    reg [8:0] adc_temp;

    wire [7:0] inx_temp;
    assign inx_temp = X + 1;
    wire [7:0] iny_temp;
    assign iny_temp = Y + 1;
    wire [7:0] dex_temp;
    assign dex_temp = X - 1;
    wire [7:0] dey_temp;
    assign dey_temp = Y - 1;

    wire [7:0] cmp_temp;
    assign cmp_temp = (A-din);
    wire [7:0] cpx_temp;
    assign cpx_temp = (X-din);
    wire [7:0] cpy_temp;
    assign cpy_temp = (Y-din);

    reg [15:0] jsr_temp;

    reg page_crossed;

    reg reset_sequence;

    wire [15:0] pc_plus_2_unless_in_interrupt;
    assign pc_plus_2_unless_in_interrupt = in_interrupt ? PC : PC + 2;

    reg loading_vector;

    wire debug_instr_start;
    assign debug_instr_start = (cycle == 0) & (~rst) & (~reset_sequence);
    
    
    always @(posedge clk) begin
        if (rst) begin
            PC      <= 16'hFFFC;
            A       <= 8'd0;
            X       <= 8'd0;
            Y       <= 8'd0;
            SP      <= 8'hFD;
            P       <= 8'b00100100;
            IR      <= 8'd0;
            address <= 16'hFFFC;
            read    <= 1;
            write   <= 0;
            dout    <= 8'd0;
            cycle <= 3'b000;
            reset_sequence <= 1;
            page_crossed <= 0;
            in_interrupt_continue <= 1'b0;
            interrupt_vector <= 16'h0000;
            interrupt_type <= 2'b00;
            loading_vector <= 0;
        end else if (ce) begin
            if (cycle == 3'b000) begin
                in_interrupt_continue <= enter_interrupt;
//                reset_sequence <= 0;
            end
            
            if (reset_sequence) begin
                if (cycle == 3'b000) begin
                    address <= address + 1;
                    din_low <= din;
                    cycle <= 3'b001;
                end else if (cycle <= 3'b001) begin
                    address <= {din, din_low};
                    PC <= {din, din_low};
                    cycle <= 3'b000;
                    reset_sequence <= 0;
                end
            end
            else begin
                if (cycle == 3'b000) begin
                    read <= 1;
                    write <= 0;
                    if (!in_interrupt) begin
                        IR <= din;
                        address <= PC + 1;
                    end else begin
                        IR <= 8'b0;
                    end
                    cycle <= 3'b001;
                end else begin
                    case (IR)
                        // LDA immediate
                        8'hA9: begin
                            case (cycle)
                                3'b001: begin
                                    A <= din;
                                    PC <= PC+2;
                                    address <= PC+2;
                                    cycle <= 3'b000;

                                    P[N] <= din[7];
                                    P[Z] <= (din == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // LDA absolute
                        8'hAD: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    A <= din;
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b000;

                                    P[N] <= din[7];
                                    P[Z] <= (din == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // LDA zero page
                        8'hA5: begin
                            case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    A <= din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;

                                    P[N] <= din[7];
                                    P[Z] <= (din == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // LDA ind X
                        8'hA1: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + X + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    A <= din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;

                                    P[N] <= din[7];
                                    P[Z] <= (din == 0) ? 1 : 0;
                                end

                                3'b111: begin // dummy cycle to match datasheet
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // LDA ind Y
                        8'hB1: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + 1) & 8'hFF};

                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    address <= {din, din_low} + Y;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        A <= din;
                                        address <= PC+2;
                                        PC <= PC+2;
                                        cycle <= 3'b000;

                                        P[N] <= din[7];
                                        P[Z] <= (din == 0) ? 1 : 0;
                                    end
                                end
                            endcase
                        end
                        // LDA zero page X
                        8'hB5: begin
                            case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    A <= din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;

                                    P[N] <= din[7];
                                    P[Z] <= (din == 0) ? 1 : 0;
                                end

                                3'b111: begin //dummy cycle
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // LDA absolute X
                        8'hBD: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low} + X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        A <= din;
                                        address <= PC+3;
                                        PC <= PC+3;
                                        cycle <= 3'b000;

                                        P[N] <= din[7];
                                        P[Z] <= (din == 0) ? 1 : 0;
                                    end
                                end
                            endcase
                        end
                        // LDA absolute Y
                        8'hB9: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low}+Y;
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        A <= din;
                                        address <= PC+3;
                                        PC <= PC+3;
                                        cycle <= 3'b000;

                                        P[N] <= din[7];
                                        P[Z] <= (din == 0) ? 1 : 0;
                                    end
                                end
                            endcase
                        end
                        // LDX immedaite
                        8'hA2: begin
                            case (cycle)
                                3'b001: begin
                                    X <= din;
                                    PC <= PC+2;
                                    address <= PC+2;
                                    cycle <= 3'b000;

                                    P[N] <= din[7];
                                    P[Z] <= (din == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // LDX absolute
                        8'hAE: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    X <= din;
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b000;

                                    P[N] <= din[7];
                                    P[Z] <= (din == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // LDX zero page
                        8'hA6: begin
                            case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    X <= din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;

                                    P[N] <= din[7];
                                    P[Z] <= (din == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // LDX absolute Y
                        8'hBE: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low}+Y;
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        X <= din;
                                        address <= PC+3;
                                        PC <= PC+3;
                                        cycle <= 3'b000;

                                        P[N] <= din[7];
                                        P[Z] <= (din == 0) ? 1 : 0;
                                    end
                                end
                            endcase
                        end
                        // LDX zero page Y
                        8'hB6: begin
                            case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + Y) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    X <= din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;

                                    P[N] <= din[7];
                                    P[Z] <= (din == 0) ? 1 : 0;
                                end

                                3'b111: begin //dummy cycle
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // LDY immedaite
                        8'hA0: begin
                            case (cycle)
                                3'b001: begin
                                    Y <= din;
                                    PC <= PC+2;
                                    address <= PC+2;
                                    cycle <= 3'b000;

                                    P[N] <= din[7];
                                    P[Z] <= (din == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // LDY absolute
                        8'hAC: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    Y <= din;
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b000;

                                    P[N] <= din[7];
                                    P[Z] <= (din == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // LDY zero page
                        8'hA4: begin
                            case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    Y <= din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;

                                    P[N] <= din[7];
                                    P[Z] <= (din == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // LDY zero page X
                        8'hB4: begin
                            case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    Y <= din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;

                                    P[N] <= din[7];
                                    P[Z] <= (din == 0) ? 1 : 0;
                                end

                                3'b111: begin //dummy cycle
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // LDY absolute X
                        8'hBC: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low}+X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        Y <= din;
                                        address <= PC+3;
                                        PC <= PC+3;
                                        cycle <= 3'b000;

                                        P[N] <= din[7];
                                        P[Z] <= (din == 0) ? 1 : 0;
                                    end
                                end
                            endcase
                        end
                        // TAX
                        8'hAA: begin
                            case (cycle)
                                3'b001: begin
                                    X <= A;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[N] <= A[7];
                                    P[Z] <= (A == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // TAY
                        8'hA8: begin
                            case (cycle)
                                3'b001: begin
                                    Y <= A;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[N] <= A[7];
                                    P[Z] <= (A == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // TSX
                        8'hBA: begin
                            case (cycle)
                                3'b001: begin
                                    X <= SP;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[N] <= SP[7];
                                    P[Z] <= (SP == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // TXA
                        8'h8A: begin
                            case (cycle)
                                3'b001: begin
                                    A <= X;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[N] <= X[7];
                                    P[Z] <= (X == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // TXS
                        8'h9A: begin
                            case (cycle)
                                3'b001: begin
                                    SP <= X;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // TYA
                        8'h98: begin
                            case (cycle)
                                3'b001: begin
                                    A <= Y;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[N] <= Y[7];
                                    P[Z] <= (Y == 0) ? 1 : 0;
                                end
                            endcase
                        end
                        // STA absolute
                        8'h8D: begin
                            case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= {din, din_low};
                                    dout <= A;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b000;
                                    read <= 1;
                                    write <= 0;
                                end
                            endcase
                        end
                        // STA zero page
                        8'h85: begin
                            case (cycle)
                                3'b001: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= din;
                                    dout <= A;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;
                                    read <= 1;
                                    write <= 0;
                                end
                            endcase
                        end
                        // STA ind X
                        8'h81: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + X + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= {din, din_low};
                                    dout <= A;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;
                                    read <= 1;
                                    write <= 0;
                                end

                                3'b111: begin // dummy cycle to match datasheet
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // STA ind Y
                        8'h91: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    read <= 0;
                                    write <= 1;
                                    address <= {din, din_low} + Y;
                                    dout <= A;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        address <= PC+2;
                                        PC <= PC+2;
                                        cycle <= 3'b101;
                                        read <= 1;
                                        write <= 0;
                                    end
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // STA zero page X
                        8'h95: begin
                            case (cycle)
                                3'b001: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    dout <= A;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;
                                    read <= 1;
                                    write <= 0;
                                end

                                3'b111: begin //dummy cycle
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // STA absolute X
                        8'h9D: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= {din, din_low} + X;
                                    dout <= A;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // STA absolute Y
                        8'h99: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= {din, din_low}+Y;
                                    dout <= A;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // STX absolute
                        8'h8E: begin
                            case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= {din, din_low};
                                    dout <= X;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b000;
                                    read <= 1;
                                    write <= 0;
                                end
                            endcase
                        end
                        // STX zero page
                        8'h86: begin
                            case (cycle)
                                3'b001: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= din;
                                    dout <= X;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;
                                    read <= 1;
                                    write <= 0;
                                end
                            endcase
                        end
                        // STX zero page Y
                        8'h96: begin
                            case (cycle)
                                3'b001: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= {8'h00, (din + Y) & 8'hFF};
                                    dout <= X;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;
                                    read <= 1;
                                    write <= 0;
                                end

                                3'b111: begin //dummy cycle
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // STY absolute
                        8'h8C: begin
                            case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= {din, din_low};
                                    dout <= Y;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b000;
                                    read <= 1;
                                    write <= 0;
                                end
                            endcase
                        end
                        // STY zero page
                        8'h84: begin
                            case (cycle)
                                3'b001: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= din;
                                    dout <= Y;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;
                                    read <= 1;
                                    write <= 0;
                                end
                            endcase
                        end
                        // STY zero page X
                        8'h94: begin
                            case (cycle)
                                3'b001: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    dout <= Y;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;
                                    read <= 1;
                                    write <= 0;
                                end

                                3'b111: begin //dummy cycle
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ADC immediate
                        8'h69: begin
                            case (cycle)
                                3'b001: begin
                                    adc_temp = A + din + P[C];

                                    A <= adc_temp[7:0];

                                    P[C] <= adc_temp[8];
                                    P[Z] <= (adc_temp[7:0] == 8'b0);
                                    P[N] <= adc_temp[7];
                                    P[V] <= (~(A[7] ^ din[7])) & (A[7] ^ adc_temp[7]);

                                    address <= PC + 2;
                                    PC <= PC + 2;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ADC absolute
                        8'h6D: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    adc_temp = A + din + P[C];

                                    A <= adc_temp[7:0];

                                    P[C] <= adc_temp[8];
                                    P[Z] <= (adc_temp[7:0] == 8'b0);
                                    P[N] <= adc_temp[7];
                                    P[V] <= (~(A[7] ^ din[7])) & (A[7] ^ adc_temp[7]);

                                    address <= PC+3;
                                    PC <= PC + 3;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ADC zero page
                        8'h65: begin
                            case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    adc_temp = A + din + P[C];

                                    A <= adc_temp[7:0];

                                    P[C] <= adc_temp[8];
                                    P[Z] <= (adc_temp[7:0] == 8'b0);
                                    P[N] <= adc_temp[7];
                                    P[V] <= (~(A[7] ^ din[7])) & (A[7] ^ adc_temp[7]);

                                    address <= PC+2;
                                    PC <= PC + 2;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ADC ind X
                        8'h61: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + X + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end
                                3'b011: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    adc_temp = A + din + P[C];

                                    A <= adc_temp[7:0];

                                    P[C] <= adc_temp[8];
                                    P[Z] <= (adc_temp[7:0] == 8'b0);
                                    P[N] <= adc_temp[7];
                                    P[V] <= (~(A[7] ^ din[7])) & (A[7] ^ adc_temp[7]);

                                    address <= PC+2;
                                    PC <= PC + 2;
                                    cycle <= 3'b111;
                                end

                                3'b111: begin // dummy cycle to match datasheet
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ADC ind Y
                        8'h71: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    address <= {din, din_low} + Y;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        adc_temp = A + din + P[C];

                                        A <= adc_temp[7:0];

                                        P[C] <= adc_temp[8];
                                        P[Z] <= (adc_temp[7:0] == 8'b0);
                                        P[N] <= adc_temp[7];
                                        P[V] <= (~(A[7] ^ din[7])) & (A[7] ^ adc_temp[7]);

                                        address <= PC+2;
                                        PC <= PC + 2;
                                        cycle <= 3'b000;
                                    end
                                end
                            endcase
                        end
                        // ADC zero page X
                        8'h75: begin
                            case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    adc_temp = A + din + P[C];

                                    A <= adc_temp[7:0];

                                    P[C] <= adc_temp[8];
                                    P[Z] <= (adc_temp[7:0] == 8'b0);
                                    P[N] <= adc_temp[7];
                                    P[V] <= (~(A[7] ^ din[7])) & (A[7] ^ adc_temp[7]);

                                    address <= PC+2;
                                    PC <= PC + 2;
                                    cycle <= 3'b111;
                                end

                                3'b111: begin //dummy cycle
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ADC absolute X
                        8'h7D: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low} + X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        adc_temp = A + din + P[C];

                                        A <= adc_temp[7:0];

                                        P[C] <= adc_temp[8];
                                        P[Z] <= (adc_temp[7:0] == 8'b0);
                                        P[N] <= adc_temp[7];
                                        P[V] <= (~(A[7] ^ din[7])) & (A[7] ^ adc_temp[7]);

                                        address <= PC+3;
                                        PC <= PC + 3;
                                        cycle <= 3'b000;
                                    end
                                end
                            endcase
                        end
                        // ADC absolute Y
                        8'h79: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low}+Y;
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        adc_temp = A + din + P[C];

                                        A <= adc_temp[7:0];

                                        P[C] <= adc_temp[8];
                                        P[Z] <= (adc_temp[7:0] == 8'b0);
                                        P[N] <= adc_temp[7];
                                        P[V] <= (~(A[7] ^ din[7])) & (A[7] ^ adc_temp[7]);

                                        address <= PC+3;
                                        PC <= PC + 3;
                                        cycle <= 3'b000;
                                    end
                                end
                            endcase
                        end
                        // SBC immediate
                        8'hE9: begin
                            case (cycle)
                                3'b001: begin
                                    adc_temp = {1'b0, A} - {1'b0, din} - (1'b1 - P[C]);

                                    A <= adc_temp[7:0];

                                    P[C] <= ~adc_temp[8];
                                    P[Z] <= (adc_temp[7:0] == 8'b0);
                                    P[N] <= adc_temp[7];
                                    P[V] <= (A[7] ^ din[7]) & (A[7] ^ adc_temp[7]);

                                    address <= PC + 2;
                                    PC <= PC + 2;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // SBC absolute
                        8'hED: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    adc_temp = {1'b0, A} - {1'b0, din} - (1'b1 - P[C]);

                                    A <= adc_temp[7:0];

                                    P[C] <= ~adc_temp[8];
                                    P[Z] <= (adc_temp[7:0] == 8'b0);
                                    P[N] <= adc_temp[7];
                                    P[V] <= (A[7] ^ din[7]) & (A[7] ^ adc_temp[7]);

                                    address <= PC + 3;
                                    PC <= PC + 3;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // SBC zero page
                        8'hE5: begin
                            case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    adc_temp = {1'b0, A} - {1'b0, din} - (1'b1 - P[C]);

                                    A <= adc_temp[7:0];

                                    P[C] <= ~adc_temp[8];
                                    P[Z] <= (adc_temp[7:0] == 8'b0);
                                    P[N] <= adc_temp[7];
                                    P[V] <= (A[7] ^ din[7]) & (A[7] ^ adc_temp[7]);

                                    address <= PC + 2;
                                    PC <= PC + 2;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // SBC ind X
                        8'hE1: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + X + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    adc_temp = {1'b0, A} - {1'b0, din} - (1'b1 - P[C]);

                                    A <= adc_temp[7:0];

                                    P[C] <= ~adc_temp[8];
                                    P[Z] <= (adc_temp[7:0] == 8'b0);
                                    P[N] <= adc_temp[7];
                                    P[V] <= (A[7] ^ din[7]) & (A[7] ^ adc_temp[7]);

                                    address <= PC + 2;
                                    PC <= PC + 2;
                                    cycle <= 3'b111;
                                end

                                3'b111: begin // dummy cycle to match datasheet
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // EBC ind Y
                        8'hF1: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    address <= {din, din_low} + Y;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        adc_temp = {1'b0, A} - {1'b0, din} - (1'b1 - P[C]);

                                        A <= adc_temp[7:0];

                                        P[C] <= ~adc_temp[8];
                                        P[Z] <= (adc_temp[7:0] == 8'b0);
                                        P[N] <= adc_temp[7];
                                        P[V] <= (A[7] ^ din[7]) & (A[7] ^ adc_temp[7]);

                                        address <= PC + 2;
                                        PC <= PC + 2;
                                        cycle <= 3'b000;
                                     end
                                end
                            endcase
                        end
                        // SBC zero page X
                        8'hF5: begin
                            case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    adc_temp = {1'b0, A} - {1'b0, din} - (1'b1 - P[C]);

                                    A <= adc_temp[7:0];

                                    P[C] <= ~adc_temp[8];
                                    P[Z] <= (adc_temp[7:0] == 8'b0);
                                    P[N] <= adc_temp[7];
                                    P[V] <= (A[7] ^ din[7]) & (A[7] ^ adc_temp[7]);

                                    address <= PC + 2;
                                    PC <= PC + 2;
                                    cycle <= 3'b111;
                                end

                                3'b111: begin //dummy cycle
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // SBC absolute X
                        8'hFD: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low} + X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        adc_temp = {1'b0, A} - {1'b0, din} - (1'b1 - P[C]);

                                        A <= adc_temp[7:0];

                                        P[C] <= ~adc_temp[8];
                                        P[Z] <= (adc_temp[7:0] == 8'b0);
                                        P[N] <= adc_temp[7];
                                        P[V] <= (A[7] ^ din[7]) & (A[7] ^ adc_temp[7]);

                                        address <= PC+3;
                                        PC <= PC + 3;
                                        cycle <= 3'b000;
                                    end
                                end
                            endcase
                        end
                        // SBC absolute Y
                        8'hF9: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low}+Y;
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        adc_temp = {1'b0, A} - {1'b0, din} - (1'b1 - P[C]);

                                        A <= adc_temp[7:0];

                                        P[C] <= ~adc_temp[8];
                                        P[Z] <= (adc_temp[7:0] == 8'b0);
                                        P[N] <= adc_temp[7];
                                        P[V] <= (A[7] ^ din[7]) & (A[7] ^ adc_temp[7]);

                                        address <= PC+3;
                                        PC <= PC + 3;
                                        cycle <= 3'b000;
                                    end
                                end
                            endcase
                        end
                        // AND immediate
                        8'h29: begin
                            case (cycle)
                                3'b001: begin
                                    A <= A & din;
                                    PC <= PC+2;
                                    address <= PC+2;
                                    cycle <= 3'b000;

                                    P[N] <= (A[7] & din[7]);
                                    P[Z] <= (A & din) == 0;
                                end
                            endcase
                        end
                        // AND absolute
                        8'h2D: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    A <= A & din;
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b000;

                                    P[N] <= (A[7] & din[7]);
                                    P[Z] <= (A & din) == 0;
                                end
                            endcase
                        end
                        // AND zero page
                        8'h25: begin
                            case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    A <= A & din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;

                                    P[N] <= (A[7] & din[7]);
                                    P[Z] <= (A & din) == 0;
                                end
                            endcase
                        end
                        // AND ind X
                        8'h21: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + X + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    A <= A & din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;

                                    P[N] <= (A[7] & din[7]);
                                    P[Z] <= (A & din) == 0;
                                end

                                3'b111: begin // dummy cycle to match datasheet
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // AND ind Y
                        8'h31: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    address <= {din, din_low} + Y;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        A <= A & din;
                                        address <= PC+2;
                                        PC <= PC+2;
                                        cycle <= 3'b000;

                                        P[N] <= (A[7] & din[7]);
                                        P[Z] <= (A & din) == 0;
                                    end
                                end
                            endcase
                        end
                        // AND zero page X
                        8'h35: begin
                            case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    A <= A & din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;

                                    P[N] <= (A[7] & din[7]);
                                    P[Z] <= (A & din) == 0;
                                end

                                3'b111: begin //dummy cycle
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // AND absolute X
                        8'h3D: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low} + X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        A <= A & din;
                                        address <= PC+3;
                                        PC <= PC+3;
                                        cycle <= 3'b000;

                                        P[N] <= (A[7] & din[7]);
                                        P[Z] <= (A & din) == 0;
                                    end
                                end
                            endcase
                        end
                        // AND absolute Y
                        8'h39: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low}+Y;
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        A <= A & din;
                                        address <= PC+3;
                                        PC <= PC+3;
                                        cycle <= 3'b000;

                                        P[N] <= (A[7] & din[7]);
                                        P[Z] <= (A & din) == 0;
                                    end
                                end
                            endcase
                        end
                        // ORA immediate
                        8'h09: begin
                            case (cycle)
                                3'b001: begin
                                    A <= A | din;
                                    PC <= PC+2;
                                    address <= PC+2;
                                    cycle <= 3'b000;

                                    P[N] <= (A[7] | din[7]);
                                    P[Z] <= (A | din) == 0;
                                end
                            endcase
                        end
                        // ORA absolute
                        8'h0D: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    A <= A | din;
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b000;

                                    P[N] <= (A[7] | din[7]);
                                    P[Z] <= (A | din) == 0;
                                end
                            endcase
                        end
                        // ORA zero page
                        8'h05: begin
                            case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    A <= A | din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;

                                    P[N] <= (A[7] | din[7]);
                                    P[Z] <= (A | din) == 0;
                                end
                            endcase
                        end
                        // ORA ind X
                        8'h01: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + X + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    A <= A | din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;

                                    P[N] <= (A[7] | din[7]);
                                    P[Z] <= (A | din) == 0;
                                end

                                3'b111: begin // dummy cycle to match datasheet
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ORA ind Y
                        8'h11: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    address <= {din, din_low} + Y;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        A <= A | din;
                                        address <= PC+2;
                                        PC <= PC+2;
                                        cycle <= 3'b000;

                                        P[N] <= (A[7] | din[7]);
                                        P[Z] <= (A | din) == 0;
                                    end
                                end
                            endcase
                        end
                        // ORA zero page X
                        8'h15: begin
                            case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    A <= A | din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;

                                    P[N] <= (A[7] | din[7]);
                                    P[Z] <= (A | din) == 0;
                                end

                                3'b111: begin //dummy cycle
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ORA absolute X
                        8'h1D: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low} + X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        A <= A | din;
                                        address <= PC+3;
                                        PC <= PC+3;
                                        cycle <= 3'b000;

                                        P[N] <= (A[7] | din[7]);
                                        P[Z] <= (A | din) == 0;
                                    end
                                end
                            endcase
                        end
                        // ORA absolute Y
                        8'h19: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low}+Y;
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        A <= A | din;
                                        address <= PC+3;
                                        PC <= PC+3;
                                        cycle <= 3'b000;

                                        P[N] <= (A[7] | din[7]);
                                        P[Z] <= (A | din) == 0;
                                    end
                                end
                            endcase
                        end
                        // EOR immediate
                        8'h49: begin
                            case (cycle)
                                3'b001: begin
                                    A <= A ^ din;
                                    PC <= PC+2;
                                    address <= PC+2;
                                    cycle <= 3'b000;

                                    P[N] <= (A[7] ^ din[7]);
                                    P[Z] <= (A ^ din) == 0;
                                end
                            endcase
                        end
                        // EOR absolute
                        8'h4D: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    A <= A ^ din;
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b000;

                                    P[N] <= (A[7] ^ din[7]);
                                    P[Z] <= (A ^ din) == 0;
                                end
                            endcase
                        end
                        // EOR zero page
                        8'h45: begin
                            case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    A <= A ^ din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;

                                    P[N] <= (A[7] ^ din[7]);
                                    P[Z] <= (A ^ din) == 0;
                                end
                            endcase
                        end
                        // EOR ind X
                        8'h41: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + X + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    A <= A ^ din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;

                                    P[N] <= (A[7] ^ din[7]);
                                    P[Z] <= (A ^ din) == 0;
                                end

                                3'b111: begin // dummy cycle to match datasheet
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // EOR ind Y
                        8'h51: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    address <= {din, din_low} + Y;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        A <= A ^ din;
                                        address <= PC+2;
                                        PC <= PC+2;
                                        cycle <= 3'b000;

                                        P[N] <= (A[7] ^ din[7]);
                                        P[Z] <= (A ^ din) == 0;
                                    end
                                end
                            endcase
                        end
                        // EOR zero page X
                        8'h55: begin
                            case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    A <= A ^ din;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;

                                    P[N] <= (A[7] ^ din[7]);
                                    P[Z] <= (A ^ din) == 0;
                                end

                                3'b111: begin //dummy cycle
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // EOR absolute X
                        8'h5D: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low} + X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        A <= A ^ din;
                                        address <= PC+3;
                                        PC <= PC+3;
                                        cycle <= 3'b000;

                                        P[N] <= (A[7] ^ din[7]);
                                        P[Z] <= (A ^ din) == 0;
                                    end
                                end
                            endcase
                        end
                        // EOR absolute Y
                        8'h59: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low}+Y;
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        A <= A ^ din;
                                        address <= PC+3;
                                        PC <= PC+3;
                                        cycle <= 3'b000;

                                        P[N] <= (A[7] ^ din[7]);
                                        P[Z] <= (A ^ din) == 0;
                                    end
                                end
                            endcase
                        end
                        // INX
                        8'hE8: begin
                            case (cycle)
                                3'b001: begin
                                    X <= X + 1;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[N] <= inx_temp[7];
                                    P[Z] <= (inx_temp) == 0;
                                end
                            endcase
                        end
                        // INY
                        8'hC8: begin
                            case (cycle)
                                3'b001: begin
                                    Y <= Y + 1;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[N] <= iny_temp[7];
                                    P[Z] <= (iny_temp) == 0;
                                end
                            endcase
                        end
                        // DEX
                        8'hCA: begin
                            case (cycle)
                                3'b001: begin
                                    X <= X - 1;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[N] <= dex_temp[7];
                                    P[Z] <= (dex_temp) == 0;
                                end
                            endcase
                        end
                        // DEY
                        8'h88: begin
                            case (cycle)
                                3'b001: begin
                                    Y <= Y - 1;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[N] <= dey_temp[7];
                                    P[Z] <= (dey_temp) == 0;
                                end
                            endcase
                        end
                        // INC absolute
                        8'hEE: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    dout <= din + 1;
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b101;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // INC zero page
                        8'hE6: begin
                           case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    dout <= din + 1;
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // INC zero page X
                        8'hF6: begin
                           case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    dout <= din + 1;
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b101;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // INC absolute X
                        8'hFE: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low} + X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    dout <= din + 1;
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        address <= PC+3;
                                        PC <= PC+3;
                                        cycle <= 3'b101;
                                        read <= 1;
                                        write <= 0;

                                        P[N] <= dout[7];
                                        P[Z] <= dout == 0;
                                    end
                                end

                                3'b101: begin
                                    cycle <= 3'b110;
                                end

                                3'b110: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // DEC absolute
                        8'hCE: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    dout <= din - 1;
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b101;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // DEC zero page
                        8'hC6: begin
                           case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    dout <= din - 1;
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // DEC zero page X
                        8'hD6: begin
                           case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    dout <= din - 1;
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b101;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // DEC absolute X
                        8'hDE: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low} + X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        dout <= din - 1;
                                        read <= 0;
                                        write <= 1;
                                        cycle <= cycle+1;
                                    end
                                end

                                3'b100: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b101;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b101: begin
                                    cycle <= 3'b110;
                                end

                                3'b110: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ASL absolute
                        8'h0E: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    P[C] <= din[7];
                                    dout <= din << 1;
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b101;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ASL zero page
                        8'h06: begin
                           case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    P[C] <= din[7];
                                    dout <= din << 1;
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ASL accumulator
                        8'h0A: begin
                            case (cycle)
                                3'b001: begin
                                    P[C] <= A[7];
                                    A <= A << 1;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[N] <= A[6];
                                    P[Z] <= (A[6:0]) == 0;
                                end
                            endcase
                        end
                        // ASL zero page X
                        8'h16: begin
                           case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    P[C] <= din[7];
                                    dout <= din << 1;
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b101;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ASL absolute X
                        8'h1E: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low} + X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        P[C] <= din[7];
                                        dout <= din << 1;
                                        read <= 0;
                                        write <= 1;
                                        cycle <= cycle+1;
                                    end
                                end

                                3'b100: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b101;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b101: begin
                                    cycle <= 3'b110;
                                end

                                3'b110: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // LSR absolute
                        8'h4E: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    P[C] <= din[0];
                                    dout <= din >> 1;
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b101;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= 0;
                                    P[Z] <= dout == 0;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // LSR zero page
                        8'h46: begin
                           case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    P[C] <= din[0];
                                    dout <= din >> 1;
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= 0;
                                    P[Z] <= dout == 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // LSR accumulator
                        8'h4A: begin
                            case (cycle)
                                3'b001: begin
                                    P[C] <= A[0];
                                    A <= A >> 1;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[N] <= 0;
                                    P[Z] <= (A >> 1) == 0;
                                end
                            endcase
                        end
                        // LSR zero page X
                        8'h56: begin
                           case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    P[C] <= din[0];
                                    dout <= din >> 1;
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= 0;
                                    P[Z] <= dout == 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b101;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // LSR absolute X
                        8'h5E: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low} + X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        P[C] <= din[0];
                                        dout <= din >> 1;
                                        read <= 0;
                                        write <= 1;
                                        cycle <= cycle+1;
                                    end
                                end

                                3'b100: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b101;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= 0;
                                    P[Z] <= dout == 0;
                                end

                                3'b101: begin
                                    cycle <= 3'b110;
                                end

                                3'b110: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ROL absolute
                        8'h2E: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    P[C] <= din[7];
                                    dout <= {din[6:0], P[C]};
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b101;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ROL zero page
                        8'h26: begin
                           case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    P[C] <= din[7];
                                    dout <= {din[6:0], P[C]};
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ROL accumulator
                        8'h2A: begin
                            case (cycle)
                                3'b001: begin
                                    P[C] <= A[7];
                                    A <= {A[6:0], P[C]};
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[N] <= A[6];
                                    P[Z] <= A[6:0] == 0 & P[C] == 0;
                                end
                            endcase
                        end
                        // ROL zero page X
                        8'h36: begin
                           case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    P[C] <= din[7];
                                    dout <= {din[6:0], P[C]};
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b101;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ROL absolute X
                        8'h3E: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low} + X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        P[C] <= din[7];
                                        dout <= {din[6:0], P[C]};
                                        read <= 0;
                                        write <= 1;
                                        cycle <= cycle+1;
                                    end
                                end

                                3'b100: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b101;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b101: begin
                                    cycle <= 3'b110;
                                end

                                3'b110: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ROR absolute
                        8'h6E: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    P[C] <= din[0];
                                    dout <= {P[C], din[7:1]};
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b101;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ROR zero page
                        8'h66: begin
                           case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    P[C] <= din[0];
                                    dout <= {P[C], din[7:1]};
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ROR accumulator
                        8'h6A: begin
                            case (cycle)
                                3'b001: begin
                                    P[C] <= A[0];
                                    A <= {P[C], A[7:1]};
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[N] <= P[C];
                                    P[Z] <= P[C] == 0 & A[7:1] == 0;
                                end
                            endcase
                        end
                        // ROR zero page X
                        8'h76: begin
                           case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    P[C] <= din[0];
                                    dout <= {P[C], din[7:1]};
                                    read <= 0;
                                    write <= 1;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b100;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b100: begin
                                    cycle <= 3'b101;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // ROR absolute X
                        8'h7E: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low} + X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        P[C] <= din[0];
                                        dout <= {P[C], din[7:1]};
                                        read <= 0;
                                        write <= 1;
                                        cycle <= cycle+1;
                                    end
                                end

                                3'b100: begin
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b101;
                                    read <= 1;
                                    write <= 0;

                                    P[N] <= dout[7];
                                    P[Z] <= dout == 0;
                                end

                                3'b101: begin
                                    cycle <= 3'b110;
                                end

                                3'b110: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CMP immediate
                        8'hC9: begin
                            case (cycle)
                                3'b001: begin
                                    P[C] <= (A >= din) ? 1 : 0;
                                    P[Z] <= (A == din) ? 1 : 0;
                                    P[N] <= cmp_temp[7];

                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CMP absolute
                        8'hCD: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    P[C] <= (A >= din) ? 1 : 0;
                                    P[Z] <= (A == din) ? 1 : 0;
                                    P[N] <= cmp_temp[7];
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CMP zero page
                        8'hC5: begin
                            case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    P[C] <= (A >= din) ? 1 : 0;
                                    P[Z] <= (A == din) ? 1 : 0;
                                    P[N] <= cmp_temp[7];
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CMP ind X
                        8'hC1: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + X + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    P[C] <= (A >= din) ? 1 : 0;
                                    P[Z] <= (A == din) ? 1 : 0;
                                    P[N] <= cmp_temp[7];
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;
                                end

                                3'b111: begin // dummy cycle to match datasheet
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CMP ind Y
                        8'hD1: begin
                            case (cycle)
                                3'b001: begin
                                    ind_offset <= din;
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    address <= {8'h00, (ind_offset + 1) & 8'hFF};
                                    din_low <= din;
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    address <= {din, din_low} + Y;
                                    cycle <= cycle+1;
                                end

                                3'b100: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        P[C] <= (A >= din) ? 1 : 0;
                                        P[Z] <= (A == din) ? 1 : 0;
                                        P[N] <= cmp_temp[7];
                                        address <= PC+2;
                                        PC <= PC+2;
                                        cycle <= 3'b000;
                                    end
                                end
                            endcase
                        end
                        // CMP zero page X
                        8'hD5: begin
                            case (cycle)
                                3'b001: begin
                                    address <= {8'h00, (din + X) & 8'hFF};
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    P[C] <= (A >= din) ? 1 : 0;
                                    P[Z] <= (A == din) ? 1 : 0;
                                    P[N] <= cmp_temp[7];
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b111;
                                end

                                3'b111: begin //dummy cycle
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CMP absolute X
                        8'hDD: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low} + X;
                                    page_crossed <= (({1'h0, din_low} + X) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        P[C] <= (A >= din) ? 1 : 0;
                                        P[Z] <= (A == din) ? 1 : 0;
                                        P[N] <= cmp_temp[7];
                                        address <= PC+3;
                                        PC <= PC+3;
                                        cycle <= 3'b000;
                                    end
                                end
                            endcase
                        end
                        // CMP absolute Y
                        8'hD9: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low}+Y;
                                    page_crossed <= (({1'h0, din_low} + Y) > 8'hFF);
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    if (page_crossed) begin
                                        page_crossed <= 0;
                                    end else begin
                                        P[C] <= (A >= din) ? 1 : 0;
                                        P[Z] <= (A == din) ? 1 : 0;
                                        P[N] <= cmp_temp[7];
                                        address <= PC+3;
                                        PC <= PC+3;
                                        cycle <= 3'b000;
                                    end
                                end
                            endcase
                        end
                        // CPX immediate
                        8'hE0: begin
                            case (cycle)
                                3'b001: begin
                                    P[C] <= (X >= din) ? 1 : 0;
                                    P[Z] <= (X == din) ? 1 : 0;
                                    P[N] <= cpx_temp[7];

                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CPX absolute
                        8'hEC: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    P[C] <= (X >= din) ? 1 : 0;
                                    P[Z] <= (X == din) ? 1 : 0;
                                    P[N] <= cpx_temp[7];
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CPX zero page
                        8'hE4: begin
                            case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    P[C] <= (X >= din) ? 1 : 0;
                                    P[Z] <= (X == din) ? 1 : 0;
                                    P[N] <= cpx_temp[7];
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CPY immediate
                        8'hC0: begin
                            case (cycle)
                                3'b001: begin
                                    P[C] <= (Y >= din) ? 1 : 0;
                                    P[Z] <= (Y == din) ? 1 : 0;
                                    P[N] <= cpy_temp[7];

                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CPY absolute
                        8'hCC: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    P[C] <= (Y >= din) ? 1 : 0;
                                    P[Z] <= (Y == din) ? 1 : 0;
                                    P[N] <= cpy_temp[7];
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CPY zero page
                        8'hC4: begin
                            case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    P[C] <= (Y >= din) ? 1 : 0;
                                    P[Z] <= (Y == din) ? 1 : 0;
                                    P[N] <= cpy_temp[7];
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // BIT absolute
                        8'h2C: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle+1;
                                end

                                3'b011: begin
                                    P[N] <= din[7];
                                    P[V] <= din[6];
                                    P[Z] <= ((A & din) == 0) ? 1 : 0;
                                    address <= PC+3;
                                    PC <= PC+3;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // BIT zero page
                        8'h24: begin
                            case (cycle)
                                3'b001: begin
                                    address <= din;
                                    cycle <= cycle+1;
                                end

                                3'b010: begin
                                    P[N] <= din[7];
                                    P[V] <= din[6];
                                    P[Z] <= ((A & din) == 0) ? 1 : 0;
                                    address <= PC+2;
                                    PC <= PC+2;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CLC
                        8'h18: begin
                            case (cycle)
                                3'b001: begin
                                    P[C] <= 0;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CLD
                        8'hD8: begin
                            case (cycle)
                                3'b001: begin
                                    P[D] <= 0;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CLI
                        8'h58: begin
                            case (cycle)
                                3'b001: begin
                                    P[I] <= 0;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // CLV
                        8'hB8: begin
                            case (cycle)
                                3'b001: begin
                                    P[V] <= 0;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // SEC
                        8'h38: begin
                            case (cycle)
                                3'b001: begin
                                    P[C] <= 1;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // SED
                        8'hF8: begin
                            case (cycle)
                                3'b001: begin
                                    P[D] <= 1;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // SEI
                        8'h78: begin
                            case (cycle)
                                3'b001: begin
                                    P[I] <= 1;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // PHA
                        8'h48: begin
                            case (cycle)
                                3'b001: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= 16'h0100 + SP;
                                    dout <= A;
                                    cycle <= 3'b010;
                                end

                                3'b010: begin
                                    SP <= SP - 1;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;
                                    read <= 1;
                                    write <= 0;
                                end
                            endcase
                        end
                        // PHP
                        8'h08: begin
                            case (cycle)
                                3'b001: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= 16'h0100 + SP;
                                    dout <= P | 8'b00110000;
                                    cycle <= 3'b010;
                                end

                                3'b010: begin
                                    SP <= SP - 1;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;
                                    read <= 1;
                                    write <= 0;
                                end
                            endcase
                        end
                        // PLA
                        8'h68: begin
                            case (cycle)
                                3'b001: begin
                                    address <= {8'h01, (SP + 8'h01)};
                                    cycle <= 3'b010;
                                end

                                3'b010: begin
                                    A <= din;
                                    SP <= SP+1;
                                    cycle <= 3'b011;
                                end

                                3'b011: begin
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b000;

                                    P[Z] <= A == 0;
                                    P[N] <= A[7];
                                end
                            endcase
                        end
                        // PLP
                        8'h28: begin
                            case (cycle)
                                3'b001: begin
                                    address <= {8'h01, (SP + 8'h01)};
                                    cycle <= 3'b010;
                                end

                                3'b010: begin
                                    P <= (din & 8'b11001111) | 8'b00100000;
                                    SP <= SP+1;
                                    address <= PC+1;
                                    PC <= PC+1;
                                    cycle <= 3'b011;
                                end

                                3'b011: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // BCC
                        8'h90: begin
                            case (cycle)
                                3'b001: begin
                                    if (P[C] == 0) begin
                                        PC <= PC + 2;
                                        address <= PC + {{8{din[7]}}, din} + 2;
                                        cycle <= 3'b010;
                                    end else begin
                                        PC <= PC+2;
                                        address <= PC+2;
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b010: begin
                                    PC <= address;
                                    if (PC[15:8] != address[15:8]) begin
                                        cycle <= 3'b011;
                                    end else begin
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b011: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // BCS
                        8'hB0: begin
                            case (cycle)
                                3'b001: begin
                                    if (P[C] == 1) begin
                                        PC <= PC + 2;
                                        address <= PC + {{8{din[7]}}, din} + 2;
                                        cycle <= 3'b010;
                                    end else begin
                                        PC <= PC+2;
                                        address <= PC+2;
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b010: begin
                                    PC <= address;
                                    if (PC[15:8] != address[15:8]) begin
                                        cycle <= 3'b011;
                                    end else begin
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b011: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // BEQ
                        8'hF0: begin
                            case (cycle)
                                3'b001: begin
                                    if (P[Z] == 1) begin
                                        PC <= PC + 2;
                                        address <= PC + {{8{din[7]}}, din} + 2;
                                        cycle <= 3'b010;
                                    end else begin
                                        PC <= PC+2;
                                        address <= PC+2;
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b010: begin
                                    PC <= address;
                                    if (PC[15:8] != address[15:8]) begin
                                        cycle <= 3'b011;
                                    end else begin
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b011: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // BNE
                        8'hD0: begin
                            case (cycle)
                                3'b001: begin
                                    if (P[Z] == 0) begin
                                        PC <= PC + 2;
                                        address <= PC + {{8{din[7]}}, din} + 2;
                                        cycle <= 3'b010;
                                    end else begin
                                        PC <= PC+2;
                                        address <= PC+2;
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b010: begin
                                    PC <= address;
                                    if (PC[15:8] != address[15:8]) begin
                                        cycle <= 3'b011;
                                    end else begin
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b011: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // BMI
                        8'h30: begin
                            case (cycle)
                                3'b001: begin
                                    if (P[N] == 1) begin
                                        PC <= PC + 2;
                                        address <= PC + {{8{din[7]}}, din} + 2;
                                        cycle <= 3'b010;
                                    end else begin
                                        PC <= PC+2;
                                        address <= PC+2;
                                        cycle <= 3'b000;
                                    end
                                end

                               3'b010: begin
                                    PC <= address;
                                    if (PC[15:8] != address[15:8]) begin
                                        cycle <= 3'b011;
                                    end else begin
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b011: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // BPL
                        8'h10: begin
                            case (cycle)
                                3'b001: begin
                                    if (P[N] == 0) begin
                                        PC <= PC + 2;
                                        address <= PC + {{8{din[7]}}, din} + 2;
                                        cycle <= 3'b010;
                                    end else begin
                                        PC <= PC+2;
                                        address <= PC+2;
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b010: begin
                                    PC <= address;
                                    if (PC[15:8] != address[15:8]) begin
                                        cycle <= 3'b011;
                                    end else begin
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b011: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // BVC
                        8'h50: begin
                            case (cycle)
                                3'b001: begin
                                    if (P[V] == 0) begin
                                        PC <= PC + 2;
                                        address <= PC + {{8{din[7]}}, din} + 2;
                                        cycle <= 3'b010;
                                    end else begin
                                        PC <= PC+2;
                                        address <= PC+2;
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b010: begin
                                    PC <= address;
                                    if (PC[15:8] != address[15:8]) begin
                                        cycle <= 3'b011;
                                    end else begin
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b011: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // BVS
                        8'h70: begin
                            case (cycle)
                                3'b001: begin
                                    if (P[V] == 1) begin
                                        PC <= PC + 2;
                                        address <= PC + {{8{din[7]}}, din} + 2;
                                        cycle <= 3'b010;
                                    end else begin
                                        PC <= PC+2;
                                        address <= PC+2;
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b010: begin
                                    PC <= address;
                                    if (PC[15:8] != address[15:8]) begin
                                        cycle <= 3'b011;
                                    end else begin
                                        cycle <= 3'b000;
                                    end
                                end

                                3'b011: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // JMP absolute
                        8'h4C: begin
                           case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    PC <= {din, din_low};
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // JMP indirect
                        8'h6C: begin
                            case (cycle)
                                3'b001: begin
                                    address <= PC + 2;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {din, din_low};
                                    cycle <= cycle + 1;
                                end

                                3'b011: begin
                                    address <= {address[15:8], (address[7:0] + 8'h01)};
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b100: begin
                                    address <= {din, din_low};
                                    PC <= {din, din_low};
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // JSR
                        8'h20: begin
                            case (cycle)
                                3'b001: begin
                                    din_low <= din;
                                    jsr_temp <= PC + 2;
                                    address <= {8'h01, SP};
                                    cycle <= 3'b010;
                                end

                                3'b010: begin
                                    address <= {8'h01, SP};
                                    dout <= jsr_temp[15:8];
                                    write <= 1;
                                    read <= 0;
                                    SP <= SP - 1;
                                    cycle <= 3'b011;
                                end

                                3'b011: begin
                                    address <= {8'h01, SP};
                                    dout <= jsr_temp[7:0];
                                    write <= 1;
                                    read <= 0;
                                    SP <= SP - 1;
                                    cycle <= 3'b100;
                                end

                                3'b100: begin
                                    address <= PC + 2;
                                    read <= 1;
                                    write <= 0;
                                    cycle <= 3'b101;
                                end

                                3'b101: begin
                                    din_high <= din;
                                    PC <= {din, din_low};
                                    address <= {din, din_low};
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // BRK
                        8'h00: begin
                            case (cycle)
                                3'b001: begin
                                    PC <= pc_plus_2_unless_in_interrupt;
                                    cycle <= cycle + 1;
                                    address <= 16'h0100 + SP;
                                    dout <= pc_plus_2_unless_in_interrupt[15:8];
                                    write <= 1;
                                    read <= 0;
                                end

                                3'b010: begin
                                    read <= 0;
                                    write <= 1;
                                    address <= 16'h0100 + SP - 1;
                                    SP <= SP-1;
                                    dout <= PC[7:0];
                                    cycle <= cycle + 1;
                                end

                                3'b011: begin
                                    address <= 16'h0100 + SP - 1;
                                    SP <= SP-1;
                                    dout <= {P[7:6], 1'b1, !in_interrupt, P[3], 1'b1, P[1:0]};
                                    cycle <= cycle + 1;
                                end

                                3'b100: begin
                                    address <= 16'h0100 + SP;
                                    case ({nmi_in_progress, reset_sequence})
                                        2'b00: address <= 16'hFFFE;
                                        2'b01: address <= 16'hFFFC;
                                        2'b10: address <= 16'hFFFA;
                                        2'b11: address <= address;
                                    endcase
                                    SP <= SP - 1;
                                    cycle <= cycle + 1;
                                    read <= 1;
                                    write <= 0;
                                    loading_vector <= 1;
                                    nmi_reset <= 0;
                                end

                                3'b101: begin
                                    address <= 16'hFFFE;
                                    case ({nmi_in_progress, reset_sequence})
                                        2'b00: address <= 16'hFFFF;
                                        2'b01: address <= 16'hFFFD;
                                        2'b10: address <= 16'hFFFB;
                                        2'b11: address <= address;
                                    endcase
                                    read <= 1;
                                    write <= 0;
                                    cycle <= cycle + 1;
                                    din_low <= din;
                                    nmi_reset <= 1;
                                end

                                3'b110: begin
                                    address <= {din, din_low};
                                    cycle <= 3'b000;
                                    PC <= {din, din_low};
                                    loading_vector <= 0;
                                end
                            endcase
                        end
                        // RTI
                        8'h40: begin
                            case (cycle)
                                3'b001: begin
                                    address <= {8'h01, (SP + 8'h01)};
                                    SP <= SP + 1;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {8'h01, (SP + 8'h01)};
                                    SP <= SP + 1;
                                    P <= din | 8'b00100000;
                                    cycle <= cycle + 1;
                                end

                                3'b011: begin
                                    address <= {8'h01, (SP + 8'h01)};
                                    SP <= SP + 1;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b100: begin
                                    address <= {din, din_low};
                                    PC <= {din, din_low};
                                    cycle <= cycle + 1;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // RTS
                        8'h60: begin
                            case (cycle)
                                3'b001: begin
                                    address <= {8'h01, (SP + 8'h01)};
                                    SP <= SP + 1;
                                    cycle <= cycle + 1;
                                end

                                3'b010: begin
                                    address <= {8'h01, (SP + 8'h01)};
                                    SP <= SP + 1;
                                    din_low <= din;
                                    cycle <= cycle + 1;
                                end

                                3'b011: begin
                                    address <= {din, din_low} + 1;
                                    PC <= {din, din_low} + 1;
                                    cycle <= cycle + 1;
                                end

                                3'b100: begin
                                    cycle <= 3'b101;
                                end

                                3'b101: begin
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                        // NOP
                        8'hEA: begin
                            case (cycle)
                                3'b001: begin
                                    PC <= PC + 1;
                                    address <= PC + 1;
                                    cycle <= 3'b000;
                                end
                            endcase
                        end
                     endcase
                 end
            end
        end
    end
endmodule

//////////////////////////////////////////////////////////////////
// Core I2C Master TX and Passive RX Controller
//////////////////////////////////////////////////////////////////
module module_i2c#(
	parameter integer DWIDTH = 32,
	parameter integer AWIDTH = 14
)
(
	input PCLK,
	input PRESETn,
	
	// TX FIFO
	input fifo_tx_f_full,
	input fifo_tx_f_empty,
	input [DWIDTH-1:0] fifo_tx_data_out,
	output reg fifo_tx_rd_en,

	// RX FIFO
	input fifo_rx_f_full,
	input fifo_rx_f_empty,
	output fifo_rx_wr_en,
	output [DWIDTH-1:0] fifo_rx_data_in,

	// Registers config
	input [AWIDTH-1:0] DATA_CONFIG_REG,
	input [AWIDTH-1:0] TIMEOUT_TX,
	
	output TX_EMPTY,
	output RX_EMPTY,
	output ERROR,
	output ENABLE_SDA,
	output ENABLE_SCL,

	// I2C Ports
	inout SDA,
	inout SCL
);

	// Interrupt assignment
	assign TX_EMPTY = fifo_tx_f_empty;
	assign RX_EMPTY = fifo_rx_f_empty;

	// Clock divider calculations
	wire [11:0] clk_div = DATA_CONFIG_REG[13:2];
	wire [11:0] q1 = clk_div >> 2;          // CLK_DIV / 4
	wire [11:0] q2 = clk_div >> 1;          // CLK_DIV / 2
	wire [11:0] q3 = clk_div - q1;          // CLK_DIV - (CLK_DIV / 4)

	// TX FSM registers
	localparam [4:0] TX_STATE_IDLE            = 5'd0,
	                 TX_STATE_START           = 5'd1,
	                 TX_STATE_CTRL            = 5'd2,
	                 TX_STATE_ACK_CTRL        = 5'd3,
	                 TX_STATE_ADDR            = 5'd4,
	                 TX_STATE_ACK_ADDR        = 5'd5,
	                 TX_STATE_DATA0           = 5'd6,
	                 TX_STATE_ACK_DATA0       = 5'd7,
	                 TX_STATE_DATA1           = 5'd8,
	                 TX_STATE_ACK_DATA1       = 5'd9,
	                 TX_STATE_RX_DATA0        = 5'd10,
	                 TX_STATE_TX_ACK_RX_DATA0 = 5'd11,
	                 TX_STATE_RX_DATA1        = 5'd12,
	                 TX_STATE_TX_ACK_RX_DATA1 = 5'd13,
	                 TX_STATE_STOP            = 5'd14;

	reg [4:0] state_tx;
	reg [11:0] clk_cnt;
	reg [2:0] bit_cnt;
	reg [31:0] tx_data_reg;
	reg tx_error;

	reg sda_out_tx;
	reg sda_oe_tx;
	reg scl_out_tx;
	reg scl_oe_tx;

	// Internal signals for RX FIFO multiplexing
	reg fifo_rx_wr_en_tx;
	reg [15:0] rx_data_reg_tx;
	reg fifo_rx_wr_en_rx_int;
	reg [31:0] fifo_rx_data_in_rx_int;

	assign fifo_rx_wr_en = fifo_rx_wr_en_tx | fifo_rx_wr_en_rx_int;
	assign fifo_rx_data_in = fifo_rx_wr_en_tx ? {16'd0, rx_data_reg_tx} : fifo_rx_data_in_rx_int;

	// RX Interface Synchronization (2-stage synchronizer)
	reg scl_sync_0, scl_sync_1;
	reg sda_sync_0, sda_sync_1;
	always @(posedge PCLK) begin
		scl_sync_0 <= SCL;
		scl_sync_1 <= scl_sync_0;
		sda_sync_0 <= SDA;
		sda_sync_1 <= sda_sync_0;
	end

	reg scl_prev, sda_prev;
	always @(posedge PCLK) begin
		scl_prev <= scl_sync_1;
		sda_prev <= sda_sync_1;
	end

	wire scl_pos = (scl_sync_1 && !scl_prev);
	wire scl_neg = (!scl_sync_1 && scl_prev);
	wire sda_pos = (sda_sync_1 && !sda_prev);
	wire sda_neg = (!sda_sync_1 && sda_prev);

	wire start_detect = sda_neg && scl_sync_1;
	wire stop_detect  = sda_pos && scl_sync_1;

	// RX FSM registers
	localparam [3:0] RX_STATE_IDLE      = 4'd0,
	                 RX_STATE_START     = 4'd1,
	                 RX_STATE_CTRL      = 4'd2,
	                 RX_STATE_ACK_CTRL  = 4'd3,
	                 RX_STATE_ADDR      = 4'd4,
	                 RX_STATE_ACK_ADDR  = 4'd5,
	                 RX_STATE_DATA0     = 4'd6,
	                 RX_STATE_ACK_DATA0 = 4'd7,
	                 RX_STATE_DATA1     = 4'd8,
	                 RX_STATE_ACK_DATA1 = 4'd9,
	                 RX_STATE_STOP      = 4'd10;

	reg [3:0] state_rx;
	reg [2:0] rx_bit_cnt;
	reg [31:0] rx_data_reg;
	reg sda_out_rx;
	reg sda_oe_rx;

	// Bidirectional Driving
	assign SDA = (sda_oe_tx) ? sda_out_tx : (sda_oe_rx) ? sda_out_rx : 1'bz;
	assign SCL = (scl_oe_tx) ? scl_out_tx : 1'bz;

	assign ENABLE_SDA = sda_oe_tx || sda_oe_rx;
	assign ENABLE_SCL = scl_oe_tx;

	assign ERROR = tx_error || (DATA_CONFIG_REG[0] && DATA_CONFIG_REG[1]);

	// TX Sequential Logic
	always @(posedge PCLK) begin
		if (!PRESETn) begin
			state_tx         <= TX_STATE_IDLE;
			clk_cnt          <= 12'd0;
			bit_cnt          <= 3'd0;
			tx_data_reg      <= 32'd0;
			fifo_tx_rd_en    <= 1'b0;
			sda_out_tx       <= 1'b1;
			sda_oe_tx        <= 1'b0;
			scl_out_tx       <= 1'b1;
			scl_oe_tx        <= 1'b0;
			tx_error         <= 1'b0;
			rx_data_reg_tx   <= 16'd0;
			fifo_rx_wr_en_tx <= 1'b0;
		end else begin
			fifo_tx_rd_en    <= 1'b0;
			fifo_rx_wr_en_tx <= 1'b0;
			
			case (state_tx)
				TX_STATE_IDLE: begin
					clk_cnt    <= 12'd0;
					bit_cnt    <= 3'd0;
					sda_out_tx <= 1'b1;
					sda_oe_tx  <= 1'b0;
					scl_out_tx <= 1'b1;
					scl_oe_tx  <= 1'b0;
					if (DATA_CONFIG_REG[0] && !DATA_CONFIG_REG[1] && !fifo_tx_f_empty) begin
						state_tx      <= TX_STATE_START;
						tx_data_reg   <= fifo_tx_data_out;
						fifo_tx_rd_en <= 1'b1;
					end
				end

				TX_STATE_START: begin
					sda_oe_tx <= 1'b1;
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						clk_cnt <= clk_cnt + 1'b1;
						if (clk_cnt >= q1) sda_out_tx <= 1'b0;
						if (clk_cnt >= q2) scl_out_tx <= 1'b0;
					end else begin
						clk_cnt  <= 12'd0;
						state_tx <= TX_STATE_CTRL;
					end
				end

				TX_STATE_CTRL: begin
					sda_oe_tx <= 1'b1;
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						if (clk_cnt == q1 && scl_sync_1 == 1'b0) clk_cnt <= clk_cnt; // Stretch
						else clk_cnt <= clk_cnt + 1'b1;
						scl_out_tx <= (clk_cnt < q1 || clk_cnt >= q3) ? 1'b0 : 1'b1;
						if (clk_cnt == 12'd0) sda_out_tx <= tx_data_reg[bit_cnt];
					end else begin
						clk_cnt <= 12'd0;
						if (bit_cnt < 3'd7) bit_cnt <= bit_cnt + 1'b1;
						else begin bit_cnt <= 3'd0; state_tx <= TX_STATE_ACK_CTRL; end
					end
				end

				TX_STATE_ACK_CTRL: begin
					sda_oe_tx <= 1'b0;
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						if (clk_cnt == q1 && scl_sync_1 == 1'b0) clk_cnt <= clk_cnt; // Stretch
						else clk_cnt <= clk_cnt + 1'b1;
						scl_out_tx <= (clk_cnt < q1 || clk_cnt >= q3) ? 1'b0 : 1'b1;
						if (clk_cnt == q2 && SDA !== 1'b0) tx_error <= 1'b1;
					end else begin
						clk_cnt <= 12'd0;
						state_tx <= tx_error ? TX_STATE_STOP : TX_STATE_ADDR;
					end
				end

				TX_STATE_ADDR: begin
					sda_oe_tx <= 1'b1;
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						if (clk_cnt == q1 && scl_sync_1 == 1'b0) clk_cnt <= clk_cnt; // Stretch
						else clk_cnt <= clk_cnt + 1'b1;
						scl_out_tx <= (clk_cnt < q1 || clk_cnt >= q3) ? 1'b0 : 1'b1;
						if (clk_cnt == 12'd0) sda_out_tx <= tx_data_reg[8 + bit_cnt];
					end else begin
						clk_cnt <= 12'd0;
						if (bit_cnt < 3'd7) bit_cnt <= bit_cnt + 1'b1;
						else begin bit_cnt <= 3'd0; state_tx <= TX_STATE_ACK_ADDR; end
					end
				end

				TX_STATE_ACK_ADDR: begin
					sda_oe_tx <= 1'b0;
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						if (clk_cnt == q1 && scl_sync_1 == 1'b0) clk_cnt <= clk_cnt; // Stretch
						else clk_cnt <= clk_cnt + 1'b1;
						scl_out_tx <= (clk_cnt < q1 || clk_cnt >= q3) ? 1'b0 : 1'b1;
						if (clk_cnt == q2 && SDA !== 1'b0) tx_error <= 1'b1;
					end else begin
						clk_cnt <= 12'd0;
						if (tx_error) state_tx <= TX_STATE_STOP;
						else state_tx <= tx_data_reg[15] ? TX_STATE_RX_DATA0 : TX_STATE_DATA0;
					end
				end

				// MASTER READ STATES
				TX_STATE_RX_DATA0: begin
					sda_oe_tx <= 1'b0; 
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						if (clk_cnt == q1 && scl_sync_1 == 1'b0) clk_cnt <= clk_cnt; // Stretch
						else clk_cnt <= clk_cnt + 1'b1;
						scl_out_tx <= (clk_cnt < q1 || clk_cnt >= q3) ? 1'b0 : 1'b1;
						if (clk_cnt == q2) rx_data_reg_tx[bit_cnt] <= SDA;
					end else begin
						clk_cnt <= 12'd0;
						if (bit_cnt < 3'd7) bit_cnt <= bit_cnt + 1'b1;
						else begin bit_cnt <= 3'd0; state_tx <= TX_STATE_TX_ACK_RX_DATA0; end
					end
				end

				TX_STATE_TX_ACK_RX_DATA0: begin
					sda_oe_tx <= 1'b1; 
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						if (clk_cnt == q1 && scl_sync_1 == 1'b0) clk_cnt <= clk_cnt; // Stretch
						else clk_cnt <= clk_cnt + 1'b1;
						scl_out_tx <= (clk_cnt < q1 || clk_cnt >= q3) ? 1'b0 : 1'b1;
						if (clk_cnt == 12'd0) sda_out_tx <= 1'b0; 
					end else begin
						clk_cnt <= 12'd0;
						state_tx <= TX_STATE_RX_DATA1;
					end
				end

				TX_STATE_RX_DATA1: begin
					sda_oe_tx <= 1'b0;
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						if (clk_cnt == q1 && scl_sync_1 == 1'b0) clk_cnt <= clk_cnt; // Stretch
						else clk_cnt <= clk_cnt + 1'b1;
						scl_out_tx <= (clk_cnt < q1 || clk_cnt >= q3) ? 1'b0 : 1'b1;
						if (clk_cnt == q2) rx_data_reg_tx[8 + bit_cnt] <= SDA;
					end else begin
						clk_cnt <= 12'd0;
						if (bit_cnt < 3'd7) bit_cnt <= bit_cnt + 1'b1;
						else begin bit_cnt <= 3'd0; state_tx <= TX_STATE_TX_ACK_RX_DATA1; end
					end
				end

				TX_STATE_TX_ACK_RX_DATA1: begin
					sda_oe_tx <= 1'b1;
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						if (clk_cnt == q1 && scl_sync_1 == 1'b0) clk_cnt <= clk_cnt; // Stretch
						else clk_cnt <= clk_cnt + 1'b1;
						scl_out_tx <= (clk_cnt < q1 || clk_cnt >= q3) ? 1'b0 : 1'b1;
						if (clk_cnt == 12'd0) sda_out_tx <= 1'b0; 
					end else begin
						clk_cnt <= 12'd0;
						state_tx <= TX_STATE_STOP;
					end
				end

				TX_STATE_DATA0: begin
					sda_oe_tx <= 1'b1;
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						if (clk_cnt == q1 && scl_sync_1 == 1'b0) clk_cnt <= clk_cnt; // Stretch
						else clk_cnt <= clk_cnt + 1'b1;
						scl_out_tx <= (clk_cnt < q1 || clk_cnt >= q3) ? 1'b0 : 1'b1;
						if (clk_cnt == 12'd0) sda_out_tx <= tx_data_reg[16 + bit_cnt];
					end else begin
						clk_cnt <= 12'd0;
						if (bit_cnt < 3'd7) bit_cnt <= bit_cnt + 1'b1;
						else begin bit_cnt <= 3'd0; state_tx <= TX_STATE_ACK_DATA0; end
					end
				end

				TX_STATE_ACK_DATA0: begin
					sda_oe_tx <= 1'b0;
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						if (clk_cnt == q1 && scl_sync_1 == 1'b0) clk_cnt <= clk_cnt; // Stretch
						else clk_cnt <= clk_cnt + 1'b1;
						scl_out_tx <= (clk_cnt < q1 || clk_cnt >= q3) ? 1'b0 : 1'b1;
						if (clk_cnt == q2 && SDA !== 1'b0) tx_error <= 1'b1;
					end else begin
						clk_cnt <= 12'd0;
						state_tx <= tx_error ? TX_STATE_STOP : TX_STATE_DATA1;
					end
				end

				TX_STATE_DATA1: begin
					sda_oe_tx <= 1'b1;
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						if (clk_cnt == q1 && scl_sync_1 == 1'b0) clk_cnt <= clk_cnt; // Stretch
						else clk_cnt <= clk_cnt + 1'b1;
						scl_out_tx <= (clk_cnt < q1 || clk_cnt >= q3) ? 1'b0 : 1'b1;
						if (clk_cnt == 12'd0) sda_out_tx <= tx_data_reg[24 + bit_cnt];
					end else begin
						clk_cnt <= 12'd0;
						if (bit_cnt < 3'd7) bit_cnt <= bit_cnt + 1'b1;
						else begin bit_cnt <= 3'd0; state_tx <= TX_STATE_ACK_DATA1; end
					end
				end

				TX_STATE_ACK_DATA1: begin
					sda_oe_tx <= 1'b0;
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						if (clk_cnt == q1 && scl_sync_1 == 1'b0) clk_cnt <= clk_cnt; // Stretch
						else clk_cnt <= clk_cnt + 1'b1;
						scl_out_tx <= (clk_cnt < q1 || clk_cnt >= q3) ? 1'b0 : 1'b1;
						if (clk_cnt == q2 && SDA !== 1'b0) tx_error <= 1'b1;
					end else begin
						clk_cnt  <= 12'd0;
						state_tx <= TX_STATE_STOP;
					end
				end

				TX_STATE_STOP: begin
					sda_oe_tx <= 1'b1;
					scl_oe_tx <= 1'b1;
					if (clk_cnt < clk_div - 1) begin
						if (clk_cnt == q1 && scl_sync_1 == 1'b0) clk_cnt <= clk_cnt; // Stretch
						else clk_cnt <= clk_cnt + 1'b1;
						scl_out_tx <= (clk_cnt < q1) ? 1'b0 : 1'b1;
						sda_out_tx <= (clk_cnt < q2) ? 1'b0 : 1'b1;
					end else begin
						clk_cnt  <= 12'd0;
						state_tx <= TX_STATE_IDLE;
						tx_error <= 1'b0;
						if (tx_data_reg[15] && !tx_error) fifo_rx_wr_en_tx <= 1'b1;
					end
				end

				default: state_tx <= TX_STATE_IDLE;
			endcase
		end
	end

	// RX Sequential Logic 
	always @(posedge PCLK) begin
		if (!PRESETn) begin
			state_rx               <= RX_STATE_IDLE;
			rx_bit_cnt             <= 3'd0;
			rx_data_reg            <= 32'd0;
			fifo_rx_wr_en_rx_int   <= 1'b0;
			fifo_rx_data_in_rx_int <= 32'd0;
			sda_out_rx             <= 1'b1;
			sda_oe_rx              <= 1'b0;
		end else begin
			fifo_rx_wr_en_rx_int <= 1'b0;

			if (start_detect && DATA_CONFIG_REG[1] && !DATA_CONFIG_REG[0]) begin
				state_rx    <= RX_STATE_START;
				rx_bit_cnt  <= 3'd0;
				rx_data_reg <= 32'd0;
				sda_out_rx  <= 1'b1;
				sda_oe_rx   <= 1'b0;
			end else begin
				case (state_rx)
					RX_STATE_IDLE: begin
						rx_bit_cnt  <= 3'd0;
						rx_data_reg <= 32'd0;
						sda_out_rx  <= 1'b1;
						sda_oe_rx   <= 1'b0;
						if (DATA_CONFIG_REG[1] && !DATA_CONFIG_REG[0] && start_detect) state_rx <= RX_STATE_START;
					end
					RX_STATE_START: if (scl_neg) state_rx <= RX_STATE_CTRL;
					RX_STATE_CTRL: begin
						if (scl_pos) rx_data_reg[rx_bit_cnt] <= sda_sync_1;
						if (scl_neg && rx_bit_cnt == 3'd7) begin rx_bit_cnt <= 3'd0; state_rx <= RX_STATE_ACK_CTRL; sda_out_rx <= 1'b0; sda_oe_rx <= 1'b1; end 
						else if (scl_neg) rx_bit_cnt <= rx_bit_cnt + 1'b1;
					end
					RX_STATE_ACK_CTRL: if (scl_neg) begin sda_oe_rx <= 1'b0; state_rx <= RX_STATE_ADDR; end
					RX_STATE_ADDR: begin
						if (scl_pos) rx_data_reg[8 + rx_bit_cnt] <= sda_sync_1;
						if (scl_neg && rx_bit_cnt == 3'd7) begin rx_bit_cnt <= 3'd0; state_rx <= RX_STATE_ACK_ADDR; sda_out_rx <= 1'b0; sda_oe_rx <= 1'b1; end 
						else if (scl_neg) rx_bit_cnt <= rx_bit_cnt + 1'b1;
					end
					RX_STATE_ACK_ADDR: if (scl_neg) begin sda_oe_rx <= 1'b0; state_rx <= RX_STATE_DATA0; end
					RX_STATE_DATA0: begin
						if (scl_pos) rx_data_reg[16 + rx_bit_cnt] <= sda_sync_1;
						if (scl_neg && rx_bit_cnt == 3'd7) begin rx_bit_cnt <= 3'd0; state_rx <= RX_STATE_ACK_DATA0; sda_out_rx <= 1'b0; sda_oe_rx <= 1'b1; end 
						else if (scl_neg) rx_bit_cnt <= rx_bit_cnt + 1'b1;
					end
					RX_STATE_ACK_DATA0: if (scl_neg) begin sda_oe_rx <= 1'b0; state_rx <= RX_STATE_DATA1; end
					RX_STATE_DATA1: begin
						if (scl_pos) rx_data_reg[24 + rx_bit_cnt] <= sda_sync_1;
						if (scl_neg && rx_bit_cnt == 3'd7) begin rx_bit_cnt <= 3'd0; state_rx <= RX_STATE_ACK_DATA1; sda_out_rx <= 1'b0; sda_oe_rx <= 1'b1; end 
						else if (scl_neg) rx_bit_cnt <= rx_bit_cnt + 1'b1;
					end
					RX_STATE_ACK_DATA1: if (scl_neg) begin sda_oe_rx <= 1'b0; state_rx <= RX_STATE_STOP; end
					RX_STATE_STOP: begin
						if (stop_detect) begin fifo_rx_wr_en_rx_int <= 1'b1; fifo_rx_data_in_rx_int <= rx_data_reg; state_rx <= RX_STATE_IDLE; end
					end
					default: state_rx <= RX_STATE_IDLE;
				endcase
			end
		end
	end
endmodule
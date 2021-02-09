library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Purpose of MCU Interface
-- Provide read/write glue logic between asynchronous read/write demands from MCU and DPRAMs within the FPGA
--		Note: There are 4 DPRAMs: Ringbuffer upper, Ringbuffer lower, LUT, Register
--		Note: The i/f uses the same system clock as the DPRAMs so does not send out clock signals to DPRAMs
-- Decode address:
--		One line for Memory/Register choice (Memory = RB or LUT; Register = param reg)
--		One line for RB/LUT choice
--		One line for choice of part (1 vs 0 = RB_UPPER vs RB_LOWER)
--		8 lines for address within chosen DPRAM (though LUT differs since it needs 10bit address)
-- Manage write commands from the MCU (asynch command, but synch write to DPRAM)
--		Respond to rise/fall of write line, initiating write process after falling edge
--		Manage synchronous write to selected address
--		Provide handshake (ready to receive) signal to MCU to confirm data storage
-- Manage read commands from the MCU (asynch command, but synch read from DPRAM)
--		Manage synchronous read from selected address, initiating read process after falling edge
--		Manage bidirectional bus
--		Provide handshake (ready to send) signal to MCU to confirm valid data on bus
--		Get confirmation of receipt from MCU (read signal returns to high)
-- Transmit Reset signal from MCU to FPGA
-- Transmit Marking ON/OFF signal from MCU to FPGA
--
-- Note on asynch to synch method: 
-- This interface logs RD/WR signals from the MCU as interrupt signals that are processed
-- on falling edges of the system clock.
-- The DPRAM acts on rising edges of the system clock, so by working on the falling edges of
-- the system clock the I/F can establish data and receive established data.

entity mcu_if is
port
(
	-- input from FPGA
	CLK : in std_logic;	-- system clock
	-- inputs from MCU
	RESET : in std_logic;		-- high level forces reset
	RD : in std_logic;	-- read clock pulse	from mcu 
	WR : in std_logic;	-- write clock pulse from mcu 
	DATA_SEL: in std_logic;		-- Data / #Address	
	MEM_SEL : in std_logic;		-- MEM/#Reg  (1 --> RB or LUT;  0 --> Param reg)
	BUFF_SEL : in std_logic;	-- RB/#LUT (when MEM_SEL = 1: 1 --> RB; 0 --> LUT)
	ADDR_HIGH : in std_logic_vector(3 downto 0);	-- upper 4 bits of 12 bit address (lower 8 bits from the bus)
	DATA_FROM_MCU : in std_logic_vector(7 downto 0); -- von MCU_BIDIR_DATA
	-- inputs from FPGA
	DATA_FROM_FPGA : in std_logic_vector(7 downto 0);		-- data received from the fpga (eg enc count value)
	
	-- outputs to MCU
	RTS_MCU : out std_logic;
	DATA_TO_MCU : out std_logic_vector(7 downto 0); -- nach MCU_BIDIR_DATA
	-- outputs to FPGA
	DATA_TO_FPGA  : out std_logic_vector(7 downto 0);	-- data out to the fpga DPRAM/reg
	ADDR_TO_FPGA  : out std_logic_vector(11 downto 0);	-- addr out to the fpga DPRAM/reg
	REG_EN : out std_logic;		-- goes to clock enable ParamReg
	GAP_EN : out std_logic;		-- goes to clock enable GapReg
	MEM_LUT_EN : out std_logic;		-- goes to clock enable input of memory
	MEM_RB_EN : out std_logic;		-- 
	WR_EN : out std_logic			-- write (1) or read (0) level to memory
);
end mcu_if;

architecture mcu_if_arch of mcu_if is
	signal RD_reg : std_logic_vector(1 downto 0);	
	signal WR_reg : std_logic_vector(1 downto 0);
	signal Rts_fpga : boolean;		-- data ready to send to one of the mem/reg
	signal Addr_12bit : unsigned(11 downto 0);
	
	signal data_to_fpga_reg : std_logic_vector(7 downto 0);

	
	signal state : natural range 0 to 2;	
	signal substate : natural range 0 to 7;	
	signal wr_en_reg : std_logic;
	
	constant state_idle: natural := 0;
	constant state_read: natural := 1;
	constant state_write: natural := 2;
	
begin
	-- do decoding of RAM selection
	REG_EN <= '1' when MEM_SEL = '0' AND BUFF_SEL = '0' AND Rts_fpga else '0'; 
	GAP_EN <= '1' when MEM_SEL = '0' AND BUFF_SEL = '1' AND Rts_fpga else '0';
	MEM_LUT_EN <= '1' when MEM_SEL = '1' AND BUFF_SEL = '0' AND Rts_fpga else '0';
	MEM_RB_EN <= '1' when MEM_SEL = '1' AND BUFF_SEL = '1' AND Rts_fpga else '0';
	ADDR_TO_FPGA <= std_logic_vector(Addr_12bit);			-- load new address	(MCU must do this first)

	DATA_TO_FPGA <= data_to_fpga_reg;
	WR_EN <= wr_en_reg;

	
	-- deal with the system clock (which is identical to DPRAM clock)
	mcuif_out_proc: process(CLK)
	begin
		-- deal with a reset as priority
		if (rising_edge(CLK)) then
			if (RESET = '1') then
				RD_reg <= (others => '0');
				WR_reg <= (others => '0');
				
				Rts_fpga <= false;
				wr_en_reg <= '0';
				DATA_TO_MCU <= (others => 'Z');
				RTS_MCU <= '0';
				state <= state_idle;
			else
				RD_reg <= RD_reg(0) & RD;
				WR_reg <= WR_reg(0) & WR;

				if (state = state_idle) then
					-- idle: flanken auf RD oder WR suchen
					if (RD_reg = "01") then
						--steigende flanke auf RD: read starten
						--zuerst intern die angeforderten daten holen
						Rts_fpga <= true; -- enable; wr_en_reg = 0
						
						state <= state_read;
					elsif (WR_reg = "01") then
						--steigende flanke auf WR: write starten
						--daten liegen an --> lesen
						state <= state_write;
						
						if (DATA_SEL = '0') then
							-- es liegt eine adresse an
							Addr_12bit <= unsigned(ADDR_HIGH & DATA_FROM_MCU);
						else
							-- es liegen daten an
							data_to_fpga_reg <= DATA_FROM_MCU;
							
							--abspeichern der daten starten
							wr_en_reg <= '1'; --write
							Rts_fpga <= true; --enable
						end if;
					end if;
					
					substate <= 0;
				elsif (state = state_read) then
					if (substate = 0) then
						--daten werden gerade geholt
						Rts_fpga <= false; -- disable
						
						--warten bis sie da sind
						substate <= 1;
					elsif (substate = 1) then
						--daten sind da --> auf den bus legen
						DATA_TO_MCU <= DATA_FROM_FPGA;
						
						substate <= 2;
					elsif (substate = 2) then
						--daten sind auf dem bus:
						RTS_MCU <= '1';
						
						--auto-inkrement adresse:
						Addr_12bit <= Addr_12bit + 1;
						substate <= 3;
					elsif (substate = 3) then
						--warten auf fallende flanke von RD
						if (RD_reg(0) = '0') then
							--bus loslassen:
							DATA_TO_MCU <= (others => 'Z');
							
							substate <= 4;
						end if;
					elsif (substate = 4) then
						--fertig
						RTS_MCU <= '0';
						
						--zurück zu idle:
						state <= state_idle;
					end if;
				elsif (state = state_write) then
					if (substate = 0) then
						--daten sind gelesen
						RTS_MCU <= '1';
					
						if (wr_en_reg = '1') then
							-- daten werden gerade gespeichert
							wr_en_reg <= '0'; --zurücksetzen
							Rts_fpga <= false; --disable

							--auto-inkrement adresse:
							Addr_12bit <= Addr_12bit + 1;
						end if;
						
						substate <= 1;
					elsif (substate = 1) then
						--warten auf fallende flanke von WR
						if (WR_reg(0) = '0') then
							RTS_MCU <= '0';
							
							--zurück zu idle:
							state <= state_idle;
						end if;
					end if;
				end if;
			end if;
		end if;
	end process mcuif_out_proc;
	
end mcu_if_arch;
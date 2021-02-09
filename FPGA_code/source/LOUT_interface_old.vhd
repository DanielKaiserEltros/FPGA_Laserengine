library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;    -- needed for to_integer

-- This is the bus#2 driving module; called "laser out interface" but should also include other board driving on bus#2 if ever added
entity lout_if is
port(
	CLK : in std_logic;					-- system clock
	START_AOD : in std_logic;	
	RESET : in std_logic;				-- high level empties registers and resets pointers
	CMD : in std_logic_vector(1 downto 0);		-- a shortened version of the main CMD input from MCU via param reg
	CMD_PAR1 : in std_logic_vector(7 downto 0);
	CMD_PAR2 : in std_logic_vector(7 downto 0);
	DATA_FROM_MEM_LUT : in std_logic_vector(31 downto 0);	-- the image data or the aod data comes in from 4-byte-wide dpram
	DATA_FROM_LOUT : in std_logic_vector(7 downto 0);

	BOARD_SEL : out std_logic_vector(1 downto 0);	
	BOARD_FUNC_SEL : out std_logic_vector(2 downto 0);		
	BOARD_WR : out std_logic;		-- drives the #WR signal to other boards on bus #2
	BOARD_RD : out std_logic;		-- drives the #RD signal when reading from other boards on bus #2
	DIR_TO_LASER : out std_logic;	-- controls the FPGA's use of the laser bus (ie setting it as input or output)
	DATA_TO_LOUT : out std_logic_vector(7 downto 0);
	LASER_PWR_LATCH : out std_logic;		-- sent to laser (bypasses LOUT CPLD) to latch power
	TRIGGER_REPEAT : out std_logic;
	STATUS_TO_MCU : out std_logic_vector(13 downto 0)	-- status info to go to mcu via param reg and including info from LaserOut bd updated here
);
end lout_if;
 
architecture arch_lout_if of lout_if is
	
	-- LaserOut board and function selection
	constant Laser_sel	: std_logic_vector(1 downto 0) 		:= "01";	-- code for laser out board on bus#2
	constant SimpleIO_sel	: std_logic_vector(1 downto 0) 	:= "11";	-- code for simple IO board on bus#2
	constant Func_prelatch : std_logic_vector(2 downto 0) 	:= "000";	-- codes for various laser out board functions when #WR or #RD is toggled on bus#2
	constant Func_high_AOD : std_logic_vector(2 downto 0) 	:= "001";
	constant Func_AOD : std_logic_vector(2 downto 0) 		:= "010";
	constant Func_freq_sel : std_logic_vector(2 downto 0) 	:= "100";
	constant Func_mod_sel : std_logic_vector(2 downto 0) 	:= "101";
	constant Laser_status_normal : std_logic_vector(2 downto 0) 	:= "001";

	
	
	-- ***************** Define signals ****************
	signal sig_STATUS_TO_MCU : std_logic_vector(13 downto 0);
	signal Can_wr : boolean;					-- enables the #WR line to be toggled
	signal Cmd_normal : boolean;				-- command value is 0x00 (system in normal state)
	signal Cmd_AOD_levels : boolean;			-- command value is 0x01 (system in AOD Service state)
	signal Cmd_laser_power : boolean;			-- command value is 0x02 (not a system state: a command to latch a power setting into laser)
	signal aod_data_byte : std_logic_vector(7 downto 0);
	signal Dir_for_normal : std_logic;		--indicates the bus direction demanded by normal operation
	signal Wr_for_normal : std_logic;
	signal Wr_for_power : std_logic;
	signal Func_for_normal : std_logic_vector(2 downto 0);	-- the BOARD_FUNC_SEL value for normal running (as opposed to special eg latching in laser power)
	signal Done_power : boolean;
	signal Laser_cpld_status : std_logic_vector(5 downto 0);
	signal IO_cpld_status : std_logic_vector(6 downto 0);
	signal aod_write_count : natural range 0 to 15;	-- sequence index for writing aod levels
	signal status_read_count : natural range 0 to 15;	-- sequence index for reading LaserOut and SimpleIO board status
	signal power_count : natural range 0 to 127;	-- sequence index

begin
	-- assign ouputs 
	STATUS_TO_MCU <= sig_STATUS_TO_MCU;
	------------- Construct status from cpld and direct info (for bits 10-0, ok=0) ---------------------------
	--sig_STATUS_TO_MCU(0) <= '0' when ((sig_STATUS_TO_MCU(1) = '0') AND (sig_STATUS_TO_MCU(3) = '0') AND (sig_STATUS_TO_MCU(5) = '0') AND (sig_STATUS_TO_MCU(10 downto 7) = "0000")) else '1';		-- any alarm except lock
	sig_STATUS_TO_MCU(0) <= IO_cpld_status(1);
	sig_STATUS_TO_MCU(1) <= '0' when ((Laser_cpld_status(2 downto 0) = Laser_status_normal) AND (Laser_cpld_status(5) = '0')) else '1';	-- any laser alarm
	sig_STATUS_TO_MCU(2) <= IO_cpld_status(5); -- active low ('0': take command from SRAM)						
	sig_STATUS_TO_MCU(3) <= NOT(IO_cpld_status(2));				-- door	(active low: active good) (this one is inverted because active is bad)
	sig_STATUS_TO_MCU(4) <= NOT(IO_cpld_status(0));				-- lock (active low: active good) (this one is inverted because active is bad)
	sig_STATUS_TO_MCU(5) <= IO_cpld_status(1);					-- estop
	sig_STATUS_TO_MCU(6) <= IO_cpld_status(6); -- active low ('0': take command from SRAM)						

	sig_STATUS_TO_MCU(7) <= IO_cpld_status(3);					-- Machine power	(active low: active good)
	sig_STATUS_TO_MCU(8) <= Laser_cpld_status(5);				-- Laser power 24V
	sig_STATUS_TO_MCU(9) <= Laser_cpld_status(3);				-- AOD power 24V
	sig_STATUS_TO_MCU(10) <= '0';								-- 24V board supply of 24V
	sig_STATUS_TO_MCU(13 downto 11) <= Laser_cpld_status(2 downto 0);		-- hardwired alarm from laser	
	

	
	Cmd_normal <= CMD = "00";			-- command value 0x00
	Cmd_AOD_levels <= CMD = "01";			-- command value 0x01
	Cmd_laser_power <= CMD = "10";			-- command value 0x02
	
	TRIGGER_REPEAT <= IO_cpld_status(4); -- low-active
	
	DATA_TO_LOUT <= aod_data_byte;
	
	DIR_TO_LASER <= Dir_for_normal when Cmd_normal OR Cmd_AOD_levels else
					'1' when Cmd_laser_power else
					'0';
			
	BOARD_WR <= Wr_for_normal when Cmd_normal OR Cmd_AOD_levels else
				Wr_for_power when Cmd_laser_power else
				'1';
				
	BOARD_FUNC_SEL <= Func_prelatch when Cmd_laser_power else
						Func_for_normal;
	
	-- Control bus#2: the AOD datastream writing, laser status read, and simple io read.
	-- NOTE: aod writing goes on continuously; it's just reset at the start of a row.
	-- this means there's activity on the bus after a row has finished marking, but this does no harm.
	-- timing: clocks out data on rising clk where data established on falling clk by data clk process....
	-- ....and only happens as a result of Can_wr_  flags being set by data clk process
	loutif_dac_proc: process(CLK)

	begin
		if (falling_edge(CLK)) then
			if (Can_wr) then
				Wr_for_normal <= '0';
			else
				Wr_for_normal <= '1';
			end if;
		end if;
		
		if (rising_edge(CLK)) then			-- establish data on falling edges				
			if (Cmd_laser_power) then 
				aod_data_byte <= CMD_PAR1;
			end if;
			
			if (RESET = '1') then
				BOARD_SEL <= Laser_sel;

				Dir_for_normal <= '0';		-- set up the laser data bus pins as input to FPGA
				aod_write_count <= 15;		-- write sequence stopped
				status_read_count <= 15;	-- laser alarm read sequence stopped
				IO_cpld_status(4) <= '1';	-- ext. trigger = idle
				Can_wr <= false;
				BOARD_RD <= '1';
			else
				-- write_laser::delay_proc::pixel_count_out wird neu gesetzt bei puls auf PX_CLK_AOD_REDGE.
				-- die daten kommen hier an über diesen pfad: pixel_count_out --> memRB --> DATA_FROM_MEM_LUT.
				-- da START_AOD mit PX_CLK_AOD_REDGE verbunden ist, müssen wir hier 2 pausen-takte einlegen.
				if (START_AOD = '1') then
					-- pausen-takt #1
					aod_write_count <= 0; 
				elsif (aod_write_count = 0) then
					-- pausen-takt #2
					BOARD_SEL <= Laser_sel;
					Dir_for_normal <= '1';		-- set up the laser data bus pins as outputs from FPGA
					--Is_freq_sel <= true;
					if (Cmd_AOD_levels) then
						aod_data_byte <= CMD_PAR2;
					end if;
					Func_for_normal <= Func_freq_sel;
					Can_wr <= true;						-- clock in freq sel on next clk rise
					aod_write_count <= 1;				-- initiate send of one pixel info to AOD
				elsif (aod_write_count = 1) then			-- set up sequence for pixel aod data
					if (Cmd_normal) then
						aod_data_byte <= "00" & DATA_FROM_MEM_LUT(27 downto 22);
					end if;
					Can_wr <= false;			
					aod_write_count <= 2;
				elsif (aod_write_count = 2) then
					Func_for_normal <= Func_high_AOD;
					Can_wr <= true;						-- clock in high aod byte on next clk rise
					aod_write_count <= 3;
				elsif (aod_write_count = 3) then
					Can_wr <= false;	
					aod_write_count <= 4;
				elsif (aod_write_count = 4) then
					Func_for_normal <= Func_AOD;
					if (Cmd_normal) then
						aod_data_byte <= "00" & DATA_FROM_MEM_LUT(21 downto 16);
					end if;
					Can_wr <= true;								-- clock in aod setting into dac on next clk rise
					aod_write_count <= 5;
				elsif (aod_write_count = 5) then					
					--Is_freq_sel <= false;							-- clock in mod sel on next clk rise
					if (Cmd_AOD_levels) then
						aod_data_byte <= CMD_PAR1;
					end if;
					Can_wr <= false;	
					aod_write_count <= 6;
				elsif (aod_write_count = 6) then	
					Func_for_normal <= Func_mod_sel;
					Can_wr <= true;				
					aod_write_count <= 7;
				elsif (aod_write_count = 7) then
					Can_wr <= false;	
					aod_write_count <= 8;
				elsif (aod_write_count = 8) then
					Func_for_normal <= Func_high_AOD;
					if (Cmd_normal) then
						aod_data_byte <= "00" & DATA_FROM_MEM_LUT(11 downto 6);
					end if;
					Can_wr <= true;						-- clock in high aod byte on next clk rise
					aod_write_count <= 9;
				elsif (aod_write_count = 9) then
					Can_wr <= false;	
					aod_write_count <= 10;
				elsif (aod_write_count = 10) then	
					Func_for_normal <= Func_AOD;
					if (Cmd_normal) then
						aod_data_byte <= "00" & DATA_FROM_MEM_LUT(5 downto 0);
					end if;
					Can_wr <= true;							-- clock in aod setting into dac on next clk rise
					aod_write_count <= 11;
				elsif (aod_write_count = 11) then
					Can_wr <= false;	
					aod_write_count <= 15;		-- stop aod write sequence
					Dir_for_normal <= '0';		-- set up the laser data bus pins as input to FPGA, reaady for reading
					status_read_count <= 0;		-- start status read sequence
				-- move these status reads to beginning of row above
				elsif (status_read_count = 0) then	
					BOARD_RD <= '0';	-- #RD goes to Lout board to instruct it to read out the laser alarm
					status_read_count <= 1;
				elsif (status_read_count = 1) then -- wait 2 clks for data from LOUT board to settle on bus lines
					status_read_count <= 2;
				elsif (status_read_count = 2) then
					status_read_count <= 3;
					Laser_cpld_status <= DATA_FROM_LOUT(5 downto 0);	-- latch the info from the lout board
				elsif (status_read_count = 3) then
					BOARD_RD <= '1';				-- end the read command to the LOUT board
					status_read_count <= 4;
				elsif (status_read_count = 4) then	-- change now to poll the simpleIO board
				
					BOARD_SEL <= SimpleIO_sel;
					status_read_count <= 5;
				elsif (status_read_count = 5) then
					BOARD_RD <= '0';	-- #RD goes to SimpleIO board to instruct it to read out its inputs
					status_read_count <= 6;
				elsif (status_read_count = 6) then -- wait 2 clks for data from SimpleIO board to settle on bus lines
					status_read_count <= 7;
				elsif (status_read_count = 7) then
					status_read_count <= 8;
					IO_cpld_status <= DATA_FROM_LOUT(6 downto 0);	-- latch the info from the SimpleIO board
				elsif (status_read_count = 8) then
					BOARD_RD <= '1';				-- end the read command to the SimpleIO board
					status_read_count <= 9;
				elsif (status_read_count = 9) then	-- wait 1 clk to allow SimpleIO to reset its bus pins as inputs
					BOARD_SEL <= Laser_sel;
					status_read_count <= 15;		-- stop the read sequence
				end if;
				
			end if;
		end if;
	end process loutif_dac_proc;	
	
	
	-- power latching into laser out board
	loutif_power_proc: process(CLK)
	
	begin
		if (rising_edge(CLK)) then
			if (Cmd_laser_power) then
				if (NOT(Done_power)) then	-- ensures sequence is just done once
					if (power_count = 1) then
						Wr_for_power <= '0';		-- pre-latch the power via CPLD into the external latch on LOUT board
					elsif (power_count = 4) then
						Wr_for_power <= '1';
					elsif (power_count = 56) then	-- there's a 2us delay @24MHz from data-on-bus to latch-into-laser
						LASER_PWR_LATCH <= '1';		-- latch power into laser via ext latch (latch trigger bypasses CPLD)
					elsif (power_count = 120) then		-- hold latch pulse for >2us
						LASER_PWR_LATCH <= '0';		-- drop latch signal
						Done_power <= true;	
					end if;
					power_count <= power_count + 1;
				end if;
			else
				Wr_for_power <= '1';
				Done_power <= false;
				power_count <= 0;
				LASER_PWR_LATCH <= '0';
			end if;
		end if;
	end process loutif_power_proc;
	
end arch_lout_if;


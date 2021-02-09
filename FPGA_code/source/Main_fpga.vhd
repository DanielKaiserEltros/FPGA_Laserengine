library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL; 

library machxo2;
use machxo2.all;

entity data_out_fpga is
port
(
	CLK_SYS : in std_logic;				-- 24MHz crystal clock
	CLK_ENC : out std_logic;			-- clock signal to enc board 
	CLK_SYS_TEST_O : out std_logic;
	CLK_PX_LASER  : out std_logic;
	CLK_PX_AOD : out std_logic;
	CLK_ROW : in std_logic;
	CLK_ROW2 : in std_logic;
	CLK_RPT : in std_logic;

	MCU_BIDIR_DATA : inout std_logic_vector(7 downto 0);
	MCU_RD : in std_logic;
	MCU_WR : in std_logic;
	MCU_MARK_EN : in std_logic;			-- controls EE line to laser, and gates ENC pulses from encoder board
	MCU_DATA_SEL : in std_logic;		-- used as pre-latch signal to latch laser power setting into ext
	MCU_MEM_SEL : in std_logic;			-- MEM/#REG	(Choose buffer memory (LUT/RB)  or  parameter register)
	MCU_BUFF_SEL : in std_logic;		-- BUFF/#LUT	(Choose RB   or   LUT)
	MCU_RESET : in std_logic;
	MCU_RTS_MCU : out std_logic;		-- Ready To Send -- advise MCU that valid data is now on bus
	MCU_LOCK_PARAMREG : in std_logic;
	MCU_MARKING : out std_logic;		-- MCU kann sehen: wenn = 0, ist der RB-puffer frei
	
	ENC_ENC : in std_logic;				-- encoder pulses from the encoder board (normally PR1A but use PL14A for test input)
	ENC_DIR : out std_logic;			-- the direction bit going to enc board (connect to PR1B pin)
	
	BOARD_SEL : out std_logic_vector(1 downto 0);		-- Called CS1-0 previously and on boards to end Nov 2012
	BOARD_FUNC_SEL : out std_logic_vector(2 downto 0);		-- Called Data/Adr, CS3, CS2 previously and on boards to end Nov 2012
	BOARD_WR : out std_logic;
	BOARD_RD : out std_logic;
	
	GLV_DO : out std_logic_vector(15 downto 0); -- data bus to galvo control board (BUS#3)
	GLV_CLRQ : out std_logic;					-- DAC reset
	GLV_LDACQ : out std_logic;					-- Load pulse active low
	GLV_CSQ : out std_logic;					-- DAC Chip select active low
	GLV_WRQ : out std_logic;					-- DAC data write enable, active low
	
	LASER_EM : out std_logic;
	LASER_EE : out std_logic;
	LASER_SYNCH : out std_logic;
	LASER_BIDIR_DATA : inout std_logic_vector(7 downto 0);
	LASER_ESTOP : out std_logic;
	LASER_GUIDE : out std_logic;
	LASER_PWR_LATCH : out std_logic	-- latch power into the laser (pass-through of signal from mcu)
);
end data_out_fpga;


architecture arch_data_out_fpga of data_out_fpga is

-- *************************************************************
--         DECLARE COMPONENTS AND ASSOCIATED SIGNALS
-- *************************************************************
constant FPGA_version_reg : std_logic_vector(15 downto 0) := x"0200"; -- set high byte to ff if testversion
		
component lout_if is
port (
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
end component;

signal Loutif_dir_to_laser : std_logic;	-- controls the FPGA's use of the laser bus (ie setting it as input or output)
signal Loutif_out_datatolout : std_logic_vector(7 downto 0);
signal Loutif_in_datafromlout : std_logic_vector(7 downto 0);
signal Loutif_out_status_to_mcu : std_logic_vector(13 downto 0);
--signal Loutif_out_status_to_mcu_mod : std_logic_vector(13 downto 0);
signal ext_trigger_reg : std_logic;

-- declare image clock manager
component image_clock_manager
port(
	CLK : in std_logic;
	RESET : in std_logic; 
	PX_DIV : in std_logic_vector(15 downto 0);		-- CLK divided by this to give square waves PX_CLK_xxx
	LASER_CLK_DELAY: in std_logic_vector(15 downto 0);	-- the offset delay from AOD to LASER pixel clocks (value can be from 0 to px_div)

	PX_CLK_AOD  : out std_logic;				-- square wave, one pulse per pixel -- shifts deflection/amplitude data out of LUT into AOD control
	PX_CLK_LASER  : out std_logic;				-- square wave, one pulse per pixel -- drives laser and shifts image data
	PX_CLK_AOD_REDGE  : out std_logic;
	PX_CLK_LASER_FEDGE  : out std_logic
--	ENC_CLK : out std_logic	
);
end component;

-- instance signals
signal Icm_out_px_clk_aod  : std_logic;			-- square wave, one pulse per pixel
signal Icm_out_px_clk_laser  : std_logic;		-- square wave, one pulse per pixel -- drives laser and shifts data
signal Icm_out_px_clk_aod_redge  : std_logic;
signal Icm_out_px_clk_laser_fedge  : std_logic;
--signal Icm_out_enc_clk : std_logic;


-- declare encoder counter
component enc_ctr
port(
	RESET: in std_logic;	-- resets when high
	CLK: in std_logic;		-- system clock input
	ENC: in std_logic;		-- encoder count pulses input (may be asynch)
	FRAC_RE: in std_logic_vector(15 downto 0);
	MARK_EN: in std_logic;		
	FRAC_D : in std_logic_vector(23 downto 0); 
	FRAC_RD : in std_logic_vector(15 downto 0);
	GALVO_STATUS : in std_logic_vector(3 downto 0); 
	
	ENC_CT_TOTAL: out std_logic_vector(23 downto 0);	-- total number of encoder pulses
	FRAC_R_SUM: out std_logic_vector(27 downto 0);
	FRAC_R_ENC: out std_logic_vector(27 downto 0);
	FRAC_ES: out std_logic_vector(17 downto 0);
	SPEED_SYSCLKS: out std_logic_vector(15 downto 0);	-- speed count
	SPEED_ENC_CTS: out std_logic_vector(15 downto 0)	-- speed count
);
end component;


--enc_ctr instance signals	
signal frac_R_sum_reg: std_logic_vector(27 downto 0); --U20.8
signal frac_R_enc_reg: std_logic_vector(27 downto 0); --U20.8
signal frac_ES_reg: std_logic_vector(17 downto 0);
signal Encctr_ct_total: std_logic_vector(23 downto 0);	-- total number of encoder pulses



component gap_manager
port(
	CLK : in std_logic;
	RESET : in std_logic;
	MARK_EN: in std_logic;
	FRAC_R_SUM: in std_logic_vector(27 downto 0); --U20.8
	MARK_ROWS_PER_RPT : in std_logic_vector(15 downto 0);
	ROW_TARGET_REACHED : in std_logic;  
    GAP_LENGTH : in std_logic_vector(15 downto 0);
    GAP_ROW : in std_logic_vector(15 downto 0);
	SETTLING_TIME_BASE : in std_logic_vector(15 downto 0);
	SETTLING_TIME_SMALL : in std_logic_vector(15 downto 0);
	DATA_FROM_MEM_RB : in std_logic_vector(31 downto 0);
	PX_PER_ROW : in std_logic_vector(6 downto 0);
	PX_CLK_DIV: in std_logic_vector(15 downto 0);
	FRAC_DE : in std_logic_vector(19 downto 0); --U4.16
	FRAC_DR : in std_logic_vector(15 downto 0); --U8.8
	FRAC_ES: in std_logic_vector(17 downto 0);
	GALVO_STATUS : in std_logic_vector(3 downto 0);
	REPEAT_READY : in std_logic;
	REPEAT_ROW : in std_logic_vector(27 downto 0); -- U20.8
	
	DEBUG_INFO : out std_logic_vector(23 downto 0);
	GET_NEXT_REPEAT : out std_logic;
	ROW_TARGET : out std_logic_vector(15 downto 0);
	ADDR_TO_MEM_RB : out std_logic_vector(9 downto 0);
    GAP_INDEX : out std_logic_vector(5 downto 0);
	ROW_CLOCK : out std_logic;
	DATA_PIXELS : out std_logic_vector(119 downto 0);
	FRAC_DS_DAC_T : out std_logic_vector(17 downto 0);
	GLV_MOVE : out std_logic_vector (2 downto 0)
);
end component;

--instance signals
signal row_target_reg :  std_logic_vector(15 downto 0);
signal glv_move_reg : std_logic_vector (2 downto 0);
signal ds_dac_t_reg : std_logic_vector(17 downto 0);
signal data_pixels_reg : std_logic_vector(119 downto 0);
signal gapman_addr_to_mem_RB : std_logic_vector(9 downto 0);
signal row_clock_reg : std_logic;
signal get_next_repeat_reg : std_logic;




component repeat_manager
port(
	CLK : in std_logic;
	RESET : in std_logic;
	RESET_PART : in std_logic;
	ROWS_PER_RPT : in std_logic_vector(19 downto 0); -- U20.0
	FRAC_R_ENC: in std_logic_vector(27 downto 0); -- U20.8
	EXT_TRIGGER : in std_logic;
	GET_NEXT_REPEAT : in std_logic;
	USE_EXT_TRIGGER : in std_logic;
	MARK_EN: in std_logic;

	REPEAT_READY : out std_logic;
	REPEAT_ROW : out std_logic_vector(27 downto 0); -- U20.8
	REPEATS_CNT: out std_logic_vector(23 downto 0)
);
end component;

--instance signals
signal repeat_ready_reg : std_logic;
signal repeat_row_reg : std_logic_vector(27 downto 0); --U20.8


component write_laser is
port (
	CLK : in std_logic;					-- system clock
	PX_CLK_AOD_REDGE  : in std_logic;			-- square wave, one pulse per pixel -- drives aod -- expected to toggle on CLK rising edge
	PX_CLK_LASER_FEDGE  : in std_logic;		-- square wave, one pulse per pixel -- drives laser and shifts data -- expected to toggle on CLK rising edge
	RESET : in std_logic;				-- high level empties registers and resets pointers
	DELAY_PX : in std_logic_vector(5 downto 0);	-- the no. of px clks to delay the beam mask by (coarse delay component)
	PX_PER_ROW : in std_logic_vector(6 downto 0);	-- the no. of pixels in one row (max 128)
	ROW_TARGET : in std_logic_vector(15 downto 0);
	CMD : in std_logic_vector(1 downto 0);		-- a shortened version of the main CMD input from MCU via param reg
	DATA_PIXELS : in std_logic_vector(119 downto 0);

	ROWS_MARKED : out std_logic_vector(15 downto 0);
	ADDR_TO_MEM_LUT : out std_logic_vector(9 downto 0);		-- the address for fetching aod data
	LASER_EM : out std_logic;		-- the laser emission output to the laser (= the image data)
	MARKING : out std_logic;
	ROW_TARGET_REACHED : out std_logic
);
end component;

-- instance signals  
signal wrlaser_rows_marked : std_logic_vector(15 downto 0);
signal wrlaser_addr_to_mem_LUT : std_logic_vector(9 downto 0);
signal row_target_reached_reg: std_logic;
signal marking_reg: std_logic;


-- declare mcu interface
component mcu_if
port(
	RESET : in std_logic;								-- low level resets
	CLK : in std_logic;									-- system clock
	RD : in std_logic;									-- read clock pulse
	WR : in std_logic;									-- write clock pulse
	DATA_SEL: in std_logic;								-- Data/#Address
	MEM_SEL : in std_logic;								-- MEM/#Reg  (MEM = RB or LUT;   Reg = Param reg)
	BUFF_SEL : in std_logic;							-- RB/#LUT
	ADDR_HIGH : in std_logic_vector(3 downto 0);		-- upper 4 bits of 12 bit address (lower 8 bits from the bus)
	DATA_FROM_MCU : in std_logic_vector(7 downto 0);

	DATA_TO_MCU : out std_logic_vector(7 downto 0);
	RTS_MCU : out std_logic;							-- Ready To Send -- advise MCU that valid data is now on bus
	DATA_FROM_FPGA : in std_logic_vector(7 downto 0);	-- data received from the fpga (eg enc count value)
	DATA_TO_FPGA  : out std_logic_vector(7 downto 0);	-- data out to the fpga DPRAM
	ADDR_TO_FPGA  : out std_logic_vector(11 downto 0);	-- addr out to the fpga DPRAM
	REG_EN : out std_logic;			-- goes to clock enable ParamReg
	GAP_EN : out std_logic;			-- goes to clock enable GapReg
	MEM_LUT_EN : out std_logic;		-- goes to clock enable input of buffer DPRAM
	MEM_RB_EN : out std_logic;		-- 
	WR_EN : out std_logic			-- write (1) or read (0) level to DPRAM
);
end component;

-- mcu_if instance signals
signal Mcuif_in_data_from_mcu : std_logic_vector(7 downto 0);	
signal Mcuif_out_data_to_mcu : std_logic_vector(7 downto 0);
signal Mcuif_in_data_from_fpga : std_logic_vector(7 downto 0);		-- data received from the fpga (eg enc count value)
signal Mcuif_out_data_to_fpga  : std_logic_vector(7 downto 0);	-- data out to the fpga DPRAM
signal Mcuif_out_addr_to_fpga  : std_logic_vector(11 downto 0);	-- addr out to the fpga DPRAM
signal Mcuif_out_memRB_en : std_logic;		
signal Mcuif_out_memLUT_en : std_logic;		
signal Mcuif_out_reg_en : std_logic;	
signal Mcuif_out_gap_en : std_logic;		-- goes to clock enable input of param reg DPRAM
signal Mcuif_out_wr_en : std_logic;			-- write (1) or read (0) level to DPRAM



component gapreg is
port ( 		
     Clock : in std_logic;
     Reset: in std_logic;							
     DataInA : in std_logic_vector(7 downto 0);			-- from MCU_IF
     AddressA : in std_logic_vector(7 downto 0);		-- from MCU_IF
     ClockEnA: in std_logic;							-- from MCU_IF
     WrA: in std_logic;									-- from MCU_IF
     GapIndex : in std_logic_vector(5 downto 0);		-- from gap msnager, pointer to actual gap data
	 
     GapStartRow : out std_logic_vector(15 downto 0);	-- to gap manager
     Gaplength : out std_logic_vector(15 downto 0)		-- to gap manager	 
);
end component;

signal  GapIndex_reg : std_logic_vector(5 downto 0);
signal  GapStartRow_reg : std_logic_vector(15 downto 0);
signal  Gaplength_reg : std_logic_vector(15 downto 0);



component galvo_dac_manager is
port(
	CLK : in std_logic;
	RESET : in std_logic;
	CMD : in std_logic_vector(1 downto 0);
	GLV_SERVICE : in std_logic_vector(15 downto 0);
	GLV_AMPL : in std_logic_vector(15 downto 0);
	FRAC_DS_DAC_T: in std_logic_vector(17 downto 0); -- U0.18 --> U2.16 alle 4 sysclocks
	GLV_DECR_FAST : in std_logic_vector(15 downto 0); --U8.8
	GALVO_DELAY : in std_logic_vector(7 downto 0);
	GLV_MOVE : in std_logic_vector (2 downto 0); 
	CABLE_DIR : in std_logic;
	MARK_EN: in std_logic;		-- mark enable signal from the MCU
	
	DEBUG_INFO : out std_logic_vector(23 downto 0);
	GALVO_STATUS : out std_logic_vector(3 downto 0);
	FRAC_D : out std_logic_vector(23 downto 0); -- U16.8
	GLV_DO  : out std_logic_vector(15 downto 0);	-- calculated galvo control
	GLV_WRQ  : out std_logic;						-- strobe signal for galvo DAC: data ready (active low)
	GLV_LDACQ  : out std_logic						-- strobe signal for galvo DAC: forward data to DAC(active low)
);
end component;

signal Glv_status : std_logic_vector(3 downto 0);
signal frac_D_reg : std_logic_vector(23 downto 0);

-- declare parameter register
--  64 x 1byte		Used for access by the MCU
component paramreg is
port ( 	
	Reset: in std_logic;
	Clock : in std_logic;							-- data latched on rising edge
	ClockEnA: in std_logic;
	DataInA : in std_logic_vector(7 downto 0);
	AddressA : in std_logic_vector(7 downto 0);	-- 64 x 1 byte so need 6 bit address for
	WrA: in std_logic;
	-- read adresses
	Enc_ct_total : in std_logic_vector(23 downto 0);
	Speed_sysclks	: in std_logic_vector(15 downto 0);		-- no. of sys clks within some encoder pulses
	Speed_enc_cts	: in std_logic_vector(15 downto 0);		-- no. of sys clks within some encoder pulses
	Repeats_moved : in std_logic_vector(23 downto 0);		-- no. of full repeats cable has moved since last reset
	addr_to_mem_RB : in std_logic_vector(9 downto 0);
	Status : in std_logic_vector(13 downto 0);				-- byte 0, 1: status info to mcu
	GALVO_STATUS : in std_logic_vector(3 downto 0);
	FPGA_version : in std_logic_vector(15 downto 0);		-- FPGA program version
	ROWS_MARKED : in std_logic_vector(15 downto 0);
	DEBUG_TX : in std_logic_vector(23 downto 0);
	LOCK_PARAMREG : in std_logic;

	DataOutA : out std_logic_vector(7 downto 0); 
	-- write adresses:
	Px_clk_div : out std_logic_vector(15 downto 0);		-- pixel clock divider for SysClk --> PxClk
	Px_per_row : out std_logic_vector(6 downto 0);			-- pixels per row in this job
	rows_per_rpt : out std_logic_vector(19 downto 0);
	Mark_rows_per_rpt : out std_logic_vector(15 downto 0);	-- rows to be marked per repeat for this job
	Beam_px_delay : out std_logic_vector(5 downto 0);		-- no. of px clks to delay beam by ie coarse delay
	Beam_clk_delay : out std_logic_vector(15 downto 0);	-- no. of sys clks to delay laser px clk by ie fine delay
	FRAC_DR : out std_logic_vector(15 downto 0);
	FRAC_RE : out std_logic_vector(15 downto 0);
	Addr_high_dpram : out std_logic_vector(3 downto 0);	-- bits 3-0 (the upper 4 bits of the 12 bit address for dpram port A
	Cable_dir_flag : out std_logic;						-- bit 0 (the encoder direction flag to be sent to enc bd
	Guide_en : out std_logic;								-- bit 1
	GLV_AMPL : out std_logic_vector(15 downto 0);			-- 2 bytes, maximum galvo PHI value which can be handled. 
	FRAC_DE : out std_logic_vector(19 downto 0); 
	Glv_decr_fast : out std_logic_vector(15 downto 0);		-- 8 bit vorkomma, 8 bit nachkomma: DAC-digits pro sysclock
	FRAC_RD : out std_logic_vector(15 downto 0);
	SETTLING_TIME_BASE : out std_logic_vector(15 downto 0);
	SETTLING_TIME_SMALL : out std_logic_vector(15 downto 0);
	Glv_service : out std_logic_vector(15 downto 0);		-- fix galvo mirror postion for service . 
	DEBUG_RX : out std_logic_vector(23 downto 0);
	CONTROL_CODE : out std_logic_vector(7 downto 0);
	Command : out std_logic_vector(23 downto 0)			-- command
);
end component;


-- ParamReg instance signals 
signal  Cable_dir_flag : std_logic;  
signal  Reg_Px_clk_div :  std_logic_vector(15 downto 0);		
signal  Reg_speed_sysclks : std_logic_vector(15 downto 0);
signal  Reg_speed_enc_cts : std_logic_vector(15 downto 0);
signal  Reg_Px_per_row :  std_logic_vector(6 downto 0);	
signal  Reg_rows_per_rpt :  std_logic_vector(19 downto 0);
signal  Reg_Mark_rows_per_rpt :  std_logic_vector(15 downto 0);	
signal  Reg_Repeats_moved :  std_logic_vector(23 downto 0);
signal  Reg_Beam_px_delay :  std_logic_vector(5 downto 0);
signal  Reg_Beam_clk_delay :  std_logic_vector(15 downto 0);
signal  frac_DR_reg : std_logic_vector(15 downto 0);
signal  frac_RE_reg : std_logic_vector(15 downto 0);
signal  Reg_Addr_high_dpram :  std_logic_vector(3 downto 0);
signal  Reg_glv_ampl : std_logic_vector(15 downto 0);
signal	frac_DE_reg : std_logic_vector(19 downto 0); 
signal	Reg_glv_decr_fast : std_logic_vector(15 downto 0);
signal	frac_RD_reg : std_logic_vector(15 downto 0);

signal  reg_settling_time_base : std_logic_vector(15 downto 0);
signal  reg_settling_time_small : std_logic_vector(15 downto 0);
signal  Reg_Glv_service  : std_logic_vector(15 downto 0);
signal  Reg_Command : std_logic_vector(23 downto 0);
signal lock_paramreg_sig: std_logic := '0'; 


-- declare mem data buffer memory (dpram4wide)
--
-- Data buffer memory is 4096 bytes, and is used as follows:
-- Port A faces the MCU and is used for writing only (access by MCU_IF only)
-- Port A is organized as 4096 x 1 byte
-- Port B faces the FPGA/AOD and is used for reading only (access by LOUT_IF only)
-- Port B is organized as 1024 x 4 bytes
component dpram4wide
port ( 	
	DataInA: in  std_logic_vector(7 downto 0); 
	AddressA: in  std_logic_vector(11 downto 0); 
	AddressB: in  std_logic_vector(9 downto 0); 
	Clock: in  std_logic; 
	ClockEnA: in  std_logic; 			-- needed since mcuif talks with both mem and reg
	--ClockEnB: in  std_logic;			-- not needed since only loutif accesses port B
	Reset: in  std_logic;
	
	DataOutB: out  std_logic_vector(31 downto 0)
);
end component;

-- mem instance signals
signal MemLUT_DataOutB: std_logic_vector(31 downto 0);
signal MemRB_DataOutB: std_logic_vector(31 downto 0);



 


-- declare other signals
signal Clk_sig: std_logic;					-- buffer for main clk_sys	
signal Reset_buf : std_logic := '0'; -- the incoming reset from the mcu
signal Reset_glob : std_logic := '1';	
signal Reset_part : std_logic := '1';
signal Mcu_mark_en_reg : std_logic;
signal Cmd_code : std_logic_vector(7 downto 0);		-- the command value
signal Cmd_param1 : std_logic_vector(7 downto 0);		-- command parameter
signal Cmd_param2 : std_logic_vector(7 downto 0);		-- command parameter
signal control_code_reg : std_logic_vector(7 downto 0);		-- additional command
signal debug_rx_reg : std_logic_vector(23 downto 0);
signal debug_tx_reg : std_logic_vector(23 downto 0);


begin	-- architecture

-- *************************************************************
--                  INSTANTIATE COMPONENTS
-- *************************************************************

-- instantiate lout_if
-- Optionally connect the row clock from the icm (divided pixel clock) or from the encctr (divided enc pulses)
loutif : lout_if
port map(
	CLK => Clk_sig,
	START_AOD => Icm_out_px_clk_aod_redge,
	RESET => Reset_glob,
	CMD => Cmd_code(1 downto 0),
	CMD_PAR1 => Cmd_param1,
	CMD_PAR2 => Cmd_param2,
	DATA_FROM_MEM_LUT => MemLUT_DataOutB,
	DATA_FROM_LOUT => Loutif_in_datafromlout,
	
	BOARD_SEL => BOARD_SEL,
	BOARD_FUNC_SEL => BOARD_FUNC_SEL,	
	BOARD_WR => BOARD_WR,
	BOARD_RD => BOARD_RD,
	DIR_TO_LASER => Loutif_dir_to_laser,
	DATA_TO_LOUT  => Loutif_out_datatolout,	
	LASER_PWR_LATCH => LASER_PWR_LATCH,
	TRIGGER_REPEAT => ext_trigger_reg,
	STATUS_TO_MCU => Loutif_out_status_to_mcu
);


-- instantiate image clock manager
imgclkmgr : image_clock_manager
port map(
	CLK => Clk_sig,
	RESET => Reset_glob,
	PX_DIV => Reg_Px_clk_div,
	LASER_CLK_DELAY => Reg_Beam_clk_delay,			

	PX_CLK_AOD => Icm_out_px_clk_aod,		-- square wave, one pulse per pixel -- drives laser and shifts data
	PX_CLK_LASER => Icm_out_px_clk_laser,	-- square wave, one pulse per pixel -- drives laser and shifts data
	PX_CLK_AOD_REDGE => Icm_out_px_clk_aod_redge,	
	PX_CLK_LASER_FEDGE => Icm_out_px_clk_laser_fedge	
--	ENC_CLK => Icm_out_enc_clk				-- clock for encoder
);

-- instantiate enc_ctr
encctr : enc_ctr
port map(
	RESET => Reset_part,
	CLK => Clk_sig,
	ENC => ENC_ENC,
	FRAC_RE => frac_RE_reg,
	MARK_EN => Mcu_mark_en_reg,
	FRAC_D => frac_D_reg,
	FRAC_RD => frac_RD_reg,
	GALVO_STATUS => Glv_status,

	ENC_CT_TOTAL => Encctr_ct_total,
	FRAC_R_SUM => frac_R_sum_reg,
	FRAC_R_ENC => frac_R_enc_reg,
	FRAC_ES => frac_ES_reg,
	SPEED_SYSCLKS => Reg_speed_sysclks,
	SPEED_ENC_CTS => Reg_speed_enc_cts
);

gapman: gap_manager
port map(
	CLK => Clk_sig,
	RESET => Reset_part,
	MARK_EN => Mcu_mark_en_reg,
	FRAC_R_SUM => frac_R_sum_reg,
	MARK_ROWS_PER_RPT => Reg_Mark_rows_per_rpt,
	ROW_TARGET_REACHED => row_target_reached_reg,  
    GAP_LENGTH => Gaplength_reg,
    GAP_ROW => GapStartRow_reg,
	SETTLING_TIME_BASE => reg_settling_time_base,
	SETTLING_TIME_SMALL => reg_settling_time_small,
	DATA_FROM_MEM_RB => MemRB_DataOutB,
	PX_PER_ROW => Reg_Px_per_row,
	PX_CLK_DIV => Reg_Px_clk_div,
	FRAC_DE => frac_DE_reg,
	FRAC_DR => frac_DR_reg,
	FRAC_ES => frac_ES_reg,
	GALVO_STATUS => Glv_status,
	REPEAT_READY => repeat_ready_reg,
	REPEAT_ROW => repeat_row_reg,
	
	--DEBUG_INFO => debug_tx_reg,
	GET_NEXT_REPEAT => get_next_repeat_reg,
	ROW_TARGET => row_target_reg,	ADDR_TO_MEM_RB => gapman_addr_to_mem_RB,
	GAP_INDEX => GapIndex_reg,
	ROW_CLOCK => row_clock_reg,
	DATA_PIXELS => data_pixels_reg,
	FRAC_DS_DAC_T=> ds_dac_t_reg,
	GLV_MOVE => glv_move_reg
);


repeatman: repeat_manager
port map(
	CLK => Clk_sig,
	RESET => Reset_glob,
	RESET_PART => Reset_part,
	ROWS_PER_RPT => Reg_rows_per_rpt,
	FRAC_R_ENC => frac_R_enc_reg,
	EXT_TRIGGER => ext_trigger_reg, -- CLK_ROW,
	GET_NEXT_REPEAT => get_next_repeat_reg,
	USE_EXT_TRIGGER => control_code_reg(1),
	MARK_EN => Mcu_mark_en_reg,
	
	REPEAT_READY => repeat_ready_reg,
	REPEAT_ROW => repeat_row_reg,
	REPEATS_CNT => Reg_Repeats_moved
);



wrlaser : write_laser
port map(
	CLK => Clk_sig,
	PX_CLK_AOD_REDGE => Icm_out_px_clk_aod_redge,
	PX_CLK_LASER_FEDGE => Icm_out_px_clk_laser_fedge,
	RESET => Reset_part,
	DELAY_PX => Reg_Beam_px_delay,
	PX_PER_ROW => Reg_Px_per_row,
	ROW_TARGET => row_target_reg,
	CMD => Cmd_code(1 downto 0),
	DATA_PIXELS => data_pixels_reg,
	
	ROWS_MARKED => wrlaser_rows_marked,
	ADDR_TO_MEM_LUT => wrlaser_addr_to_mem_LUT,
	LASER_EM => LASER_EM,
	MARKING => marking_reg,
	ROW_TARGET_REACHED => row_target_reached_reg
);



-- instantiate mcu interface
mcuif : mcu_if
port map(
	CLK => Clk_sig,	-- system clock
	RESET => Reset_glob,
	RD => MCU_RD,	-- read clock pulse
	WR => MCU_WR,	-- write clock pulse	
	DATA_SEL => MCU_DATA_SEL,		-- VS ADDR			
	MEM_SEL => MCU_MEM_SEL,
	BUFF_SEL => MCU_BUFF_SEL,
	ADDR_HIGH => Reg_Addr_high_dpram,
	DATA_FROM_MCU => Mcuif_in_data_from_mcu,
	DATA_FROM_FPGA => Mcuif_in_data_from_fpga,		-- data received from the fpga (eg enc count value)
	
	RTS_MCU => MCU_RTS_MCU,			-- Ready To Send -- advise MCU that valid data is now on bus
	DATA_TO_MCU => Mcuif_out_data_to_mcu,
	DATA_TO_FPGA => Mcuif_out_data_to_fpga,	-- data out to the fpga DPRAM
	ADDR_TO_FPGA => Mcuif_out_addr_to_fpga,	-- addr out to the fpga DPRAM
	REG_EN => Mcuif_out_reg_en,
	GAP_EN => Mcuif_out_gap_en,
	MEM_LUT_EN => Mcuif_out_memLUT_en,
	MEM_RB_EN => Mcuif_out_memRB_en,
	WR_EN => Mcuif_out_wr_en 			-- write (1) or read (0) level to DPRAM
);


-- instantiate gap information registers
gapinf : gapreg 
port map( 		
     Clock => Clk_sig,
     Reset => Reset_glob,			
     DataInA => Mcuif_out_data_to_fpga,
     AddressA => Mcuif_out_addr_to_fpga(7 downto 0),
     ClockEnA => Mcuif_out_gap_en,
     WrA => Mcuif_out_wr_en,
     GapIndex => GapIndex_reg,
	 
     GapStartRow => GapStartRow_reg,
     Gaplength => Gaplength_reg 	 
);

	 
gdm : galvo_dac_manager
port map(
	CLK => Clk_sig,
	RESET => Reset_part,
	CMD => Cmd_code(1 downto 0),
	GLV_SERVICE => Reg_Glv_service, 
	GLV_AMPL => Reg_glv_ampl,
	FRAC_DS_DAC_T=> ds_dac_t_reg,
	GLV_DECR_FAST => Reg_glv_decr_fast,
	GALVO_DELAY => x"61", -- 0x61 = 97 --> 97*32/24 = 129.3 us
	GLV_MOVE => glv_move_reg,
	CABLE_DIR => Cable_dir_flag,
	MARK_EN => Mcu_mark_en_reg,

	--DEBUG_INFO => debug_tx_reg,
	GALVO_STATUS => Glv_status,
	FRAC_D => frac_D_reg,
	GLV_DO => GLV_DO,			-- downsampled mirror position
	GLV_WRQ => GLV_WRQ,			-- strobe signal for galvo DAC: data ready (active low)
	GLV_LDACQ => GLV_LDACQ		-- strobe signal for galvo DAC: forward data to DAC(active low)
);


-- instantiate parameter register
reg : paramreg
port map (
	Reset => Reset_glob,
	Clock => Clk_sig,
	ClockEnA => Mcuif_out_reg_en,
	DataInA => Mcuif_out_data_to_fpga,
	AddressA => Mcuif_out_addr_to_fpga(7 downto 0),
	WrA => Mcuif_out_wr_en,
	Enc_ct_total => Encctr_ct_total,
	Speed_sysclks => Reg_speed_sysclks,
	Speed_enc_cts => Reg_speed_enc_cts,
	Repeats_moved => Reg_Repeats_moved,
	addr_to_mem_RB => gapman_addr_to_mem_RB,
	Status => Loutif_out_status_to_mcu, -- Loutif_out_status_to_mcu_mod
	GALVO_STATUS => Glv_status,
	FPGA_version => FPGA_version_reg,
	ROWS_MARKED => wrlaser_rows_marked,
	DEBUG_TX => debug_tx_reg,
	LOCK_PARAMREG => lock_paramreg_sig,

	DataOutA => Mcuif_in_data_from_fpga,
	Px_clk_div => Reg_Px_clk_div,
	Px_per_row => Reg_Px_per_row,
	rows_per_rpt => Reg_rows_per_rpt,
	Mark_rows_per_rpt => Reg_Mark_rows_per_rpt,
	Beam_px_delay => Reg_Beam_px_delay,
	Beam_clk_delay => Reg_Beam_clk_delay,
	FRAC_DR => frac_DR_reg,
	FRAC_RE => frac_RE_reg,
	Addr_high_dpram => Reg_Addr_high_dpram,
	Cable_dir_flag => Cable_dir_flag,
	Guide_en => LASER_GUIDE,
	GLV_AMPL => Reg_glv_ampl,
	FRAC_DE => frac_DE_reg,
	Glv_decr_fast => Reg_glv_decr_fast,
	FRAC_RD => frac_RD_reg,
	SETTLING_TIME_BASE => reg_settling_time_base,
	SETTLING_TIME_SMALL => reg_settling_time_small,
	Glv_service => Reg_Glv_service,
	DEBUG_RX => debug_rx_reg,
	CONTROL_CODE => control_code_reg,
	Command => Reg_Command
);


-- instantiate LUT buffer
-- For LUT use bytes 0 - 511
-- Port A uses 512 x 1 byte
-- Port B uses 128 x 4 bytes
--		Word 1		3&2 = freq for pixel	(1 output word of 4 bytes gives both freq and mod, so 1 clock cycle)
--					1&0 = mod for pixel
--		Word 2		7&6 = freq for next pixel
--					5&4 = mod for next pixel
--	     ....
memLUT : dpram4wide
port map (
     DataInA => Mcuif_out_data_to_fpga,
     AddressA => Mcuif_out_addr_to_fpga,
     AddressB => wrlaser_addr_to_mem_LUT,	-- loutif is the only component accessing mem port B
     Clock => Clk_sig,
     ClockEnA => Mcuif_out_memLUT_en,
     Reset => Reset_glob,

     DataOutB => MemLUT_DataOutB
);


-- instantiate RB buffer
-- For Ring buffer use 4096 bytes
-- Segment 0 is 0 - 2047
-- Segment 1 is 2048 - 4095
-- Port A uses 4096 x 1 byte
-- Port B uses 1024 x 4 bytes
-- One row out of port B comprises 16 bytes (four 4-byte addresses).
--		Row 1		0-15 on Port A, 0-3 on port B
--      .....
--      Row 128
memRB : dpram4wide
port map (
     DataInA => Mcuif_out_data_to_fpga,
     AddressA => Mcuif_out_addr_to_fpga,
     AddressB => gapman_addr_to_mem_RB,	-- loutif is the only component accessing mem port B
     Clock => Clk_sig,
     ClockEnA => Mcuif_out_memRB_en,
     Reset => Reset_glob,
	 
     DataOutB => MemRB_DataOutB
);



-- *************************************************************
--             		 BEHAVIOUR -- Outputs
-- *************************************************************
	
	ENC_DIR <= Cable_dir_flag;

	
-- *************************************************************
--             		 BEHAVIOUR -- COMMANDS
-- *************************************************************
	Cmd_code <= Reg_Command(7 downto 0);
	Cmd_param1 <= Reg_Command(15 downto 8);
	Cmd_param2 <= Reg_Command(23 downto 16);
	
-- *************************************************************
--             	 BEHAVIOUR -- LASER OUT STRAIGHT
-- *************************************************************
	LASER_SYNCH <= Icm_out_px_clk_laser;
	LASER_EE <= NOT(Reset_part) AND Mcu_mark_en_reg; -- long-term laser enable: beam available after 5ms from this going high

	LASER_ESTOP <= '1';	

	MCU_MARKING <= marking_reg;
	
	--The bus is an output when NOT reading (ie Laser_RD is high)
	LASER_BIDIR_DATA <= Loutif_out_datatolout when (Loutif_dir_to_laser = '1') else (others => 'Z');
	Loutif_in_datafromlout <= LASER_BIDIR_DATA(7 downto 0);		-- LaserO/Temp is not connected to FPGA yet
	
-- *************************************************************
--            	    BEHAVIOUR -- CLOCKS
-- *************************************************************

	Clk_sig <= CLK_SYS;
	CLK_SYS_TEST_O <= Clk_sig;
	CLK_ENC <= CLK_SYS; --Icm_out_enc_clk;
		
	CLK_PX_AOD <= control_code_reg(1);--Icm_out_px_clk_aod;
	CLK_PX_LASER <= ext_trigger_reg;--Icm_out_px_clk_laser;
	
	-- test pins
	process(Clk_sig)
		variable toggle: std_logic := '1';
	begin
		if rising_edge(Clk_sig) then
			if (row_clock_reg = '1') then 
				--CLK_ROW <= toggle;
				toggle := toggle XOR '1';
			end if;
			
			--globaler reset
			Reset_buf <= MCU_RESET; -- puffer
			Reset_glob <= Reset_buf;		
			-- partieller reset:
			Reset_part <= control_code_reg(0) OR Reset_buf;
			
			Mcu_mark_en_reg <= MCU_MARK_EN;
			lock_paramreg_sig <= MCU_LOCK_PARAMREG;
		end if;
	end process;

	--CLK_RPT <= get_next_repeat_reg; --glv_move_reg(2);
	--CLK_ROW2 <= glv_move_reg(0);
	--Loutif_out_status_to_mcu_mod <= Loutif_out_status_to_mcu(13 downto 7) & CLK_RPT & Loutif_out_status_to_mcu(5 downto 3) & CLK_ROW2 & Loutif_out_status_to_mcu(1 downto 0);

-- *************************************************************
--                BEHAVIOUR -- ENCODER COUNTER
-- *************************************************************
-- Connect the encoder counter to the encoder pulses
-- and to the REG DPRAM port B (to hold the speed count)
-- *************************************************************
	
-- *************************************************************
--            	    BEHAVIOUR -- DAC control
-- *************************************************************
	GLV_CSQ  <= '0'; --always chip select
	GLV_CLRQ <= NOT Reset_glob; -- DAC reset is active low


-- *************************************************************
--                	  BEHAVIOUR -- MCUIF
-- *************************************************************
-- Connect the MCUIF to the two DPRAMs MEM (=RB OR LUT) and REG
-- *************************************************************

	-- Drive the Bidirectional port
	MCU_BIDIR_DATA <= Mcuif_out_data_to_mcu;
	-- Read the Bidirectional port
	Mcuif_in_data_from_mcu <= MCU_BIDIR_DATA;
	
	
end arch_data_out_fpga;



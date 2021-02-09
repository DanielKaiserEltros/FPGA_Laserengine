library ieee;
use ieee.NUMERIC_STD.all;
use ieee.STD_LOGIC_UNSIGNED.all;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;

	-- Add your library and packages declaration here ...

entity MAINt_fpga_tb is
end MAINt_fpga_tb;
 
architecture TB_ARCHITECTURE of MAINt_fpga_tb is  

-- Clock period definitions
constant clk_period : time := 10 ns;  	 

-- enc pulse period , i.e. cable speed	   
constant enc_period : time := 678 ns; 

	-- Component declaration of the tested unit
	component data_out_fpga
	port(
	CLK_SYS : in std_logic;				-- 24MHz crystal clock
	CLK_PX_LASER  : out std_logic;
	CLK_PX_AOD : out std_logic;
	CLK_ROW : out std_logic;
	CLK_ENC : out std_logic;			-- a 4MHz clock signal to enc board (from dividing 24MHz CLK) to PT24D
	CLK_ROW2 : out std_logic;
	CLK_RPT : out std_logic;

	MCU_BIDIR_DATA : inout std_logic_vector(7 downto 0);
	MCU_RD : in std_logic;
	MCU_WR : in std_logic;
	MCU_MARK_EN : in std_logic;			-- controls EE line to laser, and gates ENC pulses from encoder board
	MCU_DATA_SEL : in std_logic;		-- used as pre-latch signal to latch laser power setting into ext
	MCU_MEM_SEL : in std_logic;			-- MEM/#REG	(Choose buffer memory (LUT/RB)  or  parameter register)
	MCU_BUFF_SEL : in std_logic;		-- BUFF/#LUT	(Choose RB   or   LUT)
	MCU_RTR_MCU : out std_logic;		-- Ready To Receive -- advise MCU it may send new addr/data on bus
	MCU_RTS_MCU : out std_logic;		-- Ready To Send -- advise MCU that valid data is now on bus
	MCU_FILL_RQ : out std_logic;		-- request to mcu to fill up the next RB segment
	MCU_MARKING : out std_logic;		-- goes high to indicate that marking is taking place; low means gap

	ENC_ENC : in std_logic;				-- encoder pulses from the encoder board (normally PR1A but use PL14A for test input)
	ENC_DIR : out std_logic;			-- the direction bit going to enc board (connect to PR1B pin)
	ENC_ENC2 : out std_logic;			-- a copy of the incoming ENC_ENC signal for viewing during test
	
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
	end component; 
	

	-- Stimulus signals - signals mapped to the input and inout ports of tested entity
	signal CLK_SYS : STD_LOGIC := '0';
	signal MCU_RD : STD_LOGIC := '1';
	signal MCU_WR : STD_LOGIC := '1';
	signal MCU_MARK_EN : STD_LOGIC := '0';
	signal MCU_DATA_SEL : STD_LOGIC := '0';
	signal MCU_MEM_SEL : STD_LOGIC := '0';
	signal MCU_BUFF_SEL : STD_LOGIC := '0';
	signal ENC_ENC : STD_LOGIC := '0';
	signal MCU_BIDIR_DATA : STD_LOGIC_VECTOR(7 downto 0) := ( others => 'Z' );
	signal LASER_BIDIR_DATA : STD_LOGIC_VECTOR(7 downto 0) := (OTHERS => '0');
	-- Observed signals - signals mapped to the output ports of tested entity
	signal CLK_SYS_OUTFORTEST : STD_LOGIC;
	signal CLK_PX_LASER : STD_LOGIC;
	signal CLK_PX_AOD : STD_LOGIC;
	signal CLK_ROW : STD_LOGIC;
	signal CLK_ENC : STD_LOGIC;
	signal CLK_ROW2 : STD_LOGIC;
	signal CLK_RPT : STD_LOGIC;
	signal MCU_RTR_MCU : STD_LOGIC;
	signal MCU_RTS_MCU : STD_LOGIC;
	signal MCU_FILL_RQ : STD_LOGIC;
	signal MCU_MARKING : STD_LOGIC;
	signal ENC_DIR : STD_LOGIC;
	signal ENC_ENC2 : STD_LOGIC;
	signal BOARD_SEL : STD_LOGIC_VECTOR(1 downto 0);
	signal BOARD_FUNC_SEL : STD_LOGIC_VECTOR(2 downto 0);
	signal BOARD_WR : STD_LOGIC;
	signal BOARD_RD : STD_LOGIC;
	signal LASER_EM : STD_LOGIC;
	signal LASER_EE : STD_LOGIC;
	signal LASER_SYNCH : STD_LOGIC;
	signal LASER_ESTOP : STD_LOGIC;
	signal LASER_GUIDE : STD_LOGIC;
	signal LASER_PWR_LATCH : STD_LOGIC;	
	signal GLV_DO : std_logic_vector(15 downto 0); 
	signal GLV_CLRQ :  std_logic;					-- DAC reset
	signal GLV_LDACQ :  std_logic;					-- Load pulse active low
	signal GLV_CSQ :  std_logic;					-- DAC Chip select active low
	signal GLV_WRQ :  std_logic;					-- DAC data write enable, active low
	signal SV3 : STD_LOGIC_VECTOR(7 downto 0);
	signal TEST : STD_LOGIC;
	signal TEST2 : STD_LOGIC;
	signal TEST3 : STD_LOGIC;  
	signal LastREADword : std_logic_vector(15 downto 0); 
	signal LastREADbyte : std_logic_vector(7 downto 0);
	  

begin 

	-- Unit Under Test port map
	UUT : data_out_fpga
		port map (
			CLK_SYS => CLK_SYS,
			-- CLK_SYS_OUTFORTEST => CLK_SYS_OUTFORTEST,
			CLK_PX_LASER => CLK_PX_LASER,
			CLK_PX_AOD => CLK_PX_AOD,
			CLK_ROW => CLK_ROW,
			CLK_ENC => CLK_ENC,
			CLK_ROW2 => CLK_ROW2,
			CLK_RPT => CLK_RPT,
			MCU_BIDIR_DATA => MCU_BIDIR_DATA,
			MCU_RD => MCU_RD,
			MCU_WR => MCU_WR,
			MCU_MARK_EN => MCU_MARK_EN,
			MCU_DATA_SEL => MCU_DATA_SEL,
			MCU_MEM_SEL => MCU_MEM_SEL,
			MCU_BUFF_SEL => MCU_BUFF_SEL,
			MCU_RTR_MCU => MCU_RTR_MCU,
			MCU_RTS_MCU => MCU_RTS_MCU,
			MCU_FILL_RQ => MCU_FILL_RQ,
			MCU_MARKING => MCU_MARKING,
			ENC_ENC => ENC_ENC,
			ENC_DIR => ENC_DIR,
			ENC_ENC2 => ENC_ENC2,
			BOARD_SEL => BOARD_SEL,
			BOARD_FUNC_SEL => BOARD_FUNC_SEL,
			BOARD_WR => BOARD_WR,
			BOARD_RD => BOARD_RD,
			LASER_EM => LASER_EM,
			LASER_EE => LASER_EE,
			LASER_SYNCH => LASER_SYNCH,
			LASER_BIDIR_DATA => LASER_BIDIR_DATA,	   
	    	GLV_DO => GLV_DO, 
	    	GLV_CLRQ => GLV_CLRQ,
			GLV_LDACQ	=>	GLV_LDACQ,
			GLV_CSQ => GLV_CSQ ,
			GLV_WRQ => GLV_WRQ,
			LASER_ESTOP => LASER_ESTOP,
			LASER_GUIDE => LASER_GUIDE,
			LASER_PWR_LATCH => LASER_PWR_LATCH
		);

-- Clock process definitions
   clk_process :process
   begin
		CLK_SYS <= '0';
		wait for clk_period/2;
		CLK_SYS <= '1';
		wait for clk_period/2;
   end process;			 

-- Encoder Pulse	
end_process : process
begin
	wait for enc_period;
	wait until CLK_ENC = '1';
	ENC_ENC <= '1';	 
	wait until CLK_ENC = '0';
	ENC_ENC <= '0';	
end process;

stimulus : process is  

procedure write_reset is
begin 
	MCU_WR <= '1';  	 
	wait for 50ns ;
	MCU_BIDIR_DATA <=  x"3c" ;	
	MCU_WR <= '0';	 
	wait for 50ns ;
	MCU_WR <= '1';	 
	wait for 50ns ;    
	MCU_DATA_SEL <= '1' ;
	MCU_BIDIR_DATA <= x"03";
	wait for 20ns ; 
	MCU_WR <= '0';	 
	wait for 50ns ;
	MCU_WR <= '1';	
	wait for 50ns ; 
	MCU_BIDIR_DATA <= ( others => 'Z' )	; 				   
	MCU_DATA_SEL <= '0' ;
end procedure ;	
	
procedure write_param_byte 
(   par_adr : in std_logic_vector(7 downto 0) ;
  	par_byte : in std_logic_vector(7 downto 0) ) is	
begin 
	MCU_WR <= '1';	  
	--wait until NOT(MCU_RTR_MCU = '0') ;  	 
	wait for 50ns ;
	MCU_BIDIR_DATA <= par_adr;	
	MCU_WR <= '0';	 
	wait for 50ns ;
	MCU_WR <= '1';	 
	wait for 50ns ;    
	MCU_DATA_SEL <= '1' ;	
	-- wait until MCU_RTR_MCU = '1' ;
	MCU_BIDIR_DATA <= par_byte;
	wait for 50ns ; 
	MCU_WR <= '0';	 
	wait for 50ns ;
	MCU_WR <= '1';	
	wait for 50ns ; 
	MCU_BIDIR_DATA <= ( others => 'Z' )	; 				   
	MCU_DATA_SEL <= '0' ;
end procedure ;	

Procedure write_param_16bit 
(   par_adr : in std_logic_vector(7 downto 0) ;
  	par_2byte : in std_logic_vector(15 downto 0) )   is
	variable byte_adr :  STD_LOGIC_VECTOR(7 downto 0);
begin 
	byte_adr := par_adr;  
	write_param_byte (	byte_adr , 	par_2byte( 7 downto 0));
	byte_adr := byte_adr + x"01"; 
	write_param_byte (	byte_adr , 	par_2byte(15 downto 8));	  
end procedure;

Procedure write_param_24bit 
(   par_adr : in std_logic_vector(7 downto 0) ;
  	par_3byte : in std_logic_vector(23 downto 0) )   is
	variable byte_adr :  STD_LOGIC_VECTOR(7 downto 0);
begin 
	byte_adr := par_adr;  
	write_param_byte (	byte_adr , 	par_3byte( 7 downto 0));
	byte_adr := byte_adr + x"01"; 
	write_param_byte (	byte_adr , 	par_3byte(15 downto 8));
	byte_adr := byte_adr + x"01";
	write_param_byte (	byte_adr , 	par_3byte(23 downto 16));	  
end procedure; 

procedure read_param_byte 
(   par_adr : in std_logic_vector(7 downto 0) ) is	
begin 
	MCU_RD <= '1';
	MCU_WR <= '1';	
	MCU_DATA_SEL <= '0';		 
	wait for 50ns ;
	--wait until (MCU_RTR_MCU = '1') ;	
	MCU_BIDIR_DATA <= par_adr;	
	
	MCU_WR <= '0';	 
	wait for 50ns ;
	MCU_WR <= '1';
	MCU_RD <= '0';	 
	wait for 50ns ;
	MCU_BIDIR_DATA <= ( others => 'Z' )	;
	wait until MCU_RTS_MCU = '1';
	wait for 5ns ; 
	LastREADbyte <=  MCU_BIDIR_DATA;
	wait for 5ns ;
	MCU_RD <= '1';	

end procedure ;	

Procedure read_param_16bit 
(   par_adr : in std_logic_vector(7 downto 0) )   is
	variable byte_adr :  STD_LOGIC_VECTOR(7 downto 0);
begin 
	byte_adr := par_adr;  
	read_param_byte (	byte_adr );	
	LastREADword(7 downto 0) <= LastREADbyte;
	byte_adr := byte_adr + x"01"; 
	read_param_byte (	byte_adr );	
	LastREADword(15 downto 8) <= LastREADbyte;  
end procedure;

begin
   
	wait for 150ns ;
--reset by MCU
write_reset; 	-- write RESET to command register

read_param_16bit( x"2a");    -- read FPGA_version
wait for 5us ;
-- register setup
write_param_24bit ( x"00" , x"000026"); -- Px_clk_div 	 
write_param_24bit ( x"04" , x"00000a"); -- Row_clk_div 	
write_param_16bit ( x"38" , x"1111"); 	-- Galvo service postion 
write_param_byte  ( x"0c" , x"08"); 	-- Px_per_row 
write_param_24bit ( x"10" , x"000a00"); -- Enc_per_rpt		 
write_param_16bit ( x"14" , x"0050"); 	-- Mark_rows_per_rpt		 
write_param_byte  ( x"1c" , x"07"); 	-- Beam_px_delay		 
write_param_24bit ( x"20" , x"000040");	-- Beam_clk_delay	 
write_param_24bit ( x"24" , x"070502"); -- byte 0 : Enc_cts_per_row	
										-- byte 1 bits 3-0 Addr_high_dpram
			 							-- byte 2 bit 0 Enc_dir_flag
			 							-- byte 2 bit 1 Guide_en 
										-- byte 2 bit 2 Galvo service postion enable 
wait for 2us ;	 
write_param_24bit ( x"24" , x"030502"); -- byte 0 : Enc_cts_per_row	
										-- byte 1 bits 3-0 Addr_high_dpram
			 							-- byte 2 bit 0 Enc_dir_flag
			 							-- byte 2 bit 1 Guide_en 
										-- byte 2 bit 2 Galvo service postion enable
write_param_16bit ( x"2c" , x"1543");	-- PHI_incr	  
write_param_16bit ( x"2e" , x"0078");	-- PHI_start	 
write_param_byte  ( x"30" , x"04");  	-- PHI_gain	
write_param_byte  ( x"34" , x"03");		-- mirror settling time
write_param_16bit ( x"38" , x"1111"); 	-- Galvo service postion
write_param_byte  ( x"9c" , x"77"); 	-- non existent register	 
write_param_16bit ( x"40" , x"0011"); -- first gap start  	 
write_param_16bit ( x"42" , x"0002"); -- first gap length  
write_param_16bit ( x"44" , x"0023"); --  gap start  	 	  2
write_param_16bit ( x"46" , x"0004"); --  gap length	   
write_param_16bit ( x"48" , x"0033"); --  gap start  	 	  3
write_param_16bit ( x"4a" , x"0006"); --  gap length	 
write_param_16bit ( x"4c" , x"0043"); --  gap start  	 	  4
write_param_16bit ( x"4e" , x"0009"); --  gap length	 
write_param_16bit ( x"50" , x"0053"); --  gap start  	 	   5
write_param_16bit ( x"52" , x"0007"); --  gap length	 
write_param_16bit ( x"54" , x"0063"); --  gap start  	 	  6
write_param_16bit ( x"56" , x"000a"); --  gap length	 
write_param_16bit ( x"58" , x"0073"); --  gap start  	 	  7
write_param_16bit ( x"5a" , x"000b"); --  gap length	 
write_param_16bit ( x"5c" , x"0083"); --  gap start  	 	  8
write_param_16bit ( x"5e" , x"0004"); --  gap length	 
write_param_16bit ( x"60" , x"0093"); --  gap start  	 	  9
write_param_16bit ( x"62" , x"0005"); --  gap length	 
write_param_16bit ( x"64" , x"00a3"); --  gap start  	 	  10
write_param_16bit ( x"66" , x"0005"); --  gap length	 
write_param_16bit ( x"68" , x"00b3"); --  gap start  	 	   11
write_param_16bit ( x"6a" , x"0004"); --  gap length	 
write_param_16bit ( x"6c" , x"00c3"); --  gap start  	 	   12
write_param_16bit ( x"6e" , x"0006"); --  gap length	 
write_param_16bit ( x"70" , x"00d3"); --  gap start  	 	   13
write_param_16bit ( x"72" , x"000c"); --  gap length	 
write_param_16bit ( x"74" , x"00e3"); --  gap start  	 	   14
write_param_16bit ( x"76" , x"0009"); --  gap length	 
write_param_16bit ( x"78" , x"00f3"); --  gap start  	 	   15
write_param_16bit ( x"7a" , x"0008"); --  gap length	 
write_param_16bit ( x"7c" , x"0103"); --  gap start  	 		16
write_param_16bit ( x"7e" , x"000d"); --  gap length	 
write_param_16bit ( x"80" , x"0113"); --  gap start  	 	   17
write_param_16bit ( x"82" , x"0019"); --  gap length	 
write_param_16bit ( x"84" , x"0138"); --  gap start  	 	   18
write_param_16bit ( x"86" , x"0004"); --  gap length		 
write_param_16bit ( x"88" , x"0152"); --  gap start  	 	   19
write_param_16bit ( x"8a" , x"0044"); --  gap length		 
write_param_16bit ( x"8c" , x"03e3"); --  gap start  	 	   20
write_param_16bit ( x"8e" , x"0814"); --  gap length	 		   


-- start laser write operation
MCU_MARK_EN <= '1';		   

read_param_16bit( x"28" );    -- read FPGA status

wait for 1800us ;   -- change direction

write_param_24bit ( x"24" , x"020502"); -- byte 0 : Enc_cts_per_row	
										-- byte 1 bits 3-0 Addr_high_dpram
			 							-- byte 2 bit 0 Enc_dir_flag
			 							-- byte 2 bit 1 Guide_en 
										-- byte 2 bit 2 Galvo service postion enable  
wait for 1800us ;
end process stimulus;

end TB_ARCHITECTURE;

configuration TESTBENCH_FOR_data_out_fpga of MAINt_fpga_tb is
	for TB_ARCHITECTURE
		for UUT : data_out_fpga
			use entity work.data_out_fpga(arch_data_out_fpga);
		end for;
	end for;
end TESTBENCH_FOR_data_out_fpga;


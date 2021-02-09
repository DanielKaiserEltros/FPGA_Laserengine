library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity paramreg is
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
	FRAC_RD : out std_logic_vector(15 downto 0);	-- reihen pro DAC-digit 
	SETTLING_TIME_BASE : out std_logic_vector(15 downto 0);
	SETTLING_TIME_SMALL : out std_logic_vector(15 downto 0);
	Glv_service : out std_logic_vector(15 downto 0);		-- fix galvo mirror postion for service .
	DEBUG_RX : out std_logic_vector(23 downto 0);
	CONTROL_CODE : out std_logic_vector(7 downto 0);
	Command : out std_logic_vector(23 downto 0)			-- command
);
end paramreg;

architecture arch_paramreg of paramreg is
	type regType is array (integer range <>) of std_logic_vector(7 downto 0);
	signal Param : regType(63 downto 0);
	signal AddrA : natural range 0 to 63 ;

begin
	AddrA <= to_integer(unsigned(AddressA(5 downto 0))); 
	
	
	working: process(Clock)
	begin
		 if (rising_edge(Clock)) then
			if (Reset = '1') then
				-- set e reasonable value for Px_clk_div, since
				-- it is used by the image_clock_manager
				Param(0) <= x"F0"; -- 240 --> 100 kHz
				Param(1) <= x"00";

				for i in 2 to 62 loop
					Param(i) <= (OTHERS => '0'); 
				end loop;
				-- Param(63) is a special one: it survives a reset
				
				DataOutA <= (OTHERS => '0');
			else
				if (ClockEnA = '1') then		-- carry out the write/read functions associated with MCUIF
					if (AddressA(7 downto 6) = "00") then
						if (WrA = '1') then
							Param(AddrA) <= DataInA; -- write
						else
							DataOutA <= Param(AddrA); -- read
						end if;
					elsif (WrA = '0') then
						DataOutA <= (OTHERS => '0'); -- read on an adress which is not ours
					end if;
				end if;
			end if;	
			
			if (LOCK_PARAMREG = '0') then									
				Px_clk_div <= Param(1) & Param(0);			-- pixel clock divider for SysClk --> PxClk)
				FRAC_DE <= Param(4)(3 downto 0) & Param(3) & Param(2);
			
				Param(5) <= Enc_ct_total(7 downto 0);
				Param(6) <= Enc_ct_total(15 downto 8);					
				Param(7) <= Enc_ct_total(23 downto 16);

				Param(8) <= Speed_sysclks(7 downto 0);	-- ....
				Param(9) <= Speed_sysclks(15 downto 8);	-- ....
				
				Param(10) <= Speed_enc_cts(7 downto 0);	-- ....
				Param(11) <= Speed_enc_cts(15 downto 8);	-- ....
				
				Param(12) <= addr_to_mem_RB(5 downto 0) & "00";	-- als bytes
				Param(13) <= "0000" & addr_to_mem_RB(9 downto 6);	-- ....

				Px_per_row <= Param(14)(6 downto 0);					-- pixels per row in this job
				rows_per_rpt <= Param(17)(3 downto 0) & Param(16) & Param(15);
				Mark_rows_per_rpt <= Param(19) & Param(18);

				Param(20) <= DEBUG_TX(7 downto 0);	
				Param(21) <= DEBUG_TX(15 downto 8);
				Param(22) <= DEBUG_TX(23 downto 16);
				
				DEBUG_RX <= Param(25) & Param(24) & Param(23);

				Param(26) <= Repeats_moved(7 downto 0);		-- ....
				Param(27) <= Repeats_moved(15 downto 8);	-- no. of full repeats moved since last reset)
				Param(28) <= Repeats_moved(23 downto 16);	-- no. of full repeats moved since last reset)
				
				Beam_px_delay <= Param(29)(5 downto 0);	

				Param(30) <= ROWS_MARKED(7 downto 0);
				Param(31) <= ROWS_MARKED(15 downto 8);

				Beam_clk_delay <= Param(33) & Param(32);				-- no. of sys clks to delay laser px clk by ie fine delay)
				FRAC_DR <= Param(35) & Param(34);
				FRAC_RE <= Param(37) & Param(36);
				Addr_high_dpram <= Param(38)(3 downto 0);				-- bits 3-0 are the upper 4 bits of the 12 bit address for dpram port A)
				Cable_dir_flag <= Param(39)(0);							-- bit 0 is the encoder direction flag
				Guide_en <= Param(39)(1);	
				
				Param(40) <= '0' & Status(6 downto 0);
				Param(41) <= '0' & Status(13 downto 7);		-- status info to mcu

				Param(42) <= FPGA_version(7 downto 0);
				Param(43) <= FPGA_version(15 downto 8);

				GLV_AMPL <= Param(45) & Param(44);
				--46, 47
				Glv_decr_fast <= Param(49) & Param(48);
				FRAC_RD <= Param(51) & Param(50);
				SETTLING_TIME_BASE <= Param(53) & Param(52);	
				SETTLING_TIME_SMALL <= Param(55) & Param(54);	
				Glv_service <= Param(57) & Param(56);
				
				Param(58) <= "0000" & GALVO_STATUS;
				--59
				
				Command <= Param(62) & Param(61) & Param(60);
				
				CONTROL_CODE <= Param(63);
			end if;
		end if;
	end process;
	

end arch_paramreg;
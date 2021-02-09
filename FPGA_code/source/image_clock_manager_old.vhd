library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

 
entity image_clock_manager is
port
(
	CLK : in std_logic;
	RESET : in std_logic; 
	PX_DIV : in std_logic_vector(15 downto 0);		-- CLK divided by this to give square waves PX_CLK_xxx
	LASER_CLK_DELAY: in std_logic_vector(15 downto 0);	-- the offset delay from AOD to LASER pixel clocks (value can be from 0 to px_div)

	PX_CLK_AOD  : out std_logic;				-- square wave, one pulse per pixel -- shifts deflection/amplitude data out of LUT into AOD control
	PX_CLK_LASER  : out std_logic;				-- square wave, one pulse per pixel -- drives laser and shifts image data
	PX_CLK_AOD_REDGE  : out std_logic;
	PX_CLK_LASER_FEDGE  : out std_logic
--	ENC_CLK : out std_logic					-- square wave 4MHz (so 24MHz CLK divided by 6)
);
end image_clock_manager;

architecture arch_icm of image_clock_manager is
	signal px_count_laser : natural range 0 to 65535;
	signal Px_period_end : natural range 0 to 65535;
	signal Px_period_half : natural range 0 to 65535;
	signal Delay : natural range 0 to 65535; -- buffer for Enc_clk output
	signal px_clk_aod_reg : std_logic;
	signal px_clk_laser_reg : std_logic;
	
	-- ENC_CLK soll vermutlich auch bei reset weiterlaufen
--	signal Enc_clk_sig : std_logic := '0';		-- buffer for Enc_clk output
--	signal Enc_count : natural range 0 to 3 := 0;
	
	signal px_clk_aod_redge_reg : std_logic;
	signal px_clk_laser_fedge_reg : std_logic;
	
begin
	-- establish outputs	
	PX_CLK_AOD <= px_clk_aod_reg;
	PX_CLK_LASER <= px_clk_laser_reg;

--	ENC_CLK <= Enc_clk_sig;
	
	PX_CLK_AOD_REDGE <= px_clk_aod_redge_reg;
	PX_CLK_LASER_FEDGE <= px_clk_laser_fedge_reg;
	
	-- establish counters (count is from 0 so subtract 1 for target value)
	Px_period_end <= to_integer(unsigned(PX_DIV)) - 1; 	-- set the pulse period
	Px_period_half <= to_integer(unsigned(PX_DIV))/2 - 1; 	-- set the pulse period

	Delay <= to_integer(unsigned(LASER_CLK_DELAY)); 
	
	-- create pixel clocks from input clock -- MUST be on rising edge of clock for processes elsewhere
	icm_px_proc: process(CLK)	
		variable px_count_aod : natural range 0 to 65535; 

	begin		
		if (rising_edge(CLK)) then
			px_clk_aod_redge_reg <= '0';
			px_clk_laser_fedge_reg <= '0';
			
			if (RESET = '1') then
				px_clk_aod_reg <= '0';
				px_clk_laser_reg <= '0';
				px_count_laser <= 0;
				px_count_aod := 0;
			elsif (unsigned(PX_DIV) /= 0) then
				-- AOD clock
				if (px_count_aod = Px_period_end) then
					px_clk_aod_reg <= '1';	-- high periode
					px_clk_aod_redge_reg <= '1';
					px_count_aod := 0;
				else
					if (px_count_aod = Px_period_half) then
						px_clk_aod_reg <= '0'; -- low periode
					end if;
					
					px_count_aod := px_count_aod + 1;					
				end if;
				
				-- laser clock
				if (px_count_aod = Delay) then
					px_clk_laser_reg <= '0'; -- low periode
					px_clk_laser_fedge_reg <= '1';
					px_count_laser <= 0;
				else
					if (px_count_laser = Px_period_half) then
						px_clk_laser_reg <= '1';  -- high periode
					end if;

					px_count_laser <= px_count_laser + 1;
				end if;				
				
				-- create clock signal for enc board 4MHz (24MHz divided)
--				if (Enc_count = 2) then
--					Enc_clk_sig <= NOT(Enc_clk_sig);
--					Enc_count <= 0;
--				else
--					Enc_count <= Enc_count + 1;
--				end if;
			end if;
		end if;
	end process icm_px_proc;

	
end arch_icm;
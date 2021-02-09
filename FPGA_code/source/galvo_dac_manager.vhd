library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL; 


entity galvo_dac_manager is
port(
	CLK : in std_logic;
	RESET : in std_logic;
	CMD : in std_logic_vector(1 downto 0);
	GLV_SERVICE : in std_logic_vector(15 downto 0);
	GLV_AMPL : in std_logic_vector(15 downto 0);
	FRAC_DS_DAC_T: in std_logic_vector(17 downto 0); -- U0.18 --> U2.16 alle 4 sysclocks
	GLV_DECR_FAST : in std_logic_vector(15 downto 0); --U8.8
	GALVO_DELAY : in std_logic_vector(7 downto 0); --U13.-5
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
end galvo_dac_manager;


architecture arch_gdacm of galvo_dac_manager is
	signal strobe_ctr: natural range 0 to 255;
	
	signal glv_total : natural range 0 to 65535;
	signal galvo_ampl : natural range 0 to 65535;
	
	 -- U18.16 bit
	signal glv_offset_frac : signed(33 downto 0);
	signal glv_offset_int : natural range 0 to 65535;
	signal reg_mark : signed(33 downto 0);
	signal reg_ultra_fast : signed(33 downto 0);
	signal reg_fast : signed(33 downto 0);
	signal glv_offset_warn : signed(33 downto 0);
	signal glv_offset_err : signed(33 downto 0);
	signal glv_delay_frac : signed(33 downto 0);

	
	signal frac_D_reg : unsigned(23 downto 0);

	signal incr_slow_cnt : natural range 0 to 3;

	signal cable_dir_reg : std_logic;
	signal warn_reg : std_logic;
	signal err_reg : std_logic;

	signal glv_status_reg : std_logic_vector(3 downto 0);

	signal warn_cnt : natural range 0 to 16777215;
	signal err_cnt : natural range 0 to 16777215;
	
	signal glv_total_reg : std_logic_vector(15 downto 0);
	
	constant GLV_MOVE_ZUK_ULTRA_FAST: std_logic_vector(2 downto 0) := "000";
	constant GLV_MOVE_ZUK_FAST: std_logic_vector(2 downto 0) := "001";
	constant GLV_MOVE_VERG_FAST: std_logic_vector(2 downto 0) := "011";
	constant GLV_MOVE_MARK: std_logic_vector(2 downto 0) := "100";	
	
	constant h7fff: signed(33 downto 0) := "00" & x"7fff0000";
begin

	--inputs:
	cable_dir_reg <= CABLE_DIR;
	
	-- reg_mark wird nur alle 4 sysclks addiert: U0.18 --> U2.16
	reg_mark <= resize(signed(FRAC_DS_DAC_T), reg_mark'length);
	galvo_ampl <= to_integer(unsigned(GLV_AMPL)); -- max 32767
	reg_ultra_fast <= signed("0000000000" & GLV_DECR_FAST & "00000000");
	reg_fast <= signed("0000000000000" & GLV_DECR_FAST & "00000");
	
	
	-- outputs
	GALVO_STATUS <= glv_status_reg;	
	FRAC_D <= std_logic_vector(frac_D_reg);
	
	glv_total_reg <= std_logic_vector(to_unsigned(glv_total, glv_total_reg'LENGTH));
	
	GLV_LDACQ <= '0';
	DEBUG_INFO <= std_logic_vector(glv_delay_frac(23 downto 0));	
	
	movement_proc: process(CLK)	
		variable glv_offset_frac_next : signed(33 downto 0); -- S18.16
		variable glv_add : signed(33 downto 0); -- S18.16
		variable glv_offset_frac_delaycomp : signed(33 downto 0);
		variable glv_delay_frac_tmp : signed(26 downto 0);

	begin
		if (rising_edge(CLK)) then
			if (RESET = '1')  then
				glv_offset_frac <= (others => '0');
				frac_D_reg <= (others => '0');
				glv_status_reg <= (others => '0'); -- error wird erst hier wieder gelöscht
				warn_cnt <= 0;
				warn_reg <= '0';
				err_cnt <= 0;
				err_reg <= '0';
				incr_slow_cnt <= 0;
				glv_total <= 0;
			else
				--maximaler offset = gesamtbereich - (idle-bereich oben und unten)
				glv_offset_warn <= signed("0" & GLV_AMPL & "0" & x"0000");-- 2*galvo_ampl
				glv_offset_err <= signed("00" & GLV_AMPL & x"0000") + h7fff; -- galvo_ampl + 32767: max 65534
			
				-- neuen glv_offset_frac berechnen:
				glv_add := (others => '0'); --evtl. als signal
				glv_delay_frac_tmp := (others => '0');
				
				if (MARK_EN = '1') then 
					if (GLV_MOVE = GLV_MOVE_ZUK_ULTRA_FAST) then
						glv_add := -reg_ultra_fast;
					elsif (GLV_MOVE = GLV_MOVE_ZUK_FAST) then
						glv_add := -reg_fast;
					elsif (GLV_MOVE = GLV_MOVE_VERG_FAST) then
						glv_add := reg_fast;
					elsif (GLV_MOVE = GLV_MOVE_MARK) then
						if (incr_slow_cnt = 0) then
							glv_add := reg_mark;
						end if;
						incr_slow_cnt <= incr_slow_cnt + 1;
						--galvo entsprechend der aktuellen markiergeschw. voraus setzen,
						--so dass er real dann an der stelle ist, die in frac_D_reg steht
						--U13.-5 --> U14.-5; dann: U0.18 * U14.-5 = U14.13
						glv_delay_frac_tmp := signed(FRAC_DS_DAC_T)*signed("0" & GALVO_DELAY);
					end if;
				end if;
				
				glv_offset_frac_next := glv_offset_frac + glv_add;

				-- warn/error-counter runterzählen
				glv_status_reg(0) <= '1';
				if (warn_reg = '1') then
					warn_cnt <= 16777215; --counter starten
				elsif (warn_cnt /= 0) then
					warn_cnt <= warn_cnt - 1;
				else
					glv_status_reg(0) <= '0';
				end if;

				glv_status_reg(1) <= '1';
				if (err_reg = '1') then
					err_cnt <= 16777215; --counter starten
				elsif (err_cnt /= 0) then
					err_cnt <= err_cnt - 1;
				else
					glv_status_reg(1) <= '0';
				end if;

				-- limits checken:
				warn_reg <= '0';
				err_reg <= '0';
				if (glv_offset_frac_next < 0) then
					-- unterlauf: auf 0 begrenzen:
					glv_offset_frac_next := (others => '0');
				else
					if (glv_offset_frac_next > glv_offset_warn) then
						-- warnschwelle:
						warn_reg <= '1';
					end if;
					
					if (glv_offset_frac_next >= glv_offset_err) then -- '>=' damit es nicht nur bei jedem 4.ten mal anschlägt
						-- am absoluten anschlag: limitieren
						glv_offset_frac_next := glv_offset_err;
						err_reg <= '1';
					end if;
				end if;
				glv_status_reg(2) <= err_reg; -- throttling

						
				-- S18.16 --> U16.8
				frac_D_reg <= unsigned(glv_offset_frac_next(31 downto 8));
				glv_offset_frac <= glv_offset_frac_next;
				
				-- galvo-delay ausgleichen; nur für den galvo, nicht die interne berechnung (frac_D_reg)
				glv_delay_frac <= resize(glv_delay_frac_tmp(26 downto 5) & x"00", glv_delay_frac'length); -- U14.13 --> U14.8 --> U18.16
				glv_offset_frac_delaycomp := glv_offset_frac + glv_delay_frac;
				if (glv_offset_frac_delaycomp < 0) then
					-- unterlauf: auf 0 begrenzen:
					glv_offset_frac_delaycomp := (others => '0');
				elsif (glv_offset_frac_delaycomp > glv_offset_err) then
					-- am absoluten anschlag: limitieren
					glv_offset_frac_delaycomp := glv_offset_err;
				end if;
				glv_offset_int <= to_integer(unsigned(glv_offset_frac_delaycomp(31 downto 16))); 
				
				if (glv_offset_int < 256) then
					glv_status_reg(3) <= '1';
				else 
					glv_status_reg(3) <= '0';
				end if;

				-- gesamtwert berechnen
				if (cable_dir_reg = '0') then
					--positive richtung
					glv_total <= 32768 - galvo_ampl + glv_offset_int; -- max 65535
				else
					--negative richtung
					glv_total <= 32768 + galvo_ampl - glv_offset_int; -- min 1
				end if;
			end if;
		end if;
	end process movement_proc;


	

	strobe_proc: process(CLK)	

	begin
		if (rising_edge(CLK)) then
			if (RESET = '1')  then
				strobe_ctr <= 0; 
				GLV_WRQ <= '1';
			else  
				-- down sampling and output assignment
				if (strobe_ctr = 0) then
					if (CMD = "01") then 
						GLV_DO <= GLV_SERVICE;
					else
						GLV_DO <= glv_total_reg;
					end if;
				elsif strobe_ctr = 4 then
					GLV_WRQ <= '0';
				elsif strobe_ctr = 8 then
					GLV_WRQ <= '1';
				end if;
				
				-- 24 MHz --> 800 kHz
				if (strobe_ctr = 29) then
					strobe_ctr <= 0; 
				else
					strobe_ctr <= strobe_ctr + 1;
				end if;
			end if;
		end if;
	end process strobe_proc;

	
end arch_gdacm;
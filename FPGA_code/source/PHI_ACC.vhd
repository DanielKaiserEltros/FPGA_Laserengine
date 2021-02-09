library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL; 


entity PHI_ACC is
port
(
	CLK : in std_logic;
	RESET : in std_logic;
	MCU_MARK_EN : in std_logic;						-- laser write operation enabled
	service_mode : in std_logic;
	Direction  : in std_logic;						-- direction of mirror progression
	Mirror_serv : in std_logic_vector(15 downto 0); -- parameter , service postion of mirror
    Gaplength : in std_logic_vector(15 downto 0);	-- from GapReg, length of next gap
	noGap : in std_logic;						    -- active text to be written. If not assigned the output will be set to zero  
	Px_clk_div  : in std_logic_vector(23 downto 0);	-- number of clocks per pixel
	Row_clk_div  : in std_logic_vector(23 downto 0);-- number of pixel clocks per row
	Mirror_ts : in std_logic_vector(7 downto 0);	-- mirror settling time in number of rows
	PHI_incr : in std_logic_vector(15 downto 0);	-- PHI increment value. Constant delivered by MCU
	PHI_start : in std_logic_vector(15 downto 0);	-- maximum PHI value which can be handled. Constant delivered by MCU
	PHI_gain : in std_logic_vector(7 downto 0);		-- output gain control in steps of 1,2,4,8,....	
	
	GLV_DO  : out std_logic_vector(15 downto 0);	-- calculated galvo control
	GLV_WRQ  : out std_logic;						-- strobe signal for galvo DAC: data ready (active low)
	GLV_LDACQ  : out std_logic;						-- strobe signal for galvo DAC: forward data to DAC(active low)
	GLV_idle : out std_logic;						-- Mirror in idle postion, GLV_DO = PHI_start
	PHI_ovfl  : out std_logic						-- maximum PHI value reached , error flag
);
end PHI_ACC;

architecture arch_icm of PHI_ACC is

	signal not_Mirror_ts : std_logic_vector(17 downto 0);
	signal minus_Mirror_ts : std_logic_vector(17 downto 0);
	signal pos_gap : std_logic_vector(17 downto 0);
	signal effective_gap : std_logic_vector(17 downto 0);
	
	signal PHI_incr_per_pix : std_logic_vector(39 downto 0);		-- PHI increment per row
	signal PHI_incr_per_row : std_logic_vector(63 downto 0);		-- PHI increment per row
	signal PHI_incr_of_gap : std_logic_vector(79 downto 0);			-- virtual PHI increment of next gap, to be substarcted from PHI-accu at start of gap
	signal not_PHI_incr_of_gap : std_logic_vector(31 downto 0);		-- one's complement of limited PHI increment of next gap
	signal minus_PHI_incr_of_gap : std_logic_vector(31 downto 0);	-- two's complement of limited PHI increment of next gap
	signal not_PHI_start : std_logic_vector(17 downto 0);				-- one's complement of 
	signal minus_PHI_start : std_logic_vector(17 downto 0);			-- two's complement of 
	signal PHI : std_logic_vector(15 downto 0);						-- registered PHIaccu_shift 
	signal not_PHI : std_logic_vector(15 downto 0);					-- inverted PHI
	signal PHI_compl : std_logic_vector(15 downto 0);				-- two's complement of PHI 
	signal signed_PHI : std_logic_vector(17 downto 0);				-- "00" &  PHI 
	signal PHI_LIM_DIFF : std_logic_vector(17 downto 0);			-- PHI - PHI_start
	signal PHI_accu_plus : std_logic_vector(31 downto 0);			-- to be added to PHI_accu every CLK cycle
	signal PHI_accu : std_logic_vector(31 downto 0);				-- accumulated PHI raw data, two MSBs should always be '00' , sign positive
	signal accustart : std_logic_vector(31 downto 0);				-- startvalue of PHI_accu 
	signal not_accustart : std_logic_vector(31 downto 0);			-- one's complemet of startvalue of PHI_accu 
	signal minus_accustart : std_logic_vector(31 downto 0);			-- two's complemet of startvalue of PHI_accu 
	signal delta_accu : std_logic_vector(31 downto 0);				-- PHI_accu - startaccu
	signal ctr  : std_logic_vector(7 downto 0);						-- for output strobe generation
	signal noGap_d : std_logic;										-- delayed input for rising edge detection
--signal GLV_DO_acc : std_logic_vector(15 downto 0);	-- todo
begin

pos_gap <= "00" & Gaplength;
not_Mirror_ts <=  "1111111111" & NOT Mirror_ts;
minus_Mirror_ts <= not_Mirror_ts + "000000000000000001";
effective_gap <= pos_gap + minus_Mirror_ts;
not_PHI_start <= "11" & NOT PHI_start;
PHI_accu_plus <=  "0000000000000000" & PHI_incr;
signed_PHI <= "00" &  PHI ;	 	 
PHI_incr_per_pix <= PHI_incr * 	Px_clk_div;
PHI_incr_per_row <= PHI_incr_per_pix * 	Row_clk_div;
PHI_incr_of_gap <= PHI_incr_per_row * effective_gap(15 downto 0);
minus_PHI_incr_of_gap <= not_PHI_incr_of_gap + x"00000001";
not_PHI <= NOT PHI;
PHI_compl <= not_PHI + x"0001";

-- test if PHI_accu < accustart , can happen when minus_PHI_incr_of_gap is large
not_accustart <= NOT accustart;
minus_accustart <= accustart + x"00000001";
delta_accu <= PHI_accu + minus_accustart;   -- must always be positive, i.e. PHI_accu > accustart

with PHI_gain select 
		PHI	 <= 	PHI_accu(29 downto 14) when x"01",
					PHI_accu(28 downto 13) when x"02",
					PHI_accu(27 downto 12) when x"04",
					PHI_accu(26 downto 11) when x"08",
					PHI_accu(25 downto 10) when x"10",
					PHI_accu(24 downto 9) when x"20",
					PHI_accu(23 downto 8) when x"40",
					PHI_accu(22 downto 7) when x"80",
					(others =>'0') when others;
with PHI_gain select 
		accustart	 <= "00" & PHI_start & "00000000000000"	when x"01",
					    "000" & PHI_start & "0000000000000" when x"02",
					    "0000" & PHI_start & "000000000000" when x"04",
					    "00000" & PHI_start & "00000000000" when x"08",
					    "000000" & PHI_start & "0000000000" when x"10",
					    "0000000" & PHI_start & "000000000" when x"20",
					    "00000000" & PHI_start & "00000000" when x"40",
					    "000000000" & PHI_start & "0000000" when x"80",
					(others =>'0') when others;
					
	icm_phi_proc: process(CLK)	
	begin
		if (rising_edge(CLK)) then
			if  RESET = '1'  then
				not_PHI_incr_of_gap <= (others => '0');
				noGap_d <= '0';	  
				GLV_idle <= '1';
				
				-- down sampling and output assignment
				ctr <= x"00"; 
				GLV_WRQ <= '1';
				GLV_LDACQ <= '1';
			else  
				noGap_d <= noGap;
				ctr <= ctr + x"01";
				minus_PHI_start <= not_PHI_start + "000000000000000001"; 
				if PHI_incr_of_gap(79 downto 30) = "00000000000000000000000000000000000000000000000000" then
					not_PHI_incr_of_gap <= NOT PHI_incr_of_gap(31 downto 0);
				else
					not_PHI_incr_of_gap <= x"c0000000" ;
				end if;		
				-- integration of PHI value
				if MCU_MARK_EN = '0' then
					PHI_accu <= accustart ;
					PHI_ovfl <= '0';
				else
				    if noGap = '0' then
						if noGap_d ='1' then 
							PHI_accu <= PHI_accu + minus_PHI_incr_of_gap;
						elsif delta_accu(31 downto 30) = "00" then  -- if PHI_accu > accustart
							PHI_accu <= PHI_accu;
						else
							PHI_accu <= accustart;
							GLV_idle <= '1';
						end if;
					else -- noGap = '1'
						GLV_idle <= '0';
						PHI_accu <= PHI_accu + PHI_accu_plus;
					end if;
					-- ovfl detection
					PHI_LIM_DIFF <= signed_PHI + minus_PHI_start;
					if PHI_LIM_DIFF(17) = '1' then 
						PHI_ovfl <= '1';
					end if;	
				end if;
				
				-- down sampling and output assignment
				if ctr = x"00" then
					if service_mode = '1' then
						GLV_DO <= Mirror_serv;
					elsif Direction = '1' then
						GLV_DO <= PHI; 
					else
						GLV_DO <= PHI_compl; 
					end if;
				elsif ctr = x"04" then GLV_WRQ <= '0';
				elsif ctr = x"08" then GLV_WRQ <= '1';
				elsif ctr = x"0c" then GLV_LDACQ <= '0';
				elsif ctr = x"10" then GLV_LDACQ <= '1';				
				elsif ctr = x"f0" then ctr <= x"00"; -- 24 MHz --> 100 kHz
				end if;				
			end if;
		end if;
	end process;

end arch_icm;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Description
-- based on encoder pulses, various counts are done. 
--
-- Clk_count_spd is designed to measure the cable speed:
-- It counts system clocks over a set number of encoder pulses
-- It puts the total value into the parameter register.
-- It repeats this endlessly subject to RESET

entity enc_ctr is

port(
	RESET: in std_logic;	-- resets when high
	CLK: in std_logic;		-- system clock input
	ENC: in std_logic;		-- encoder count pulses input (may be asynch)
	FRAC_RE: in std_logic_vector(15 downto 0);	-- U-2.18
	MARK_EN: in std_logic;
	FRAC_D : in std_logic_vector(23 downto 0); 	-- U16.8
	FRAC_RD : in std_logic_vector(15 downto 0); -- U-2.18
	GALVO_STATUS : in std_logic_vector(3 downto 0); 

	ENC_CT_TOTAL: out std_logic_vector(23 downto 0);	-- total number of encoder pulses
	FRAC_R_SUM: out std_logic_vector(27 downto 0); -- U20.8
	FRAC_R_ENC: out std_logic_vector(27 downto 0); -- U20.8
	FRAC_ES: out std_logic_vector(17 downto 0); -- U-2.20
	SPEED_SYSCLKS: out std_logic_vector(15 downto 0);	-- speed count
	SPEED_ENC_CTS: out std_logic_vector(15 downto 0)	-- speed count
);
end enc_ctr;


architecture enc_ctr_arch of enc_ctr is
	signal Enc_reg : std_logic_vector(1 downto 0);
	
	signal Enc_count_total: natural range 0 to 16777215;	-- 24 bit

	signal Enc_count_spd: unsigned(15 downto 0);
	signal Enc_count_spd_reg: unsigned(15 downto 0);	
	signal Clk_count_spd: unsigned(15 downto 0);
	signal Clk_count_spd_reg: unsigned(15 downto 0);
			

	signal E_t: unsigned (19 downto 0); -- U-2.22
	signal dE_t: unsigned (5 downto 0); -- U-2.8
	signal dR_enc: unsigned (21 downto 0); -- U-4.26
	signal R_enc: unsigned (45 downto 0); -- U20.26
	signal R_sum: unsigned (27 downto 0); -- U20.8
	signal R_dac: unsigned (23 downto 0); -- U14.10

	
	signal ES_t: std_logic_vector(37 downto 0); -- U16.22
	
	
	component division is

	generic( 
		N : positive;
		F : positive
	);

port(
	clk: in std_logic;
	reset: in std_logic;
	ddent : in std_logic_vector(N-1 downto 0);
	dsor : in std_logic_vector(N-1 downto 0);
    
	busy : out std_logic;
    quot : out std_logic_vector(N+F-1 downto 0)
	);
	end component;
	
begin
	-- in:
	
	-- out:
	ENC_CT_TOTAL <= std_logic_vector(to_unsigned(Enc_count_total, ENC_CT_TOTAL'LENGTH));
	SPEED_SYSCLKS <= std_logic_vector(Clk_count_spd_reg);
	SPEED_ENC_CTS <= std_logic_vector(Enc_count_spd_reg); 

	FRAC_R_SUM <= std_logic_vector(R_sum);
	FRAC_R_ENC <= std_logic_vector(R_enc(45 downto 18)); 
	FRAC_ES <= ES_t(19 downto 2); -- U-2.20
		
	div : division
	
	generic map( 
		N => 16,
		F => 22
	)

	port map(
		clk => CLK,
		reset => RESET,
		ddent => std_logic_vector(Enc_count_spd_reg), -- 16.0 
		dsor => std_logic_vector(Clk_count_spd_reg),
		
		quot => ES_t -- 16.22 
	);
	
	
	enc_proc: process(CLK)
		variable reset_spd : boolean;
		variable R_dac_tmp: unsigned (39 downto 0); -- U 14.26
		variable E_t_new: unsigned (19 downto 0); -- U-2.22
		variable R_sum_tmp: unsigned (29 downto 0); -- U20.10

	begin

		if (rising_edge(CLK)) then	
			-- normalfall: clock-signale sind 0
			if (RESET = '1') then
				Enc_reg <= "11";	-- we want to detect a rising edge so ensure we must clock a real 0 first
				Enc_count_spd_reg <= (others => '0'); -- kein ergebnis
				reset_spd := true;
				Enc_count_total <= 0;

				E_t <= (others => '0');
				dE_t <= (others => '0');
				dR_enc <= (others => '0');
				R_enc <= (others => '0');
				R_dac <= (others => '0');
				R_sum <= (others => '0');
			else			
				-- speed-berechnung bei langsamem kabel: überlauf vermeiden
				if (Clk_count_spd /= x"ffff") then
					Clk_count_spd <= Clk_count_spd + 1;
				else
					Enc_count_spd_reg <= (others => '0'); -- "zu langsam, kein ergebnis"
					
					reset_spd := true; --zähler resetten
				end if;

				-- externes asynchrones encoder-signal synchronisieren
				Enc_reg <= Enc_reg(0) & ENC;
								
				-- echte encoder-flanke verarbeiten
				if (Enc_reg = "01") then 
					-- speed counting checken
					if (reset_spd = false) then
						if ((Clk_count_spd(15 downto 13) /= "000") and (Enc_count_spd(1 downto 0) = "00")) then
							-- kopie vom aktuellen zählerstand nehmen
							Enc_count_spd_reg <= Enc_count_spd;
							Clk_count_spd_reg <= Clk_count_spd;
							
							reset_spd := true; --zähler resetten
						else
							Enc_count_spd <= Enc_count_spd + 1;
						end if;
					end if;
						
					if (reset_spd = true) then
						Clk_count_spd <= x"0001"; 
						Enc_count_spd <= x"0001";
						reset_spd := false;
					end if;
					
					--gesamtzahl der pulse
					Enc_count_total <= Enc_count_total + 1;
				end if; -- else: kein puls, oder throttling an
				
				
				if (MARK_EN = '1') then 
					-- encoder-beitrag zu kombi-counts:
					if (GALVO_STATUS(2) = '0') then
						E_t_new := E_t + unsigned(ES_t(19 downto 0)); -- U-2.22 (obere bits von ES_t sind 0)
					else
						--galvo steht am anschlag: throttling auf 1/32 der echten kabelgeschw.,
						--damit der markierprozess auf keinen fall überfahren wird
						E_t_new := E_t + unsigned(ES_t(24 downto 5));
					end if;
				else
					E_t_new := to_unsigned(0, E_t_new'length);
				end if; 	

				dE_t <= E_t_new(19 downto 14); -- obere 6 bits abschöpfen: U-2.8
				E_t <= "000000" & E_t_new(13 downto 0); -- untere 14 bits drinlassen
				
				dR_enc <= dE_t*unsigned(FRAC_RE); -- die abgeschöpfen bit in rows: U-4.26
				R_enc <= R_enc + resize(dR_enc, R_enc'length); -- die aktuelle encoder-row: U20.26

				R_dac_tmp := unsigned(FRAC_D)*unsigned(FRAC_RD); -- die galvo-stellung in rows: U14.26
				R_dac <= R_dac_tmp(39 downto 16); -- untere bits wegwerfen: U14.10 (spart auch multiplikations-aufwand)

				R_sum_tmp := R_enc(45 downto 16) - resize(R_dac, R_sum_tmp'length); -- U20.10
				R_sum <= R_sum_tmp(29 downto 2); -- U20.8
			end if;
		end if;
	end process enc_proc;


end enc_ctr_arch;


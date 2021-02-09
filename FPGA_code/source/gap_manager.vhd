library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity gap_manager is

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
	FRAC_DE : in std_logic_vector(19 downto 0); -- U4.16
	FRAC_DR : in std_logic_vector(15 downto 0); -- U8.8
	FRAC_ES: in std_logic_vector(17 downto 0); -- -2.20
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
end gap_manager;


architecture gap_manager_arch of gap_manager is
	signal gap_status : natural range 0 to 7;
	signal lock_status : natural range 0 to 3;

	signal gap_index_reg : natural range 0 to 63;
	signal gap_row_reg : natural range 0 to 65535;
	
	signal glv_move_reg : std_logic_vector (2 downto 0);
	
	signal row_target_count : natural range 0 to 65535;
	signal mark_rows_per_repeat : natural range 0 to 65535; 

	-- alles U20.8
	signal frac_now : unsigned(27 downto 0); 
	signal frac_next_row : unsigned(27 downto 0);  
	signal frac_diff : signed(27 downto 0); 
	constant one_row : unsigned(27 downto 0) := to_unsigned(256, frac_now'length);
	signal repeat_row_reg : unsigned(27 downto 0);

	signal Rb_ptr : natural range 0 to 1023;
	signal RB_ptr_next : natural range 0 to 1023;
	signal rb_read_count : natural range 0 to 15;
	signal read_RB_status : natural range 0 to 3;
	signal read_RB_action : std_logic;


	signal max_pixels : unsigned(6 downto 0);
	signal max_pixels_prev : unsigned(6 downto 0);
	signal data_pixels_tmp : std_logic_vector(119 downto 0);
	signal data_pixels_out : std_logic_vector(119 downto 0);

	signal word_cnt : std_logic_vector(1 downto 0);
	signal px_per_row_add : std_logic_vector(6 downto 0);

	signal row_clk_redge : std_logic;
	signal get_next_repeat_reg : std_logic;
	
	
	constant REPEAT_FINISHED: natural := 0;
	constant WAIT_ROW: natural := 1;
	constant CHECK_SETTLING: natural := 2;
	constant CHECK_POSITION: natural := 3;
	constant STEP_BACK: natural := 4;
	constant FAST_FORWARD: natural := 5;
	constant SETTL_FINISH: natural := 6;
	
	constant RB_READ_STATUS_RESET: natural := 0;
	constant RB_READ_STATUS_IDLE: natural := 1;
	constant RB_READ_STATUS_START: natural := 2;
	constant RB_READ_STATUS_BUSY: natural := 3;
	
	constant GLV_MOVE_ZUK_ULTRA_FAST: std_logic_vector(2 downto 0) := "000";
	constant GLV_MOVE_ZUK_FAST: std_logic_vector(2 downto 0) := "001";
	constant GLV_MOVE_VERG_FAST: std_logic_vector(2 downto 0) := "011";
	constant GLV_MOVE_MARK: std_logic_vector(2 downto 0) := "100";

	constant SIEBEN : std_logic_vector(6 downto 0) := "0000111";
	


	signal SR_min_raw : unsigned(15 downto 0); --U16.0
	signal SR_min : unsigned(15 downto 0); --U16.0
	-- prozessierung einer zeile kann max. ca. 150 sysclocks dauern (120 pixel, plus diverses)
	constant SR_min_limit : unsigned(15 downto 0) := to_unsigned(240, 16); 
	
	signal DS_max : unsigned(17 downto 0); -- U0.18 
	signal DS_t : unsigned(17 downto 0); --U0.18
	signal DS_dac_t_out : signed(17 downto 0); --U0.18
	signal DS_dac_t : signed(17 downto 0); --U0.18

	signal frac_DR_reg : std_logic_vector(15 downto 0); --U8.8
	
	signal DS_max_tmp: std_logic_vector(25 downto 0); --U8.18
	
	signal S_set: std_logic_vector(15 downto 0); -- U16.0
	signal dR_set: std_logic_vector(23 downto 0); --U16.8
	signal dR_set_base : unsigned(27 downto 0); -- U20.8
	signal dR_set_base_plus : unsigned(27 downto 0); -- U20.8
	signal dR_set_small : unsigned(27 downto 0); -- U20.8
	
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
	gap_row_reg <= to_integer(unsigned(GAP_ROW));
	mark_rows_per_repeat <= to_integer(unsigned(MARK_ROWS_PER_RPT));
	frac_now <= unsigned(FRAC_R_SUM);
	frac_DR_reg <= FRAC_DR;
	repeat_row_reg <= unsigned(REPEAT_ROW);

	
	-- out:
	GAP_INDEX <= std_logic_vector(to_unsigned(gap_index_reg, GAP_INDEX'LENGTH));
	ROW_TARGET <= std_logic_vector(to_unsigned(row_target_count, ROW_TARGET'LENGTH));
	
	ADDR_TO_MEM_RB <= std_logic_vector(to_unsigned(RB_ptr, ADDR_TO_MEM_RB'length));
	DATA_PIXELS <= data_pixels_out;
	ROW_CLOCK <= row_clk_redge;
	GET_NEXT_REPEAT <= get_next_repeat_reg;

	GLV_MOVE <= glv_move_reg;
	FRAC_DS_DAC_T <= std_logic_vector(DS_dac_t_out);
--	DEBUG_INFO(0) <= '1' when ((read_RB_status /= RB_READ_STATUS_IDLE) AND (read_RB_action = '1')) else '0'; 
--	DEBUG_INFO(1) <= '1' when (gap_status = CHECK_SETTLING) else '0'; --"000000" & std_logic_vector(DS_max);

	frac_diff <= signed(frac_next_row - frac_now);
								
	gap_proc: process(CLK)
		variable update_frac_ds : std_logic;
		
	begin
		if (rising_edge(CLK)) then
			row_clk_redge <= '0';
			get_next_repeat_reg <= '0';
			read_RB_action <= '0';
			update_frac_ds := '0';
			
			if (RESET = '1') then
				row_target_count <= 0;
				gap_status <= REPEAT_FINISHED;
				lock_status <= 0;
				DS_dac_t_out <= (others => '0');
				max_pixels_prev <= (others => '0');
				glv_move_reg <= GLV_MOVE_ZUK_ULTRA_FAST;
			else
				if (gap_status = REPEAT_FINISHED) then
					row_target_count <= 0; -- reset write_em_proc				
					gap_index_reg <= 0; -- ersten gap anwählen
					
					if (REPEAT_READY = '1') then
						-- beginn des naechsten repeats (REPEAT_ROW) ist gueltig: uebernehmen
						if (signed(repeat_row_reg - frac_now) < 0) then
							-- naechster repeat liegt in der vergangenheit:
							frac_next_row <= frac_now;
						else
							frac_next_row <= repeat_row_reg;
						end if;
						
						--naechsten repeat schonmal anfordern:
						get_next_repeat_reg <= '1'; --kurzer puls
						gap_status <= CHECK_SETTLING;
					end if;
				elsif (gap_status = WAIT_ROW) then
					if (frac_diff < 0) then
						-- nächste reihe erreicht
						if (row_target_count = mark_rows_per_repeat) then
							-- das war die letzte reihe
							gap_status <= REPEAT_FINISHED;
						elsif ((gap_row_reg /= 0) AND (row_target_count = gap_row_reg)) then
							-- gap-start erreicht:
							gap_index_reg <= gap_index_reg + 1;	-- nächsten gap selektieren
							-- nächste reihe auf erste reihe nach gap legen
							frac_next_row <= frac_next_row + unsigned(GAP_LENGTH & x"00");
							gap_status <= CHECK_SETTLING;
						else --kein gap bzw. repeat-ende
							if ((lock_status = 0) AND (GALVO_STATUS(3) = '1') AND (DS_dac_t <= 0)) then
								-- galvo vorm unteren anschlag, und geschwindigkeit < 0: 
								-- einmal zurücksetzen, dann einfrieren (lock_status = 2)
								gap_status <= CHECK_SETTLING;
								lock_status <= 1;
							elsif (max_pixels_prev /= max_pixels) then
								--pixelzahl der neuen zeile ist anders:
								gap_status <= CHECK_SETTLING;
							else
								-- neue zeile zur markierung freigeben:
								update_frac_ds := '1';
								data_pixels_out <= data_pixels_tmp; -- pixeldaten veröffentlichen und..
								row_target_count <= row_target_count + 1; -- .. signal an write_em_proc
								read_RB_action <= '1'; -- nächste pixeldaten lesen
								frac_next_row <= frac_next_row + one_row;
							end if;
						end if;
						
						row_clk_redge <= '1';
					end if;
				elsif (gap_status = CHECK_SETTLING) then
					-- gap, oder repeat-ende: wir unterstellen pixelzahl-wechsel.
					-- pixelzahl ändert sich im markierbetrieb: segment-wechsel.
					if ((lock_status = 2) AND (DS_dac_t <= 0)) then
						-- locking aktiv, und galvo-geschwindigkeit immer noch <= 0: locking aufrecht erhalten
						gap_status <= SETTL_FINISH;
					else
						if (DS_dac_t > 0) then
							-- galvo-geschwindigkeit > 0: galvo muss mitlaufen --> locking aufheben
							lock_status <= 0;
						end if;
						
						if (ROW_TARGET_REACHED = '1') then 
							-- d.h. ein settling ist in jedem fall nötig - bevor aber irgendwas
							-- gemacht wird: warten bis alle pixel geschrieben sind, dann 
							gap_status <= CHECK_POSITION;
						end if;
					end if;
				elsif (gap_status = CHECK_POSITION) then
					--lage beurteilen
					if ((frac_diff < signed(dR_set_small)) AND ((max_pixels /= 0) OR (lock_status /= 0))) then
						-- wir sind so nah an frac_next_row, dass die small settling time
						-- nicht eingehalten werden kann: wenn echt markiert werden muss, 
						-- oder das locking eingeleitet wurde: zurücksetzen
						gap_status <= STEP_BACK;						
					else
						-- wir sind weiter entfernt von frac_next_row; oder max_pixels = 0:
						-- schnell vorwärts, normales settling
						gap_status <= FAST_FORWARD;
					end if;
				elsif (gap_status = STEP_BACK) then
					-- in die vergangenheit, bis settling-stelle erreicht;
					-- aber nur wenn der galvo nicht schon oben anschlägt (throttling):
					if ((frac_diff < signed(dR_set_small)) AND (GALVO_STATUS(2) = '0')) then
						glv_move_reg <= GLV_MOVE_VERG_FAST;
					else
						-- fertig
						gap_status <= SETTL_FINISH;
					end if;
				elsif (gap_status = FAST_FORWARD) then
					--schnell in die zukunft, bis settling-stelle erreicht
					if (frac_diff > signed(dR_set_base_plus)) then
						-- weiter weg: vollgas
						glv_move_reg <= GLV_MOVE_ZUK_ULTRA_FAST;
					elsif ((frac_diff > signed(dR_set_base)) OR ((max_pixels = 0) AND (frac_diff > 0))) then
						-- näher dran (max_pixels = 0: kein settling, ganz vor zur reihe): langsamer
						glv_move_reg <= GLV_MOVE_ZUK_FAST;
					else
						-- settling-grenze erreicht: fertig
						gap_status <= SETTL_FINISH;
					end if;
				else --SETTL_FINISH
					-- settling-stelle erreicht:
					if (lock_status /= 0) then
						lock_status <= 2;
					end if;
					
					update_frac_ds := '1';
					glv_move_reg <= GLV_MOVE_MARK; -- auf markiergeschwindigkeit umschalten
					max_pixels_prev <= max_pixels;
					gap_status <= WAIT_ROW;-- fertig
				end if;
			end if;
			
			if (update_frac_ds = '1') then
				if (lock_status /= 0) then
					DS_dac_t_out <= (others => '0');
				else 
					DS_dac_t_out <= DS_dac_t; -- normale markiergeschw.
				end if;
			end if;
		end if;
	end process gap_proc;
	
	
	
	
	-- lesen der pixeldaten
	word_cnt <= px_per_row_add(6 downto 5);
	RB_ptr_next <= RB_ptr + 1; 
		read_RB_proc: process(CLK)

	begin
		if (rising_edge(CLK)) then
			if (RESET = '1') then
				px_per_row_add <= (others => '0');
				read_RB_status <= RB_READ_STATUS_RESET;
				RB_ptr <= 0; -- mind. 2 clocks bis...
			else
				-- grafikdaten lesen:
				if (read_RB_status = RB_READ_STATUS_RESET) then
					if (MARK_EN = '1') then
						-- MCU hat die erste zeile geschrieben; der erste puls
						-- auf read_RB_action kommt erst viel später
						read_RB_status <= RB_READ_STATUS_START;
					end if;
				elsif (read_RB_status = RB_READ_STATUS_IDLE) then
					if (read_RB_action = '1') then
						read_RB_status <= RB_READ_STATUS_START;
					end if;
				elsif (read_RB_status = RB_READ_STATUS_START) then
					rb_read_count <= 0;
					read_RB_status <= RB_READ_STATUS_BUSY;
				elsif (read_RB_status = RB_READ_STATUS_BUSY) then
					-- pixel-daten einlesen
					if (rb_read_count = 0) then -- ...daten fertig
						max_pixels <= unsigned(DATA_FROM_MEM_RB(6 downto 0)); -- geht weiter zu calculations_proc
						data_pixels_tmp(23 downto 0) <= DATA_FROM_MEM_RB(31 downto 8); 
						RB_ptr <= RB_ptr_next;	
						
						if (word_cnt = "00") then
							read_RB_status <= RB_READ_STATUS_IDLE;	
						end if;
					-- pausen-clock						
					elsif (rb_read_count = 2) then
						data_pixels_tmp(55 downto 24) <= DATA_FROM_MEM_RB;
						RB_ptr <= RB_ptr_next;
						
						if (word_cnt = "01") then
							read_RB_status <= RB_READ_STATUS_IDLE;
						end if;
					-- pausen-clock
					elsif (rb_read_count = 4) then
						data_pixels_tmp(87 downto 56) <= DATA_FROM_MEM_RB;
						RB_ptr <= RB_ptr_next;

						if (word_cnt = "10") then
							read_RB_status <= RB_READ_STATUS_IDLE;
						end if;
					-- pausen-clock
					elsif (rb_read_count = 6) then
						data_pixels_tmp(119 downto 88) <= DATA_FROM_MEM_RB;	
						RB_ptr <= RB_ptr_next;
						read_RB_status <= RB_READ_STATUS_IDLE;
					end if;	

					rb_read_count <= rb_read_count + 1;
				end if;
				
				-- 1 .. 24 pixel: '00'
				-- 25 .. 56 pixel: '01'
				-- 57 .. 88 pixel: '10'
				-- 89 .. 120 pixel: '11'
				px_per_row_add <= std_logic_vector(unsigned(PX_PER_ROW) + unsigned(SIEBEN));
			end if;
		end if;

	end process read_RB_proc;

	
	
	-- für die berechnung der mitführgeschw. DS_dac_t_out
	div_DS : division
	
	generic map( 
		N => 16,
		F => 10
	)

	port map(
		clk => CLK,
		reset => RESET,
		ddent => std_logic_vector(frac_DR_reg), -- U8.8 
		dsor => std_logic_vector(SR_min),
		
		quot => DS_max_tmp -- U8.18
	);


	-- für die berechnung der settling time dR_set (in reihen)
	div_settl : division
	
	generic map( 
		N => 16,
		F => 8
	)

	port map(
		clk => CLK,
		reset => RESET,
		ddent => std_logic_vector(S_set), -- U16.0 
		dsor => std_logic_vector(SR_min),
		
		quot => dR_set -- U16.8
	);


	-- berechnen der mitführgeschw. und der settling zeit(en)
	calculations_proc: process(CLK)	
		variable SR_min_tmp : unsigned(16 downto 0);
		variable DS_t_tmp : unsigned(37 downto 0); -- U2.36
		variable dR_set_small_tmp : unsigned(23 downto 0); -- U8.16
		
	begin
		if (rising_edge(CLK)) then
			if (RESET = '1')  then
				SR_min <= (others => '0');
				SR_min_raw <= (others => '0');
				DS_max <= (others => '0');
				DS_t <= (others => '0');
				S_set <= (others => '0');
				dR_set_base <= (others => '0');
				dR_set_small <= (others => '0');
			else
				-- max_pixels kommt von der aktuell eingelesenen reihe (d.h. nach der aktuell markierten)
				SR_min_tmp := unsigned(PX_CLK_DIV(9 downto 0))*max_pixels;
				SR_min_raw <= SR_min_tmp(15 downto 0);
				
				-- SR_min darf nicht zu klein werden:
				if (SR_min_raw < SR_min_limit) then
					SR_min <= SR_min_limit;
				else
					SR_min <= SR_min_raw;
				end if;
				
				-- berechne mitlaufgeschwindigkeit DS_dac_t
				DS_max <= unsigned(DS_max_tmp(17 downto 0)); -- U0.18
				
				DS_t_tmp := unsigned(FRAC_ES)*unsigned(FRAC_DE); -- U2.36
				DS_t <= DS_t_tmp(35 downto 18); -- U0.18
				
				DS_dac_t <= signed(DS_t - DS_max); --U0.18
				
				-- settling time base:
				S_set <= SETTLING_TIME_BASE;
				dR_set_base <= resize(unsigned(dR_set), dR_set_base'length); -- U16.8 --> U20.8
				dR_set_base_plus <= dR_set_base + one_row;
				
				-- settling time small: dR_set --> U8.8; SETTLING_TIME_SMALL: U0.8 
				dR_set_small_tmp := unsigned(dR_set(15 downto 0))*unsigned(SETTLING_TIME_SMALL(7 downto 0)); -- U8.8 * U0.8 --> U8.16
				dR_set_small <= resize(dR_set_small_tmp(23 downto 8), dR_set_small'length); -- U8.16 --> U20.8
			end if;
		end if;
	end process calculations_proc;
	

end gap_manager_arch;


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- manages the starting points (in rows) of the repeats
entity repeat_manager is

port(
	CLK : in std_logic;
	RESET : in std_logic;
	RESET_PART : in std_logic;
	ROWS_PER_RPT : in std_logic_vector(19 downto 0); -- U20.0
	FRAC_R_ENC: in std_logic_vector(27 downto 0); -- U20.8
	EXT_TRIGGER : in std_logic;
	GET_NEXT_REPEAT : in std_logic; -- '1': start of next repeat is requested
	USE_EXT_TRIGGER : in std_logic;
	MARK_EN: in std_logic;

	REPEAT_READY : out std_logic;
	REPEAT_ROW : out std_logic_vector(27 downto 0); -- U20.8
	REPEATS_CNT: out std_logic_vector(23 downto 0)
);
end repeat_manager;


architecture repeat_manager_arch of repeat_manager is
	signal repeats_cnt_reg : unsigned(23 downto 0);
	signal ext_trigger_prev : std_logic;
	
	type regType is array (integer range <>) of unsigned(27 downto 0); -- U20.8
	constant ARR_SIZE : natural := 3;
	signal rpt_arr : regType(ARR_SIZE downto 0);
	signal rpt_rd: natural range 0 to ARR_SIZE;
	signal rpt_wr: natural range 0 to ARR_SIZE;
	signal rpt_wr_next: natural range 0 to ARR_SIZE;
	signal rpt_rd_next: natural range 0 to ARR_SIZE;
	
	signal rpt_status: natural range 0 to 1;
	
begin
	-- in:

	
	-- out:
	REPEAT_READY <= '0' when (rpt_rd = rpt_wr) else '1';
	REPEAT_ROW <= std_logic_vector(rpt_arr(rpt_rd));
	REPEATS_CNT <= std_logic_vector(repeats_cnt_reg);
	
	rpt_wr_next <= rpt_wr + 1;
	rpt_rd_next <= rpt_rd + 1;
	

	repeat_proc: process(CLK)
	-- kommunikation zwischen uns und gap_manager::gap_proc:
	-- wenn bei uns ein repeat vorhanden ist: rpt_rd != rpt_wr --> REPEAT_READY = 1 
	-- wenn gap_manager::gap_proc einen repeat fertig hat, und REPEAT_READY sieht,
	-- uebernimmt es den aktuell anliegenden repeat, und gibt einen puls auf GET_NEXT_REPEAT
		
	begin
		if (rising_edge(CLK)) then
			if ((RESET = '1') OR (RESET_PART = '1')) then
				rpt_rd <= 0;
				rpt_wr <= 0; -- REPEAT_READY = 0
				rpt_status <= 0;
					
				if (USE_EXT_TRIGGER = '0') then
					--normal
					rpt_arr(0) <= to_unsigned(32768, REPEAT_ROW'length); -- 128 rows
				end if;
				
				if (RESET = '1') then
					repeats_cnt_reg <= (others => '0');
				end if;
			elsif (rpt_status = 0) then
				-- sicherstellen, dass ROWS_PER_RPT aktuell (insb. /= 0) ist:
				if (MARK_EN = '1') then
					rpt_status <= 1;
				end if;
			else -- rpt_status = 1
				if (USE_EXT_TRIGGER = '0') then
					rpt_wr <= 1; -- REPEAT_READY = 1
					
					-- rd, wr:
					if (GET_NEXT_REPEAT = '1') then
						rpt_arr(0) <= rpt_arr(0) + unsigned(ROWS_PER_RPT & x"00");
					end if;
				else -- USE_EXT_TRIGGER = '1'
					-- rd:
					if (GET_NEXT_REPEAT = '1') then
						-- den read-counter eins weiter drehen; kann nichts schiefgehen,
						-- da der puls in GET_NEXT_REPEAT nur kommt, wenn REPEAT_READY = 1 (d.h. rpt_rd != rpt_wr)
						-- danach allerdings evtl. rpt_rd = rpt_wr, REPEAT_READY = 0
						rpt_rd <= rpt_rd_next;
					end if;
	
					-- wr:
					if ((MARK_EN = '1') and (EXT_TRIGGER = '0') and (ext_trigger_prev = '1')) then
						-- kabel schnell genug, und falling edge: neuen repeat eintragen
						rpt_arr(rpt_wr) <= unsigned(FRAC_R_ENC) + unsigned(ROWS_PER_RPT & x"00");
						
						if (rpt_wr_next = rpt_rd) then
							-- puffer ist voll: aeltesten wert rauswerfen:
							rpt_rd <= rpt_rd_next;
						end if;
						
						rpt_wr <= rpt_wr_next;
					end if;
				end if;
				
				-- repeat-counter:
				if (GET_NEXT_REPEAT = '1') then
					repeats_cnt_reg <= repeats_cnt_reg + 1;
				end if;				
			end if;

			-- always:
			ext_trigger_prev <= EXT_TRIGGER;
		end if;
	end process repeat_proc;
	


end repeat_manager_arch;


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;    -- needed for to_integer

entity write_laser is
port(
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
end write_laser;
 
architecture arch_write_laser of write_laser is
	constant ARR_SIZE : natural := 15; -- 4 bit, see assignment of laser_delay_idx, AOD_delay_idx
	constant PX_MAX : natural := 119; -- see DATA_PIXELS

	type AOD_shift_type is array (integer range <>) of natural range 0 to PX_MAX;
	
	-- ***************** Define signals ****************	
	signal laser_shift_reg : std_logic_vector(ARR_SIZE downto 0);	-- the laser delay shift reg, array of <pixel_value_cand>
	signal laser_delay_idx : natural range 0 to ARR_SIZE; -- the index where to insert data into laser_shift_reg[]
	signal pixel_value_cand : std_logic;

	signal AOD_shift_reg : AOD_shift_type(ARR_SIZE downto 0);	-- the AOD delay shift reg, array of <pixel_count_cand>
	signal AOD_delay_idx : natural range 0 to ARR_SIZE; -- the index where to insert data into AOD_shift_reg[]
	signal pixel_count_cand : natural range 0 to PX_MAX;
	
	signal pixel_count : natural range 0 to PX_MAX;

	signal data_pixels_reg : std_logic_vector(PX_MAX downto 0);
	
	signal write_status : natural range 0 to 3;		-- flag to show that marking is enabled and should be going on now; false means a gap region (either normal or through disabling)
	signal Px_per_row_sig : natural range 0 to PX_MAX;		-- the natural version of PX_PER_ROW input
	
	signal Cmd_AOD_levels : boolean;			-- command value is 0x01 (system in AOD Service state)
	signal rows_marked_count : natural range 0 to 65535;	-- count no. of rows marked so far this repeat
	signal row_target_count : natural range 0 to 65535;
	
	signal delay_em_cnt : natural range 0 to 3;
	signal row_target_reached_reg : std_logic;
	
	constant WAIT_ROW: natural := 0;
	constant SEARCH_PIXEL: natural := 1;
	constant WAIT_PIXEL: natural := 2;
	
begin
	-- assign ouputs 
	Cmd_AOD_levels <= CMD = "01";			-- command value 0x01

	-- '3 downto 0': see ARR_SIZE
	laser_delay_idx <= to_integer(unsigned(DELAY_PX(3 downto 0))) when (DELAY_PX(5) = '0') else 0;
	AOD_delay_idx <= to_integer(unsigned(DELAY_PX(3 downto 0))) when (DELAY_PX(5) = '1') else 0;
	
	Px_per_row_sig <= to_integer(unsigned(PX_PER_ROW));
	row_target_count <= to_integer(unsigned(ROW_TARGET));
	
	ROWS_MARKED <= std_logic_vector(to_unsigned(rows_marked_count, ROWS_MARKED'length));
	
	-- laser and AOD output = element #0 of the corresponding shift register:
	ADDR_TO_MEM_LUT <= std_logic_vector(to_unsigned(AOD_shift_reg(0), ADDR_TO_MEM_LUT'length)); -- von 7 auf 10 bit
	LASER_EM <= '1' when Cmd_AOD_levels else laser_shift_reg(0);
	
	MARKING  <= '1' when (rows_marked_count /= 0) else '0';
	ROW_TARGET_REACHED <= row_target_reached_reg;

	
	write_em_proc: process(CLK)

	begin
		if (rising_edge(CLK)) then
			if (RESET = '1') then
				write_status <= WAIT_ROW;
				rows_marked_count <= 0;
				row_target_reached_reg <= '0';
				pixel_value_cand <= '0';
				pixel_count_cand <= 0;
			else
				if (write_status = WAIT_ROW) then
					-- warten auf nächste reihe
					if (rows_marked_count < row_target_count) then
						-- die nächste zeile angehen (row_target_count > 0)
						row_target_reached_reg <= '0';
						rows_marked_count <= rows_marked_count + 1;
						data_pixels_reg <= DATA_PIXELS; --daten übernehmen
						pixel_count <= 0;
						write_status <= SEARCH_PIXEL;
					else
						if (row_target_count = 0) then -- row_target_count = 0: landet immer hier
							--reset
							rows_marked_count <= 0;
						end if;
						
						if ((laser_shift_reg = (laser_shift_reg'range => '0')) AND
							(AOD_shift_reg = (AOD_shift_reg'range => 0)) ) then
							-- erst bescheid geben, wenn die zeile komplett auf dem kabel ist
							row_target_reached_reg <= '1';
						end if;
					end if;
				elsif (write_status = SEARCH_PIXEL) then
					-- alle pixel durchgehen
					if (pixel_count /= Px_per_row_sig) then
						--zum naechsten ges. pixel vorspulen
						if (data_pixels_reg(pixel_count) = '0') then
							-- ges. pixel gefunden: kandidaten setzen...
							pixel_value_cand <= '1';
							pixel_count_cand <= pixel_count;
							write_status <= WAIT_PIXEL;
						end if;
						
						--in jedem fall weitersuchen
						pixel_count <= pixel_count + 1;
					else
						-- kein ges. pixel mehr da:
						write_status <= WAIT_ROW; -- zeile fertig		
					end if;
				elsif (write_status = WAIT_PIXEL) then
					-- ...und warten, bis sie in delay_proc übernommen wurden
					if (PX_CLK_AOD_REDGE = '1') then
						-- kandidaten bis auf weiteres auf 'kein pixel' setzen
						pixel_value_cand <= '0';
						pixel_count_cand <= 0;
						-- und weitersuchen
						write_status <= SEARCH_PIXEL;
					end if;
				end if;
			end if; 
		end if;	
	end process write_em_proc;	



	delay_proc: process(CLK) -- laeuft immer durch

	begin
		if (rising_edge(CLK)) then
			if (RESET = '1') then
				delay_em_cnt <= 0;
				laser_shift_reg <= (others => '0');
				AOD_shift_reg <= (others => 0);
			else
				-- wenn LASER_CLK_DELAY = 0, dann kommen PX_CLK_AOD_REDGE und PX_CLK_LASER_FEDGE
				-- gleichzeitig --> gleichzeitige ausführung verhindern --> delay_em_cnt
			
				-- neuen pixel übernehmen
				if (PX_CLK_AOD_REDGE = '1') then
					-- die kandidaten übernehmen
					
					-- AOD delayline weiterschieben, und pixel-nummer einfügen;
					-- d.h. im naechsten takt geht neuer wert auf ADDR_TO_MEM_LUT raus:
					AOD_shift_reg <= 0 & AOD_shift_reg((AOD_shift_reg'LENGTH - 1) downto 1); -- shift nach rechts..
					AOD_shift_reg(AOD_delay_idx) <= pixel_count_cand; -- ..index [AOD_delay_idx] ueberschreiben 
					
					-- pixel-wert in laser-delayline einfügen..
					laser_shift_reg(laser_delay_idx+1) <= pixel_value_cand;
				end if;
				
				-- nächsten pixel auf den laser geben
				if (PX_CLK_LASER_FEDGE = '1') then
					delay_em_cnt <= 1;
				elsif (delay_em_cnt = 1) then
					-- .. und im naechsten takt auf LASER_EM geben:
					laser_shift_reg <= '0' & laser_shift_reg((laser_shift_reg'LENGTH - 1) downto 1); -- shift nach rechts	
					delay_em_cnt <= 0;
				end if;
			end if; 
		end if;	
	end process delay_proc;	

	
end arch_write_laser;


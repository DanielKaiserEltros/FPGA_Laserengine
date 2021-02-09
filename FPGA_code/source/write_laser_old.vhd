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
	
	-- ***************** Define signals ****************
	signal data_pixels_reg : std_logic_vector(119 downto 0);
	signal Delay_shift_reg : std_logic_vector(15 downto 0);	-- the delay shift reg 
	signal Delay_pixels : natural range 0 to 15;			
	signal pixel_value_out : std_logic;
	signal pixel_count_out : natural range 0 to 119;
	signal pixel_count_cand : natural range 0 to 119;
	signal pixel_count : natural range 0 to 119;
	signal pixel_value_cand : std_logic;
	signal write_status : natural range 0 to 3;		-- flag to show that marking is enabled and should be going on now; false means a gap region (either normal or through disabling)
	signal Px_per_row_sig : natural range 0 to 119;		-- the natural version of PX_PER_ROW input
	
	
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

	Delay_pixels <= to_integer(unsigned(DELAY_PX));
	Px_per_row_sig <= to_integer(unsigned(PX_PER_ROW));
	row_target_count <= to_integer(unsigned(ROW_TARGET));
	
	ROWS_MARKED <= std_logic_vector(to_unsigned(rows_marked_count, ROWS_MARKED'length));
	ADDR_TO_MEM_LUT <= std_logic_vector(to_unsigned(pixel_count_out, ADDR_TO_MEM_LUT'length)); -- von 7 auf 10 bit
	LASER_EM <= '1' when Cmd_AOD_levels else pixel_value_out;
	
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
						
						if ((Delay_shift_reg = x"0000") AND (pixel_value_out = '0')) then
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



	delay_proc: process(CLK)

	begin
		if (rising_edge(CLK)) then
			if (RESET = '1') then
				delay_em_cnt <= 0;
				Delay_shift_reg <= (others => '0');
				pixel_value_out <= '0';
				pixel_count_out <= 0;
			else
				-- wenn LASER_CLK_DELAY = 0, dann kommen PX_CLK_AOD_REDGE und PX_CLK_LASER_FEDGE gleichzeitig
			
				-- neuen pixel übernehmen
				if (PX_CLK_AOD_REDGE = '1') then
					-- die kandidaten übernehmen
					pixel_count_out <= pixel_count_cand;
					-- pixel in delayline einfügen
					Delay_shift_reg <= '0' & Delay_shift_reg((Delay_shift_reg'LENGTH - 1) downto 1);
					Delay_shift_reg(Delay_pixels) <= pixel_value_cand;
				end if;
				
				-- nächsten pixel ausgeben
				if (PX_CLK_LASER_FEDGE = '1') then
					delay_em_cnt <= 1;
				elsif (delay_em_cnt = 1) then
					--delay-ten pixel auf den laser geben:
					pixel_value_out <= Delay_shift_reg(0);			
					delay_em_cnt <= 0;
				end if;
			end if; 
		end if;	
	end process delay_proc;	

	
end arch_write_laser;


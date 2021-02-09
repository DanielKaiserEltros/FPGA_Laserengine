library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
--use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.NUMERIC_STD.ALL;

-- this module is designed to store information on start and endpoint of gaps
-- data is supplied by the MCU IF and delivered to the gapmanager module

entity gapreg is
port ( 		
     Clock : in std_logic;
     Reset: in std_logic;							
     DataInA : in std_logic_vector(7 downto 0);			-- from MCU_IF
     AddressA : in std_logic_vector(7 downto 0);		-- from MCU_IF
     ClockEnA: in std_logic;							-- from MCU_IF
     WrA: in std_logic;									-- from MCU_IF
     GapIndex : in std_logic_vector(5 downto 0);		-- from gap msnager, pointer to actual gap data
	 
     GapStartRow : out std_logic_vector(15 downto 0);	-- to gap manager
     Gaplength : out std_logic_vector(15 downto 0)		-- to gap manager	 
);
end gapreg;

architecture arch_gapreg of gapreg is
	type regType is array (integer range <>) of std_logic_vector(7 downto 0);
	signal gapreg : regType(159 downto 0);
	signal AddrA : natural range 0 to 255;
	signal idx: natural range 0 to 255;

    signal GapStartRow_out : std_logic_vector(15 downto 0);	
    signal Gaplength_out : std_logic_vector(15 downto 0); 

begin
	AddrA <= to_integer(unsigned(AddressA)); 
	idx <= to_integer(unsigned(GapIndex))*4; 
	 
	GapStartRow <= GapStartRow_out;
	Gaplength <= Gaplength_out;
	
	working: process(Clock)
	begin
		if (rising_edge(Clock)) then
			if (Reset = '1') then
				for i in 0 to 159 loop
					gapreg(i) <= (OTHERS => '0');
				end loop;
				
				GapStartRow_out <= (OTHERS => '0'); 
				Gaplength_out <= (OTHERS => '0');
			else
				-- prepare data
				if (idx < 157) then
					GapStartRow_out <= gapreg(idx + 1) & gapreg(idx);
					Gaplength_out <= gapreg(idx + 3) & gapreg(idx + 2);
				else
					GapStartRow_out <= (OTHERS => '0');
					Gaplength_out <= (OTHERS => '0');
				end if;
				
				-- handle write access
				if (ClockEnA = '1') then		-- carry out the write/read functions associated with MCUIF
					if (WrA = '1') and (AddrA < 160) then
						gapreg(AddrA) <= DataInA;
					end if;
				end if;
			end if;			
		end if;
	end process;
	
end arch_gapreg;
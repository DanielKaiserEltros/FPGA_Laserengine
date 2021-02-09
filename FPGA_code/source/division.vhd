library IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;


entity division is

generic( 
	N : positive := 32;
	F : positive := 16
);

port(
	clk: in std_logic;
	reset: in std_logic;
	ddent : in std_logic_vector(N-1 downto 0);
	dsor : in std_logic_vector(N-1 downto 0);
    
	busy : out std_logic;
    quot : out std_logic_vector(N+F-1 downto 0)
);
end division;


architecture arch_div of division is
	signal div_state : natural range 0 to 3;
	signal ddent_cp : std_logic_vector(N-1 downto 0);
	signal dsor_cp : std_logic_vector(N-1 downto 0);
	signal remainder_work : std_logic_vector(N downto 0); -- high bit added
	signal remainder_frac : std_logic_vector(N-2 downto 0);  -- high bit removed
	signal quot_reg : unsigned(N+F-1 downto 0);
	signal quot_out : unsigned(N+F-1 downto 0);
	signal bit_pos : natural range 0 to N+F-1;

begin
	
	quot <= std_logic_vector(quot_out);
	busy <= '1' when (div_state /= 0) else '0';

	process(clk)
		variable remainder : unsigned(N downto 0);
		variable divisor : unsigned(N downto 0);

	begin
		if rising_edge(clk) then
			if (reset = '1') then
				div_state <= 0;
				ddent_cp <= (others => '0');
				dsor_cp <= (others => '0');
				quot_out <= (others => '0');
			else
				if (div_state = 0) then
					--wait for start
					if ((ddent_cp /= ddent) OR (dsor_cp /= dsor)) then
						-- something has changed: start new calculation
						ddent_cp <= ddent; -- ddent_cp: only used to detect changes
						dsor_cp <= dsor; -- dsor_cp: used in calculation
						
						if (ddent = (ddent'range => '0')) then	
							-- 0/x = 0
							quot_out <= (others => '0');					
						elsif (dsor = (dsor'range => '0')) then
							--division durch 0
							quot_out <= (others => '1');
						else
							remainder_work(N downto 1) <= (others => '0');
							remainder_work(0) <= ddent(N-1);
							remainder_frac <= ddent(N-2 downto 0);
							bit_pos <= N+F-1;
							div_state <= 1;
						end if;
					end if;
				elsif (div_state = 1) then
					remainder := unsigned(remainder_work);
					divisor := unsigned('0' & dsor_cp);
					
					if (remainder >= divisor) then
						remainder := remainder - divisor;
						quot_reg(bit_pos) <= '1';
					else
						quot_reg(bit_pos) <= '0';
					end if;
					
					--shift left:
					remainder_work(N downto 1) <= std_logic_vector(remainder(N-1 downto 0));
					remainder_work(0) <= remainder_frac(N-2);
					remainder_frac <= remainder_frac(N-3 downto 0) & '0';
					
					if (bit_pos /= 0) then
						bit_pos <= bit_pos - 1;
					else
						-- 1 clock pause, damit obige zuweisungen durchlaufen können
						div_state <= 3;
					end if;
				elsif (div_state = 3) then
					--ergebnis rausgeben:
					quot_out <= quot_reg;
					div_state <= 0;
				end if;
			end if;
		end if;
	
	end process;

end arch_div;

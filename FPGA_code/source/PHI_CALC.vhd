library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Missing : PHI_ovfl generation

entity PHI_CALC is
port
(
	CLK : in std_logic;
	RESET : in std_logic;
	WR_active : in std_logic;						-- laser writing active. If not assigned the output will be set to zero
	ENC_EDGE : in std_logic;						-- a 1 clock cycle pulse at the rising edge of ENC
	KD_fine : in std_logic_vector(11 downto 0);		-- Constant delivered by MCU
	KD_coarse : in std_logic_vector(11 downto 0);	-- constant multiplier of PHI output, allowed values are 1,2,4,8,16,32,64,128 
	PHI_max : in std_logic_vector(15 downto 0);		-- maximum PHI value which can be handled. Constant delivered by MCU
	SPD_CT_min : in std_logic_vector(23 downto 0);	-- minimum SPD_CT_DATA (i.e. maximum cable speed) without galvo action, Constant delivered by MCU
	SPD_CT_DATA: in std_logic_vector(23 downto 0);	-- number of CLK cycles between two encoder pulses. i.e. reciprocally proportional to cable speed
	PHI  : out std_logic_vector(15 downto 0);		-- calculated galvo control
	PHI_ovfl  : out std_logic						-- maximum PHI value reached , error flag
);
end PHI_CALC;

architecture arch_icm of PHI_CALC is
	signal not_PHI_max : std_logic_vector(15 downto 0);				-- one's complement of 
	signal signed_SPD_CT_min : in std_logic_vector(25 downto 0);	-- SPD_CT_min with positive sign extension		
    signal not_SPD_CT_DATA : in std_logic_vector(25 downto 0);		-- one's complement of  SPD_CT_DATA
	signal minus_SPD_CT_DATA : in std_logic_vector(25 downto 0);	-- two's complement of  SPD_CT_DATA
	signal SPD_CT_diff : std_logic_vector(25 downto 0);				-- SPD_CT_min - SPD_CT_DATA 
	signal SPD_CT_diff_pos : std_logic_vector(23 downto 0);			-- SPD_CT_min - SPD_CT_DATA limited to positive values
	signal MULT_A  : std_logic_vector(35 downto 0);					-- multiplier input and shift register
	signal MULT : std_logic_vector(35 downto 0);					-- serial multiplier accumulator
	signal PHI_incr : std_logic_vector(35 downto 0);				-- calculated increment of PHI per row period ;
	signal PHI_accu : std_logic_vector(63 downto 0);				-- accumulated PHI raw data;
	signal serial_state : natural range 0 to 15;
	
begin

not_SPD_CT_DATA <= "11" & NOT SPD_CT_DATA;

	icm_phi_proc: process(CLK)	
	begin
		if (rising_edge(CLK)) then
			if (RESET = '1') then
				PHI_accu <= (others => '0');
				PHI_incr <= (others => '0');
				serial_state <= (others => '0');
			else
				minus_SPD_CT_DATA <= not_SPD_CT_DATA + "00000000000000000000000001";
				SPD_CT_diff <= signed_SPD_CT_min + minus_SPD_CT_DATA;
				SPD_CT_diff_pos <= x"000000" when SPD_CT_diff(25) = '1' else SPD_CT_diff(23 downto 0);
				-- serial calulations
				if serial_state = 0 then
					MULT_A <= x"000" & SPD_CT_diff_pos;
					if SPD_CT_diff_pos = (others => '0') then
						PHI_incr <= (others => '0');
						serial_state <= 0;
					else serial_state <= 1;
					end if;
				else if serial_state > 11 then
					PHI_incr <= MULT;
					serial_state <= 0;
				else
				-- multiplier
					for serial_state in 1 to 11 loop
						MULT_A <= MULT_A sll 1;
						if KD_fine(serial_state -1) = '1' then 
							MULT <= MULT + MULT_A ;
						end if;
						serial_state <=  serial_state + 1;
					end loop
				end if;
				-- integration of PHI value
				if WR_active = '0' then
					PHI_accu <= (others => '0');
				else if ENC_EDGE = '1' then 
					PHI_accu <= PHI_accu + (x"0000000" & PHI_incr);
				end if;
				-- generate output to galvo unit
				if (KD_coarse(11) = '1' then 
					PHI <= PHI_accu(63 downto 48);
				else if (KD_coarse(10) = '1' then
					PHI <= PHI_accu(62 downto 47);
				else if (KD_coarse(9) = '1' then
					PHI <= PHI_accu(61 downto 46);
				else if (KD_coarse(8) = '1' then
					PHI <= PHI_accu(60 downto 45);
				else if (KD_coarse(7) = '1' then
					PHI <= PHI_accu(59 downto 44);
				else if (KD_coarse(6) = '1' then
					PHI <= PHI_accu(58 downto 43);
				else if (KD_coarse(5) = '1' then
					PHI <= PHI_accu(57 downto 42);
				else if (KD_coarse(4) = '1' then
					PHI <= PHI_accu(56 downto 41);
				else if (KD_coarse(3) = '1' then
					PHI <= PHI_accu(55 downto 40);
				else if (KD_coarse(2) = '1' then
					PHI <= PHI_accu(54 downto 39);
				else if (KD_coarse(1) = '1' then
					PHI <= PHI_accu(53 downto 38);
				else 
					PHI <= PHI_accu(52 downto 37);
				end if;
			end if;
		end if;
	end process;

end arch_icm;
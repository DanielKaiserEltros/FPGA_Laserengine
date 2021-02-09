library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL; 


entity dpram4wide is
port (
	DataInA: in  std_logic_vector(7 downto 0); 
	AddressA: in  std_logic_vector(11 downto 0); 
	AddressB: in  std_logic_vector(9 downto 0); 
	Clock: in  std_logic; 
	ClockEnA: in  std_logic; 
	Reset: in  std_logic;				-- active high);	
	
	DataOutB: out  std_logic_vector(31 downto 0));		
end dpram4wide;

architecture arch_dpram4wide of dpram4wide is

-- *************************************************************
--         DECLARE COMPONENTS AND ASSOCIATED SIGNALS
-- *************************************************************

-- parameterized module component declaration
component DataBuffer
    port (
		DataInA: in  std_logic_vector(7 downto 0); 
        DataInB: in  std_logic_vector(7 downto 0); 
        AddressA: in  std_logic_vector(9 downto 0); 
        AddressB: in  std_logic_vector(9 downto 0); 
        ClockA: in  std_logic; 
		ClockB: in  std_logic; 
        ClockEnA: in  std_logic; 
		ClockEnB: in  std_logic; 
        WrA: in  std_logic; 
		WrB: in  std_logic; 
		ResetA: in  std_logic; 
        ResetB: in  std_logic; 
		QA: out  std_logic_vector(7 downto 0); 
        QB: out  std_logic_vector(7 downto 0));
end component;

-- Declare signals for using DataBuffer component

-- Declare signals for dpram0
	
	signal dpr0_ClockEnA: std_logic; 
	signal dpr0_QA: std_logic_vector(7 downto 0); -- dummy
	signal dpr0_QB: std_logic_vector(7 downto 0);
	
-- Declare signals for dpram1
	signal dpr1_ClockEnA: std_logic;
	signal dpr1_QA: std_logic_vector(7 downto 0); -- dummy
	signal dpr1_QB: std_logic_vector(7 downto 0);
	
-- Declare signals for dpram2
	signal dpr2_ClockEnA: std_logic; 
	signal dpr2_QA: std_logic_vector(7 downto 0); -- dummy
	signal dpr2_QB: std_logic_vector(7 downto 0);
	
-- Declare signals for dpram3
	signal dpr3_ClockEnA: std_logic;
	signal dpr3_QA: std_logic_vector(7 downto 0); -- dummy
	signal dpr3_QB: std_logic_vector(7 downto 0);

-- declare other signals
	
	signal zero8bit : std_logic_vector(7 downto 0);
	
-- end declare other signals

begin	-- architecture

-- *************************************************************
--                  INSTANTIATE COMPONENTS
-- *************************************************************

dpram0 : DataBuffer					-- for addresses xxxxxxxx00
port map
(
	DataInA => DataInA,
	DataInB => zero8bit,
	AddressA => AddressA(11 downto 2),
	AddressB => AddressB,
	ClockA => Clock,
	ClockB => Clock,
	ClockEnA => dpr0_ClockEnA,
	ClockEnB => '1',
	WrA => '1',
	WrB => '0',
	ResetA => Reset,
	ResetB => Reset,
	QA => dpr0_QA,
	QB => dpr0_QB
);

dpram1 : DataBuffer					-- for addresses xxxxxxxx01
port map
(
	DataInA => DataInA,
	DataInB => zero8bit,
	AddressA => AddressA(11 downto 2),
	AddressB => AddressB,
	ClockA => Clock,
	ClockB => Clock,
	ClockEnA => dpr1_ClockEnA,
	ClockEnB => '1',
	WrA => '1',
	WrB => '0',
	ResetA => Reset,
	ResetB => Reset,
	QA => dpr1_QA,
	QB => dpr1_QB
);

dpram2 : DataBuffer					-- for addresses xxxxxxxx10
port map
(
	DataInA => DataInA,
	DataInB => zero8bit,
	AddressA => AddressA(11 downto 2),
	AddressB => AddressB,
	ClockA => Clock,
	ClockB => Clock,
	ClockEnA => dpr2_ClockEnA,
	ClockEnB => '1',
	WrA => '1',
	WrB => '0',
	ResetA => Reset,
	ResetB => Reset,
	QA => dpr2_QA,
	QB => dpr2_QB
);

dpram3 : DataBuffer					-- for addresses xxxxxxxx11
port map
(
	DataInA => DataInA,
	DataInB => zero8bit,
	AddressA => AddressA(11 downto 2),
	AddressB => AddressB,
	ClockA => Clock,
	ClockB => Clock,
	ClockEnA => dpr3_ClockEnA,
	ClockEnB => '1',
	WrA => '1',
	WrB => '0',
	ResetA => Reset,
	ResetB => Reset,
	QA => dpr3_QA,
	QB => dpr3_QB
);


-- *************************************************************
--                  		BEHAVIOUR
-- *************************************************************
	zero8bit <= "00000000";
	
	--combine from AddrA = X11 & X10 & X01 & X00 (eg addr 3,2,1,0 or 7,6,5,4...)
	DataOutB <= dpr3_QB & dpr2_QB & dpr1_QB & dpr0_QB;		
	
	-- put AddrA = X00 into dpr0, X01 into dpr1, X10 into dpr2, X11 into dpr3
	dpr0_ClockEnA <= '1' when AddressA(1 downto 0) = "00" AND ClockEnA = '1' else '0';
	dpr1_ClockEnA <= '1' when AddressA(1 downto 0) = "01" AND ClockEnA = '1' else '0';
	dpr2_ClockEnA <= '1' when AddressA(1 downto 0) = "10" AND ClockEnA = '1' else '0';
	dpr3_ClockEnA <= '1' when AddressA(1 downto 0) = "11" AND ClockEnA = '1' else '0';	
	

end arch_dpram4wide;


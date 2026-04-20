library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- It provides a periodic tick signal one clock cycle long
-- The period is a generic parameter given in units of clock ticks

entity periodicTick is
  port (
    Clock      : in  STD_LOGIC;
    Reset      : in  STD_LOGIC;
    TickPeriod : in  unsigned(31 downto 0);
    Tick       : out STD_LOGIC
  );
end periodicTick;

architecture behavior of periodicTick is

begin

  process (Clock)

    variable Timer : unsigned(31 downto 0) := x"0000_0000";

  begin
    if rising_edge(Clock) then

      if Reset = '1' then
        Tick <= '0';
        Timer := x"0000_0000";
      else

        Tick <= '0';
        Timer := Timer + x"0000_0001";

        if Timer >= TickPeriod then
          Tick <= '1';
          Timer := x"0000_0000";
        end if;

      end if;
    end if;
  end process;

end architecture;
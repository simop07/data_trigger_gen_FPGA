-- -----------------------------------------------------------------------
-- LongerPulse
-- -----------------------------------------------------------------------
--
-- It takes in input a signal (pulse) and provides in output a longer copy 
-- of the input signal by prolonging it by a specific DURATION in clock
-- ticks. The LongPulse begins when the rising edge of the incoming
-- pulse is detected
--

library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;

entity LongerPulse is
  generic (DURATION : NATURAL := 5_000_000); -- 50 ms @ 100 MHz
  port (
    -- Inputs
    Clock : in STD_LOGIC;
    Reset : in STD_LOGIC;
    Pulse : in STD_LOGIC;

    -- Outputs
    LongPulse : out STD_LOGIC
  );
end entity LongerPulse;

architecture logic of LongerPulse is
begin

  process (Clock)

    variable counter : NATURAL range 0 to DURATION := 0;
    variable oldPulse : STD_LOGIC := '1';

  begin

    if rising_edge(Clock) then
      if Reset = '1' then
        oldPulse := '1';
        counter := 0;
        LongPulse <= '0';
      else

        if Pulse = '1' and oldPulse = '0' then
          counter := DURATION;
        end if;

        if counter > 0 then
          counter := counter - 1;
          LongPulse <= '1';
        else
          LongPulse <= '0';
        end if;

        oldPulse := Pulse;

      end if;
    end if;
  end process;

end architecture logic;
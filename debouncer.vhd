library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Eliminates metastability of a button and synchronizes the button signal
--
--   1. A double flip-flop (btn_sync) synchronizes the asynchronous signal and
--      eliminates metastability in input
--   2. Stability counter (stable_cnt): signal is stable if after STABLE_CYCLES
--      clock cycles it has the same value

entity debouncer is
  generic (
    -- 500_000 cycles @ 100 MHz = 5 ms (the typical bounce is < 1 ms)
    STABLE_CYCLES : INTEGER := 500_000
  );
  port (
    Clock         : in  STD_LOGIC;
    Btn_in        : in  STD_LOGIC; -- Raw button from FPGA
    Stable_button : out STD_LOGIC
  );
end entity debouncer;

architecture Rtl of debouncer is

  signal btn_sync : STD_LOGIC_VECTOR(1 downto 0) := (others => '0');
  signal stable_cnt : INTEGER range 0 to STABLE_CYCLES := 0;
  signal stable_reg : STD_LOGIC := '0';

begin

  process (Clock)
  begin
    if rising_edge(Clock) then

      -- 2 flip-flops synchronization
      btn_sync(0) <= Btn_in;
      btn_sync(1) <= btn_sync(0);

      if btn_sync(1) /= stable_reg then
        if stable_cnt = STABLE_CYCLES - 1 then

          stable_reg <= btn_sync(1);
          stable_cnt <= 0;
        else
          stable_cnt <= stable_cnt + 1;
        end if;
      else

        stable_cnt <= 0;
      end if;

    end if;
  end process;

  Stable_button <= stable_reg;

end architecture;
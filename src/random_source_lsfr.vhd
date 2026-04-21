library IEEE;
use IEEE.std_logic_1164.all;

entity random_source_lsfr is
  port (
    Clock        : in  STD_LOGIC;
    Reset        : in  STD_LOGIC;
    Seed         : in  STD_LOGIC_VECTOR(23 downto 0);
    RandomNumber : out STD_LOGIC_VECTOR(23 downto 0)
  );
end entity random_source_lsfr;

architecture Rtl of random_source_lsfr is

  signal state : STD_LOGIC_VECTOR(23 downto 0) := x"ABCDEF";

begin

  process (Clock)
  begin

    if rising_edge(Clock) then

      if Reset = '1' then
        state <= Seed;
      else
        -- 24-bit LFSR using Galois primitive polynomial x^24 + x^23 + x^22 + x^17 + 1
        -- Taps at positions 23, 22, 21, 16 (0-based)
        state <= state(22 downto 0) &
                 (state(23) xor state(22) xor state(21) xor state(16));

      end if;
    end if;
  end process;

  RandomNumber <= state;

end architecture;
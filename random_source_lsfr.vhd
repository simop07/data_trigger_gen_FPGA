library IEEE;
use IEEE.std_logic_1164.all;

entity random_source_lsfr is
  port (
    Clock        : in  STD_LOGIC;
    Reset        : in  STD_LOGIC;
    Seed         : in  STD_LOGIC_VECTOR(19 downto 0);
    RandomNumber : out STD_LOGIC_VECTOR(19 downto 0)
  );
end entity random_source_lsfr;

architecture Rtl of random_source_lsfr is

  signal state : STD_LOGIC_VECTOR(19 downto 0) := x"ABCDE";

begin

  process (Clock, Reset)
  begin
    if Reset = '1' then
      state <= Seed;

    elsif rising_edge(Clock) then
      -- 20-bit LFSR source using Galois primitive polynomial x^20 + x^17 + 1
      state <= state(18 downto 0) &
               (state(19) xor state(16));
    end if;
  end process;

  RandomNumber <= state;

end architecture;
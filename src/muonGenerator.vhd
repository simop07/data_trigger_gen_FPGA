library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity muonGenerator is
  port (
    -- Inputs
    Clock : in STD_LOGIC;
    Reset : in STD_LOGIC;

    -- Outputs
    Adc_value : out STD_LOGIC_VECTOR(11 downto 0);
    In_pulse  : out STD_LOGIC
  );
end entity muonGenerator;

architecture Rtl of muonGenerator is

  -- Signals for random vector
  signal Seed : STD_LOGIC_VECTOR(19 downto 0) := x"ABCDE";
  signal lsfr : STD_LOGIC_VECTOR(19 downto 0);

  -- States of the pulse
  type Pulse_state is (BASELINE, RISE, DECAY);
  signal state : Pulse_state := BASELINE;

  -- Noise state
  signal noise : unsigned(7 downto 0) := (others => '0');

  -- Time elapsing before next muon pulse arrives (at 100 MHz, every 10 ms <=> 1_000_000 clocks)
  signal arrival_counter : unsigned(23 downto 0) := (others => '0');
  signal arrival_target : unsigned(23 downto 0) := to_unsigned(300000, 24);

  -- Adc local signal
  signal adc_loc : unsigned(11 downto 0) := (others => '0');

  -- Pulse maximum
  signal pulse_max : unsigned(11 downto 0) := (others => '0');

  -- Current pulse value
  signal pulse_val : unsigned(11 downto 0) := (others => '0');

  -- Counter for pulse rise time
  signal rise_counter : unsigned(2 downto 0) := (others => '0');

  -- Maximum pulse rise time
  signal rise_max : unsigned(2 downto 0) := to_unsigned(4, 3); -- 50 ns @ 100 MHz

  signal in_pulse_reg : STD_LOGIC := '0';

begin

  -- Generate 20-bit random vector [0,1048575]
  LSFR_RND : entity work.random_source_lsfr
    port map(
      Clock        => Clock,
      Reset        => Reset,
      Seed         => Seed,
      RandomNumber => lsfr
    );

  process (Clock)

    variable new_amp : unsigned(11 downto 0);
    variable decay_val : unsigned(11 downto 0);
    variable adc_sum : unsigned(12 downto 0);
    variable next_pulse_val : unsigned(11 downto 0);

  begin

    if rising_edge(Clock) then

      if Reset = '1' then
        in_pulse_reg <= '0';
        state <= BASELINE;
        adc_loc <= (others => '0');
        arrival_counter <= (others => '0');
        arrival_target <= to_unsigned(300000, 24);
        pulse_max <= (others => '0');
        pulse_val <= (others => '0');
        rise_counter <= (others => '0');
        rise_max <= to_unsigned(4, 3);
        new_amp := (others => '0');
        decay_val := (others => '0');
        adc_sum := (others => '0');
        next_pulse_val := (others => '0');
        noise <= (others => '0');

      else

        -- Noise pedestal is given by 6 LSB of lsfr [0,63] + 80 => [80,143]
        noise <= resize(unsigned(lsfr(5 downto 0)), 8) + to_unsigned(80, 8);

        case state is

          when BASELINE =>
            pulse_val <= (others => '0');
            arrival_counter <= arrival_counter + 1;
            adc_loc <= resize(noise, 12);
            in_pulse_reg <= '0';

            if arrival_counter >= arrival_target then

              -- New max amplitude: 11 LSB of lsfr [0,2047] + 1500 => [1500,3547]
              new_amp := resize(unsigned(lsfr(10 downto 0)), 12) + to_unsigned(1500, 12);

              -- Safety clamp: keep room for noise (+143) to stay within 4095
              -- max safe pulse_max = 4095 - 143 = 3952; we keep 3800 for margin
              if new_amp > to_unsigned(3800, 12) then
                new_amp := to_unsigned(3800, 12);
              end if;

              pulse_max <= new_amp;
              arrival_counter <= (others => '0');

              -- Randomize next arrival [0,1_048_576] + 10_000_000 => [10_000_000,11_048_576] (~100-110 ms)
              arrival_target <= resize(unsigned(lsfr(19 downto 0)), 24)
                                + to_unsigned(10_000_000, 24);

              rise_counter <= (others => '0');
              state <= RISE;
            end if;

          when RISE =>
            rise_counter <= rise_counter + 1;

            -- Rise duration fixed by rise_counter
            if rise_counter >= rise_max then
              -- Force the value to exactly pulse_max on the last rise cycle
              next_pulse_val := pulse_max;
              rise_counter <= (others => '0');
              state <= DECAY;
            else
              next_pulse_val := pulse_val + shift_right(pulse_max, 2); -- + pulse_max/4 per cycle
            end if;

            pulse_val <= next_pulse_val;
            in_pulse_reg <= '1';

            -- Use 13-bit sum then saturate to 12 bits
            adc_sum := ('0' & resize(noise, 12)) + ('0' & next_pulse_val);
            if adc_sum > to_unsigned(4095, 13) then
              adc_loc <= (others => '1'); -- saturate at 4095
            else
              adc_loc <= adc_sum(11 downto 0);
            end if;

          when DECAY =>
            -- 15/16 * pulse_val, meaning decay lasts ~ 500 ns
            decay_val := pulse_val - shift_right(pulse_val, 4); -- 15/16 * pulse_val

            in_pulse_reg <= '1';

            if decay_val < to_unsigned(150, 12) then
              pulse_val <= (others => '0');
              adc_loc <= resize(noise, 12);
              in_pulse_reg <= '0';
              state <= BASELINE;
            else
              pulse_val <= decay_val;

              -- Use updated decay_val and 13-bit saturating addition
              adc_sum := ('0' & resize(noise, 12)) + ('0' & decay_val);
              if adc_sum > to_unsigned(4095, 13) then
                adc_loc <= (others => '1');
              else
                adc_loc <= adc_sum(11 downto 0);
              end if;
            end if;

          when others =>
            state <= BASELINE;

        end case;
      end if;
    end if;
  end process;

  Adc_value <= STD_LOGIC_VECTOR(adc_loc);
  In_pulse <= in_pulse_reg;

end architecture;
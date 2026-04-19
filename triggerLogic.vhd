library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity triggerLogic is
  generic (
    -- Threshold in ADC counts (12-bit)
    THRESHOLD : NATURAL := 600;
    -- To prevent re-triggering on the same pulse
    HYSTERESIS : NATURAL := 100;
    -- Pulse width in clock cycles (20 cycles = 200 ns @ 100 MHz)
    PULSE_WIDTH : NATURAL := 20);
  port (
    -- Inputs
    Clock     : in STD_LOGIC;
    Reset     : in STD_LOGIC;
    Adc_value : in STD_LOGIC_VECTOR(11 downto 0);

    -- Outputs
    Trigger_out : out STD_LOGIC
  );
end entity triggerLogic;

architecture Rtl of triggerLogic is

  -- Define local trigger
  signal trg_loc : STD_LOGIC := '0';

  -- Define counter
  signal width_counter : NATURAL range 0 to PULSE_WIDTH := 0;

  -- Define state of the pulse
  type PulseState is (InPulse, OutPulse, Lockout);
  signal toState : PulseState := OutPulse;

  -- Transform naturals to unsigned
  constant THRESHOLD_U : unsigned(11 downto 0) := to_unsigned(THRESHOLD, 12);
  constant HYSTERESIS_U : unsigned(11 downto 0) := to_unsigned(THRESHOLD - HYSTERESIS, 12);

begin

  process (Clock)
  begin

    if rising_edge(Clock) then
      if Reset = '1' then
        trg_loc <= '0';
        toState <= OutPulse;
        width_counter <= 0;
      else

        case toState is
          when OutPulse =>
            trg_loc <= '0';
            if unsigned(Adc_value) >= THRESHOLD_U then
              width_counter <= 0;
              toState <= InPulse;
            end if;

          when InPulse =>
            trg_loc <= '1';
            if width_counter < PULSE_WIDTH - 1 then
              width_counter <= width_counter + 1;
            else
              toState <= Lockout;
            end if;

          when Lockout =>
            trg_loc <= '0';
            if unsigned(Adc_value) <= HYSTERESIS_U then
              toState <= OutPulse;
            end if;

          when others =>
            toState <= OutPulse;
        end case;

      end if;
    end if;
  end process;

  Trigger_out <= trg_loc;

end architecture;
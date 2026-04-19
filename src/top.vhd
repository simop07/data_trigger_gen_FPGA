-- =============================================================================
-- Physical connections of top entity
-- =============================================================================
--
--  Signal      | FPGA pin | Physical connector    | Info
-- -------------|----------|-----------------------|----------------------
--  CLK         | W5       | Onboard oscillator    | Dedicated 100 MHz
--  BTNC        | U18      | Button btnC (central) | Active-HIGH
--  trigger_out | J1       | PMOD JA, pin 1 (left) | -> GPIO Altera board
--  uart_to_pc  | A18      | USB-UART RsTx (top)   | -> PC via USB
--  led[0]      | U16      | LD0                   | Active muon pulse
--  led[1]      | E19      | LD1                   | Shooted trigger
--  led[2]      | U19      | LD2                   | UART busy

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity top is
  port (
    CLK        : in  STD_LOGIC; -- 100 MHz clock
    BTNC       : in  STD_LOGIC; -- High when pressed
    triggerOut : out STD_LOGIC; -- JA1 Pmod
    uart_to_pc : out STD_LOGIC; -- UART transmission;
    led        : out STD_LOGIC_VECTOR(2 downto 0)
  );
end entity;

architecture rtl of top is

  signal adc_val_loc : STD_LOGIC_VECTOR(11 downto 0) := (others => '0');
  signal adc_val_latched : STD_LOGIC_VECTOR(11 downto 0) := (others => '0');
  signal trg_out_loc : STD_LOGIC := '0';
  signal in_pulse_loc : STD_LOGIC := '0';
  signal trg_out_stretched : STD_LOGIC := '0';
  signal in_pulse_stretched : STD_LOGIC := '0';
  signal SyncStableReset : STD_LOGIC := '0';
  signal uart_busy : STD_LOGIC := '0';
  signal send_packet_loc : STD_LOGIC := '0';
  signal trg_prev : STD_LOGIC := '1';

begin

  MuonGenerator : entity work.muonGenerator
    port map(
      Clock     => CLK,
      Reset     => SyncStableReset,
      Adc_value => adc_val_loc,
      In_pulse  => in_pulse_loc
    );

  TriggerLogic : entity work.triggerLogic
    generic map(
      THRESHOLD   => 600,
      HYSTERESIS  => 100,
      PULSE_WIDTH => 20 -- 20 @ 100 MHz = 200 ns
    )
    port map(
      Clock       => CLK,
      Reset       => SyncStableReset,
      Adc_value   => adc_val_loc,
      Trigger_out => trg_out_loc
    );

  UARTConnection : entity work.uart
    generic map(
      CLK_FREQ  => 100_000_000,
      BAUD_RATE => 115_200
    )
    port map(
      Clock       => CLK,
      Reset       => SyncStableReset,
      adc_data    => adc_val_latched,
      send_packet => send_packet_loc,
      uart_pin    => uart_to_pc,
      busy        => uart_busy
    );

  DebouncerButton : entity work.debouncer
    generic map(
      STABLE_CYCLES => 500_000 --500_000 cycles @ 100 MHz = 5 ms
    )
    port map(
      Clock         => CLK,
      Btn_in        => BTNC,
      Stable_button => SyncStableReset
    );

  StretchInPulse : entity work.LongerPulse
    generic map(
      DURATION => 5_000_000 -- 50 ms @ 100 MHz
    )
    port map(
      Clock     => CLK,
      Reset     => SyncStableReset,
      Pulse     => in_pulse_loc,
      LongPulse => in_pulse_stretched
    );

  StretchInTrigger : entity work.LongerPulse
    generic map(
      DURATION => 5_000_000 -- 50 ms @ 100 MHz
    )
    port map(
      Clock     => CLK,
      Reset     => SyncStableReset,
      Pulse     => trg_out_loc,
      LongPulse => trg_out_stretched
    );

  -- LEDs
  led(0) <= in_pulse_stretched; -- From 550 ns -> 50 ms
  led(1) <= trg_out_stretched; -- From 200 ns -> 50 ms
  led(2) <= uart_busy; -- UART busy

  triggerOut <= trg_out_loc;

  -- Send ADC packet at the trigger edge
  process (CLK)
  begin
    if rising_edge(CLK) then

      if SyncStableReset = '1' then
        send_packet_loc <= '0';
        trg_prev <= '1';
        adc_val_latched <= (others => '0');
      else

        send_packet_loc <= '0'; -- Default behaviour

        if trg_out_loc = '1' and trg_prev = '0' then
          adc_val_latched <= adc_val_loc;

          if uart_busy = '0' then
            send_packet_loc <= '1';
          end if;
        end if;

        trg_prev <= trg_out_loc;
      end if;
    end if;
  end process;

end architecture;
-- =======================================================================
-- Physical connections of top entity
-- =======================================================================
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
--  led[3]      | V19      | LD3                   | Write acknowledge
--  led[4]      | W18      | LD4                   | FIFO almost full
--  led[5]      | U15      | LD5                   | Reset button
--  sw          | V17      | SW0                   | Rapid/Slow mode

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity top is
  port (
    CLK        : in  STD_LOGIC; -- 100 MHz clock
    BTNC       : in  STD_LOGIC; -- High when pressed
    sw         : in  STD_LOGIC; -- Change generator rate
    triggerOut : out STD_LOGIC; -- JA1 Pmod
    uart_to_pc : out STD_LOGIC; -- UART transmission;
    led        : out STD_LOGIC_VECTOR(5 downto 0)
  );
end entity;

architecture rtl of top is

  -- ADC data path signals
  signal adc_val_loc : STD_LOGIC_VECTOR(11 downto 0) := (others => '0');
  signal adc_val_latched : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
  signal adc_fifo_in : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
  signal adc_fifo_out : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

  -- Trigger and in_pulse signals
  signal in_pulse_loc : STD_LOGIC := '0';
  signal in_pulse_stretched : STD_LOGIC := '0';
  signal trg_out_loc : STD_LOGIC := '0';
  signal trg_out_stretched : STD_LOGIC := '0';

  -- Reset and communication signals
  signal SyncStableReset : STD_LOGIC := '0';
  signal uart_busy : STD_LOGIC := '0';
  signal send_packet_loc : STD_LOGIC := '0';

  -- FIFO signals for writing and reading
  signal full_loc : STD_LOGIC := '0';
  signal almost_full_loc : STD_LOGIC := '0';
  signal wr_ack_loc : STD_LOGIC := '0';
  signal wr_ack_loc_stretched : STD_LOGIC := '0';
  signal empty_loc : STD_LOGIC := '1';
  signal read_en_loc : STD_LOGIC := '0';
  signal data_ready : STD_LOGIC := '0';
  signal wr_en_loc : STD_LOGIC := '0';
  constant TickPeriodRead : unsigned(31 downto 0) := to_unsigned(2_000, 32); -- 20 us @ 100 MHz
  constant TickPeriodWrite : unsigned(31 downto 0) := to_unsigned(200_000, 32); -- 2 ms @ 100 MHz
  signal PeriodicPulseRead : STD_LOGIC := '0';
  signal PeriodicPulseWrite : STD_LOGIC := '0';
  signal delta_t_latch : unsigned(17 downto 0);
  signal counter_delta_t : unsigned(17 downto 0) := (others => '0');

  -- To monitor fast pulses through ILA
  attribute mark_debug : STRING;
  attribute mark_debug of in_pulse_loc : signal is "true";
  attribute mark_debug of trg_out_loc : signal is "true";

begin

  MuonGenerator : entity work.muonGenerator
    port map(
      Clock     => CLK,
      Reset     => SyncStableReset,
      Switch    => sw,
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

  StretchInWrAck : entity work.LongerPulse
    generic map(
      DURATION => 5_000_000 -- 50 ms @ 100 MHz
    )
    port map(
      Clock     => CLK,
      Reset     => SyncStableReset,
      Pulse     => wr_ack_loc,
      LongPulse => wr_ack_loc_stretched
    );

  -- LEDs
  -- Stretch from 600 ns to 50 ms if in slow mode
  led(0) <= in_pulse_stretched when sw = '0' else
            in_pulse_loc;
  -- Stretch from 200 ns to 50 ms if in slow mode
  led(1) <= trg_out_stretched when sw = '0' else
            trg_out_loc;
  led(2) <= uart_busy; -- UART busy
  led(3) <= wr_ack_loc_stretched; -- Write acknowledge stretched
  led(4) <= almost_full_loc; -- FIFO almost full
  led(5) <= SyncStableReset; -- Reset button

  -- Output trigger
  triggerOut <= trg_out_loc;

  -- Use 32-bits adc for FIFO with:
  --  - [11:0] adc_val_loc
  --  - [29:12] delta_t_latch (18-bit -> it gets slightly above 2 ms)
  adc_fifo_in <= "00" & STD_LOGIC_VECTOR(delta_t_latch) & adc_val_loc;

  FIFO : entity work.fifo_generator_0
    port map(
      -- Inputs
      clk   => CLK,
      srst  => SyncStableReset,
      din   => adc_fifo_in,
      wr_en => wr_en_loc,
      rd_en => read_en_loc,

      -- Outputs
      dout        => adc_fifo_out,
      full        => full_loc,
      almost_full => almost_full_loc,
      wr_ack      => wr_ack_loc,
      empty       => empty_loc
    );

  -- Write ADC packets on FIFO
  process (CLK)
  begin
    if rising_edge(CLK) then
      if SyncStableReset = '1' then
        wr_en_loc <= '0';
        counter_delta_t <= (others => '0');
      else
        -- Default behaviour: write nothing
        wr_en_loc <= '0';
        counter_delta_t <= counter_delta_t + 1;

        -- Write on FIFO when in_pulse is asserted, FIFO is not almost full
        -- and slow mode is activated
        if (almost_full_loc = '0' and sw = '0') then
          if (in_pulse_loc = '1' or PeriodicPulseWrite = '1') then
            delta_t_latch <= counter_delta_t;
            counter_delta_t <= (others => '0');
            wr_en_loc <= '1';
          end if;
        end if;

      end if;
    end if;
  end process;

  -- Generate periodic read every TickPeriodRead ticks
  PerRead : entity work.periodicTick
    port map(
      Clock      => CLK,
      Reset      => SyncStableReset,
      TickPeriod => TickPeriodRead,
      Tick       => PeriodicPulseRead
    );

  -- Generate periodic write every TickPeriodWrite ticks
  PerWrite : entity work.periodicTick
    port map(
      Clock      => CLK,
      Reset      => SyncStableReset,
      TickPeriod => TickPeriodWrite,
      Tick       => PeriodicPulseWrite
    );

  -- Read ADC data from FIFO and transfer it via UART
  process (CLK)
  begin
    if rising_edge(CLK) then

      if SyncStableReset = '1' then
        adc_val_latched <= (others => '0');
        send_packet_loc <= '0';
        read_en_loc <= '0';
        data_ready <= '0';
      else
        -- Default behaviour: do not transfer data
        send_packet_loc <= '0';

        -- If Switch is off (slow mode is activated) read and send signals
        if sw = '0' then

          -- Read FIFO periodically when FIFO is not empty and UART is not busy
          read_en_loc <= PeriodicPulseRead and (not empty_loc) and (not uart_busy);

          -- The standard read operation provides data on the cycle after it is requested
          data_ready <= read_en_loc;

          if data_ready = '1' then
            adc_val_latched <= adc_fifo_out;
            send_packet_loc <= '1';
          end if;

        end if;
      end if;
    end if;
  end process;

end architecture;
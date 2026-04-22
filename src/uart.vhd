-- To send data through UART (then USB to the PC), we decompose data as follows:
--
--   [11:0]  adc_val_loc    (12-bit ADC sample)
--   [29:12] next_adc_latch (18-bit time to next ADC sample)
--   [31:20] reserved       (0b00)

-- Packet format (sent on each trigger event):
-- 
--   Byte 0:  0xAA
--   Byte 1:  adc_val_loc[11:4]
--   Byte 2:  adc_val_loc[3:0] & "00" & delta_t_latch[17:16]
--   Byte 3:  delta_t_latch[15:8]
--   Byte 4:  delta_t_latch[7:0]
--   Byte 5:  0x55
--
-- - Each byte costs 10 bits (8 actual bits + 2 framing bits), meaning that in total,
--   each packet costs 60 bits
-- - The baud rate is 115200/s, meaning that the time between two bits is ~ 8.68 us,
--   meaning that each packet employs 60 * 8.68 u ~ 520 us to being transmitted
-- - We have 60 samples per event (a pulse lasts 600 ns -> @ 100 MHz), so the total transmission
--   time will be 520 us * 60 samples = 31 ms (within budget)

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity uart is
  generic (
    CLK_FREQ  : NATURAL := 100_000_000; -- 100 MHz
    BAUD_RATE : NATURAL := 115_200      -- Standard boud rate
  );
  port (
    -- Inputs 
    Clock       : in STD_LOGIC;
    Reset       : in STD_LOGIC;
    adc_data    : in STD_LOGIC_VECTOR(31 downto 0); -- Data to send
    send_packet : in STD_LOGIC;                     -- High for 1 clock cycle to trigger transmission

    -- Outputs
    uart_pin : out STD_LOGIC;
    busy     : out STD_LOGIC -- High while transmitting (do not pulse send_packet while busy)
  );
end entity;

architecture Rtl of uart is

  -- Clock ticks between two bits (duration of the pulse of each transmitted bit)
  constant CLKS_PER_BIT : NATURAL := CLK_FREQ / BAUD_RATE; -- ~ 868 @ 100 MHz

  -- Packet of 6 bytes
  type packet_t is array (0 to 5) of STD_LOGIC_VECTOR(7 downto 0);
  signal packet : packet_t;

  -- State machine used for transmission
  type tx_state_t is (IDLE, LOAD, START_BIT, DATA_BITS, STOP_BIT, NEXT_BYTE);
  signal tx_state : tx_state_t := IDLE;

  signal baud_cnt : NATURAL range 0 to CLKS_PER_BIT := 0;
  signal bit_idx : NATURAL range 0 to 7 := 0;
  signal byte_idx : NATURAL range 0 to 5 := 0;

  -- Using the MARK/SPACE convention: 1 = MARK = no transmission
  signal tx_reg : STD_LOGIC := '1';

  -- Shift register used to serialize data from parallel 12-bit adc_data
  signal shift_reg : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');

begin

  process (Clock)
  begin
    if rising_edge(Clock) then
      if Reset = '1' then
        tx_state <= IDLE;
        tx_reg <= '1';
        baud_cnt <= 0;
        bit_idx <= 0;
        byte_idx <= 0;

      else

        case tx_state is
          when IDLE =>
            tx_reg <= '1';
            if send_packet = '1' then
              packet(0) <= x"AA"; -- SOF
              packet(1) <= adc_data(11 downto 4);
              packet(2) <= adc_data(3 downto 0) & "00" & adc_data(29 downto 28);
              packet(3) <= adc_data(27 downto 20);
              packet(4) <= adc_data(19 downto 12);
              packet(5) <= x"55"; -- EOF
              byte_idx <= 0;
              tx_state <= LOAD;
            end if;

          when LOAD =>
            shift_reg <= packet(byte_idx);
            baud_cnt <= 0;
            bit_idx <= 0;
            tx_state <= START_BIT;

          when START_BIT =>
            tx_reg <= '0';
            if baud_cnt = CLKS_PER_BIT - 1 then
              baud_cnt <= 0;
              tx_state <= DATA_BITS;
            else
              baud_cnt <= baud_cnt + 1;
            end if;

          when DATA_BITS =>
            tx_reg <= shift_reg(bit_idx);

            if baud_cnt = CLKS_PER_BIT - 1 then
              baud_cnt <= 0;
              if bit_idx = 7 then
                tx_state <= STOP_BIT;
              else
                bit_idx <= bit_idx + 1;
              end if;
            else
              baud_cnt <= baud_cnt + 1;
            end if;

          when STOP_BIT =>
            tx_reg <= '1';
            if baud_cnt = CLKS_PER_BIT - 1 then
              baud_cnt <= 0;
              tx_state <= NEXT_BYTE;
            else
              baud_cnt <= baud_cnt + 1;
            end if;

          when NEXT_BYTE =>
            if byte_idx = 5 then
              tx_state <= IDLE;
            else
              byte_idx <= byte_idx + 1;
              tx_state <= LOAD;
            end if;

          when others =>
            tx_state <= IDLE;
        end case;

      end if;
    end if;
  end process;

  uart_pin <= tx_reg;
  busy <= '0' when tx_state = IDLE else
          '1';

end architecture;
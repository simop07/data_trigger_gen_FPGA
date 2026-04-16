entity top is
  port (
    clk100    : in  STD_LOGIC;
    btnC      : in  STD_LOGIC;
    led       : out STD_LOGIC_VECTOR(11 downto 0);
    led_pulse : out STD_LOGIC
  );
end entity;

architecture rtl of top is

begin

  UUT : entity work.muonGenerator
    port map(
      Clock     => clk100,
      Reset     => btnC,
      Adc_value => led,
      In_pulse  => led_pulse
    );

end architecture;
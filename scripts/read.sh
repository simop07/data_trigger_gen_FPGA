#!/bin/bash

DEV="/dev/ttyUSB4" # Find path of current serial port used by FPGA
BAUD=115200        # Communication speed of USB - uart serial port

# stty -F $DEV $BAUD: configure serial port
# cs8: 8-bit characters
# -cstopb: 1 stop bit
# -parenb: no parity bit
# -ixon -ixoff: disables software flow control
# raw: sisables all special processing of input/output (treats data as raw bytes)
# -echo: Prevents the terminal from "echoing" characters back
stty -F $DEV $BAUD cs8 -cstopb -parenb -ixon -ixoff raw -echo

echo "Listening on $DEV at $BAUD baud rate..."

# Using python to read serial port communication
python3 - <<'EOF' # dash needed to treat std input as source file

# Import system-specific params
import sys

# Redefines the device path inside the Python environment
dev = "/dev/ttyUSB4"

# Defining Start / End of Files
SOF = 0xAA
EOF_MARK = 0x55

def main():

    # Opening the serial port as a binary file .rb. buffering=0 ensures data is read
    immediately as it arrives rather than waiting for a buffer to fill.
    with open(dev, "rb", buffering=0) as f:

        # Creating mutable array of bytes
        buf = bytearray()

        # Event counter
        pack_counter = 0

        while True:
            b = f.read(1) # read 1 byte at a time

            # If no reading is possible, jumpt to next byte
            if not b:
                continue

            # Append each byte to the array of bytes
            buf.append(b[0])

            # Keep length of array fixed
            if len(buf) > 4:
                buf.pop(0)

            # Search for valid data frame: AA xx xx 55
            if len(buf) == 4:
                if buf[0] == SOF and buf[3] == EOF_MARK:
                    b1 = buf[1]
                    b2 = buf[2]

                    adc = ((b1 & 0x0F) << 8) | b2
                    print(f"  Event {pack_counter}: {adc} ADC", flush=True)

                    # Clear buffer waiting for next event and increase counter
                    buf.clear()
                    pack_counter += 1

if __name__ == "__main__":
    main()
EOF

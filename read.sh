#!/bin/bash

DEV="/dev/ttyUSB4"
BAUD=115200

# Configura la seriale
stty -F $DEV $BAUD cs8 -cstopb -parenb -ixon -ixoff raw -echo

echo "Listening on $DEV at $BAUD baud..."

# Utilizzando python per eseguire tutto il codice in basso
python3 - <<'EOF'
import sys

dev = "/dev/ttyUSB4"

SOF = 0xAA
EOF_MARK = 0x55

def main():
    with open(dev, "rb", buffering=0) as f:
        buf = bytearray()

        while True:
            b = f.read(1)
            if not b:
                continue

            buf.append(b[0])

            # Mantieni solo ultimi 4 byte
            if len(buf) > 4:
                buf.pop(0)

            # Cerca frame valido: AA xx xx 55
            if len(buf) == 4:
                if buf[0] == SOF and buf[3] == EOF_MARK:
                    b1 = buf[1]
                    b2 = buf[2]

                    adc = ((b1 & 0x0F) << 8) | b2
                    print(f"SOF - ADC AT TRIGGER:{adc} - EOF", flush=True)

                    buf.clear()

if __name__ == "__main__":
    main()
EOF

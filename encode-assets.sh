#!sh
for x in font stage stuff
do
    ./assets/encode-png.py ./assets/$x.png ./src/$x.bin
done

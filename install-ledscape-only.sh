#!/usr/bin/env bash

if [[ ! -f ledscape.c ]]; then

	echo "Could not find ledscape.c. Must run from inside the LEDscape directory."
	exit -1
fi

echo "Making ledscape..."
make

echo Copying config file to /etc

if [[ -f "//etc/ledscape-config.json" ]]; then

	echo Leaving existing /etc/ledscape-config.json intact. 
	
else

	cp configs/ws281x-config.json /etc/ledscape-config.json
	
fi


echo "Done. Please enter reboot to reboot the machine and enable changes."
		

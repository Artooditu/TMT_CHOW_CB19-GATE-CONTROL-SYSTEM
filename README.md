# First and foremost, shoutout to RPJacobs 
Who did the majority from which uppon I made modifications to make the codes more lean and readable, and focusing only on the solution to create a local control of the CB19 board and rip out TMT-Chow from the equasion. Original source https://github.com/RPJacobs

# CB19-GATE-CONTROL-SYSTEM

Removing my TMT CHOW remote gate control, because it connects to an external server (security risk). Intergrate RS323 via ESP32 with MQTT > Homeassistant

Step 0: History of the project:
RPJacobs did the investigation and found out that TMT-Chow module and Mainboard uses unencrytpted unauthenticated text based commands on a serial. My rewrite will only focus on the remote operation and status read.

Step 1:
Open the TMT module

<table>
<tr><td>
<img src="https://user-images.githubusercontent.com/14312145/198314056-47c4af81-4ce5-4bf7-b1a2-107f2e96255c.png" width=40% height=40%>

</td></tr>
<tr><td>
<img src="https://github.com/Artooditu/TMT_CHOW_CB19-GATE-CONTROL-SYSTEM/blob/main/img/tmt1.jpg?raw=true" width=20% height=20%>
</td><td>
<img src="https://github.com/Artooditu/TMT_CHOW_CB19-GATE-CONTROL-SYSTEM/blob/main/img/tmt2.jpg?raw=true" width=20% height=20%>
</td></tr>
</table>

Here we can find the PIN OUT

RST
V5
RX
TX
GND

Instead of soldering I used krimped NSR style connectors for ESP connection, my goal is to save the original cable and device as a backup concept and store it in the drawer and never ever use it again :D

After connecting the 5V RX TX GND you need to flash the ESP with Tasmota (https://tasmota.github.io/)
You need to configure MQTT in Tasmota, **do not configure Serial, it is configured in Berry**

In gatev2.be you may need to adapt the MQTT topic, it flies under the name:  self.topic_base = "**tasmota_gate_new**" (or you can just keep it and call it a day)

Next step is to upload the gatev2.be to Berry (https://tasmota.github.io/docs/Berry/)
Also you need to create an autoexec.be which will be run on each startup, and makes sure your gatev2.be is called.

Tasmota done, now Home Assistant:

Add lines [configuration](https://github.com/Artooditu/TMT_CHOW_CB19-GATE-CONTROL-SYSTEM/blob/main/configuration.yaml) to configuration.yaml, and reload configuration in HA.

Final step is a nice dashboard from [lovelace.yaml](https://github.com/Artooditu/TMT_CHOW_CB19-GATE-CONTROL-SYSTEM/blob/main/lovelace.yaml):
<img width="640" height="674" alt="image" src="https://github.com/user-attachments/assets/edbbbc07-348b-4baa-96c3-cadd949f1707" />



I also left the control box documentation attached if needed, but did not expose the settings as it should never be changed once the gate is installed. Also this can be done at the gate:
[CB19U-34100-125-10-C_CB19_manual_std_Wi-Fi_au.pdf](CB19U-34100-125-10-C_CB19_manual_std_Wi-Fi_au.pdf) 












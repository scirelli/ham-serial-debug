# CCK-HAM-Debugging-Scripts
Small scripts to help debug CCK HAM hardware.

# hamUtils.sh

## Running
At the time of this writing the default behavior when running this script is to cycle the HAM's pawl from, back to front, and back. It does this by sending the `{"event":"start-test-motor-cycle-reset"}` event. Which is in the latest [state table](https://github.cloud.capitalone.com/ATMoF/HamServer/blob/master/src/server_config.json#L1019-L1027).
```
$./hamUtils.sh
```
If you know which port the HAM is connected on you can put that in a file called `.tty` in the same folder the script is running from. This script will attempt to open a connection on that port first.
<br/>
<br/>
If a connection can not be made on that port, the script will attempt to find the port the HAM is connected on, or throw an error. If it finds the correct port it will create the `.tty` file.
<br/>
<br/>
This script can connect to the ham simulator, and it will attempt to connect to it as well.
<br/>
<br/>
---

## Sourcing
If you require more control than just cycling the motor you can `source` the script.
<br/>
<br/>
When you source the script, it will generate functions for sending commands to the HAM. To generate a full set of functions you will need to place a `stateTable.json` file in the same location as the script. It is the same JSON sent from the HAMServer's intro. If the file is not there, it will be created on first connection with the state table sent from the HAMServer. An example state table is stored in `example_stateTable.json`.
```
cp example_stateTable.json stateTable.json
```
<br/>
<br/>
Given that sourcing the `hamUtils.sh` script will add a whole bunch of functions to your current shell, you can instead run `activate` to create a subshell. Type `exit` to break out of it. This should be the preferred way to source the script. This will allow you to exit the subshell and create a new one if anything breaks or locks up.
<br/>
<br/>
Assuming the state table file is there:
- **ham.cmdShutdown**: Shutdown the HAM.
- **ham.cmdSystem_reset**: Reset the HAM. This will require you to close the connection and reconnect.
- **ham.eventAccess_door_open**: Send the `access-open-door` event.
- **ham.eventClear_displays**: Send the `clear-displays` event.
- **ham.eventDemo_mode**: Send the `demo-mode` event.
- **ham.eventDemo_motor_cycle_1**: Send the `demo-motor-cycle_1` event.
- **ham.eventDemo_motor_cycle_2**: Send the `demo-motor-cycle_2` event.
- **ham.eventDemo_rainbow**: Send the `demo-rainbow` event.
- **ham.eventEject**: Send the `eject` event.
- **ham.eventMotor_backward**: Send the `motor-backward` event.
- **ham.eventMotor_brake**: Send the `motor-brake` event.
- **ham.eventMotor_disable**: Send the `motor-disable` event.
- **ham.eventMotor_enable**: Send the `motor-enable` event.
- **ham.eventMotor_enable_output_register_change**: Send the `motor-enable-output-register-change` event.
- **ham.eventMotor_forward**: Send the `motor-forward` event.
- **ham.eventMotor_overcurrent_true**: Send the `motor-overcurrent` event.
- **ham.eventMotor_stop**: Send the `motor-stop` event.
- **ham.eventReset**: Send the `reset` event.
- **ham.eventSet_pixels**: Send the `set-pixels` event. You will need to provide the pixel array as the first param. Eg. `ham.eventSet_pixels '[[[1,255,0,0]]]'` which will make the pixel at index 1 red.
- **ham.eventSet_segment_color**: Send the `set-segment-color` event. Eg. `ham.eventSet_segment_color '[1,0,0,0]'`
- **ham.eventSet_sequence_color**: Send the `set-sequence-color` event. Eg. `ham.eventSet_sequence_color '[1, [[0,0,0,0]]]'`
- **ham.eventShutdown**: Send the `shutdown` event.
- **ham.eventStart_calibration**: Send the `start-calibration` event.
- **ham.eventStart_test_fastpull**: Send the `start-test-fastpull` event.
- **ham.eventStart_test_la_1**: Send the `start-test-la-1` event.
- **ham.eventStart_test_la_2**: Send the `start-test-la-2` event.
- **ham.eventStart_test_motor_cycle**: Send the `start-tset-motor-cycle` event.
- **ham.eventStart_test_motor_cycle_reset**: Send the `start-test-motor-cycle-reset` event. This is the event sent if you execute this script.
- **ham.eventSystem_reset**: Send the `system-reset` event.
- **ham.eventTest_com_mode**: Send the `test-com-mode` event.
- **ham.getDiskspace**: Get the available disk space.
- **ham.getIntro**: Get the `intro` message.
- **ham.getLogs**: Get logs from the HAM.
- **ham.getRamstats**: Get the RAM stats from the HAM.
- **ham.getState**: Get the HAM's state.
- **ham.getSystem_logs**: Get the HAM's system logs.
- **ham.getSystem_logs_ham**: Get the HAM's system logs filtered by the HAM service.
- **ham.send**: Send generic JSON to the HAM. If there is not an open connection to a HAM, it will attempt to open one. This is the base function that sends all messages to the HAM. Eg. `ham.send '{"event":"motor-limit-rear-pressed"}'`
- **ham.sendConfig**: Send the `stateTable.json` file located in the same location as this script. This is useful if you want to update the state table on the HAM.
- **ham.setState**: Force the HAM into a provided state. Eg. `ham.setState 'Idle'`


## Troubleshooting
You can enable debug output with
```
export HAM_DEBUG=0
```


## Requirements
- Bash >= 4
  - If you are on a Mac you can `brew install bash`.  If you want to source the script directly you will then have to go into your Terminals settings -> General -> Shells open with -> Command (complete path)
  - Enter the location where brew install bash. Eg. `/opt/homebrew/bin/bash`
  - Otherwise use the `activate` script.
- jq

#!/bin/bash
#
# Script to check if connected to intranet, if connected, connect shared and user drive, based on hostname.

# Set internet to default to not connected.
internet=1

# Function driveconnect, written in AppleScript, to connect User drive and shared drive, and make sure show network drives on desktop is enabled.
function atldriveconnect {
    osascript <<EOF
        mount volume "smb://$USER@atlfs01/users/$USER"
        mount volume "smb://$USER@atlfs01/shared"
        tell application "System Events"
            tell process "Finder"
                set frontmost to true
                click menu item "Preferences…" of menu 1 of menu bar item "Finder" of menu bar 1
                click button "General" of tool bar 1 of window "Finder Preferences"
                if value of checkbox "Connected servers" of window "Finder Preferences" is 0 then
                    click checkbox "Connected servers" of window "Finder Preferences"
                end if
            end tell
        end tell
        tell application "Finder" to close window "Finder Preferences"
EOF
}

# Ping intranet server to confirm connection, if not open Anyconnect.
if ping -c 1 -W 1 10.10.10.1 > /dev/null 2>&1; then
    internet=0
else
    osascript -e 'tell application "System Events" to display dialog "Please connect VPN or Ethernet and run this program again."'
fi

# Call the appropriate function based on hostname.
case $(networksetup -getcomputername) in
    *"ATL"*) atldriveconnect;;
    *"Atl"*) atldriveconnect;;
    *"atl"*) atldriveconnect;;
    *)       internet=1
             osascript -e 'tell application "System Events" to display dialog "Your Mac is not correctly named for our network."';;
esac

exit 0

#!/bin/bash
#
# script to check if connected to intranet, if connected, connect shared and user drive, based on hostname


# set internet to default to not connected
internet=1
x=0

# create the function driveconnect, written in AppleScript, to connect User drive and shared drive, and make sure show network drives on desktop is enable due to changing the finder setting for network drive, Terminal, or the program created from this script must be placed in the Accessibility settings of MacOS

function atldriveconnect
	{
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
			tell application "Finder"
			close window "Finder Preferences"
			end tell


EOF

        }

function cgdriveconnect
        {
osascript <<EOF
                        mount volume "smb://$USER@corfs02/users/$USER"
                        mount volume "smb://$USER@corfs02/shared"
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
                        tell application "Finder"
                        close window "Finder Preferences"
                        end tell


EOF

        }

function nydriveconnect
        {
osascript <<EOF
                        mount volume "smb://$USER@nycfs01/users/$USER"
                        mount volume "smb://$USER@nycfs01/shared"
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
                        tell application "Finder"
                        close window "Finder Preferences"
                        end tell


EOF

        }


function chidriveconnect
        {
osascript <<EOF
                        mount volume "smb://$USER@chifs01/users/$USER"
                        mount volume "smb://$USER@chifs01/shared"
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
                        tell application "Finder"
                        close window "Finder Preferences"
                        end tell


EOF

        }

function daldriveconnect
        {
osascript <<EOF
                        mount volume "smb://$USER@dalfs01/users/$USER"
                        mount volume "smb://$USER@dalfs01/shared"
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
                        tell application "Finder"
                        close window "Finder Preferences"
                        end tell


EOF

        }

function gledriveconnect
        {
osascript <<EOF
                        mount volume "smb://$USER@glefs01/users/$USER"
                        mount volume "smb://$USER@glefs01/shared"
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
                        tell application "Finder"
                        close window "Finder Preferences"
                        end tell


EOF

        }

function mcldriveconnect
        {
osascript <<EOF
                        mount volume "smb://$USER@mclfs01/users/$USER"
                        mount volume "smb://$USER@mclfs01/shared"
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
                        tell application "Finder"
                        close window "Finder Preferences"
                        end tell


EOF

        }

function mildriveconnect
        {
osascript <<EOF
                        mount volume "smb://$USER@milfs02/users/$USER"
                        mount volume "smb://$USER@milfs02/shared"
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
                        tell application "Finder"
                        close window "Finder Preferences"
                        end tell


EOF

        }

function loudriveconnect
        {
osascript <<EOF
                        mount volume "smb://$USER@loufs01/users/$USER"
                        mount volume "smb://$USER@loufs01/shared"
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
                        tell application "Finder"
                        close window "Finder Preferences"
                        end tell


EOF

        }


function sfdriveconnect
        {
osascript <<EOF
                        mount volume "smb://$USER@sfofs02/users/$USER"
                        mount volume "smb://$USER@sfofs02/shared"
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
                        tell application "Finder"
                        close window "Finder Preferences"
                        end tell


EOF

        }

function waldriveconnect
        {
osascript <<EOF
                        mount volume "smb://$USER@walfs01/users/$USER"
                        mount volume "smb://$USER@walfs01/shared"
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
                        tell application "Finder"
                        close window "Finder Preferences"
                        end tell


EOF

        }




# ping 10.10.10.1 to confirm intranet connected, if not open Anyconnect

ping -c 1 10.10.10.1 > /tmp/ping.$

	if [[ $? -ne 0 ]]; then
osascript -e 'tell application "System Events" to display dialog "Please connect VPN or Ethernet and run this program again."'
	
# if intranet is connected, then call the function, based on hostname

	elif	
internet=0	
	[[ ${internet} -eq 0 ]]; then

# this checks for the hostname and runs the correct function based on that
pc=$(networksetup -getcomputername)
		if 	[[ $pc == *"ATL"* ]]; then
				atldriveconnect
		elif	[[ $pc == *"Atl"* ]]; then
				atldriveconnect
		elif	[[ $pc == *"atl"* ]]; then
				atldriveconnect
		elif 	[[ $pc == *"COR"* ]]; then
                                cgdriveconnect
                elif    [[ $pc == *"Cor"* ]]; then
                                cgdriveconnect
                elif    [[ $pc == *"cor"* ]]; then
                                cgdriveconnect
		elif    [[ $pc == *"NY"* ]]; then
                                nydriveconnect
                elif    [[ $pc == *"Ny"* ]]; then
                                nydriveconnect
                elif    [[ $pc == *"ny"* ]]; then
                                nydriveconnect
		elif    [[ $pc == *"CH"* ]]; then
                                chidriveconnect
                elif    [[ $pc == *"Ch"* ]]; then
                                chidriveconnect
                elif    [[ $pc == *"ch"* ]]; then
                                chidriveconnect
		elif    [[ $pc == *"DA"* ]]; then
                                daldriveconnect
                elif    [[ $pc == *"Da"* ]]; then
                                daldriveconnect
                elif    [[ $pc == *"da"* ]]; then
                                daldriveconnect
		elif    [[ $pc == *"GL"* ]]; then
                                gledriveconnect
                elif    [[ $pc == *"Gl"* ]]; then
                                gledriveconnect
                elif    [[ $pc == *"gl"* ]]; then
                                gledriveconnect
		elif    [[ $pc == *"MC"* ]]; then
                                mcldriveconnect
                elif    [[ $pc == *"Mc"* ]]; then
                                mcldriveconnect
                elif    [[ $pc == *"mc"* ]]; then
                                mcldriveconnect		
		elif    [[ $pc == *"MI"* ]]; then
                                mildriveconnect
                elif    [[ $pc == *"Mi"* ]]; then
                                mildriveconnect
                elif    [[ $pc == *"mi"* ]]; then
                                mildriveconnect
		elif    [[ $pc == *"LO"* ]]; then
                                loudriveconnect
                elif    [[ $pc == *"Lo"* ]]; then
                                loudriveconnect
                elif    [[ $pc == *"lo"* ]]; then
                                loudriveconnect
		elif    [[ $pc == *"SF"* ]]; then
                                sfdriveconnect
                elif    [[ $pc == *"Sf"* ]]; then
                                sfdriveconnect
                elif    [[ $pc == *"sf"* ]]; then
                                sfdriveconnect
		elif    [[ $pc == *"WA"* ]]; then
                                waldriveconnect
                elif    [[ $pc == *"Wa"* ]]; then
                                waldriveconnect
                elif    [[ $pc == *"wa"* ]]; then
                                waldriveconnect	
		else

osascript -e 'tell application "System Events" to display dialog "Your Mac is not correctly named for our network."'

			fi
internet=1
	fi 

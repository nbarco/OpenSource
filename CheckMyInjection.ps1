﻿# ===========================================================================================
#
# Function Name 'Get_Folder_Path' - Prompts for folder path to store files
#
# ===========================================================================================
Function Get_Folder_Path
{
    $objShell = ""
    $Script:NamedFolder = ""
    $Script:Log_File = ""
    $Script:Folder_Path = ""
    $objShell = new-object -com shell.application
    $Script:NamedFolder = $objShell.BrowseForFolder(0,"Please select where to save the log files to:",0,"$env:USERPROFILE\Desktop")
    if ($Script:NamedFolder -eq $null) {
        Write-Host "YOU MUST SELECT A FOLDER TO STORE THE LOGS!" -Fore Red
        . Get_Folder_Path }
    Else {
        $Script:Folder_Path = $Script:NamedFolder.self.path
        write-host "Pick_Up_Sticks will write all files to: $Script:Folder_Path"
        New-Item -type file -force "$Script:Folder_Path\Log_File_$Script:curDate.txt" | Out-Null
        $Script:Log_File = "$Script:Folder_Path\Log_File_$Script:curDate.txt"
        # ====================================
        # Starting the Log_File
        # ====================================
        echo "Script started - "$Script:curDate | out-file $Script:Log_File -Append
        echo "--------------------------------------------------------------" | out-file $Script:Log_File -Append }
}

# ========================================================================
# Function Name 'ListComputers' - Takes entered domain and lists all computers
# ========================================================================
Function ListComputers
{
    $DN = ""
    $Response = ""
    $DNSName = ""
    $DNSArray = ""
    $objSearcher = ""
    $colProplist = ""
    $objComputer = ""
    $objResults = ""
    $colResults = ""
    $Computer = ""
    $comp = ""
    New-Item -type file -force "$Script:Folder_Path\Computer_List_$Script:curDate.txt" | Out-Null
    $Script:Compute = "$Script:Folder_Path\Computer_List_$Script:curDate.txt"
    $strCategory = "(ObjectCategory=Computer)"
    
    Write-Host "Would you like to automatically pull from your domain or provide your own domain?"
    Write-Host "Auto pull uses the current domain you are on, if you need to select a different domain use manual."
    $response = Read-Host = "[1] Auto Pull, [2] Manual Selection"
    
    If($Response -eq "1") {
        $DNSName = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
        If($DNSName -ne $Null) {
            $DNSArray = $DNSName.Split(".") 
            for ($x = 0; $x -lt $DNSArray.Length ; $x++) {  
                if ($x -eq ($DNSArray.Length - 1)){$Separator = ""}else{$Separator =","} 
                [string]$DN += "DC=" + $DNSArray[$x] + $Separator  } }
        $Script:Domain = $DN
        echo "Pulled computers from: "$Script:Domain | Out-File $Script:Log_File -Append
        $objSearcher = New-Object System.DirectoryServices.DirectorySearcher("LDAP://$Script:Domain")
        $objSearcher.Filter = $strCategory
        $objSearcher.PageSize = 100000
        $objSearcher.SearchScope = "SubTree"
        $colProplist = "name"
        foreach ($i in $colPropList) {
            $objSearcher.propertiesToLoad.Add($i) }
        $colResults = $objSearcher.FindAll()
        foreach ($objResult in $colResults) {
            $objComputer = $objResult.Properties
            $comp = $objComputer.name
            echo $comp | Out-File $Script:Compute -Append }
        $Script:Computers = (Get-Content $Script:Compute) | Sort-Object
    }
	elseif($Response -eq "2")
    {
        <#
            This is where an admin can build the tool to utilize their OU structure. If you feel that you do not 
            want to utilize this method you can replace the section labeled # EDITABLE SECTION START and END with the below:

            $Script:Domain = Read-Host "Enter your Domain here: OU=systems,DC=ds,DC=company,DC=com"
        #>
        
        # EDITABLE SECTION START
        $Script:Domain = Read-Host "Enter your Domain here: OU=systems,DC=ds,DC=company,DC=com"
        # EDITABLE SECTION END

        echo "Pulling computers from: "$Script:Domain | Out-File $Script:Log_File -Append
        $objOU = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$Script:Domain")
        $objSearcher = New-Object System.DirectoryServices.DirectorySearcher
        $objSearcher.SearchRoot = $objOU
        $objSearcher.Filter = $strCategory
        $objSearcher.PageSize = 100000
        $objSearcher.SearchScope = "SubTree"
        $colProplist = "name"
        foreach ($i in $colPropList) { $objSearcher.propertiesToLoad.Add($i) }
        $colResults = $objSearcher.FindAll()
        foreach ($objResult in $colResults) {
            $objComputer = $objResult.Properties
            $comp = $objComputer.name
            echo $comp | Out-File $Script:Compute -Append }
        $Script:Computers = (Get-Content $Script:Compute) | Sort-Object
    }
    else {
        Write-Host "You did not supply a correct response, Please select a response." -foregroundColor Red
        . ListComputers }
}

# ========================================================================
# Function Name 'ListTextFile' - Enumerates Computer Names in a text file
# Create a text file and enter the names of each computer, IP, or subnet. 
# One computer name, IP, or subnet per line. Supply the path to the text 
# file when prompted.
# ========================================================================
Function ListTextFile 
{
	$file_Dialog = ""
    $file_Name = ""
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    $file_Dialog = New-Object System.Windows.Forms.OpenFileDialog
    $file_Dialog.InitialDirectory = "$env:USERPROFILE\Desktop"
    $File_Dialog.Filter = "All files (*.*)| *.*"
    $file_Dialog.MultiSelect = $False
    $File_Dialog.ShowHelp = $True
    $file_Dialog.ShowDialog() | Out-Null
    $file_Name = $file_Dialog.Filename
    $Comps = Get-Content $file_Name
    If ($Comps -eq $Null) {
        Write-Host "Your file was empty. You must select a file with at least one computer in it." -Fore Red
        . ListTextFile }
    Else
    {
        $Script:Computers = @()
        ForEach ($Comp in $Comps)
        {
            If ($Comp -match "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}")
            {
                $Temp = $Comp.Split("/")
                $IP = $Temp[0]
                $Mask = $Temp[1]
                . Get-Subnet-Range $IP $Mask
                $Script:Computers += $Script:IPList
            }
            Else
            {
                $Script:Computers += $Comp
            }
        }

        echo " " | Out-File $Script:Log_File -Append
        echo "Computer list located: $file_Name" | Out-File $Script:Log_File -Append 
        
    }
}
Function SingleEntry 
{
    $Comp = Read-Host "Enter Computer Name or IP (1.1.1.1) or IP Subnet (1.1.1.1/24)"
    If ($Comp -eq $Null) { . SingleEntry }
    ElseIf ($Comp -match "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}")
    {
        $Temp = $Comp.Split("/")
        $IP = $Temp[0]
        $Mask = $Temp[1]
        . Get-Subnet-Range $IP $Mask
        $Script:Computers = $Script:IPList
    }
    Else
    { $Script:Computers = $Comp} 
}
# ========================================================================
# Get-Subnet-Range Found this online at 
# http://www.indented.co.uk/index.php/2010/01/23/powershell-subnet-math/
# This takes the inputs from the admin and if the entry is a subnet this 
# will break the subnet out and build a list to be used by the tool.
# ========================================================================
Function Get-Subnet-Range {
    #.Synopsis
    # Lists all IPs in a subnet.
    #.Example
    # Get-Subnet-Range -IP 192.168.1.0 -Netmask /24
    #.Example
    # Get-Subnet-Range -IP 192.168.1.128 -Netmask 255.255.255.128        
    Param(
        [string]
        $IP,
        [string]
        $netmask
    )  
    Begin {
        $IPs = New-Object System.Collections.ArrayList

        Function Get-NetworkAddress {
            #.Synopsis
            # Get the network address of a given lan segment
            #.Example
            # Get-NetworkAddress -IP 192.168.1.36 -mask 255.255.255.0
            Param (
                [string]
                $IP,
               
                [string]
                $Mask,
               
                [switch]
                $Binary
            )
            Begin {
                $NetAdd = $null
            }
            Process {
                $BinaryIP = ConvertTo-BinaryIP $IP
                $BinaryMask = ConvertTo-BinaryIP $Mask
                0..34 | %{
                    $IPBit = $BinaryIP.Substring($_,1)
                    $MaskBit = $BinaryMask.Substring($_,1)
                    IF ($IPBit -eq '1' -and $MaskBit -eq '1') {
                        $NetAdd = $NetAdd + "1"
                    } elseif ($IPBit -eq ".") {
                        $NetAdd = $NetAdd +'.'
                    } else {
                        $NetAdd = $NetAdd + "0"
                    }
                }
                if ($Binary) {
                    return $NetAdd
                } else {
                    return ConvertFrom-BinaryIP $NetAdd
                }
            }
        }
       
        Function ConvertTo-BinaryIP {
            #.Synopsis
            # Convert an IP address to binary
            #.Example
            # ConvertTo-BinaryIP -IP 192.168.1.1
            Param (
                [string]
                $IP
            )
            Process {
                $out = @()
                Foreach ($octet in $IP.split('.')) {
                    $strout = $null
                    0..7|% {
                        IF (($octet - [math]::pow(2,(7-$_)))-ge 0) {
                            $octet = $octet - [math]::pow(2,(7-$_))
                            [string]$strout = $strout + "1"
                        } else {
                            [string]$strout = $strout + "0"
                        }  
                    }
                    $out += $strout
                }
                return [string]::join('.',$out)
            }
        }
 
 
        Function ConvertFrom-BinaryIP {
            #.Synopsis
            # Convert from Binary to an IP address
            #.Example
            # Convertfrom-BinaryIP -IP 11000000.10101000.00000001.00000001
            Param (
                [string]
                $IP
            )
            Process {
                $out = @()
                Foreach ($octet in $IP.split('.')) {
                    $strout = 0
                    0..7|% {
                        $bit = $octet.Substring(($_),1)
                        IF ($bit -eq 1) {
                            $strout = $strout + [math]::pow(2,(7-$_))
                        }
                    }
                    $out += $strout
                }
                return [string]::join('.',$out)
            }
        }

        Function ConvertTo-MaskLength {
            #.Synopsis
            # Convert from a netmask to the masklength
            #.Example
            # ConvertTo-MaskLength -Mask 255.255.255.0
            Param (
                [string]
                $mask
            )
            Process {
                $out = 0
                Foreach ($octet in $Mask.split('.')) {
                    $strout = 0
                    0..7|% {
                        IF (($octet - [math]::pow(2,(7-$_)))-ge 0) {
                            $octet = $octet - [math]::pow(2,(7-$_))
                            $out++
                        }
                    }
                }
                return $out
            }
        }
 
        Function ConvertFrom-MaskLength {
            #.Synopsis
            # Convert from masklength to a netmask
            #.Example
            # ConvertFrom-MaskLength -Mask /24
            #.Example
            # ConvertFrom-MaskLength -Mask 24
            Param (
                [int]
                $mask
            )
            Process {
                $out = @()
                [int]$wholeOctet = ($mask - ($mask % 8))/8
                if ($wholeOctet -gt 0) {
                    1..$($wholeOctet) |%{
                        $out += "255"
                    }
                }
                $subnet = ($mask - ($wholeOctet * 8))
                if ($subnet -gt 0) {
                    $octet = 0
                    0..($subnet - 1) | %{
                         $octet = $octet + [math]::pow(2,(7-$_))
                    }
                    $out += $octet
                }
                for ($i=$out.count;$i -lt 4; $I++) {
                    $out += 0
                }
                return [string]::join('.',$out)
            }
        }

        Function Get-IPRange {
            #.Synopsis
            # Given an Ip and subnet, return every IP in that lan segment
            #.Example
            # Get-IPRange -IP 192.168.1.36 -Mask 255.255.255.0
            #.Example
            # Get-IPRange -IP 192.168.5.55 -Mask /23
            Param (
                [string]
                $IP,
               
                [string]
                $netmask
            )
            Process {
                iF ($netMask.length -le 3) {
                    $masklength = $netmask.replace('/','')
                    $Subnet = ConvertFrom-MaskLength $masklength
                } else {
                    $Subnet = $netmask
                    $masklength = ConvertTo-MaskLength -Mask $netmask
                }
                $network = Get-NetworkAddress -IP $IP -Mask $Subnet
               
                [int]$FirstOctet,[int]$SecondOctet,[int]$ThirdOctet,[int]$FourthOctet = $network.split('.')
                $TotalIPs = ([math]::pow(2,(32-$masklength)) -2)
                $blocks = ($TotalIPs - ($TotalIPs % 256))/256
                if ($Blocks -gt 0) {
                    1..$blocks | %{
                        0..255 |%{
                            if ($FourthOctet -eq 255) {
                                If ($ThirdOctet -eq 255) {
                                    If ($SecondOctet -eq 255) {
                                        $FirstOctet++
                                        $secondOctet = 0
                                    } else {
                                        $SecondOctet++
                                        $ThirdOctet = 0
                                    }
                                } else {
                                    $FourthOctet = 0
                                    $ThirdOctet++
                                }  
                            } else {
                                $FourthOctet++
                            }
                            Write-Output ("{0}.{1}.{2}.{3}" -f `
                            $FirstOctet,$SecondOctet,$ThirdOctet,$FourthOctet)
                        }
                    }
                }
                $sBlock = $TotalIPs - ($blocks * 256)
                if ($sBlock -gt 0) {
                    1..$SBlock | %{
                        if ($FourthOctet -eq 255) {
                            If ($ThirdOctet -eq 255) {
                                If ($SecondOctet -eq 255) {
                                    $FirstOctet++
                                    $secondOctet = 0
                                } else {
                                    $SecondOctet++
                                    $ThirdOctet = 0
                                }
                            } else {
                                $FourthOctet = 0
                                $ThirdOctet++
                            }  
                        } else {
                            $FourthOctet++
                        }
                        Write-Output ("{0}.{1}.{2}.{3}" -f `
                        $FirstOctet,$SecondOctet,$ThirdOctet,$FourthOctet)
                    }
                }
            }
        }
    }
    Process {
        #get every ip in scope
        Get-IPRange $IP $netmask | %{
        [void]$IPs.Add($_)
        }
        $Script:IPList = $IPs
    }
}



Function RemoveHunt
{
    Param(
        [string]$Computer
    )
    echo "I am attempting to remove the folder from $Computer" | Out-File $Script:Log_File -Append
    If(Test-Path -Path \\$Computer\c$\folder)
    {
        echo "Folder Exists on $Computer" | Out-File $Script:Log_File -Append
        Remove-Item \\$Computer\C$\folder -Force -Recurse
        If(!(Test-Path -Path \\$Computer\c$\folder))
        {
            echo "SUCCESSFULLY Removed Folder from $Computer" | Out-File $Script:Log_File -Append
        }
        else
        {
            echo "@@@@@@@@@@@ FOLDER DIRECTORY STILL EXISTS. REMOVE MANUALLY ON $Computer" | Out-File $Script:Log_File -Append
            echo "^^^^^^^^^^^" | Out-File $Script:Log_File -Append
            echo "|||||||||||" | Out-File $Script:Log_File -Append
        }
    }
}
Function Compress
{
    Param(
        $Source,
        $Destination
    )
    echo "Attempting to compress $Source" | Out-File $Script:Log_File -Append
    Add-Type -assembly "system.io.compression.filesystem"
    [io.compression.zipfile]::CreateFromDirectory($Source, $destination)
}


# ========================================================================
# Function Name 'Check_Status' - Runs the required BAT file
# ========================================================================
Function Check_Status
{
    Param(
        $CompFile
    )
    $i = 0
    New-Item -type file -force "$Script:Folder_Path\ReviveComps_$Script:curDate.txt" | Out-Null
    $Script:ReviveComps = "$Script:Folder_Path\ReviveComps_$Script:curDate.txt"
    
    $Computers = $CompFile
    ForEach ($Computer in $Computers)
    {
        $i++
        $remaining = $Script:Computers.count - $i
        $total = $Script:Computers.count
        write-progress -id 1 -Activity "Searching through systems..." -Status "Searched $i systems out of $total... Currently on $Computer" -PercentComplete ($i / $Script:Computers.count * 100)

        $ping = ""
        echo "#######################################################" | Out-File $Script:Log_File -Append
        echo "###   Now Checking.... $Computer   ###" | Out-File $Script:Log_File -Append
        

        # ========================================================================
        # Pinging the machine. If pass check for admin share access
        # ========================================================================
        If (Test-Connection -CN $Computer -Count 1 -BufferSize 16 -Quiet) 
        {
            echo "************************************************" | Out-File $Script:Log_File -Append
            echo "$Computer - ping was successful." | Out-File $Script:Log_File -Append

            If (Test-Path \\$Computer\C$)
            {
                $OS = gwmi -Namespace root\cimv2 -Class Win32_OperatingSystem -Impersonation 3 -ComputerName $Computer
                
                If ($OS -eq $Null)
                {
                    . No_WMI $Computer
                    $Script:Total_Bad_Computers = $Script:Total_Bad_Computers + 1
                }
                else
                {
                    If(!(Get-Process -ComputerName $Computer -Name HairyShaman*) -and !(Get-Process -ComputerName $Computer -Name ZombieHunter*))
                    {
                        $FinalResting = "\\chief-msi\c$"
                        $HSResults = "\\$Computer\C$\folder\$Computer\HairyShaman\HairyShaman\" + $Computer + "_C.txt"
                        $ZHResults = "\\$Computer\C$\folder\$Computer\ZombieHunter\ZombieHunter\$Computer\All_Listing.txt"
                        $HSCopy = "\\$Computer\C$\folder\$Computer\HairyShaman"
                        $ZHCopy = "\\$Computer\C$\folder\$Computer\ZombieHunter"
                        $TestHS = "$FinalResting\$Computer\HairyShaman\" + $Computer + "_C.txt"
                        $ZHCompress = "\\$Computer\C$\folder\ZombieHunter.zip"
                        $HSCompress = "\\$Computer\C$\folder\HairyShaman.zip"
                        $ZHFinal = "$FinalResting\Results\$Computer\ZombieHunter.zip"
                        $HSFinal = "$FinalResting\Results\$Computer\HairyShaman.zip"
                        Write-Host "Working $Computer now...."
                        If(Test-Path $ZHResults)
                        {
                            If(!(Test-Path $ZHCompress))
                            {
                                . Compress $ZHCopy $ZHCompress
                            }
                            If(!(Test-Path $ZHFinal))
                            {
                                If(!(Test-Path "$FinalResting\Results\$Computer")){New-Item -type Directory -force "$FinalResting\Results\$Computer" | Out-Null}
                                Copy-Item -Path $ZHCompress -Destination $ZHFinal -Recurse | Out-Null
                                if(Test-Path -Path "$FinalResting\Results\$Computer\$ZHCompress")
                                { echo "ZombieHunter file was copied from $computer" | Out-File $Script:Log_File -Append }
                            }
                            Else{ echo "ZombieHunter Zip already exists $ZHFinal" | Out-File $Script:Log_File -Append }
                        }
                        else{Write-Host "didnt work - $ZHResults"}
                        
                        If(Test-Path $HSResults)
                        {
                            If(!(Test-Path $HSCompress))
                            {
                                . Compress $HSCopy $HSCompress
                            }
                            
                            If(!(Test-Path $HSFinal))
                            {
                                If(!(Test-Path "$FinalResting\Results\$Computer")){New-Item -type Directory -force "$FinalResting\Results\$Computer" | Out-Null}
                                Copy-Item -Path $HSCompress -Destination $HSFinal -Recurse | Out-Null
                                If(Test-Path -path "$FinalResting\Results\$Computer\$HSCompress")
                                { echo "HairyShaman file was copied from $computer" | Out-File $Script:Log_File -Append }
                            }
                            Else{ echo "HairyShaman Zip already exists $HSFinal" | Out-File  $Script:Log_File -Append }
                        }else{Write-Host "didnt work - $HSResults"}
                        . RemoveHunt $Computer
                    }
                    Else
                    {
                        echo "$Computer" | Out-File $Script:ReviveComps -Append
                        echo "$Computer still working one of the programs" | Out-File $Script:Log_File -Append
                    }
                }
            }
            Else
            {
                . No_Admin_Share $Computer
                $Script:Total_Bad_Computers = $Script:Total_Bad_Computers + 1
            }
        }
        Else 
        { 
            . No_Ping $Computer
            $Script:Total_Bad_Computers = $Script:Total_Bad_Computers + 1
        }
        echo "#######################################################" | Out-File $Script:Log_File -Append
    }
    . Revive $Script:ReviveComps

}
# ==============================================================================================
# Revive Check Status
# ==============================================================================================
Function Revive
{
    Param(
        [string]$CompFile
    )
        Write-Host "Waiting 10 minutes then will attempt to run Revive" -ForegroundColor Red
        Start-Sleep -s 600
        If ((Get-Content $CompFile) -ne $Null) 
        {
            $Computers = Get-Content $CompFile
            . Check_Status $Computers
        }
}
# ========================================================================
# Check Name 'No_Ping' - Logs when a system is unreachable by ping
# ========================================================================
Function No_Ping ($Computer)
{
    echo $Computer | Out-File $Script:Bad_Computers_File_Log -Append
    echo "=======================================================================" | Out-File $Script:Log_File -Append
    echo "$Computer - was unreachable by PING" | Out-File $Script:Log_File -Append
    echo "=======================================================================" | Out-File $Script:Log_File -Append
    Write-Host "=======================================================" -Fore Red
    Write-host -Fore red "Unreachable by Ping - $Computer"
    Write-Host "=======================================================" -Fore Red
}


# ========================================================================
# Check Name 'No_WMI' - Logs when system is unreachable by WMI
# ========================================================================
Function No_WMI ($Computer)
{
    echo $Computer | Out-File $Script:Bad_Computers_File_Log -Append
    echo "$Computer - was unreachable by WMI" | Out-File $Script:Log_File -Append
    Write-Host "=======================================================" -Fore Red
    Write-Host -Fore Red "Unreachable by WMI - $Computer"
    Write-Host -Fore Red "Check that psexec worked." - $Computer
    Write-Host "=======================================================" -Fore Red
}

# ========================================================================
# Check Name 'No_Admin_Share' - Log when a system is unreachable by admin share
# ========================================================================
Function No_Admin_Share ($Computer)
{
    echo $Computer | Out-File $Script:Bad_Computers_File_Log -Append
    echo "$Computer - was unreachable by Admin Share" | Out-File $Script:Log_File -Append
    Write-Host "=======================================================" -Fore Red
    Write-Host -Fore Red "Unreachable by Admin Share - $Computer"
    Write-Host "=======================================================" -Fore Red
}

# ========================================================================
# Function Name 'Test-Administrator' - Checks if ran as admin
# ========================================================================
function Test-Administrator  
{  
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)  
}
# ==============================================================================================
# Script Body - This is where the beginning magic happens
# ==============================================================================================
$erroractionpreference = "Continue"
# This tests to see if the user is an administrator, if not script attempts to runas the script.
If ((Test-Administrator) -ne $True)
{
    Write-Host "You are not an administrator" -Fore Red
    $Invocation = (Get-Variable MyInvocation).Value
    $Argument = (Split-Path $Invocation.MyCommand.Path) + "\" + ($invocation.mycommand.name)
    if ($Argument -ne "") 
    {   
        $arg = "-file `"$($Argument)`"" 
        Start-Process "$psHome\powershell.exe" -Verb Runas -ArgumentList $arg -ErrorAction 'stop'  
    }
    exit # Quit this session of powershell  
}
$Script:curDate = $((Get-Date).ToString("yyyy_MMM_dd-HH.mm.ss-tt"))
. Get_Folder_Path

Write-Host " "
Write-Host "How do you want to list computers?"	-ForegroundColor Green
$strResponse = Read-Host "`n[1] All Domain Computers (Must provide Domain), `n[2] Computer names from a File, `n[3] List a Single Computer manually"
If($strResponse -eq "1"){. ListComputers | Sort-Object}
	elseif($strResponse -eq "2"){. ListTextFile}
	elseif($strResponse -eq "3"){. SingleEntry}
	else{Write-Host "You did not supply a correct response, `
	Please run script again."; pause -foregroundColor Red}

echo "Got computer list... Next task..." | Out-File $Script:Log_File -Append
echo " " | Out-File $Script:Log_File -Append
    
    New-Item -type file -force "$Script:Folder_Path\Bad_Computers_$Script:curDate.txt" | Out-Null
    $Script:Bad_Computers_File_Log = "$Script:Folder_Path\Bad_Computers_$Script:curDate.txt"
    $Script:Total_Bad_Computers = 0

    New-Item -type file -force "$Script:Folder_Path\Good_Computers_$Script:curDate.txt" | Out-Null
    $Script:GoodComputers_Log = "$Script:Folder_Path\Good_Computers_$Script:curDate.txt"

    New-Item -type file -force "$Script:Folder_Path\ZH_Bad_Log_$Script:curDate.txt" | Out-Null
    $Script:ZH_Bad_Log = "$Script:Folder_Path\ZH_Bad_Log_$Script:curDate.txt"

    New-Item -type file -force "$Script:Folder_Path\HS_Bad_Log_$Script:curDate.txt" | Out-Null
    $Script:HS_Bad_Log = "$Script:Folder_Path\HS_Bad_Log_$Script:curDate.txt"

. Check_Status $Script:Computers

echo "Script ended "$((Get-Date).ToString("yyyy_MMM_dd-HH.mm.ss-tt")) | Out-File $Script:Log_File -Append
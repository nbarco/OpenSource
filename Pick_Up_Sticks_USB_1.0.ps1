<#
    .SYNOPSIS  
        Locates usb devices that user's have plugged in and provides when they did it. 

    .DESCRIPTION  
        This program compares each users uniquely mounted USB device against the system mounted devices. When it finds a match 
        it grabs the device name and serial. It also grabs the last write time of the user's unique key. This proves that the 
        user plugged the device in on that day and time. The program then outputs the findings in three ways. First, is via a simple
        text file, as an html file, and via xml.  

    .NOTES  
        File Name      : Pick_Up_Sticks_USB.ps1
        Version        : v.1.0 
        Author         : StillWorthless
        Email          : 
        Prerequisite   : PowerShell
        Created        : 30APR16
     
     .CHANGELOG
        Update         : DATE 30 APR 16
            Changes:   : Added the ability to check if remote registry is enabled, 
                         if not it will start it and then turn it back off once it is done

     .TODO
        1. Create a frontend form to control the program

    #################################################################################### 


#>
# Set Variables
$Script:dump = "" #This is where you place your share drive \\system\folder to store files anytime this is ran on your network by any admin.
$Script:IADump = $False #change this to $True if you want to enable IADUMP.
$Script:MountPoints = "Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2"
$Script:USBSTOR = "SYSTEM\currentcontrolset\enum\USBSTOR"
$Script:MountedDevices = "SYSTEM\MountedDevices"
$Script:Network_Card_Key = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkCards"
$Script:Service_Key = "SYSTEM\CurrentControlSet\services"
$Script:Name_Key = "SYSTEM\CurrentControlSet\services\Tcpip\Parameters\Interfaces"
$Script:SetupAPI = "$env:windir\inf\setupapi.dev.log"
$Script:HKUroot = [Microsoft.Win32.RegistryHive]::Users
$Script:HKLMroot = [Microsoft.Win32.RegistryHive]::LocalMachine
$Script:HKU = "HKU"
$Script:curDate = ""
$Script:curDate = $((Get-Date).ToString("yyyy_MMM_dd-HH.mm.ss-tt")) ##Sets the date and time##
$Global:FinalItemsFound = @()
#Build XML Template
$Script:XMLtemplate = @'
<Pick_Up_Sticks Version='0.1'>
<System ComputerName="computer"> 
<System_Info>
<IP>"0.0.0.0"</IP>
<Subnet>"1.1.1.1"</Subnet>
<DefaultGateway>"1.1.1.1"</DefaultGateway>
<DNS>"1.1.1.1"</DNS>
<MAC>"1.1.1.1"</MAC>
<DHCP>"1.1.1.1"</DHCP>
</System_Info>
<User_Info>
<User UserName="user">
<USB_Info>
<MountPoint>"1.1.1.1"</MountPoint>
<USBFriendlyName>"1.1.1.1"</USBFriendlyName>
<USB_Device>"1.1.1.1"</USB_Device>
<USB_Serial>"1.1.1.1"</USB_Serial>
<LastWriteTime>"1.1.1.1"</LastWriteTime>
</USB_Info>
</User>
</User_Info>
</System>
</Pick_Up_Sticks>
'@

$Script:xslTemplate = @'
<?xml version="1.0"?>
<xsl:stylesheet
   version="1.0"
   xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
   xmlns:xsd="http://www.w3.org/2001/XMLSchema"
   xmlns:msxsl="urn:schemas-microsoft-com:xslt"
>
  <xsl:strip-space elements="*"/>
  <xsl:output method="xml"
      omit-xml-declaration="yes"
      indent="yes"
      standalone="yes" />
  
  <xsl:template match="/">
    <xsl:for-each select="Pick_Up_Sticks">
		<xsl:element name="Pick_Up_Sticks">
			<xsl:for-each select="System">
				<xsl:element name="System">
					<xsl:attribute name="ComputerName">
						<xsl:value-of select="@ComputerName"/>
					</xsl:attribute>
			
					<xsl:for-each select="System_Info">
						<xsl:element name="System_Info">
							<xsl:attribute name="DHCP">
								<xsl:value-of select="DHCP"/>
							</xsl:attribute>
							<xsl:attribute name="MAC">
								<xsl:value-of select="MAC"/>
							</xsl:attribute>
							<xsl:attribute name="DNS">
								<xsl:value-of select="DNS"/>
							</xsl:attribute>
							<xsl:attribute name="DefaultGateway">
								<xsl:value-of select="DefaultGateway"/>
							</xsl:attribute>
							<xsl:attribute name="Subnet">
								<xsl:value-of select="Subnet"/>
							</xsl:attribute>
							<xsl:attribute name="IP">
								<xsl:value-of select="IP"/>
							</xsl:attribute>
						</xsl:element>
					</xsl:for-each>
			
					<xsl:for-each select="User_Info">
						<xsl:element name="User_Info">
							<xsl:for-each select="User">
								<xsl:element name="User">
									<xsl:attribute name="UserName">
										<xsl:value-of select="@UserName"/>
									</xsl:attribute>
					
									<xsl:for-each select="USB_Info">
										<xsl:element name="USB_Info"> 
											<xsl:attribute name="LastWriteTime">
												<xsl:value-of select="LastWriteTime"/>
											</xsl:attribute>
											<xsl:attribute name="USB_Serial">
												<xsl:value-of select="USB_Serial"/>
											</xsl:attribute>
											<xsl:attribute name="USB_Device">
												<xsl:value-of select="USB_Device"/>
											</xsl:attribute>
											<xsl:attribute name="USBFriendlyName">
												<xsl:value-of select="USBFriendlyName"/>
											</xsl:attribute>
											<xsl:attribute name="MountPoint">
												<xsl:value-of select="MountPoint"/>
											</xsl:attribute>
										</xsl:element>
									</xsl:for-each>
								</xsl:element>
							</xsl:for-each>
						</xsl:element>
					</xsl:for-each>
				</xsl:element>
			</xsl:for-each>
		</xsl:element>
    </xsl:for-each>
  </xsl:template>
</xsl:stylesheet>
'@
# ===========================================================================================
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

            $Script:Domain = Read-Host "Enter your Domain here: OU=users,DC=company,DC=com"
        #>
        
        # EDITABLE SECTION START
        Write-Host "Select 0 to enter your own domain entry."
        $response = Read-Host = "`n[0] Manual Entry"
        if($response -eq 0){$Script:Domain = Read-Host "Enter your Domain here: OU=users,DC=company,DC=com"}
        else {Write-Host "You did not provide a valid response."; . ListComputers}
        # EDITABLE SECTION END

        echo "Pulled computers from: "$Script:Domain | Out-File $Script:Log_File -Append
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

# ========================================================================
# Function Name 'SingleEntry' - Enumerates Computer from user input
# ========================================================================
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

# ========================================================================
# Function Name 'System_Info' - Gathers System Information on a finding
# ========================================================================
Function System_Info ($Computer, $curLogFile)
{
    If ($Script:System_Data -ne $True)
    {
        echo "System Information....." | Out-File $curLogFile -Append
        #Collecting the IP Address of the system
        $colItems = GWMI -cl "Win32_NetworkAdapterConfiguration" -name "root\CimV2" -Impersonation 3 -ComputerName $Computer -filter "IpEnabled = TRUE"
        $actualIP = [System.Net.Dns]::GetHostAddresses("$computer") | foreach {if ($_.IPAddressToString -notmatch ":") {echo $_.IPAddressToString} }
        If (($colItems -ne $Null) -and ($colItems -ne ""))
        {                                
            ForEach ($objItem in $colItems)
            {
                if ($actualIP -eq $objItem.IpAddress)
                {
                    $ip = $objItem.IpAddress
                    $sub = $objItem.IPSubnet
                    $dfgw = $objItem.DefaultIPGateway
                    $dns = $objItem.DNSServerSearchOrder
                    $mac = $objItem.MACAddress
                    $dhcp = $objItem.DHCPEnabled
                    #========================================================#
                    #Testing for new output
                    #========================================================#
                    $Script:newcomputersysinfo = $Script:xml.CreateElement("System_Info")
                    [void]$Script:newcomputer.InsertBefore($Script:newcomputersysinfo, $Script:newcomputerUserinfo)
                    
                    $Script:newComputerUSBsysIP = $Script:xml.CreateElement("IP")
                    $Script:newComputerUSBsysIPtext = $Script:xml.CreateTextNode([string]$ip)
                    [void]$Script:newComputerUSBsysIP.AppendChild($Script:newComputerUSBsysIPtext)
                    [void]$Script:newComputersysinfo.AppendChild($Script:newComputerUSBsysIP)
                                                    
                    $Script:newComputerUSBsysSubnet = $Script:xml.CreateElement("Subnet")
                    $Script:newComputerUSBsysSubnettext = $Script:xml.CreateTextNode([string]$sub)
                    [void]$Script:newComputerUSBsysSubnet.AppendChild($Script:newComputerUSBsysSubnettext)                                
                    [void]$Script:newComputersysinfo.AppendChild($Script:newComputerUSBsysSubnet)
                    
                    $Script:newComputerUSBsysDFGW = $Script:xml.CreateElement("DefaultGateway")
                    $Script:newComputerUSBsysDFGWtext = $Script:xml.CreateTextNode([string]$dfgw)
                    [void]$Script:newComputerUSBsysDFGW.AppendChild($Script:newComputerUSBsysDFGWtext)
                    [void]$Script:newComputersysinfo.AppendChild($Script:newComputerUSBsysDFGW)
                    
                    $Script:newComputerUSBsysdns = $Script:xml.CreateElement("DNS")
                    $Script:newComputerUSBsysdnstext = $Script:xml.CreateTextNode([string]$dns)
                    [void]$Script:newComputerUSBsysdns.AppendChild($Script:newComputerUSBsysdnstext)
                    [void]$Script:newComputersysinfo.AppendChild($Script:newComputerUSBsysdns)
                    
                    $Script:newComputerUSBsysMAC = $Script:xml.CreateElement("MAC")
                    $Script:newComputerUSBsysMACtext = $Script:xml.CreateTextNode([string]$mac)
                    [void]$Script:newComputerUSBsysMAC.AppendChild($Script:newComputerUSBsysMACtext)
                    [void]$Script:newComputersysinfo.AppendChild($Script:newComputerUSBsysMAC)
                    
                    $Script:newComputerUSBsysDHCP = $Script:xml.CreateElement("DHCP")
                    $Script:newComputerUSBsysDHCPtext = $Script:xml.CreateTextNode([string]$dhcp)
                    [void]$Script:newComputerUSBsysDHCP.AppendChild($Script:newComputerUSBsysDHCPtext)
                    [void]$Script:newComputersysinfo.AppendChild($Script:newComputerUSBsysDHCP)
                    #========================================================#
                    #Testing for new output
                    #========================================================#

                    #========================================================#
                    #Testing for new HTML Output
                    #========================================================#
                    $htmlOutput += "<h2>System Information</h2>"
                    $htmlOutput += "<table>"
                    $htmlOutput += "<tr><td>IP Address----------:</td><td>$ip</td></tr>"
                    $htmlOutput += "<tr><td>Subnet--------------:</td><td>$sub</td></tr>"
                    $htmlOutput += "<tr><td>Default Gateway-----:</td><td>$dfgw</td></tr>"
                    $htmlOutput += "<tr><td>DNS Servers---------:</td><td>$dns</td></tr>"
                    $htmlOutput += "<tr><td>MAC Address---------:</td><td>$mac</td></tr>"
                    $htmlOutput += "<tr><td>DHCP Enabled--------:</td><td>$dhcp</td></tr>"
                    $htmlOutput += "</table>"

                    #========================================================#
                    #Testing for new HTML Output
                    #========================================================#
                    # Write to log file
                    echo "IP Address is: $ip" | Out-File $curLogFile -Append
                    echo "Subnet is: $sub" | Out-File $curLogFile -Append
                    echo "Default Gateway is: $dfgw" | Out-File $curLogFile -Append
                    echo "DNS Servers are: $dns" | Out-File $curLogFile -Append
                    echo "MAC Address is: $mac" | Out-File $curLogFile -Append
                    echo "Is DHCP Enabled: $dhcp" | Out-File $curLogFile -Append
                    echo "=======================================================================" | Out-File $curLogFile -Append
                    echo "=======================================================================" | Out-File $curLogFile -Append
                    echo " " | Out-File $curLogFile -Append
                    echo " " | Out-File $curLogFile -Append
                }
            }
        }
        else
        {
            #If WMI does not work report it to the log file and then get registry entries for the needed information.
            echo "WMI did not work on $computer. Grabbing information from the registry." | Out_File $curLogFile -Append
            #opens remote system base key (HKLM or HKU etc)
            #$rootkey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey($Script:HKLMroot, $Computer)
            # opens a key under root key
            # Opens the network card key to gather all network cards
            $NetworkCardKey = $Script:HKLMrootKey.OpenSubKey($Network_Card_Key)
            #Gets all keys under rootkey
            # Gets the names of all network cards
            $NetworkCardNameKeys = $NetworkCardKey.GetSubKeyNames()
            Foreach ($networkCard in $NetworkCardNameKeys)
            {
                $NetworkCard = $NetworkCardKey.OpenSubKey($networkCard)
                # gets value of the ServiceName for that networkcard
                $NeworkCardServiceName = $NetworkCard.GetValue("ServiceName")
                #Define variable for the Tcpip key
                $Service_Network_Key = $Service_Key + "\" + $NeworkCardServiceName + "\Parameters\Tcpip"
                # Open the subkey to the interface
                $Network_Info = $rootkey.OpenSubKey($Service_Network_Key)
                If ($Network_Info -ne $Null) {
                    # Get information about each tcpip parameter
                    $ipaddresses = $Network_Info.GetValue("IPAddress")
                    If (($ipaddresses -ne $Null) -and ($ipaddresses -ne "")) {        
                        if ($actualIP -eq $ipaddresses) {
                            echo "IP Address is: $ip" | Out-File $curLogFile -Append
                            $Subnets = $Network_Info.GetValue("Subnet")
                            If (($Subnets -ne $Null) -and ($Subnets -ne "")) { 
                                foreach ($Sub in $Subnets) { echo "Subnet is: $sub" | Out-File $curLogFile -Append } }
                            $DefaultGateways = $Network_Info.GetValue("DefaultGateway")
                            If (($DefaultGateways -ne $Null) -and ($DefaultGateways -ne "")) { 
                                foreach ($dfgw in $DefaultGateways) { echo "Default Gateway is: $dfgw" | Out-File $curLogFile -Append } }
                            $dhcp = $Network_Info.GetValue("EnableDHCP")
                            If ($dhcp -eq 1) { echo "Is DHCP Enabled: $True" | Out-File $curLogFile -Append }
                            elseif ($dhcp -eq 0) { echo "Is DHCP Enabled: $False" | Out-File $curLogFile -Append } }

                        $NameServerKey = $Name_Key + "\" + $NeworkCardServiceName
                        $NameServer_Key = $rootkey.OpenSubKey($NameServerKey)
                
                        If ($NameServer_Key -ne $Null) {
                            $NameServer = $NameServer_Key.GetValue("NameServer")
                            If (($NameServer -ne "") -and ($NameServer -ne $Null)) { 
                                foreach ($dns in $NameServer) { echo "DNS Servers are: "$dns | Out-File $curLogFile -Append } } }
                        echo "=======================================================================" | Out-File $curLogFile -Append
                        echo "=======================================================================" | Out-File $curLogFile -Append
                        echo " " | Out-File $curLogFile -Append
                        echo " " | Out-File $curLogFile -Append
                        #========================================================#
                        #Testing for new output
                        #========================================================#
                        $Script:newcomputersysinfo = $Script:xml.CreateElement("System_Info")
                        [void]$Script:newcomputer.InsertBefore($Script:newcomputersysinfo, $Script:newcomputerUserinfo)
                    
                        $Script:newComputerUSBsysIP = $Script:xml.CreateElement("IP")
                        $Script:newComputerUSBsysIPtext = $Script:xml.CreateTextNode([string]$ip)
                        [void]$Script:newComputerUSBsysIP.AppendChild($Script:newComputerUSBsysIPtext)
                        [void]$Script:newComputersysinfo.AppendChild($Script:newComputerUSBsysIP)
                                                    
                        $Script:newComputerUSBsysSubnet = $Script:xml.CreateElement("Subnet")
                        $Script:newComputerUSBsysSubnettext = $Script:xml.CreateTextNode([string]$sub)
                        [void]$Script:newComputerUSBsysSubnet.AppendChild($Script:newComputerUSBsysSubnettext)                                
                        [void]$Script:newComputersysinfo.AppendChild($Script:newComputerUSBsysSubnet)
                    
                        $Script:newComputerUSBsysDFGW = $Script:xml.CreateElement("DefaultGateway")
                        $Script:newComputerUSBsysDFGWtext = $Script:xml.CreateTextNode([string]$dfgw)
                        [void]$Script:newComputerUSBsysDFGW.AppendChild($Script:newComputerUSBsysDFGWtext)
                        [void]$Script:newComputersysinfo.AppendChild($Script:newComputerUSBsysDFGW)
                    
                        $Script:newComputerUSBsysdns = $Script:xml.CreateElement("DNS")
                        $Script:newComputerUSBsysdnstext = $Script:xml.CreateTextNode([string]$dns)
                        [void]$Script:newComputerUSBsysdns.AppendChild($Script:newComputerUSBsysdnstext)
                        [void]$Script:newComputersysinfo.AppendChild($Script:newComputerUSBsysdns)
                    
                        $Script:newComputerUSBsysMAC = $Script:xml.CreateElement("MAC")
                        $Script:newComputerUSBsysMACtext = $Script:xml.CreateTextNode("N/A")
                        [void]$Script:newComputerUSBsysMAC.AppendChild($Script:newComputerUSBsysMACtext)
                        [void]$Script:newComputersysinfo.AppendChild($Script:newComputerUSBsysMAC)
                    
                        $Script:newComputerUSBsysDHCP = $Script:xml.CreateElement("DHCP")
                        $Script:newComputerUSBsysDHCPtext = $Script:xml.CreateTextNode([string]$dhcp)
                        [void]$Script:newComputerUSBsysDHCP.AppendChild($Script:newComputerUSBsysDHCPtext)
                        [void]$Script:newComputersysinfo.AppendChild($Script:newComputerUSBsysDHCP)
                        #========================================================#
                        #Testing for new output
                        #========================================================#

                        #========================================================#
                        #Testing for new HTML Output
                        #========================================================#
                        $htmlOutput += "<h2>System Information</h2>"
                        $htmlOutput += "<table>"
                        $htmlOutput += "<tr><td>IP Address----------:</td><td>$ip</td></tr>"
                        $htmlOutput += "<tr><td>Subnet--------------:</td><td>$sub</td></tr>"
                        $htmlOutput += "<tr><td>Default Gateway-----:</td><td>$dfgw</td></tr>"
                        $htmlOutput += "<tr><td>DNS Servers---------:</td><td>$dns</td></tr>"
                        $htmlOutput += "<tr><td>MAC Address---------:</td><td>N/A</td></tr>"
                        $htmlOutput += "<tr><td>DHCP Enabled--------:</td><td>$dhcp</td></tr>"
                        $htmlOutput += "</table>"

                        #========================================================#
                        #Testing for new HTML Output
                        #========================================================#
                    }
                }
                $Network_Info.Close()
                $NameServer_Key.Close()
                $NetworkCard.Close()
            }
            $NetworkCardKey.Close()
        }
        $Script:System_Data = $True
    }
}
# ========================================================================
# Check Name 'No_Ping' - Logs when a system is unreachable by ping
# ========================================================================
Function No_Ping ($Computer, $Bad_Comp_File_Ping)
{
    echo $Computer | Out-File $Bad_Comp_File_Ping -Append
    echo "=======================================================================" | Out-File $Script:Log_File -Append
    echo "$Computer - was unreachable by PING" | Out-File $Script:Log_File -Append
    echo "=======================================================================" | Out-File $Script:Log_File -Append
}

# ========================================================================
# No_WMI logs the machine to bad computers if WMI is off
# ========================================================================
Function No_WMI ($Computer, $Bad_Computers_File_Log)
{
    echo $Computer | Out-File $Bad_Comp_File_Ping -Append
    echo "=======================================================================" | Out-File $Script:Log_File -Append
    echo "$Computer - Was unreachable by WMI" | Out-File $Script:Log_File -Append
    echo "=======================================================================" | Out-File $Script:Log_File -Append
}
# ========================================================================
# Test_Remote_Registry
# ========================================================================
Function Test_Remote_Registry ($Computer)
{
    $RemReg = Get-WmiObject -ComputerName $computer win32_service -namespace root\cimv2 -filter "Name='RemoteRegistry'"
    $Running = $RemReg.State
    $startMode = $RemReg.StartMode
    echo "********==========================********" | Out-File $Script:Log_File -Append
    If($Running -eq "Running")
    {
        echo "$Computer - Remote Registry was on." | Out-File $Script:Log_File -Append
        $ret = @("Good","Running")
        Return $ret
    }
    Else
    {
        echo "$Computer - Remote registry was off; attempting to start it." | Out-File $Script:Log_File -Append
        . TurnOn_Remote_Registry $Computer
    }
    echo "********==========================********" | Out-File $Script:Log_File -Append
}

# ========================================================================
# No_Remote_Registry logs the machine to bad computers if Remote Registry is off
# ========================================================================
Function No_Remote_Registry ($Computer, $Bad_Computers_File_Log)
{
    echo $Computer | Out-File $Bad_Comp_File_Ping -Append
    echo "!!!=======================================================================!!!" | Out-File $Script:Log_File -Append
    echo "$Computer - Was unreachable by Remote Registry" | Out-File $Script:Log_File -Append
    echo "!!!=======================================================================!!!" | Out-File $Script:Log_File -Append
}
# ========================================================================
# TurnOn_Remote_Registry 
# ========================================================================
Function TurnOn_Remote_Registry ($Computer)
{
    $time = 15
    echo "********==========================********" | Out-File $Script:Log_File -Append
    $RemReg = Get-WmiObject -ComputerName $computer win32_service -namespace root\cimv2 -filter "Name='RemoteRegistry'"
    $Running = $RemReg.State
    $startMode = $RemReg.StartMode
    If($Running -eq "Stopped")
    {
        If($startMode -eq "Disabled")
        {
            #change startmode to manual if disabled
            $rtn = $RemReg.changestartmode("manual") 
            if($rtn.returnvalue -eq 0) 
            { 
                echo "Start Modewas set to Disabled" | Out-File $Script:Log_File -Append
                echo "Change Start Mode to Manual was Successful" | Out-File $Script:Log_File -Append 
                $StartRemReg = $remReg.StartService()
                Sleep $time
                If($StartRemReg.ReturnValue -eq 0)
                {
                    echo "Start Remote Registry Service was Successful" | Out-File $Script:Log_File -Append
                    $ret = @("Disabled","Running")
                    Return $ret
                }
                Else
                {
                    switch ($StartRemReg.returnvalue) {
                        0 { echo "The request was accepted."  | Out-File $Script:Log_File -Append }
                        1 { echo "The request is not supported."  | Out-File $Script:Log_File -Append }
                        2 { echo "The user did not have the necessary access."  | Out-File $Script:Log_File -Append }
                        3 { echo "The service cannot be stopped because other services that are running are dependent on it."  | Out-File $Script:Log_File -Append }
                        4 { echo "The requested control code is not valid, or it is unacceptable to the service."  | Out-File $Script:Log_File -Append }
                        5 { echo "The requested control code cannot be sent to the service because the state of the service (Win32_BaseService.State property) is equal to 0, 1, or 2."  | Out-File $Script:Log_File -Append }
                        6 { echo "The service has not been started."  | Out-File $Script:Log_File -Append }
                        7 { echo "The service did not respond to the start request in a timely fashion."  | Out-File $Script:Log_File -Append }
                        8 { echo "Unknown failure when starting the service."  | Out-File $Script:Log_File -Append }
                        9 { echo "The directory path to the service executable file was not found."  | Out-File $Script:Log_File -Append }
                        10 { echo "The service is already running."  | Out-File $Script:Log_File -Append }
                        11 { echo "The database to add a new service is locked."  | Out-File $Script:Log_File -Append }
                        12 { echo "A dependency this service relies on has been removed from the system."  | Out-File $Script:Log_File -Append }
                        13 { echo "The service failed to find the service needed from a dependent service."  | Out-File $Script:Log_File -Append }
                        14 { echo "The service has been disabled from the system."  | Out-File $Script:Log_File -Append }
                        15 { echo "The service does not have the correct authentication to run on the system."  | Out-File $Script:Log_File -Append }
                        16 { echo "This service is being removed from the system."  | Out-File $Script:Log_File -Append }
                        17 { echo "The service has no execution thread."  | Out-File $Script:Log_File -Append }
                        18 { echo "The service has circular dependencies when it starts."  | Out-File $Script:Log_File -Append }
                        19 { echo "A service is running under the same name."  | Out-File $Script:Log_File -Append }
                        20 { echo "The service name has invalid characters."  | Out-File $Script:Log_File -Append }
                        21 { echo "Invalid parameters have been passed to the service."  | Out-File $Script:Log_File -Append }
                        22 { echo "The account under which this service runs is either invalid or lacks the permissions to run the service."  | Out-File $Script:Log_File -Append }
                        23 { echo "The service exists in the database of services available from the system."  | Out-File $Script:Log_File -Append }
                        24 { echo "The service is currently paused in the system."  | Out-File $Script:Log_File -Append }
                        default { echo "$($StartRemReg.ReturnValue) is not listed."  | Out-File $Script:Log_File -Append }
                    }
                    $ret = @("Disabled","Failed to Start - Stopped")
                    Return $ret
                }
            } 
            ELSE 
            { 
                switch ($rtn.returnvalue) {
                    0 { echo "Success" | Out-File $Script:Log_File -Append }
                    1 { echo "Not Supported" | Out-File $Script:Log_File -Append } 
                    2 { echo "Access Denied" | Out-File $Script:Log_File -Append } 
                    3 { echo "Dependent Services Running" | Out-File $Script:Log_File -Append } 
                    4 { echo "Invalid Service Control" | Out-File $Script:Log_File -Append } 
                    5 { echo "Service Cannot Accept Control" | Out-File $Script:Log_File -Append }
                    6 { echo "Service Not Active" | Out-File $Script:Log_File -Append }
                    7 { echo "Service Request Timeout" | Out-File $Script:Log_File -Append }
                    8 { echo "Unknown Failure" | Out-File $Script:Log_File -Append }
                    9 { echo "Path Not Found" | Out-File $Script:Log_File -Append }
                    10 { echo "Service Already Running" | Out-File $Script:Log_File -Append }
                    11 { echo "Service Database Locked" | Out-File $Script:Log_File -Append }
                    12 { echo "Service Dependency Deleted" | Out-File $Script:Log_File -Append }
                    13 { echo "Service Dependency Failure" | Out-File $Script:Log_File -Append }
                    14 { echo "Service Disabled" | Out-File $Script:Log_File -Append }
                    15 { echo "Service Logon Failed" | Out-File $Script:Log_File -Append }
                    16 { echo "Service Marked For Deletion" | Out-File $Script:Log_File -Append }
                    17 { echo "Service No Thread" | Out-File $Script:Log_File -Append }
                    18 { echo "Status Circular Dependency" | Out-File $Script:Log_File -Append }
                    19 { echo "Status Duplicate Name" | Out-File $Script:Log_File -Append }
                    20 { echo "Status Invalid Name" | Out-File $Script:Log_File -Append }
                    21 { echo "Status Invalid Parameter" | Out-File $Script:Log_File -Append }
                    22 { echo "Status Invalid Service Account" | Out-File $Script:Log_File -Append }
                    23 { echo "Status Service Exists" | Out-File $Script:Log_File -Append }
                    24 { echo "Service Already Paused" | Out-File $Script:Log_File -Append } 
                    default { echo "$($rtn.ReturnValue) is not listed."  | Out-File $Script:Log_File -Append }
                }
                $ret = @("Disabled","Failed Change Mode - Stopped")
                Return $ret
            }
        }
        ElseIf ($startMode -eq "Manual")
        {
            $StartRemReg = $remReg.StartService()
            Sleep $time
            If($StartRemReg.ReturnValue -eq 0)
            {
                echo "Start Remote Registry Service was Successful" | Out-File $Script:Log_File -Append
                $ret = @("Manual","Running")
                Return $ret
            }
            Else
            {
                switch ($StartRemReg.returnvalue) {
                    0 { echo "The request was accepted."  | Out-File $Script:Log_File -Append }
                    1 { echo "The request is not supported."  | Out-File $Script:Log_File -Append }
                    2 { echo "The user did not have the necessary access."  | Out-File $Script:Log_File -Append }
                    3 { echo "The service cannot be stopped because other services that are running are dependent on it."  | Out-File $Script:Log_File -Append }
                    4 { echo "The requested control code is not valid, or it is unacceptable to the service."  | Out-File $Script:Log_File -Append }
                    5 { echo "The requested control code cannot be sent to the service because the state of the service (Win32_BaseService.State property) is equal to 0, 1, or 2."  | Out-File $Script:Log_File -Append }
                    6 { echo "The service has not been started."  | Out-File $Script:Log_File -Append }
                    7 { echo "The service did not respond to the start request in a timely fashion."  | Out-File $Script:Log_File -Append }
                    8 { echo "Unknown failure when starting the service."  | Out-File $Script:Log_File -Append }
                    9 { echo "The directory path to the service executable file was not found."  | Out-File $Script:Log_File -Append }
                    10 { echo "The service is already running."  | Out-File $Script:Log_File -Append }
                    11 { echo "The database to add a new service is locked."  | Out-File $Script:Log_File -Append }
                    12 { echo "A dependency this service relies on has been removed from the system."  | Out-File $Script:Log_File -Append }
                    13 { echo "The service failed to find the service needed from a dependent service."  | Out-File $Script:Log_File -Append }
                    14 { echo "The service has been disabled from the system."  | Out-File $Script:Log_File -Append }
                    15 { echo "The service does not have the correct authentication to run on the system."  | Out-File $Script:Log_File -Append }
                    16 { echo "This service is being removed from the system."  | Out-File $Script:Log_File -Append }
                    17 { echo "The service has no execution thread."  | Out-File $Script:Log_File -Append }
                    18 { echo "The service has circular dependencies when it starts."  | Out-File $Script:Log_File -Append }
                    19 { echo "A service is running under the same name."  | Out-File $Script:Log_File -Append }
                    20 { echo "The service name has invalid characters."  | Out-File $Script:Log_File -Append }
                    21 { echo "Invalid parameters have been passed to the service."  | Out-File $Script:Log_File -Append }
                    22 { echo "The account under which this service runs is either invalid or lacks the permissions to run the service."  | Out-File $Script:Log_File -Append }
                    23 { echo "The service exists in the database of services available from the system."  | Out-File $Script:Log_File -Append }
                    24 { echo "The service is currently paused in the system."  | Out-File $Script:Log_File -Append }
                    default { echo "$($StartRemReg.ReturnValue) is not listed."  | Out-File $Script:Log_File -Append }
                }
                $ret = @("Manual","Failed to start - Stopped")
                Return $ret
            }
        }
        Else
        {
            $StartRemReg = $remReg.StartService()
            Sleep $time
            If($StartRemReg.ReturnValue -eq 0)
            {
                echo "Start Remote Registry Service was Successful" | Out-File $Script:Log_File -Append
                $ret = @("Other","Running")
                Return $ret
            }
            Else
            {
                switch ($StartRemReg.returnvalue) {
                    0 { echo "The request was accepted."  | Out-File $Script:Log_File -Append }
                    1 { echo "The request is not supported."  | Out-File $Script:Log_File -Append }
                    2 { echo "The user did not have the necessary access."  | Out-File $Script:Log_File -Append }
                    3 { echo "The service cannot be stopped because other services that are running are dependent on it."  | Out-File $Script:Log_File -Append }
                    4 { echo "The requested control code is not valid, or it is unacceptable to the service."  | Out-File $Script:Log_File -Append }
                    5 { echo "The requested control code cannot be sent to the service because the state of the service (Win32_BaseService.State property) is equal to 0, 1, or 2."  | Out-File $Script:Log_File -Append }
                    6 { echo "The service has not been started."  | Out-File $Script:Log_File -Append }
                    7 { echo "The service did not respond to the start request in a timely fashion."  | Out-File $Script:Log_File -Append }
                    8 { echo "Unknown failure when starting the service."  | Out-File $Script:Log_File -Append }
                    9 { echo "The directory path to the service executable file was not found."  | Out-File $Script:Log_File -Append }
                    10 { echo "The service is already running."  | Out-File $Script:Log_File -Append }
                    11 { echo "The database to add a new service is locked."  | Out-File $Script:Log_File -Append }
                    12 { echo "A dependency this service relies on has been removed from the system."  | Out-File $Script:Log_File -Append }
                    13 { echo "The service failed to find the service needed from a dependent service."  | Out-File $Script:Log_File -Append }
                    14 { echo "The service has been disabled from the system."  | Out-File $Script:Log_File -Append }
                    15 { echo "The service does not have the correct authentication to run on the system."  | Out-File $Script:Log_File -Append }
                    16 { echo "This service is being removed from the system."  | Out-File $Script:Log_File -Append }
                    17 { echo "The service has no execution thread."  | Out-File $Script:Log_File -Append }
                    18 { echo "The service has circular dependencies when it starts."  | Out-File $Script:Log_File -Append }
                    19 { echo "A service is running under the same name."  | Out-File $Script:Log_File -Append }
                    20 { echo "The service name has invalid characters."  | Out-File $Script:Log_File -Append }
                    21 { echo "Invalid parameters have been passed to the service."  | Out-File $Script:Log_File -Append }
                    22 { echo "The account under which this service runs is either invalid or lacks the permissions to run the service."  | Out-File $Script:Log_File -Append }
                    23 { echo "The service exists in the database of services available from the system."  | Out-File $Script:Log_File -Append }
                    24 { echo "The service is currently paused in the system."  | Out-File $Script:Log_File -Append }
                    default { echo "$($StartRemReg.ReturnValue) is not listed."  | Out-File $Script:Log_File -Append }
                }
                $ret = @("Other","Failed to start - Stopped")
                Return $ret
            }
        }
    }
    echo "********==========================********" | Out-File $Script:Log_File -Append
}
# ========================================================================
# TurnOff_Remote_Registry 
# ========================================================================
Function TurnOff_Remote_Registry ($Computer, $ChangeMode)
{
    $time = 10
    echo "********==========================********" | Out-File $Script:Log_File -Append
    $RemReg = Get-WmiObject -ComputerName $computer win32_service -namespace root\cimv2 -filter "Name='RemoteRegistry'"
    If($ChangeMode -eq "Disabled")
    {
        $StopRemReg = $RemReg.stopservice()
        Sleep $time
        If($StopRemReg.ReturnValue -eq 0)
        {
            echo "Stopping Remote Registry Service was Successful" | Out-File $Script:Log_File -Append
            $rtn = $RemReg.changestartmode("Disabled") 
            if($rtn.returnvalue -eq 0) 
            { 
                echo "Change Start Mode to Disabled was Successful" | Out-File $Script:Log_File -Append 
            }
            Else
            {
                switch ($rtn.returnvalue) {
                    0 { echo "Success" | Out-File $Script:Log_File -Append }
                    1 { echo "Not Supported" | Out-File $Script:Log_File -Append } 
                    2 { echo "Access Denied" | Out-File $Script:Log_File -Append } 
                    3 { echo "Dependent Services Running" | Out-File $Script:Log_File -Append } 
                    4 { echo "Invalid Service Control" | Out-File $Script:Log_File -Append } 
                    5 { echo "Service Cannot Accept Control" | Out-File $Script:Log_File -Append }
                    6 { echo "Service Not Active" | Out-File $Script:Log_File -Append }
                    7 { echo "Service Request Timeout" | Out-File $Script:Log_File -Append }
                    8 { echo "Unknown Failure" | Out-File $Script:Log_File -Append }
                    9 { echo "Path Not Found" | Out-File $Script:Log_File -Append }
                    10 { echo "Service Already Running" | Out-File $Script:Log_File -Append }
                    11 { echo "Service Database Locked" | Out-File $Script:Log_File -Append }
                    12 { echo "Service Dependency Deleted" | Out-File $Script:Log_File -Append }
                    13 { echo "Service Dependency Failure" | Out-File $Script:Log_File -Append }
                    14 { echo "Service Disabled" | Out-File $Script:Log_File -Append }
                    15 { echo "Service Logon Failed" | Out-File $Script:Log_File -Append }
                    16 { echo "Service Marked For Deletion" | Out-File $Script:Log_File -Append }
                    17 { echo "Service No Thread" | Out-File $Script:Log_File -Append }
                    18 { echo "Status Circular Dependency" | Out-File $Script:Log_File -Append }
                    19 { echo "Status Duplicate Name" | Out-File $Script:Log_File -Append }
                    20 { echo "Status Invalid Name" | Out-File $Script:Log_File -Append }
                    21 { echo "Status Invalid Parameter" | Out-File $Script:Log_File -Append }
                    22 { echo "Status Invalid Service Account" | Out-File $Script:Log_File -Append }
                    23 { echo "Status Service Exists" | Out-File $Script:Log_File -Append }
                    24 { echo "Service Already Paused" | Out-File $Script:Log_File -Append } 
                    default { echo "$($rtn.ReturnValue) is not listed."  | Out-File $Script:Log_File -Append }
                }
            }
        }    
        Else
        {
            switch ($StopRemReg.returnvalue) {
                0 { echo "The request was accepted." | Out-File $Script:Log_File -Append }
                1 { echo "The request is not supported." | Out-File $Script:Log_File -Append }
                2 { echo "The user did not have the necessary access." | Out-File $Script:Log_File -Append }
                3 { echo "The service cannot be stopped because other services that are running are dependent on it." | Out-File $Script:Log_File -Append }
                4 { echo "The requested control code is not valid, or it is unacceptable to the service." | Out-File $Script:Log_File -Append }
                5 { echo "The requested control code cannot be sent to the service because the state of the service (Win32_BaseService.State property) is equal to 0, 1, or 2." | Out-File $Script:Log_File -Append }
                6 { echo "The service has not been started." | Out-File $Script:Log_File -Append }
                7 { echo "The service did not respond to the start request in a timely fashion." | Out-File $Script:Log_File -Append }
                8 { echo "Unknown failure when starting the service." | Out-File $Script:Log_File -Append }
                9 { echo "The directory path to the service executable file was not found." | Out-File $Script:Log_File -Append }
                10 { echo "The service is already running." | Out-File $Script:Log_File -Append }
                11 { echo "The database to add a new service is locked." | Out-File $Script:Log_File -Append }
                12 { echo "A dependency this service relies on has been removed from the system." | Out-File $Script:Log_File -Append }
                13 { echo "The service failed to find the service needed from a dependent service." | Out-File $Script:Log_File -Append }
                14 { echo "The service has been disabled from the system." | Out-File $Script:Log_File -Append }
                15 { echo "The service does not have the correct authentication to run on the system." | Out-File $Script:Log_File -Append }
                16 { echo "This service is being removed from the system." | Out-File $Script:Log_File -Append }
                17 { echo "The service has no execution thread." | Out-File $Script:Log_File -Append }
                18 { echo "The service has circular dependencies when it starts." | Out-File $Script:Log_File -Append }
                19 { echo "A service is running under the same name." | Out-File $Script:Log_File -Append }
                20 { echo "The service name has invalid characters." | Out-File $Script:Log_File -Append }
                21 { echo "Invalid parameters have been passed to the service." | Out-File $Script:Log_File -Append }
                22 { echo "The account under which this service runs is either invalid or lacks the permissions to run the service." | Out-File $Script:Log_File -Append }
                23 { echo "The service exists in the database of services available from the system." | Out-File $Script:Log_File -Append }
                24 { echo "The service is currently paused in the system." | Out-File $Script:Log_File -Append }
                default { echo "$($StopRemReg.ReturnValue) is not listed."  | Out-File $Script:Log_File -Append }
            }
        }
    }
    ElseIf ($ChangeMode -eq "Manual")
    {
        $StopRemReg = $RemReg.stopservice()
        Sleep $time
        If($StopRemReg.ReturnValue -eq 0)
        {
            echo "Stopping Remote Registry Service was Successful" | Out-File $Script:Log_File -Append
            $rtn = $RemReg.changestartmode("Manual") 
            if($rtn.returnvalue -eq 0) 
            { 
                echo "Change Start Mode to Manual was Successful" | Out-File $Script:Log_File -Append 
            }
            Else
            {
                switch ($rtn.returnvalue) {
                    0 { echo "Success" | Out-File $Script:Log_File -Append }
                    1 { echo "Not Supported" | Out-File $Script:Log_File -Append } 
                    2 { echo "Access Denied" | Out-File $Script:Log_File -Append } 
                    3 { echo "Dependent Services Running" | Out-File $Script:Log_File -Append } 
                    4 { echo "Invalid Service Control" | Out-File $Script:Log_File -Append } 
                    5 { echo "Service Cannot Accept Control" | Out-File $Script:Log_File -Append }
                    6 { echo "Service Not Active" | Out-File $Script:Log_File -Append }
                    7 { echo "Service Request Timeout" | Out-File $Script:Log_File -Append }
                    8 { echo "Unknown Failure" | Out-File $Script:Log_File -Append }
                    9 { echo "Path Not Found" | Out-File $Script:Log_File -Append }
                    10 { echo "Service Already Running" | Out-File $Script:Log_File -Append }
                    11 { echo "Service Database Locked" | Out-File $Script:Log_File -Append }
                    12 { echo "Service Dependency Deleted" | Out-File $Script:Log_File -Append }
                    13 { echo "Service Dependency Failure" | Out-File $Script:Log_File -Append }
                    14 { echo "Service Disabled" | Out-File $Script:Log_File -Append }
                    15 { echo "Service Logon Failed" | Out-File $Script:Log_File -Append }
                    16 { echo "Service Marked For Deletion" | Out-File $Script:Log_File -Append }
                    17 { echo "Service No Thread" | Out-File $Script:Log_File -Append }
                    18 { echo "Status Circular Dependency" | Out-File $Script:Log_File -Append }
                    19 { echo "Status Duplicate Name" | Out-File $Script:Log_File -Append }
                    20 { echo "Status Invalid Name" | Out-File $Script:Log_File -Append }
                    21 { echo "Status Invalid Parameter" | Out-File $Script:Log_File -Append }
                    22 { echo "Status Invalid Service Account" | Out-File $Script:Log_File -Append }
                    23 { echo "Status Service Exists" | Out-File $Script:Log_File -Append }
                    24 { echo "Service Already Paused" | Out-File $Script:Log_File -Append } 
                    default { echo "$($rtn.ReturnValue) is not listed."  | Out-File $Script:Log_File -Append }
                }
            }
        }    
        Else
        {
            switch ($StopRemReg.returnvalue) {
                0 { echo "The request was accepted." | Out-File $Script:Log_File -Append }
                1 { echo "The request is not supported." | Out-File $Script:Log_File -Append }
                2 { echo "The user did not have the necessary access." | Out-File $Script:Log_File -Append }
                3 { echo "The service cannot be stopped because other services that are running are dependent on it." | Out-File $Script:Log_File -Append }
                4 { echo "The requested control code is not valid, or it is unacceptable to the service." | Out-File $Script:Log_File -Append }
                5 { echo "The requested control code cannot be sent to the service because the state of the service (Win32_BaseService.State property) is equal to 0, 1, or 2." | Out-File $Script:Log_File -Append }
                6 { echo "The service has not been started." | Out-File $Script:Log_File -Append }
                7 { echo "The service did not respond to the start request in a timely fashion." | Out-File $Script:Log_File -Append }
                8 { echo "Unknown failure when starting the service." | Out-File $Script:Log_File -Append }
                9 { echo "The directory path to the service executable file was not found." | Out-File $Script:Log_File -Append }
                10 { echo "The service is already running." | Out-File $Script:Log_File -Append }
                11 { echo "The database to add a new service is locked." | Out-File $Script:Log_File -Append }
                12 { echo "A dependency this service relies on has been removed from the system." | Out-File $Script:Log_File -Append }
                13 { echo "The service failed to find the service needed from a dependent service." | Out-File $Script:Log_File -Append }
                14 { echo "The service has been disabled from the system." | Out-File $Script:Log_File -Append }
                15 { echo "The service does not have the correct authentication to run on the system." | Out-File $Script:Log_File -Append }
                16 { echo "This service is being removed from the system." | Out-File $Script:Log_File -Append }
                17 { echo "The service has no execution thread." | Out-File $Script:Log_File -Append }
                18 { echo "The service has circular dependencies when it starts." | Out-File $Script:Log_File -Append }
                19 { echo "A service is running under the same name." | Out-File $Script:Log_File -Append }
                20 { echo "The service name has invalid characters." | Out-File $Script:Log_File -Append }
                21 { echo "Invalid parameters have been passed to the service." | Out-File $Script:Log_File -Append }
                22 { echo "The account under which this service runs is either invalid or lacks the permissions to run the service." | Out-File $Script:Log_File -Append }
                23 { echo "The service exists in the database of services available from the system." | Out-File $Script:Log_File -Append }
                24 { echo "The service is currently paused in the system." | Out-File $Script:Log_File -Append }
                default { echo "$($StopRemReg.ReturnValue) is not listed."  | Out-File $Script:Log_File -Append }
            }
        }
    }
    Else
    {
        $StopRemReg = $RemReg.stopservice()
        Sleep $time
        If($StopRemReg.ReturnValue -eq 0)
        {
            echo "Stopping Remote Registry Service was Successful" | Out-File $Script:Log_File -Append
        }    
        Else
        {
            switch ($StopRemReg.returnvalue) {
                0 { echo "The request was accepted." | Out-File $Script:Log_File -Append }
                1 { echo "The request is not supported." | Out-File $Script:Log_File -Append }
                2 { echo "The user did not have the necessary access." | Out-File $Script:Log_File -Append }
                3 { echo "The service cannot be stopped because other services that are running are dependent on it." | Out-File $Script:Log_File -Append }
                4 { echo "The requested control code is not valid, or it is unacceptable to the service." | Out-File $Script:Log_File -Append }
                5 { echo "The requested control code cannot be sent to the service because the state of the service (Win32_BaseService.State property) is equal to 0, 1, or 2." | Out-File $Script:Log_File -Append }
                6 { echo "The service has not been started." | Out-File $Script:Log_File -Append }
                7 { echo "The service did not respond to the start request in a timely fashion." | Out-File $Script:Log_File -Append }
                8 { echo "Unknown failure when starting the service." | Out-File $Script:Log_File -Append }
                9 { echo "The directory path to the service executable file was not found." | Out-File $Script:Log_File -Append }
                10 { echo "The service is already running." | Out-File $Script:Log_File -Append }
                11 { echo "The database to add a new service is locked." | Out-File $Script:Log_File -Append }
                12 { echo "A dependency this service relies on has been removed from the system." | Out-File $Script:Log_File -Append }
                13 { echo "The service failed to find the service needed from a dependent service." | Out-File $Script:Log_File -Append }
                14 { echo "The service has been disabled from the system." | Out-File $Script:Log_File -Append }
                15 { echo "The service does not have the correct authentication to run on the system." | Out-File $Script:Log_File -Append }
                16 { echo "This service is being removed from the system." | Out-File $Script:Log_File -Append }
                17 { echo "The service has no execution thread." | Out-File $Script:Log_File -Append }
                18 { echo "The service has circular dependencies when it starts." | Out-File $Script:Log_File -Append }
                19 { echo "A service is running under the same name." | Out-File $Script:Log_File -Append }
                20 { echo "The service name has invalid characters." | Out-File $Script:Log_File -Append }
                21 { echo "Invalid parameters have been passed to the service." | Out-File $Script:Log_File -Append }
                22 { echo "The account under which this service runs is either invalid or lacks the permissions to run the service." | Out-File $Script:Log_File -Append }
                23 { echo "The service exists in the database of services available from the system." | Out-File $Script:Log_File -Append }
                24 { echo "The service is currently paused in the system." | Out-File $Script:Log_File -Append }
                default { echo "$($StopRemReg.ReturnValue) is not listed."  | Out-File $Script:Log_File -Append }
            }
        }
    }
    echo "********==========================********" | Out-File $Script:Log_File -Append
}
# ========================================================================
# Check Name 'Clear' - Clears entries prior to running the function
# ========================================================================
Function Clear
{
    $Computer = ""
    $OS = ""
    $entry = ""
    $results = ""
    $result = ""
    $found = ""
    $colItems = ""
    $objItem = ""
    $colItems2 = ""
    $objItem2 = ""
}
# ========================================================================
# Check_Users is the main function that finds the violators
# ========================================================================
Function Check_Users 
{
    New-Item -type file -force "$Script:Folder_Path\Bad_Computers_$Script:curDate.txt" | Out-Null
    $Script:Bad_Computers_File_Log = "$Script:Folder_Path\Bad_Computers_$Script:curDate.txt"
    $Script:Total_Bad_Computers = 0
    $totalTime = @()
    $htmlOutput = @()
    echo "Checking for users in HKU ..." | out-file $Script:Log_File -Append
    echo " " | out-file $Script:Log_File -Append
    $i = 0
    
    $Working = $Script:Folder_Path + "\WorkingFiles"
    If ((Test-Path $Working) -ne $True) 
    {
        New-Item -type Directory -Force $Working | Out-Null
    }
    #Creates the template
    $Script:XMLtemplate | Out-File $Script:Folder_Path\WorkingFiles\computerTemplate.xml -Encoding UTF8
    $template = "$Script:Folder_Path\WorkingFiles\computerTemplate.xml"
    $Script:xml = [xml](Get-Content -Path $Template)
    $newRun = $False #used to build the HTML
    ForEach ($Computer in $Script:Computers)
    {
        . Clear_Computer
        $newSystem = $False
        $newuserInfo = $False
        $newsysInfo = $False
        #========================================================#
        #Testing for new output
        #========================================================#
        $Script:newcomputer = $Script:xml.CreateElement("System")
        [void]$Script:newcomputer.SetAttribute("ComputerName", [string]$Computer)
        $Script:newcomputerUserinfo = $Script:xml.CreateElement("User_Info")
        #========================================================#
        #Testing for new output
        #========================================================#
        #Starts stopwatch for each computer check
        $Time = [System.Diagnostics.Stopwatch]::StartNew()
        $ping = ""
        echo "#######################################################" | Out-File $Script:Log_File -Append
        echo "###   Now Checking.... $Computer   ###" | Out-File $Script:Log_File -Append
        echo "#######################################################" | Out-File $Script:Log_File -Append
        # ========================================================================
        # Pinging the machine. If pass check for admin share access
        # ========================================================================
        $i++
        $avg = ($totaltime | Measure-Object -Average).average     
        $remaining = $computers.count - $i
        $total = $Computers.count
        $s = $avg * $remaining
        write-progress -id 1 -Activity "Pick_Up_Sticks_USB is searching through systems..." -Status "Searched $i systems out of $total... Currently on $Computer" -PercentComplete ($i / $Script:Computers.count * 100)
        
        $ping = Test-Connection -CN $Computer -Count 1 -BufferSize 16 -Quiet

        If ($ping -match 'True') 
        {
            echo "************************************************" | Out-File $Script:Log_File -Append
            echo "$Computer - ping was successful." | Out-File $Script:Log_File -Append
            $OS = gwmi -Namespace root\cimv2 -Class Win32_OperatingSystem -Impersonation 3 -ComputerName $Computer
            If ($OS -ne $Null)
            {
                $RemRegStatus = . Test_Remote_Registry $computer
                If($RemRegStatus[1] -eq "Running")
                {
                    $Script:System_Data = $False

                    $HKUrootkey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]::Users,$computer)
                        if(-not $HKUrootkey) { echo "Can't open the remote $Script:HKUroot registry hive" | Out-File $Script:Log_File -Append }

                    $HKUSubKeyNames = $HKURootKey.GetSubKeyNames()
                        if(-not $HKUSubKeyNames) { echo "Can't open $Script:HKUroot on $Computer" | Out-File $Script:Log_File -Append }
                    $j = 0
                    ForEach ($HKUSubKey in $HKUSubKeyNames)           
                    { 
                        $j++
                        . Clear_Key
                        write-progress -id 2 -parentId 1 -Activity "Searching Keys..." -Status "Searching for violations..." -PercentComplete ($j / $HKUSubKeyNames.count * 100)
                        $SID = $HKUSubKey
                        $objSID = New-Object System.Security.Principal.SecurityIdentifier($SID)
                        $objUser = $objSID.Translate([System.Security.Principal.NTAccount])
                        $User_Name = $objUser.Value
                        $point = $SID + "\$Script:MountPoints"
                        $MountKey = $HKUrootkey.OpenSubKey($SID + "\$Script:MountPoints")
                        $AppendedUser = $False
                        #========================================================#
                        #Testing for new output
                        #========================================================#
                        $Script:newcomputerUser = $Script:xml.CreateElement("User")
                        [void]$Script:newcomputerUser.SetAttribute("UserName", [String]$User_Name)
                        #========================================================#
                        #Testing for new output
                        #========================================================#

                        if ($MountKey -ne $null)
                        {
                            $mountedpoints = $MountKey.GetSubKeyNames()
                            foreach ($mountedpoint in $mountedpoints)
                            {
                                if ($mountedpoint -notmatch "##")
                                {
                                    # creates a table of mounteddevices for evaluation
                                    $Script:HKLMrootKey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$computer)
                                    if(-not $Script:HKLMrootKey) { Write-Error "Can't open the remote $root registry hive" }

                                    $HKLMsubkeyname = $Script:HKLMrootKey.opensubkey($Script:MountedDevices)
                                    if(-not $HKLMsubkeyname) { Write-Error "Can't open $($Script:HKLMroot) on $computer" }
                                    $HKLMSubKeyNames = $HKLMsubkeyname.GetValueNames()
                                    if(-not $HKLMSubKeyNames) { Write-Error "Can't open $($Script:HKLMroot) on $computer" }
                                    $k=0
                                    Foreach ($HKLMsubkey in $HKLMSubKeyNames)
                                    {
                                        $k++
                                        write-progress -id 3 -parentid 2 -Activity "Searching Mounts..." -Status "Searching for violations..." -PercentComplete ($k / $HKLMSubKeyNames.count * 100)
                                    
                                        if ($HKLMsubkey -match $mountedpoint)
                                        {
                                            $bin = $HKLMsubkeyname.GetValue($HKLMsubkey)
                                            $decoded = @()
                                            $bin | foreach {
                                            $decoded = [System.Text.Encoding]::Unicode.GetString($bin)
                                            }
                                            $USB_Whole_Name = $decoded -join ""
                                            $USB_Split_Name = $USB_Whole_Name.Split("#")
                                            $USB_Name = ""
                                            $USB_Serial = ""
                                            $USB_Name = $USB_Split_Name[1]
                                            $USB_Serial = $USB_Split_Name[2]
                                            if (($user_Name -ne $NULL) -and ($SID -ne $NULL) -and ($USB_Name -ne $NULL) -and ($USB_Serial -ne $NULL))
                                            {
                                                if (($USB_Name -notmatch "GENERIC_FLOPPY_DRIVE") -and ($USB_Name -notmatch "DTCDROM") -and ($USB_Name -notmatch "PERC") -and ($USB_Name -notmatch "DiskDELL") -and ($USB_Name -notmatch "RemovableMedia") -and ($USB_Name -notmatch "^VID_[0-9a-zA-Z][0-9a-zA-Z]&OID.*$") -and ($USB_Name -notmatch "^CdRom(?!.*HUAWEI.*).*$") -and ($USB_Name -notmatch "PERC_6") -and ($USB_Name -notmatch "Floppy") -and ($USB_Name -notmatch "vmware") -and ($USB_Name -notmatch "iDRAC") -and ($USB_Name -notmatch "O2Micro&Prod_MSPro") -and ($USB_Name -notmatch "O2Micro&Prod_SD") -and ($USB_Name -notmatch "Ricoh") -and ($USB_Name -notmatch "Prod_CardReader_SM_XD") -and ($USB_Name -notmatch "SFloppy"))
                                                {
                                                    $Script:HKLMNameKey = ""
                                                    $HKLMUSBSTORKey = ""
                                                    $HKLMFriendlyNames = ""
                                                    $HKLMFriendlyName = ""
                                                
                                                    $storkey = $Script:USBSTOR + "\" + $USB_Name + "\" + $USB_Serial + "\"

                                                    $HKLMUSBSTORKey = $Script:HKLMrootKey.opensubkey($storkey)
                                                    if(-not $HKLMUSBSTORKey) { Write-Error "Can't open $($Script:HKLMroot) on $computer" }
                                                
                                                    $HKLMFriendlyName = $HKLMUSBSTORKey.GetValue("FriendlyName")

                                                    $SubKey_Send = $SID + "\" + $Script:MountPoints

                                                    $Last_Write_Time = . Get_LastWriteTime_Reg $Computer $Script:HKU $SubKey_Send $MountedPoint
                                    
                                                    if ($Last_Write_Time -ne $Null)
                                                    {
                                                        $curLogFile = $Script:Folder_Path + '\Results\Findings\' + $Computer + '_' + $Script:curDate + '.txt'
                                                        $Script:FindingsFolder = $Script:Folder_Path + "\Results\Findings"
                                                        If ((Test-Path $Script:FindingsFolder) -ne $True) { New-Item -type Directory -Force $Script:FindingsFolder | Out-Null}
                                                        If ((Test-Path $curLogFile) -ne $True) { New-Item -type file -force $curLogFile | Out-Null }
                                                        #========================================================#
                                                        #Testing for new output
                                                        #========================================================#
                                                        If ($newRun -ne $True) {
                                                            $htmlOutput += "<!DOCTYPE html PUBLIC '-//W3C//DTD XHTML 1.0 Strict//EN'  'http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd'>"
                                                            $htmlOutput += "<html xmlns='http://www.w3.org/1999/xhtml'>"
                                                            $htmlOutput += "<head>"
                                                            $htmlOutput += "<title>Pick_Up_Sticks</title>"
                                                            $htmlOutput += "</head><body>"
                                                            $htmlOutput += "<h1>Pick_Up_Sticks_USB</h1>"
                                                            $htmlOutput += "<h3>Report Generated on $(Get-Date)</h3>"
                                                            $newRun = $True
                                                        }
                                                        
                                                        If ($newSystem -ne $True) { [void]$Script:xml.Pick_Up_Sticks.AppendChild($Script:newcomputer); $newSystem = $True;
                                                            $htmlOutput += "<table>"
                                                            $htmlOutput += "<h1>$Computer</h1>"
                                                            $htmlOutput += "</table>"
                                                        }
                                                        If ($newuserInfo -ne $True) { [void]$Script:newcomputer.AppendChild($Script:newcomputerUserinfo); $newuserInfo = $True }
                                                        If ($AppendedUser -ne $True) { [void]$Script:newcomputerUserinfo.AppendChild($Script:newcomputerUser); $AppendedUser = $True; 
                                                            . System_Info $Computer $curLogFile;
                                                            $htmlOutput += "<h2>User Name = $User_Name</h2>"
                                                            $htmlOutput += "<h2>USB Information</h2>"
                                                        }
                                                        #gets system information and creates the xml info
                                                    
                                                        $Script:newcomputerUSBinfo = $Script:xml.CreateElement("USB_Info")
                                                        [void]$Script:newcomputerUser.AppendChild($Script:newcomputerUSBinfo)
                                                    
                                                        $Script:newComputerUSBMountPoint = $Script:xml.CreateElement("MountPoint")
                                                        $Script:newComputerUSBMountPointtext = $Script:xml.CreateTextNode([string]$MountedPoint)
                                                        [void]$Script:newComputerUSBMountPoint.AppendChild($Script:newComputerUSBMountPointtext)
                                                        [void]$Script:newComputerUSBInfo.AppendChild($Script:newComputerUSBMountPoint)
                                                    
                                                        $Script:newcomputerUSBFN = $Script:xml.CreateElement("USBFriendlyName")
                                                        $Script:newcomputerUSBFNtext = $Script:xml.CreateTextNode([string]$HKLMFriendlyName)
                                                        [void]$Script:newcomputerUSBFN.AppendChild($Script:newcomputerUSBFNtext)
                                                        [void]$Script:newComputerUSBInfo.AppendChild($Script:newcomputerUSBFN)
                                                    
                                                        $Script:newcomputerUSBDev = $Script:xml.CreateElement("USB_Device")
                                                        $Script:newcomputerUSBDevtext = $Script:xml.CreateTextNode([string]$USB_Name)
                                                        [void]$Script:newcomputerUSBDev.AppendChild($Script:newcomputerUSBDevtext)
                                                        [void]$Script:newComputerUSBInfo.AppendChild($Script:newcomputerUSBDev)
                                                    
                                                        $Script:newcomputerUSBSer = $Script:xml.CreateElement("USB_Serial")
                                                        $Script:newcomputerUSBSertext = $Script:xml.CreateTextNode([string]$USB_Serial)
                                                        [void]$Script:newcomputerUSBSer.AppendChild($Script:newcomputerUSBSertext)
                                                        [void]$Script:newComputerUSBInfo.AppendChild($Script:newcomputerUSBSer)
                                                    
                                                        $Script:newcomputerUSBLWT = $Script:xml.CreateElement("LastWriteTime")
                                                        $Script:newcomputerUSBLWTtext = $Script:xml.CreateTextNode([string]$Last_Write_Time.LastWriteTime)
                                                        [void]$Script:newcomputerUSBLWT.AppendChild($Script:newcomputerUSBLWTtext)
                                                        [void]$Script:newComputerUSBInfo.AppendChild($Script:newcomputerUSBLWT)

                                                        #========================================================#
                                                        #Testing for new output
                                                        #========================================================#
                                                        #========================================================#
                                                        #Testing for new HTML Output
                                                        #========================================================#
                                                        $lwt = $Last_Write_Time.LastWriteTime
                                                        $htmlOutput += "<table>"
                                                        $htmlOutput += "<tr><td>MountPoint-------------:</td><td>$mountedpoint</td></tr>"
                                                        $htmlOutput += "<tr><td>USB Friendly Name------:</td><td>$HKLMFriendlyName</td></tr>"
                                                        $htmlOutput += "<tr><td>USB Device-------------:</td><td>$USB_Name</td></tr>"
                                                        $htmlOutput += "<tr><td>USB Serial-------------:</td><td>$USB_Serial</td></tr>"
                                                        $htmlOutput += "<tr><td>Last Write Time--------:</td><td>$lwt</td></tr>"
                                                        $htmlOutput += "<tr>========================================================================================</tr>"
                                                        $htmlOutput += "</table>"

                                                        #========================================================#
                                                        #Testing for new HTML Output
                                                        #========================================================#


                                                        echo "Computer name is - $Computer" | out-file $curLogFile -Append
                                                        echo "Looking at - $User_Name" | out-file $curLogFile -Append
                                                        echo "We searched for - $mountedpoint" | out-file $curLogFile -Append
                                                        if (($HKLMFriendlyName -ne $NULL) -and ($HKLMFriendlyName -ne "")){
                                                            echo "The USB Friendly Name is - $HKLMFriendlyName" | out-file $curLogFile -Append}
                                                        Else{ echo "There is no USB Friendly Name" | out-file $curLogFile -Append}
                                                        echo "Found this Device - $USB_Name" | out-file $curLogFile -Append
                                                        echo "The device serial is - $USB_Serial" | out-file $curLogFile -Append
                                                        echo "This device was last used - "$Last_Write_Time.LastWriteTime | out-file $curLogFile -Append

                                                        echo " " | out-file $curLogFile -Append
                                                        echo " " | out-file $curLogFile -Append
                                                        echo "=======================================================================" | Out-File $curLogFile -Append
                                                        echo "=======================================================================" | Out-File $curLogFile -Append
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    $Script:HKLMrootKey.Close()
                                    $HKLMsubkeyname.Close()
                                    $HKLMUSBSTORKey.Close()
                                    #$bin.Close()
                                }
                            } # end of foreach loop for mounted points
                        }
                    }
                }
                $HKUrootkey.Close()
                $MountKey.Close()
                $mountedpoint.Close()

                #Turn remote registry back off if it was turned off previously
                If($RemRegStatus[0] -eq "Disabled")
                {
                    . TurnOff_Remote_Registry $computer "Disabled"
                }
                ElseIf($RemRegStatus[0] -eq "Manual")
                {
                    . TurnOff_Remote_Registry $computer "Manual"
                }
                ElseIf($RemRegStatus[0] -ne "Good")
                {
                    . TurnOff_Remote_Registry $computer "Other"
                }
            }
            Else
            {
                No_Remote_Registry $Computer $Script:Bad_Computers_File_Log
                $Script:Total_Bad_Computers = $Script:Total_Bad_Computers + 1
            }
        }
        else 
        {
            . No_Ping $Computer $Script:Bad_Computers_File_Log
            $Script:Total_Bad_Computers = $Script:Total_Bad_Computers + 1
        }
        # Ends stopwatch per system and adds to Total Time Array
        $time.stop()
        $totalTime += $time.elapsed.seconds
    }
    # This removes the first portion of the template XML file.
    [void]$Script:xml.Pick_Up_Sticks.RemoveChild($Script:xml.Pick_Up_Sticks.System[0])

    #========================================================#
    #Testing for new output
    #========================================================#
    $XMLLogFile = $Script:Folder_Path + '\Results\XML_Results\' + $Script:curDate + '.xml'
    $Script:XMLFolder = $Script:Folder_Path + "\Results\XML_Results"
    
    If ($Script:xml -notcontains "0.0.0.0")
    {
        If ((Test-Path $Script:XMLFolder) -ne $True){ New-Item -type Directory -Force $Script:XMLFolder | Out-Null }
        $Script:xml.Save($XMLLogFile)
        . TransformXML
    }
    #========================================================#
    #Testing for new output
    #========================================================#
    If ($htmlOutput -ne $Null)
    {
        $htmlOutput += "<table>"
        $htmlOutput += "</table>"
        $htmlOutput += "</body></head>"
        $Script:HtmlPath = $Script:Folder_Path + "\Results\Results_" + $Script:curDate + ".html"

        $htmlOutput | out-file $Script:HtmlPath; ii $Script:HtmlPath
    }
    If($Script:IADump -eq $True)
    {
        . IADump
    }
}

# ========================================================================
# TransformXML An admin asked for the result file to be in XSL format.
# ========================================================================
Function TransformXML
{
    $Working = $Script:Folder_Path + "\WorkingFiles"
    #Creates the template
    If ((Test-Path $Working) -ne $True) 
    {
        New-Item -type Directory -Force $Working | Out-Null
    }
    $Script:xsltemplate | Out-File $Script:Folder_Path\WorkingFiles\computerTemplate.xsl
    $template = "$Script:Folder_Path\WorkingFiles\computerTemplate.xsl"
    
    $outputxml = $Script:XMLFolder + "\" + $Script:curDate + "_Converted.xml"
    $xml = $XMLLogFile
    $xsl = $template
    $output = $outputxml

    if (-not $xml -or -not $xsl -or -not $output)
    {
	    Write-Host "& .xslt.ps1 [-xml] xml-input [-xsl] xsl-input [-output] transform-output"
	    exit;
    }

    trap [Exception]
    {
	    Write-Host $_.Exception;
    }

    $xslt = New-Object System.Xml.Xsl.XslCompiledTransform;
    $xslt.Load($xsl);
    $xslt.Transform($xml, $output);

    #Write-Host "generated" $output
}
# ========================================================================
# Get_LastWriteTime_Reg connects via remote registry and pulls the last
# write time for the key that was sent as subkey
# ========================================================================
Function Get_LastWriteTime_Reg ($Computer, [string] $key, [string] $SubKey, [string] $Key_Time)
{
<#
    This function was taken from: 
    http://blog.securitywhole.com/2010/02/getting-registry-last-write-time-with_2641.html
    Written by Tim Medin
    Found: 27APR13
    
    I added the ability to connect to remote registry for the last write time.
#>
    switch ($Key) {
        "HKCR" { $searchKey = 0x80000000} #HK Classes Root
        "HKCU" { $searchKey = 0x80000001} #HK Current User
        "HKLM" { $searchKey = 0x80000002} #HK Local Machine
        "HKU"  { $searchKey = 0x80000003} #HK Users
        "HKCC" { $searchKey = 0x80000005} #HK Current Config
        default { 
            #throw "Invalid Key. Use one of the following options HKCR, HKCU, HKLM, HKU, HKCC"
        }
    }
    $KEYQUERYVALUE = 0x1
    $KEYREAD = 0x19
    $KEYALLACCESS = 0x3F
    
    $sig0 = @'
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern int RegConnectRegistry(
    string lpmachineName, 
    int hKey, 
    ref int phKResult);
'@
    $type0 = Add-Type -MemberDefinition $sig0 -Name Win32Utils `
        -Namespace RegConnectRegistry -Using System.Text -PassThru
    $sig1 = @'
    [DllImport("advapi32.dll", CharSet = CharSet.Auto)]
    public static extern int RegOpenKeyEx(
        int hKey,
        string subKey,
        int ulOptions,
        int samDesired,
        out int hkResult);
'@
    $type1 = Add-Type -MemberDefinition $sig1 -Name Win32Utils `
        -Namespace RegOpenKeyEx -Using System.Text -PassThru
    $sig2 = @'
    [DllImport("advapi32.dll", EntryPoint = "RegEnumKeyEx")]
    extern public static int RegEnumKeyEx(
        int hkey,
        int index,
        StringBuilder lpName,
        ref int lpcbName,
        int reserved,
        int lpClass,
        int lpcbClass,
        out long lpftLastWriteTime);
'@
    $type2 = Add-Type -MemberDefinition $sig2 -Name Win32Utils `
        -Namespace RegEnumKeyEx -Using System.Text -PassThru
    $sig3 = @'
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern int RegCloseKey(
        int hKey); 
'@
    $type3 = Add-Type -MemberDefinition $sig3 -Name Win32Utils `
         -Namespace RegCloseKey -Using System.Text -PassThru
    

    $phKResult = New-Object IntPtr(0)
    $Comp_Name = "\\" + $Computer
    $result = $type0::RegConnectRegistry($Comp_Name,$searchKey,[ref] $phKResult)
    $hKey = new-object int
    $result = $type1::RegOpenKeyEx($searchKey, $SubKey, 0, $KEYREAD,[ref] $hKey)

    #$searchKey, $SubKey, 0, $KEYREAD, [ref] $hKey
    #initialize variables
    $builder = New-Object System.Text.StringBuilder 1024
    $index = 0
    $length = [int] 1024
    $time = New-Object Long

    #234 means more info, 0 means success. Either way, keep reading
    while ( 0,234 -contains $type2::RegEnumKeyEx($hKey, $index++, `
        $builder, [ref] $length, $null, $null, $null, [ref] $time) )
    {
        #create output object
        $tmp = $builder.ToString()
        if ($tmp -eq $Key_Time)
        {
        $o = "" | Select Key, LastWriteTime
        $o.Key = $builder.ToString()
        $o.LastWriteTime = (Get-Date $time).AddYears(1600)
        $o
        }
        #reinitialize for next time through the loop  
        $length = [int] 1024
        $builder = New-Object System.Text.StringBuilder 1024
    }
    $result = $type3::RegCloseKey($hKey);
}


# ========================================================================
# IADump sends a copy of the results to a local share for IAM's
# ========================================================================
Function IADump
{
    # EDIT $dump to send the files to a local share
    $scanner = [Environment]::UserDomainName + "_" + [Environment]::UserName
    $curDump = $Script:Dump + "\" + $scanner + "_" + $Script:curDate
    $XMLLogFile = $Script:Folder_Path + '\Results\XML_Results\' + $Script:curDate + '.xml'
    #$Script:HtmlPath = $Script:Folder_Path + '\Results\Results_' + $Script:curDate + '.html'
    $xmldump = $curDump + "\" + $scanner + "_" + $Script:curDate + ".xml"
    $htmldump = $curDump + "\" + $scanner + "_" + $Script:curDate + ".html"
    $Script:HtmlPath = $Script:Folder_Path + "\Results\Results_" + $Script:curDate + ".html"
    
    If ($XMLLogFile -notcontains '<IP>"0.0.0.0"</IP>')
    {
        If ((Test-Path $curDump) -ne $True)
        {
            New-Item -type Directory -Force $curDump | Out-Null
        }
        #Copies the XML file over for IA
        cp $XMLLogFile $xmldump
    }
    If ((Test-Path $Script:HTMLPath) -eq $True)
    {
        If ((Test-Path $curDump) -ne $True)
        {
            New-Item -type Directory -Force $curDump | Out-Null
        }
        #Copies the HTML file over for IA
        cp $Script:HtmlPath $htmldump
    }
}
# ========================================================================
# Clear_Key clears specific variables prior to check_users is ran
# ========================================================================
Function Clear_Key
{
    $SID = ""
    $objSID = ""
    $objUser = ""
    $User_Name = ""
    $point = ""
    $MountKey = ""
    $mountedpoints = ""
    $Script:HKLMrootKey = ""
    $HKLMsubkeyname = ""
    $HKLMSubKeyNames = ""
    $bin = ""
    $decoded = ""
    $USB_Whole_Name = ""
    $USB_Split_Name = ""
    $USB_Name = ""
    $USB_Serial = ""
    $SubKey_Send = ""
    $Last_Write_Time = ""
}
# ========================================================================
# Clear_Computer clears specific variables
# ========================================================================
Function Clear_Computer
{
    $HKUrootkey = ""
    $HKUSubKeyNames = ""
    $curLogFile = ""
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
$erroractionpreference = "SilentlyContinue"
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

Write-Host "Pick_Up_Sticks_USB needs to know where to write the results to." -ForegroundColor Green
Write-Host "Please select the location to store the files." -ForegroundColor Green
. Get_Folder_Path

echo "Got folder path... Next task..." | Out-File $Script:Log_File -Append
echo " " | Out-File $Script:Log_File -Append

Write-Host " "
Write-Host "How do you want to list computers?"	-ForegroundColor Green
$strResponse = Read-Host "`n[1] All Domain Computers (Must provide Domain), `n[2] Computer names from a File, `n[3] List a SingleComputer manually"
If($strResponse -eq "1"){. ListComputers | Sort-Object}
	elseif($strResponse -eq "2"){. ListTextFile}
	elseif($strResponse -eq "3"){. SingleEntry}
	else{Write-Host "You did not supply a correct response, `
	Please run script again."; pause -foregroundColor Red}				

echo "Got computer list... Next task..." | Out-File $Script:Log_File -Append
echo " " | Out-File $Script:Log_File -Append

. Check_Users
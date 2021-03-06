Function Get-LocalAdmins {
    [Cmdletbinding()]
     Param (
        [string]$ComputerName,
        [string]$Username,
        [securestring]$SecurePassword
    )
    Begin {
        #initialize the accounts array
        $accounts = @();
        #convert securestring back to string
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        #clear securestring from memory
        $SecurePassword.Dispose()
        #Convert disabled User flags to readable format. Credit Boe Prox
        Function Convert-UserFlag {
            Param ($UserFlag)
            $List = New-Object System.Collections.ArrayList
            Switch  ($UserFlag) {
                ($UserFlag  -BOR 0x0002)  {
                    [void]$List.Add('Disabled');
                }
            }
            return $List
        }
    }# End Begin Block
    Process {
        try{
            $ports=@(135,445);
            $ports.ForEach({
                Test-NetConnection -ComputerName $ComputerName -Port $_ -InformationLevel Quiet -ErrorAction Stop -WarningAction Stop | Out-Null
            });
        }
        catch {
            throw "Port Scan: {0}" -f $_.exception.message
        }
        try {
            $endPoint = "WinNT://$ComputerName,computer"
            New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList $endPoint,$Username, $password -OutVariable computer -ErrorAction Stop | Out-Null
            $password = $null
        }
        catch {
            throw "Directory Entry: {0}" -f $_.exception.message
        }
        try {
            $groups = $computer.Children | Where-Object { $_.schemaclassname -eq 'group' }
            #I'm using the foreach construct instead of the method because the method doesn't support break
            ForEach($_ in $groups) {
                $strSID = (New-Object System.Security.Principal.SecurityIdentifier($_.objectSid.value,0)).Value
                if($strSID -eq "S-1-5-32-544") {
                    $members = @($_.Invoke("Members"))
                    break;
                }
            }
        }
        catch {
            throw "Group Memebers: {0}" -f $_.exception.message
        }
        $members.ForEach({
            $name = $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null);
            $adsPath = $_.GetType().InvokeMember("ADsPath", 'GetProperty', $null, $_, $null);
            $class= $_.GetType().InvokeMember("Class", 'GetProperty', $null, $_, $null)
            if($class -eq "user"){
                $userFlags = $_.GetType().InvokeMember("UserFlags", 'GetProperty', $null, $_, $null);
            }
            $status = Convert-UserFlag -UserFlag $userFlags
            if($status -ne "Disabled" -and $class -eq "user" ) {
                # If the account is local, then add it to the object
                if ($adsPath -like "*/$ComputerName/*") {
                    $account = "" | Select-Object Machine,Username,Enabled
                    $account.Machine = $ComputerName
                    $account.Username = $name
                    $account.Enabled = $true
                    $accounts += $account
                }
            }
        });
        return $accounts
    }#End Process Block
}#Fuction End
#we need to split the FQDN from the machine name
$computerName = $args[0].split(".")[0]
Get-LocalAdmins -ComputerName $computerName -Username $args[1] -SecurePassword (ConvertTo-SecureString $args[2] -AsPlainText -Force) -ErrorAction stop
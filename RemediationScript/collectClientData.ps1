#### Configuration ####
$azureFunctionUrl = ""
$cpuTestCycle = 10
$ramTestCycle = 10
$time = Get-Date
$runFrequenz = 1

function Get-AvgCpuUtilization($cpuTestCycle){
    $avgLoad = 0
    1..$cpuTestCycle | % {
        $avgLoad += (Get-WmiObject Win32_Processor | Measure-Object -property LoadPercentage -Average).Average
        Start-Sleep -Milliseconds 50
    }

    return @"
    {
        "cpuLoadAvg" : $(($avgLoad / $cpuTestCycle))
    }
"@
}
function Get-AvgRam($ramTestCycle){
    $totalvisiblememorysize = 0
    $freephysicalmemory = 0
    $totalvirtualmemorysize = 0
    $freevirtualmemory = 0
    1..$ramTestCycle | % {
        $ramUsage = Get-WmiObject win32_OperatingSystem
        $totalvisiblememorysize += $ramUsage.totalvisiblememorysize
        $freephysicalmemory += $ramUsage.freephysicalmemory
        $totalvirtualmemorysize += $ramUsage.totalvirtualmemorysize
        $freevirtualmemory += $ramUsage.freevirtualmemory
        Start-Sleep -Milliseconds 50
    }

    return @"
    {
        "totalPhisicalMemoryAvg" : $($totalvisiblememorysize / $ramTestCycle)
        ,"freePhisicalMemoryAvg" : $($freephysicalmemory / $ramTestCycle)
        ,"totalVirtualMemoryAvg" : $($totalvirtualmemorysize / $ramTestCycle)
        ,"freeVirtualMemoryAvg" : $($freevirtualmemory / $ramTestCycle)
    }
"@
}

function Get-CrashEvents{
    ## Add last 
    $crashes = @(Get-WinEvent -LogName Application -MaxEvents 300 -ov events | ConvertTo-CrashObject -OutVariable crashes | Select-Object TimeCreated, Computername, AppName, AppVersion, AppPath, ModuePath, ExeptionCode, AppStartTime | Where-Object {$_.Timecreated -gt ($time.AddHours(-$runFrequenz))})
    return $crashes | ConvertTo-Json
}

function Get-ValidationInfo{
		$AzureADJoinInfoRegistryKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo"
        $AzureADJoinInfoKey = Get-ChildItem -Path $AzureADJoinInfoRegistryKeyPath | Select-Object -ExpandProperty "PSChildName"
		if ($AzureADJoinInfoKey -ne $null) {
                if ([guid]::TryParse($AzureADJoinInfoKey, $([ref][guid]::Empty))) {
                    $AzureADJoinCertificate = Get-ChildItem -Path "Cert:\LocalMachine\My" -Recurse | Where-Object { $PSItem.Subject -like "CN=$($AzureADJoinInfoKey)" }
                }
                else {
                    $AzureADJoinCertificate = Get-ChildItem -Path "Cert:\LocalMachine\My" -Recurse | Where-Object { $PSItem.Thumbprint -eq $AzureADJoinInfoKey }    
                }
			if ($AzureADJoinCertificate -ne $null) {
				$AzureADDeviceID = ($AzureADJoinCertificate | Select-Object -ExpandProperty "Subject") -replace "CN=", ""
				$AzureADJoinDate = ($AzureADJoinCertificate | Select-Object -ExpandProperty "NotBefore") 
			}
		}
    $AzureADTenantInfoRegistryKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo"
	$AzureADTenantID = Get-ChildItem -Path $AzureADTenantInfoRegistryKeyPath | Select-Object -ExpandProperty "PSChildName"
	

    return @"
    {
        "aadDeviceId" : "$($AzureADDeviceID)"
        ,"aadDeviceJoinDate" : "$(($AzureADJoinDate).ToString("MM/dd/yyyy HH:mm:ss"))"
        ,"tenantId" : "$($AzureADTenantID)"
    }
"@
}


####### Start #######

$result = @"
{
    "data" : {
        "hostname" : "$($env:computername)"
        ,"cpu": $(Get-AvgCpuUtilization($cpuTestCycle))
        ,"ram" : $(Get-AvgRam($ramTestCycle))
        ,"crashes" : [$(Get-CrashEvents)]
    }
    ,"validation" : $(Get-ValidationInfo)
    ,"time" : "$($time.ToUniversalTime().ToString("MM/dd/yyyy HH:mm:ss"))"
}
"@ | ConvertFrom-Json

$result


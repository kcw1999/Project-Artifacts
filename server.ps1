Import-Module ActiveDirectory

$outputFile = "" 
$smtpServer = ""              
$smtpPort =                              
$smtpUser = "@"        
$smtpPass = ""           
$fromEmail = "@"       
$toEmail = ""         
$emailSubject = "Daily Active Directory Report" 
$emailBody = "Please find attached the exported Active Directory data." 

Write-Host "Starting Active Directory export..."
$computers = Get-ADComputer -Filter * -Property Name, OperatingSystem, LastLogonDate, DistinguishedName

$results = @()
foreach ($computer in $computers) {
    
    try {
        $ip = ([System.Net.Dns]::GetHostAddresses($computer.Name) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -ExpandProperty IPAddressToString) -join ", "
    } catch {
        $ip = "Unresolved"
    }

    
    $owner = Get-ADUser -Filter {Description -like "*$($computer.Name)*"} -Property SamAccountName, DisplayName | 
             Select-Object -ExpandProperty DisplayName

    
    $results += [PSCustomObject]@{
        Name             = $computer.Name
        IP               = $ip
        OU               = $computer.DistinguishedName
        Owner            = $owner
        LastMachineLogon = $computer.LastLogonDate
        Domain           = $env:USERDNSDOMAIN
    }
}

Write-Host "Exporting data to $outputFile..."
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Host "Active Directory data exported successfully."
Write-Host "Preparing to send email..."
try {
    $credential = New-Object PSCredential ($smtpUser, (ConvertTo-SecureString $smtpPass -AsPlainText -Force))
    Send-MailMessage -From $fromEmail -To $toEmail -Subject $emailSubject -Body $emailBody `
        -SmtpServer $smtpServer -Port $smtpPort -Credential $credential -UseSsl -Attachments $outputFile -Verbose
    Write-Host "Email sent successfully to $toEmail."
} catch {
    Write-Host "Failed to send email. Error details:"
    Write-Host $_.Exception.Message
}

Write-Host "Script execution completed."

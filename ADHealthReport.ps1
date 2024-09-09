Function ADHealthReport {
# Ensure Active Directory and ImportExcel modules are installed
try {
Import-Module ActiveDirectory -ErrorAction Stop
} catch {
Write-Host "Error: ActiveDirectory module not installed or loaded." -ForegroundColor Red
exit
}

try {
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
Install-Module -Name ImportExcel -Force -ErrorAction Stop
}
Import-Module ImportExcel -ErrorAction Stop
} catch {
Write-Host "Error: ImportExcel module not installed or failed to load." -ForegroundColor Red
exit
}

# Define the output Excel file path
$excelFilePath = "C:\ADHealthReport.xlsx"

# Verify if we can access Active Directory
try {
$forest = Get-ADForest -ErrorAction Stop
$domain = Get-ADDomain -ErrorAction Stop
} catch {
Write-Host "Error: Unable to connect to Active Directory. Please ensure you have sufficient permissions." -ForegroundColor Red
exit
}

# Function to safely collect data
function Get-SafeADData {
param (
[scriptblock]$DataRetrieval
)
try {
return & $DataRetrieval
} catch {
Write-Host "Warning: Failed to retrieve data - $($_.Exception.Message)" -ForegroundColor Yellow
return $null
}
}

# Collect basic AD data (works as before)
$dcHealth = Get-SafeADData { Get-ADDomainController -Filter * | Select-Object Name, Site, IPv4Address, OperatingSystem, IsGlobalCatalog, IsReadOnly, Domain, Forest }
$replicationStatus = Get-SafeADData { Get-ADReplicationPartnerMetadata -Target $domain.Name | Select-Object Source, Partner, Partition, TransportType, LastSyncResult }
$fsmoRoles = Get-SafeADData { Get-ADDomain | Select-Object InfrastructureMaster, PDCEmulator, RIDMaster }
$forestFsmoRoles = Get-SafeADData {
[PSCustomObject]@{
SchemaMaster = $forest.SchemaMaster
DomainNamingMaster = $forest.DomainNamingMaster
}
}

# NEW: Trust Relationships and GPO Info (no WMI access required)
$trustRelationships = Get-SafeADData { Get-ADTrust -Filter * | Select-Object Name, Direction, TrustType, IsTransitive }
$gpoStatus = Get-SafeADData {
Get-GPO -All | Select-Object DisplayName, GpoStatus, CreationTime, ModificationTime, Owner
}

# Create Excel sheets only if data is available
$excelData = @()

if ($dcHealth) {
$excelData += @{ Title = "Domain Controllers"; Data = $dcHealth }
} else {
Write-Host "Warning: Domain Controllers data is missing." -ForegroundColor Yellow
}

if ($replicationStatus) {
$excelData += @{ Title = "Replication Status"; Data = $replicationStatus }
} else {
Write-Host "Warning: Replication Status data is missing." -ForegroundColor Yellow
}

if ($fsmoRoles) {
$excelData += @{ Title = "FSMO Roles"; Data = $fsmoRoles }
} else {
Write-Host "Warning: FSMO Roles data is missing." -ForegroundColor Yellow
}

if ($forestFsmoRoles) {
$excelData += @{ Title = "Forest Level FSMO Roles"; Data = $forestFsmoRoles }
} else {
Write-Host "Warning: Forest Level FSMO Roles data is missing." -ForegroundColor Yellow
}

if ($trustRelationships) {
$excelData += @{ Title = "Trust Relationships"; Data = $trustRelationships }
} else {
Write-Host "Warning: Trust Relationships data is missing." -ForegroundColor Yellow
}

if ($gpoStatus) {
$excelData += @{ Title = "GPO Status"; Data = $gpoStatus }
} else {
Write-Host "Warning: GPO Status data is missing." -ForegroundColor Yellow
}

# Check if we have data to write
if ($excelData.Count -eq 0) {
Write-Host "Error: No data to export to Excel." -ForegroundColor Red
exit
}

# Try exporting the data to Excel
try {
foreach ($sheet in $excelData) {
$sheet.Data | Export-Excel -Path $excelFilePath -WorksheetName $sheet.Title -AutoSize -ErrorAction Stop
}
} catch {
Write-Host "Error: Failed to export data to Excel - $($_.Exception.Message)" -ForegroundColor Red
exit
}

# Apply formatting to the Excel file
try {
$workbook = Open-ExcelPackage -Path $excelFilePath -ErrorAction Stop

# Light Cyan background fill for formatting
$fill = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$bgColor = "E0FFFF"

foreach ($sheet in $workbook.Workbook.Worksheets) {
$sheet.Cells.Style.Fill.PatternType = $fill
$sheet.Cells.Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::FromName($bgColor))
$sheet.Cells.AutoFitColumns()
}

# Save and close the Excel file
Close-ExcelPackage $workbook

Write-Host "Success: Active Directory health report has been generated and saved to $excelFilePath." -ForegroundColor Green
} catch {
Write-Host "Error: Failed to format or save the Excel file - $($_.Exception.Message)" -ForegroundColor Red
exit
}
}

ADHealthReport
<#
.SYNOPSIS
  Opens the non-destructive Codex Rescue physical USB readiness GUI.

.DESCRIPTION
  Validates a selected rescue ISO against an expected SHA-256 value, requires
  exactly one online writable USB disk that is not a boot or system disk, and
  saves a JSON write plan to local non-USB storage after explicit operator
  confirmation. The script does not modify the target USB and does not launch a
  USB-writing utility.

.PARAMETER IsoPath
  Optional initial path to the verified Codex Rescue ISO.

.PARAMETER ExpectedSha256
  Expected SHA-256 for the ISO. The default is the verified alpha.13 artifact.

.EXAMPLE
  .\Open-PhysicalUsbReadinessGui.ps1 -IsoPath 'C:\Rescue\Codex-Rescue.iso'
#>

[CmdletBinding()]
param(
    [string]$IsoPath = '',

    [ValidatePattern('^[A-Fa-f0-9]{64}$')]
    [string]$ExpectedSha256 = '67E79C37021879BAE2BC405B4618B666D6FD11397227D95C111353020E64A794'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'This readiness GUI requires Windows 10 or Windows 11.'
}
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'Windows Forms requires an STA session. Use Open-PhysicalUsbReadinessGui.cmd.'
}
if (!(Get-Command Get-Disk -ErrorAction SilentlyContinue)) {
    throw 'The Windows Storage module and Get-Disk command are required.'
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

function Get-EligibleUsbDisk {
    [CmdletBinding()]
    param()

    $eligibleDisks = @(
        Get-Disk -ErrorAction Stop |
            Where-Object {
                $_.BusType -eq 'USB' -and
                !$_.IsBoot -and
                !$_.IsSystem -and
                !$_.IsOffline -and
                !$_.IsReadOnly
            } |
            Sort-Object Number
    )

    if ($eligibleDisks.Count -ne 1) {
        throw "Expected exactly one online, writable, non-system USB disk; found $($eligibleDisks.Count). Disconnect every USB storage device except the intended blank rescue drive, then refresh."
    }

    return $eligibleDisks[0]
}

function Get-DiskIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Disk
    )

    return [ordered]@{
        Number = [int]$Disk.Number
        FriendlyName = [string]$Disk.FriendlyName
        SerialNumber = ([string]$Disk.SerialNumber).Trim()
        UniqueId = ([string]$Disk.UniqueId).Trim()
        SizeBytes = [long]$Disk.Size
        BusType = [string]$Disk.BusType
        MediaType = [string]$Disk.MediaType
        PartitionStyle = [string]$Disk.PartitionStyle
    }
}

function Get-DiskFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Disk
    )

    $identity = Get-DiskIdentity -Disk $Disk
    return '{0}|{1}|{2}|{3}|{4}' -f @(
        $identity.Number,
        $identity.FriendlyName,
        $identity.SerialNumber,
        $identity.UniqueId,
        $identity.SizeBytes
    )
}

function Get-ValidatedIso {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExpectedHash
    )

    if ([IO.Path]::GetExtension($Path) -ine '.iso') {
        throw 'Select an .iso file.'
    }
    $resolvedIso = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $item = Get-Item -LiteralPath $resolvedIso -ErrorAction Stop
    if ($item.PSIsContainer -or $item.Length -le 0) {
        throw 'The selected ISO must be a non-empty file.'
    }

    $actualHash = (Get-FileHash -LiteralPath $resolvedIso -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
    if ($actualHash -cne $ExpectedHash.ToUpperInvariant()) {
        throw "ISO SHA-256 mismatch. Expected $($ExpectedHash.ToUpperInvariant()); found $actualHash."
    }

    return [ordered]@{
        Path = $resolvedIso
        FileName = $item.Name
        SizeBytes = [long]$item.Length
        Sha256 = $actualHash
    }
}

function Assert-SafePlanPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [int]$TargetDiskNumber
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($fullPath)
    if ($root -notmatch '^[A-Za-z]:\\$') {
        throw 'The plan must be saved to local non-USB storage.'
    }

    $driveLetter = $root.Substring(0, 1)
    $partitions = @(Get-Partition -DriveLetter $driveLetter -ErrorAction Stop)
    if ($partitions.Count -ne 1) {
        throw 'The plan destination could not be bound to exactly one local disk.'
    }

    $destinationDisk = Get-Disk -Number $partitions[0].DiskNumber -ErrorAction Stop
    if ($destinationDisk.Number -eq $TargetDiskNumber -or $destinationDisk.BusType -eq 'USB') {
        throw 'The plan must be saved to local non-USB storage, never to the target or another USB disk.'
    }
}

function Show-ErrorMessage {
    param([Parameter(Mandatory)][string]$Message)

    [void][Windows.Forms.MessageBox]::Show(
        $Message,
        'Codex Rescue USB readiness',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error
    )
}

$script:eligibleDisk = $null
$script:validatedDiskFingerprint = $null
$script:validatedIso = $null

$form = [Windows.Forms.Form]::new()
$form.Text = 'Codex Rescue USB - physical media readiness'
$form.ClientSize = [Drawing.Size]::new(790, 610)
$form.MinimumSize = [Drawing.Size]::new(806, 649)
$form.StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
$form.Font = [Drawing.Font]::new('Segoe UI', 10)

$title = [Windows.Forms.Label]::new()
$title.Text = 'Validate the ISO and target USB before using an external writer'
$title.Font = [Drawing.Font]::new('Segoe UI Semibold', 16)
$title.AutoSize = $true
$title.Location = [Drawing.Point]::new(22, 18)
$form.Controls.Add($title)

$boundary = [Windows.Forms.Label]::new()
$boundary.Text = 'Safety boundary: this GUI never erases or writes the target USB and never opens a writer. It saves a readiness record to local non-USB storage only.'
$boundary.AutoSize = $false
$boundary.Size = [Drawing.Size]::new(740, 46)
$boundary.Location = [Drawing.Point]::new(25, 58)
$boundary.ForeColor = [Drawing.Color]::DarkRed
$form.Controls.Add($boundary)

$isoLabel = [Windows.Forms.Label]::new()
$isoLabel.Text = 'Verified rescue ISO'
$isoLabel.AutoSize = $true
$isoLabel.Location = [Drawing.Point]::new(25, 112)
$form.Controls.Add($isoLabel)

$isoTextBox = [Windows.Forms.TextBox]::new()
$isoTextBox.Location = [Drawing.Point]::new(28, 138)
$isoTextBox.Size = [Drawing.Size]::new(630, 26)
$isoTextBox.Text = $IsoPath
$form.Controls.Add($isoTextBox)

$browseButton = [Windows.Forms.Button]::new()
$browseButton.Text = 'Browse...'
$browseButton.Location = [Drawing.Point]::new(670, 136)
$browseButton.Size = [Drawing.Size]::new(94, 30)
$form.Controls.Add($browseButton)

$hashLabel = [Windows.Forms.Label]::new()
$hashLabel.Text = "Expected SHA-256: $($ExpectedSha256.ToUpperInvariant())"
$hashLabel.AutoSize = $true
$hashLabel.Location = [Drawing.Point]::new(25, 176)
$form.Controls.Add($hashLabel)

$diskLabel = [Windows.Forms.Label]::new()
$diskLabel.Text = 'Eligible USB target (exactly one is required)'
$diskLabel.AutoSize = $true
$diskLabel.Location = [Drawing.Point]::new(25, 216)
$form.Controls.Add($diskLabel)

$diskTextBox = [Windows.Forms.TextBox]::new()
$diskTextBox.Location = [Drawing.Point]::new(28, 242)
$diskTextBox.Size = [Drawing.Size]::new(630, 82)
$diskTextBox.Multiline = $true
$diskTextBox.ReadOnly = $true
$diskTextBox.BackColor = [Drawing.Color]::White
$diskTextBox.Text = 'Not scanned.'
$form.Controls.Add($diskTextBox)

$refreshButton = [Windows.Forms.Button]::new()
$refreshButton.Text = 'Refresh USB'
$refreshButton.Location = [Drawing.Point]::new(670, 242)
$refreshButton.Size = [Drawing.Size]::new(94, 34)
$form.Controls.Add($refreshButton)

$validateButton = [Windows.Forms.Button]::new()
$validateButton.Text = 'Validate ISO + USB'
$validateButton.Location = [Drawing.Point]::new(28, 344)
$validateButton.Size = [Drawing.Size]::new(180, 36)
$validateButton.Enabled = $false
$form.Controls.Add($validateButton)

$statusTextBox = [Windows.Forms.TextBox]::new()
$statusTextBox.Location = [Drawing.Point]::new(28, 398)
$statusTextBox.Size = [Drawing.Size]::new(736, 80)
$statusTextBox.Multiline = $true
$statusTextBox.ReadOnly = $true
$statusTextBox.BackColor = [Drawing.Color]::White
$statusTextBox.Text = 'Choose the verified ISO, connect only the intended USB target, then refresh.'
$form.Controls.Add($statusTextBox)

$confirmationCheckBox = [Windows.Forms.CheckBox]::new()
$confirmationCheckBox.Text = 'I confirmed the disk number, model, serial, and size against the physical USB in my hand.'
$confirmationCheckBox.AutoSize = $true
$confirmationCheckBox.Location = [Drawing.Point]::new(28, 494)
$confirmationCheckBox.Enabled = $false
$form.Controls.Add($confirmationCheckBox)

$savePlanButton = [Windows.Forms.Button]::new()
$savePlanButton.Text = 'Save non-destructive write plan...'
$savePlanButton.Location = [Drawing.Point]::new(28, 535)
$savePlanButton.Size = [Drawing.Size]::new(260, 38)
$savePlanButton.Enabled = $false
$form.Controls.Add($savePlanButton)

$closeButton = [Windows.Forms.Button]::new()
$closeButton.Text = 'Close'
$closeButton.Location = [Drawing.Point]::new(670, 535)
$closeButton.Size = [Drawing.Size]::new(94, 38)
$form.Controls.Add($closeButton)

$resetValidation = {
    $script:validatedDiskFingerprint = $null
    $script:validatedIso = $null
    $confirmationCheckBox.Checked = $false
    $confirmationCheckBox.Enabled = $false
    $savePlanButton.Enabled = $false
}

$isoTextBox.Add_TextChanged({
    & $resetValidation
    $validateButton.Enabled = ($null -ne $script:eligibleDisk -and ![string]::IsNullOrWhiteSpace($isoTextBox.Text))
})

$browseButton.Add_Click({
    $dialog = [Windows.Forms.OpenFileDialog]::new()
    $dialog.Title = 'Select the verified Codex Rescue ISO'
    $dialog.Filter = 'ISO images (*.iso)|*.iso'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false
    if ($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {
        $isoTextBox.Text = $dialog.FileName
    }
    $dialog.Dispose()
})

$refreshButton.Add_Click({
    & $resetValidation
    $script:eligibleDisk = $null
    $validateButton.Enabled = $false
    try {
        $disk = Get-EligibleUsbDisk
        $script:eligibleDisk = $disk
        $identity = Get-DiskIdentity -Disk $disk
        $sizeGiB = [Math]::Round($identity.SizeBytes / 1GB, 2)
        $diskTextBox.Text = @(
            "Disk $($identity.Number): $($identity.FriendlyName)",
            "Serial: $($identity.SerialNumber)    Size: $sizeGiB GiB",
            "Bus: $($identity.BusType)    Media: $($identity.MediaType)    Partitions: $($identity.PartitionStyle)"
        ) -join [Environment]::NewLine
        $statusTextBox.Text = 'One eligible target is present. Select the verified ISO, then validate both items.'
        $validateButton.Enabled = ![string]::IsNullOrWhiteSpace($isoTextBox.Text)
    }
    catch {
        $diskTextBox.Text = 'No unique eligible USB target.'
        $statusTextBox.Text = $_.Exception.Message
        Show-ErrorMessage -Message $_.Exception.Message
    }
})

$validateButton.Add_Click({
    & $resetValidation
    try {
        $currentDisk = Get-EligibleUsbDisk
        if ((Get-DiskFingerprint -Disk $currentDisk) -cne (Get-DiskFingerprint -Disk $script:eligibleDisk)) {
            throw 'The USB target changed after refresh. Refresh and inspect it again.'
        }
        $script:validatedIso = Get-ValidatedIso -Path $isoTextBox.Text -ExpectedHash $ExpectedSha256
        $script:eligibleDisk = $currentDisk
        $script:validatedDiskFingerprint = Get-DiskFingerprint -Disk $currentDisk
        $statusTextBox.Text = "READY: ISO SHA-256 matches and the same one eligible USB target is present.`r`nNo disk write was performed. Confirm the physical identity below to save a plan."
        $confirmationCheckBox.Enabled = $true
    }
    catch {
        $statusTextBox.Text = "NOT READY: $($_.Exception.Message)"
        Show-ErrorMessage -Message $_.Exception.Message
    }
})

$confirmationCheckBox.Add_CheckedChanged({
    $savePlanButton.Enabled = (
        $confirmationCheckBox.Checked -and
        $null -ne $script:validatedIso -and
        $null -ne $script:validatedDiskFingerprint
    )
})

$savePlanButton.Add_Click({
    try {
        if (!$confirmationCheckBox.Checked) {
            throw 'Physical USB identity confirmation is required.'
        }

        $currentDisk = Get-EligibleUsbDisk
        $currentFingerprint = Get-DiskFingerprint -Disk $currentDisk
        if ($currentFingerprint -cne $script:validatedDiskFingerprint) {
            throw 'The USB target changed after validation. No plan was saved.'
        }

        $currentIso = Get-ValidatedIso -Path $script:validatedIso.Path -ExpectedHash $ExpectedSha256
        $diskIdentity = Get-DiskIdentity -Disk $currentDisk
        $plan = [ordered]@{
            SchemaVersion = 1
            CreatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            PlanType = 'Codex Rescue physical USB readiness'
            WritePerformed = $false
            ExternalWriterRequired = $true
            OperatorConfirmationRecorded = $true
            Iso = $currentIso
            TargetDisk = $diskIdentity
            SafetyBoundary = 'This plan does not authorize erasing or writing any disk.'
            NextStep = "In a dedicated USB-writing tool, independently re-check Disk $($diskIdentity.Number), model, serial, and size before accepting that tool's erase warning."
            RequiredHardwareValidation = @(
                'Boot the physical USB on a disposable UEFI test computer.',
                'Confirm read-only evidence collection is still the default.',
                'Record hardware inventory, export checksums, known limitations, and owner approval.'
            )
        }

        $saveDialog = [Windows.Forms.SaveFileDialog]::new()
        $saveDialog.Title = 'Save Codex Rescue USB readiness plan'
        $saveDialog.Filter = 'JSON files (*.json)|*.json'
        $saveDialog.FileName = 'Codex-Rescue-USB-write-plan.json'
        $saveDialog.OverwritePrompt = $false
        $documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
        if (![string]::IsNullOrWhiteSpace($documentsPath) -and (Test-Path -LiteralPath $documentsPath -PathType Container)) {
            $saveDialog.InitialDirectory = $documentsPath
        }
        if ($saveDialog.ShowDialog($form) -ne [Windows.Forms.DialogResult]::OK) {
            $saveDialog.Dispose()
            return
        }
        $planPath = $saveDialog.FileName
        $saveDialog.Dispose()

        if (Test-Path -LiteralPath $planPath) {
            throw 'The selected plan file already exists. Choose a new filename; existing records are never overwritten.'
        }
        Assert-SafePlanPath -Path $planPath -TargetDiskNumber $diskIdentity.Number
        $plan | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $planPath -Encoding UTF8 -NoNewline
        $statusTextBox.Text = "PLAN SAVED: $planPath`r`nWritePerformed remains false. The USB itself was not changed."
        [void][Windows.Forms.MessageBox]::Show(
            "Readiness plan saved.`r`n`r`n$planPath`r`n`r`nThe USB itself was not changed.",
            'Codex Rescue USB readiness',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Information
        )
    }
    catch {
        $statusTextBox.Text = "PLAN NOT SAVED: $($_.Exception.Message)"
        Show-ErrorMessage -Message $_.Exception.Message
    }
})

$closeButton.Add_Click({ $form.Close() })
$form.AcceptButton = $validateButton
$form.CancelButton = $closeButton

[void]$form.ShowDialog()
$form.Dispose()

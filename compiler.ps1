param (
    [string]$InputFile = "input.c",
    [string]$OutputFile = "output.asm"
)

$dataSection = New-Object System.Collections.Generic.List[string]
$output = New-Object System.Collections.Generic.List[string]
$suspiciousLines = New-Object System.Collections.Generic.List[string]
$variables = @{}

$foundPrintf = $false
$returnValue = $null

$output.Add("global main")
$output.Add("")

$lines = Get-Content $InputFile

# First pass: store variable declarations
foreach ($line in $lines) {
    $trimmed = $line.Trim()

    # Detect int variable declarations like: int x = 5;
    if ($trimmed -match '^\s*int\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(\d+)\s*;\s*$') {
        $varName = $matches[1]
        $varValue = [int]$matches[2]
        $variables[$varName] = $varValue
    }
}

# Second pass: process printf, return, and typos
foreach ($line in $lines) {
    $trimmed = $line.Trim()

    # Detect return value: return <literal or variable>;
    if ($trimmed -match '^\s*return\s+([a-zA-Z_][a-zA-Z0-9_]*|\d+)\s*;\s*$') {
        $ret = $matches[1]
        if ($ret -match '^\d+$') {
            $returnValue = [int]$ret
        } elseif ($variables.ContainsKey($ret)) {
            $returnValue = $variables[$ret]
        } else {
            $suspiciousLines.Add("⚠️ Unknown variable in return: $ret")
        }
        continue
    }

    # Match valid printf("..."); lines
    if ($trimmed -match '^\s*printf\s*\(\s*"([^"]+)"\s*\)\s*;.*$') {
        $foundPrintf = $true
        $str = $matches[1]
        $convertedStr = '`' + $str + '`'
        $label = "msg$($dataSection.Count)"
        $dataSection.Add("    $label db $convertedStr, 0")
        continue
    }

    # Detect typos
    if ($trimmed -match '\bmajn\s*\(' -or $trimmed -match '\bprintd\s*\(') {
        $suspiciousLines.Add("Possible typo detected: $trimmed")
    }

    if ($trimmed -match '\b(pr.n.tf|p.*ntf|pr.*df)\s*\(' -and -not ($trimmed -match 'printf\s*\(')) {
        $suspiciousLines.Add("Suspicious printf variant: $trimmed")
    }
}

# Show typo or logic warnings
if ($suspiciousLines.Count -gt 0) {
    Write-Warning "⚠️ Issues found in your code:"
    $suspiciousLines | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
}

# Add externs and data section if needed
if ($foundPrintf) {
    $output.Add("extern printf")
    $output.Add("section .data")
    $output.AddRange($dataSection)
    $output.Add("")
}

# Code section
$output.Add("section .text")
$output.Add("main:")
$output.Add("    sub rsp, 40")

# Insert printf calls
if ($foundPrintf) {
    for ($i = 0; $i -lt $dataSection.Count; $i++) {
        $output.Add("    lea rcx, [rel msg$i]")
        $output.Add("    call printf")
    }
}

# Final return logic
$output.Add("    add rsp, 40")

if ($null -ne $returnValue) {
    $output.Add("    mov eax, $returnValue")
} else {
    $output.Add("    xor eax, eax")
}

$output.Add("    ret")

# Write out the result
Set-Content -Path $OutputFile -Value $output -Encoding UTF8
Write-Host "✅ Generated $OutputFile with printf, return, and variable support"

# Compile
nasm -f win64 output.asm -o output.obj
gcc output.obj -o output.exe

param (
    [string]$InputFile = "input.c",
    [string]$OutputFile = "output.asm"
)

$dataSection = New-Object System.Collections.Generic.List[string]
$output = New-Object System.Collections.Generic.List[string]
$suspiciousLines = New-Object System.Collections.Generic.List[string]
$variables = @{}
$regMap = @{}
$availableRegs = @("ebx", "ecx", "edx", "esi", "edi")

$foundPrintf = $false
$returnValue = $null

$output.Add("global main")
$output.Add("")

$lines = Get-Content $InputFile

# First pass: store variables and expressions
foreach ($line in $lines) {
    $trimmed = $line.Trim()

    # Match: int x = 42;
    if ($trimmed -match '^\s*int\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+?)\s*;\s*$') {
        $varName = $matches[1]
        $expression = $matches[2]
        $variables[$varName] = $expression
        continue
    }

    # Match: return something;
    if ($trimmed -match '^\s*return\s+([a-zA-Z_][a-zA-Z0-9_]*|\d+)\s*;\s*$') {
        $returnValue = $matches[1]
        continue
    }

    # Match: printf("something");
    if ($trimmed -match '^\s*printf\s*\(\s*"([^"]+)"\s*\)\s*;.*$') {
        $foundPrintf = $true
        $str = $matches[1]
        $convertedStr = '`' + $str + '`'
        $label = "msg$($dataSection.Count)"
        $dataSection.Add("    $label db $convertedStr, 0")
        continue
    }

    # Typos
    if ($trimmed -match '\bmajn\s*\(' -or $trimmed -match '\bprintd\s*\(') {
        $suspiciousLines.Add("Possible typo detected: $trimmed")
    }
}

# Show warnings
if ($suspiciousLines.Count -gt 0) {
    Write-Warning "⚠️ Issues found in your code:"
    $suspiciousLines | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
}

# Output sections
if ($foundPrintf) {
    $output.Add("extern printf")
    $output.Add("section .data")
    $output.AddRange($dataSection)
    $output.Add("")
}

$output.Add("section .text")
$output.Add("main:")
$output.Add("    sub rsp, 40")

$unresolved = $variables.Clone()
$resolved = @{}

while ($unresolved.Count -gt 0) {
    $progress = $false

    foreach ($varName in $unresolved.Keys) {
        $expression = $unresolved[$varName].Trim()

        # Extract variable tokens from expression
        $tokens = ($expression -split '[^\w\d_]') | Where-Object { $_ -match '^[a-zA-Z_]' }

        # Check if all dependencies are already resolved
        $depsResolved = $true
        foreach ($token in $tokens) {
            if (-not $resolved.ContainsKey($token) -and -not ($token -match '^\d+$')) {
                $depsResolved = $false
                break
            }
        }

        if (-not $depsResolved) {
            continue
        }

        # OK to process now
        $destReg = $availableRegs[0]
        $availableRegs = $availableRegs[1..($availableRegs.Count - 1)]
        $regMap[$varName] = $destReg
        $resolved[$varName] = $true
        $progress = $true

        if ($expression -match '^\d+$') {
            $output.Add("    mov $destReg, $expression")
        }
        elseif ($expression -match '^\s*([a-zA-Z_][a-zA-Z0-9_]*|\d+)\s*([\+\-\*\/\^])\s*([a-zA-Z_][a-zA-Z0-9_]*|\d+)\s*$') {
            $lhs = $matches[1]
            $op = $matches[2]
            $rhs = $matches[3]

            $lhsVal = ($lhs -match '^\d+$') ? $lhs : $regMap[$lhs]
            $rhsVal = ($rhs -match '^\d+$') ? $rhs : $regMap[$rhs]

            $output.Add("    mov $destReg, $lhsVal")
            switch ($op) {
                '+' { $output.Add("    add $destReg, $rhsVal") }
                '-' { $output.Add("    sub $destReg, $rhsVal") }
                '*' { $output.Add("    imul $destReg, $rhsVal") }
                '/' {
                    $output.Add("    mov eax, $destReg")
                    $output.Add("    cdq")
                    $output.Add("    idiv $rhsVal")
                    $output.Add("    mov $destReg, eax")
                }
                '^' {
                    # Generate unique label
                    $labelBase = "pow$($varName)"
                    $loop = ".${labelBase}"
                    $done = ".${labelBase}_done"

                    $output.Add("    mov eax, $lhsVal")    # base
                    $output.Add("    mov ecx, $rhsVal")    # exponent
                    $output.Add("    mov $destReg, 1")     # result = 1

                    $output.Add($loop + ":")
                    $output.Add("    test ecx, ecx")
                    $output.Add("    jz $done")
                    $output.Add("    imul $destReg, eax")
                    $output.Add("    dec ecx")
                    $output.Add("    jmp $loop")
                    $output.Add($done + ":")
                }
            }
        }
        $unresolved.Remove($varName)
        break
    }

    if (-not $progress) {
        Write-Warning "❌ Stuck: circular or undefined dependencies in variables"
        break
    }
}

# Printfs (if used)
if ($foundPrintf) {
    for ($i = 0; $i -lt $dataSection.Count; $i++) {
        $output.Add("    lea rcx, [rel msg$i]")
        $output.Add("    call printf")
    }
}

# Return
$output.Add("    add rsp, 40")
if ($null -ne $returnValue) {
    if ($returnValue -match '^\d+$') {
        $output.Add("    mov eax, $returnValue")
    } elseif ($regMap.ContainsKey($returnValue)) {
        $output.Add("    mov eax, $($regMap[$returnValue])")
    } else {
        $output.Add("    xor eax, eax")
        Write-Warning "⚠️ Return value unknown: $returnValue"
    }
} else {
    $output.Add("    xor eax, eax")
}
$output.Add("    ret")

# Write the output file
Set-Content -Path $OutputFile -Value $output -Encoding UTF8
Write-Host "✅ Generated $OutputFile with math and return support"

# Compile
nasm -f win64 output.asm -o output.obj
gcc output.obj -o output.exe

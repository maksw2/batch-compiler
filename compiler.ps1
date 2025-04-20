param (
    [string]$InputFile = "input.c",
    [string]$OutputFile = "output.asm"
)

$dataSection = New-Object System.Collections.Generic.List[string]
$textSection = New-Object System.Collections.Generic.List[string]
$output = New-Object System.Collections.Generic.List[string]
$variables = @{}
$regMap = @{}
$availableRegs = @("ebx", "ecx", "edx", "esi", "edi", "r8d", "r9d")
$returnValue = $null
$foundPrintf = $false

$output.Add("global main")
$output.Add("")

$lines = Get-Content $InputFile

foreach ($line in $lines) {
    $trimmed = $line.Trim()

    if ($trimmed -match '^\s*printf\s*\(\s*"([^"]+)"\s*\)\s*;.*$') {
        $foundPrintf = $true
        $str = $matches[1]
        $convertedStr = '`' + $str + '`'
        $label = "msg$($dataSection.Count)"
        $dataSection.Add("    $label db $convertedStr, 0")
    }

    if ($trimmed -match '^\s*return\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*;\s*$') {
        $returnValue = $matches[1]
    }

    if ($trimmed -match '^\s*int\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+);\s*$') {
        $varName = $matches[1]
        $expression = $matches[2]
        $variables[$varName] = $expression
    }
}

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

        $tokens = ($expression -split '[^\w\d_]') | Where-Object { $_ -match '^[a-zA-Z_]' }

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

        $destReg = $availableRegs[0]
        $availableRegs = $availableRegs[1..($availableRegs.Count - 1)]
        $regMap[$varName] = $destReg
        $resolved[$varName] = $true
        $progress = $true

        # Special hack for "a ^ b - c"
        if ($expression -match '^\s*(\d+|\w+)\s*\^\s*(\d+|\w+)\s*-\s*(\d+|\w+)\s*$') {
            $base = $matches[1]
            $exp = $matches[2]
            $minus = $matches[3]

            $labelBase = "pow$($varName)"
            $loop = ".${labelBase}"
            $done = ".${labelBase}_done"

            $output.Add("    mov eax, $base")
            $output.Add("    mov ecx, $exp")
            $output.Add("    mov $destReg, 1")
            $output.Add("${loop}:")
            $output.Add("    test ecx, ecx")
            $output.Add("    jz $done")
            $output.Add("    imul $destReg, eax")
            $output.Add("    dec ecx")
            $output.Add("    jmp $loop")
            $output.Add("${done}:")
            $output.Add("    sub $destReg, $minus")
            $unresolved.Remove($varName)
            break
        }

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
                    $labelBase = "pow$($varName)"
                    $loop = ".${labelBase}"
                    $done = ".${labelBase}_done"

                    $output.Add("    mov eax, $lhsVal")
                    $output.Add("    mov ecx, $rhsVal")
                    $output.Add("    mov $destReg, 1")
                    $output.Add("${loop}:")
                    $output.Add("    test ecx, ecx")
                    $output.Add("    jz $done")
                    $output.Add("    imul $destReg, eax")
                    $output.Add("    dec ecx")
                    $output.Add("    jmp $loop")
                    $output.Add("${done}:")
                }
            }
        }
        else {
            Write-Warning "⚠️ Unable to parse expression for variable '$varName': $expression"
        }

        $unresolved.Remove($varName)
        break
    }

    if (-not $progress) {
        Write-Warning "❌ Stuck: circular or undefined dependencies in variables"
        break
    }
}

# Add printf calls if present
if ($foundPrintf) {
    for ($i = 0; $i -lt $dataSection.Count; $i++) {
        $output.Add("    lea rcx, [rel msg$i]")
        $output.Add("    call printf")
    }
}

$output.Add("    add rsp, 40")

if ($null -ne $returnValue) {
    if ($regMap.ContainsKey($returnValue)) {
        $output.Add("    mov eax, $($regMap[$returnValue])")
    } elseif ($returnValue -match '^\d+$') {
        $output.Add("    mov eax, $returnValue")
    } else {
        Write-Warning "⚠️ Return value unknown: $returnValue"
        $output.Add("    xor eax, eax")
    }
} else {
    $output.Add("    xor eax, eax")
}

$output.Add("    ret")

Set-Content -Path $OutputFile -Value $output -Encoding UTF8

Write-Host "✅ Generated $OutputFile with math, return value, and printf support"

nasm -f win64 output.asm -o output.obj
gcc output.obj -o output.exe

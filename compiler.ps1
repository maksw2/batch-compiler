param (
    [string]$InputFile = "input.c",
    [string]$OutputFile = "output.asm"
)

# Helper function to ensure strings are enclosed in backquotes for NASM
function Convert-SpecialChars {
    param ($str)

    # Return the string enclosed in backquotes (`` ` ``) for NASM processing
    return "`"$str`""  # Ensure the string is enclosed in backquotes (`` ` ``)
}

$dataSection = New-Object System.Collections.Generic.List[string]
$textSection = New-Object System.Collections.Generic.List[string]
$output = New-Object System.Collections.Generic.List[string]

$dataSection.Add("section .data")
$textSection.Add("section .text")
$textSection.Add("global main")
$textSection.Add("extern printf")
$textSection.Add("")
$textSection.Add("main:")
$textSection.Add("    sub rsp, 40")  # Windows ABI shadow space

$printfCounter = 0
$lines = Get-Content $InputFile

foreach ($line in $lines) {
    $trimmed = $line.Trim()

    # Match printf("..."); lines
    if ($trimmed -match '^\s*printf\s*\(\s*"([^"]+)"\s*\)\s*;.*$') {
        $str = $matches[1]
        
        # Ensure the string is enclosed in backquotes (`` ` ``) for NASM
        $convertedStr = '`' + $str + '`'  # Manually use backquotes here instead of double quotes

        # Create a label for the string
        $label = "str$printfCounter"
        
        # Add the converted string to the .data section with backquotes
        $dataSection.Add("$label db $convertedStr, 0")
        
        # Add the printf call in the .text section
        $textSection.Add("    lea rcx, [rel $label]")
        $textSection.Add("    call printf")
        
        $printfCounter++
    }
}

# Add return code and restore stack
$textSection.Add("    xor eax, eax")
$textSection.Add("    add rsp, 40")
$textSection.Add("    ret")

# Combine all sections
$output.AddRange($dataSection)
$output.Add("")
$output.AddRange($textSection)

# Write the output to the .asm file
Set-Content -Path $OutputFile -Value $output -Encoding UTF8

Write-Host "✅ Generated $OutputFile using printf, with special characters handled"

# Execute NASM
& "C:\Program Files\NASM\nasm.exe" -f win64 output.asm

# Execute GCC
gcc output.obj -o output.exe

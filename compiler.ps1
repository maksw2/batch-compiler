param (
    [string]$InputFile = "input.c",
    [string]$OutputFile = "output.asm"
)

$dataSection = New-Object System.Collections.Generic.List[string]
$textSection = New-Object System.Collections.Generic.List[string]
$output = New-Object System.Collections.Generic.List[string]

$foundPrintf = $false  # Flag to track if printf was used

# Add externs and globals first, as per your request
$output.Add("global main")
$output.Add("")  # Blank line between sections

# Check if printf() exists in input file and handle accordingly
$lines = Get-Content $InputFile

# Add .data section if any printf calls are found
foreach ($line in $lines) {
    $trimmed = $line.Trim()

    # Match printf("..."); lines
    if ($trimmed -match '^\s*printf\s*\(\s*"([^"]+)"\s*\)\s*;.*$') {
        $foundPrintf = $true

        $str = $matches[1]
        
        # Ensure the string is enclosed in backquotes (`` ` ``) for NASM
        $convertedStr = '`' + $str + '`'  # Manually use backquotes here instead of double quotes

        # Create a label for the string
        $label = "msg$($dataSection.Count)"
        
        # Add the converted string to the .data section with backquotes
        $dataSection.Add("    $label db $convertedStr, 0")
    }
}

# Only add .data section if printf was used
if ($foundPrintf) {
    $output.Add("extern printf")
    $output.Add("section .data")
    $output.AddRange($dataSection)
    $output.Add("")  # Blank line after .data section
}

# Add .text section and main function
$output.Add("section .text")
$output.Add("main:")

# Adding the necessary instructions for main
$output.Add("    sub rsp, 40")  # Windows ABI shadow space

# Add printf calls for each string in .data
if ($foundPrintf) {
    for ($i = 0; $i -lt $dataSection.Count; $i++) {
        $output.Add("    lea rcx, [rel msg$i]")  # Load address of the string into rcx
        $output.Add("    call printf")  # Call printf with the string
    }
}

# End of main function: clean up and return
$output.Add("    add rsp, 40")  # Restore stack space
$output.Add("    xor eax, eax")  # Return value 0
$output.Add("    ret")  # Return from main

# Write the output to the .asm file
Set-Content -Path $OutputFile -Value $output -Encoding UTF8

Write-Host "✅ Generated $OutputFile using printf, with special characters handled"

# Execute NASM
nasm -f win64 output.asm -o output.obj

# Execute GCC to link the object file and generate the executable
gcc output.obj -o output.exe

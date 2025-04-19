param (
    [string]$InputFile = "input.c",
    [string]$OutputFile = "output.asm"
)

$dataSection = New-Object System.Collections.Generic.List[string]
$textSection = New-Object System.Collections.Generic.List[string]
$output = New-Object System.Collections.Generic.List[string]

# Add externs and globals first, as per your request
$output.Add("extern printf")
$output.Add("global main")
$output.Add("")  # Blank line between sections

# Add .data section
$dataSection.Add("section .data")

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
        $label = "msg$printfCounter"
        
        # Add the converted string to the .data section with backquotes
        $dataSection.Add("    $label db $convertedStr, 0")
        
        $printfCounter++
    }
}

# Add .data section to the output
$output.AddRange($dataSection)
$output.Add("")  # Blank line

# Add .text section and main function
$textSection.Add("section .text")
$textSection.Add("main:")

# Adding the necessary instructions for main
$textSection.Add("    sub rsp, 40")  # Windows ABI shadow space

# Add printf calls for each string in .data
foreach ($i in 0..($printfCounter - 1)) {
    $textSection.Add("    lea rcx, [rel msg$i]")  # Load address of the string into rcx
    $textSection.Add("    call printf")  # Call printf with the string
}

# End of main function: clean up and return
$textSection.Add("    add rsp, 40")  # Restore stack space
$textSection.Add("    xor eax, eax")  # Return value 0
$textSection.Add("    ret")  # Return from main

# Add .text section to the output
$output.AddRange($textSection)

# Write the output to the .asm file
Set-Content -Path $OutputFile -Value $output -Encoding UTF8

Write-Host "✅ Generated $OutputFile using printf, with special characters handled"

# Execute NASM
& "C:\Program Files\NASM\nasm.exe" -f win64 output.asm -o output.obj

# Execute GCC to link the object file and generate the executable
gcc output.obj -o output.exe

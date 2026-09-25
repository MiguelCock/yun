# Builds the tree-sitter runtime and grammar static libraries for one Windows
# target using MSVC (cl + lib). Run from a "Developer Command Prompt" / after
# `ilammy/msvc-dev-cmd`, so that cl and lib are on PATH.
#
# Usage: scripts/build-tree-sitter-windows.ps1 [-Target windows-x64]

param(
    [string]$Target = "windows-x64"
)

$ErrorActionPreference = "Stop"

# $PSScriptRoot is <repo>/scripts
$root = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $root "lib/tree_sitter.c3l/upstream"
$runtimeInclude = Join-Path $runtimeDir "lib/include"

function Build-TreeSitterLib {
    param(
        [string]$Name,
        [string]$SourceDir,
        [string]$OutDir
    )

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $srcRoot = Join-Path $SourceDir "src"

    $sources = @()
    foreach ($candidate in @("parser.c", "scanner.c", "scanner.cc")) {
        $path = Join-Path $srcRoot $candidate
        if (Test-Path $path) { $sources += $path }
    }

    $objects = @()
    $index = 0
    foreach ($source in $sources) {
        $object = Join-Path $OutDir "$Name-$index.obj"
        cl /nologo /c /O2 /I"$runtimeInclude" /I"$srcRoot" /Fo"$object" "$source"
        $objects += $object
        $index++
    }

    $libPath = Join-Path $OutDir "$Name.lib"
    lib /nologo /OUT:"$libPath" @objects
    Remove-Item $objects -Force
    Write-Host "built $libPath"
}

$runtimeOut = Join-Path $root "lib/tree_sitter.c3l/linked-libs/$Target"
New-Item -ItemType Directory -Force -Path $runtimeOut | Out-Null
cl /nologo /c /O2 /I"$runtimeInclude" /Fo"$runtimeOut/tree-sitter.obj" (Join-Path $runtimeDir "lib/src/lib.c")
lib /nologo /OUT:"$runtimeOut/tree-sitter.lib" "$runtimeOut/tree-sitter.obj"
Remove-Item "$runtimeOut/tree-sitter.obj" -Force
Write-Host "built $runtimeOut/tree-sitter.lib"

Build-TreeSitterLib "tree-sitter-c" (Join-Path $root "lib/tree_sitter_c.c3l/upstream") (Join-Path $root "lib/tree_sitter_c.c3l/linked-libs/$Target")
Build-TreeSitterLib "tree-sitter-python" (Join-Path $root "lib/tree_sitter_python.c3l/upstream") (Join-Path $root "lib/tree_sitter_python.c3l/linked-libs/$Target")
Build-TreeSitterLib "tree-sitter-javascript" (Join-Path $root "lib/tree_sitter_javascript.c3l/upstream") (Join-Path $root "lib/tree_sitter_javascript.c3l/linked-libs/$Target")
Build-TreeSitterLib "tree-sitter-c3" (Join-Path $root "lib/tree_sitter_c3.c3l/upstream") (Join-Path $root "lib/tree_sitter_c3.c3l/linked-libs/$Target")

Write-Host "done ($Target)"

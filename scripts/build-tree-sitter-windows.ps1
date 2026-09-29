# Builds the tree-sitter runtime and grammar libraries for one Windows target
# using MSVC (cl + link). Run from a "Developer Command Prompt" / after
# `ilammy/msvc-dev-cmd`, so that cl and link are on PATH.
#
# Grammars are discovered from lib/tree_sitter_*.c3l (each with an upstream/
# submodule). Optional per-grammar options live in that directory's
# grammar.conf (key=value): src, queries, lib.
#
# The runtime is always static; grammars build as DLLs by default (loaded lazily
# at runtime) or static .lib with -Static.
#
# Usage: scripts/build-tree-sitter-windows.ps1 [-Target windows-x64] [-Grammar python,c3] [-Static]

param(
    [string]$Target = "windows-x64",
    [string[]]$Grammar = @(),
    [switch]$Static
)

$ErrorActionPreference = "Stop"

# $PSScriptRoot is <repo>/scripts
$root = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $root "lib/tree_sitter.c3l/upstream"
$runtimeInclude = Join-Path $runtimeDir "lib/include"

function Read-GrammarConf {
    param([string]$Path, [string]$Key, [string]$Fallback)

    if (-not (Test-Path $Path)) { return $Fallback }
    foreach ($line in Get-Content $Path) {
        if ($line -match "^\s*$Key\s*=\s*(.+?)\s*$") { return $Matches[1] }
    }
    return $Fallback
}

function Build-TreeSitterLib {
    param(
        [string]$Name,
        [string]$SourceDir,
        [string]$SrcRoot,
        [string]$OutDir,
        [string]$ExportSymbol
    )

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $rootPath = Join-Path $SourceDir $SrcRoot

    $sources = @()
    foreach ($candidate in @("parser.c", "scanner.c", "scanner.cc")) {
        $path = Join-Path $rootPath $candidate
        if (Test-Path $path) { $sources += $path }
    }
    if ($sources.Count -eq 0) {
        Write-Warning "no parser.c under $rootPath; skipping $Name"
        return
    }

    $objects = @()
    $index = 0
    foreach ($source in $sources) {
        $object = Join-Path $OutDir "$Name-$index.obj"
        cl /nologo /c /O2 /I"$runtimeInclude" /I"$rootPath" /Fo"$object" "$source"
        $objects += $object
        $index++
    }

    if ($Static) {
        $libPath = Join-Path $OutDir "$Name.lib"
        lib /nologo /OUT:"$libPath" @objects
        Write-Host "built $libPath"
    }
    else {
        $dllPath = Join-Path $OutDir "$Name.dll"
        if ($ExportSymbol) {
            link /nologo /DLL /OUT:"$dllPath" "/EXPORT:$ExportSymbol" @objects
        }
        else {
            link /nologo /DLL /OUT:"$dllPath" @objects
        }
        Write-Host "built $dllPath"
    }
    Remove-Item $objects -Force
}

$runtimeOut = Join-Path $root "lib/tree_sitter.c3l/linked-libs/$Target"
New-Item -ItemType Directory -Force -Path $runtimeOut | Out-Null
cl /nologo /c /O2 /I"$runtimeInclude" /Fo"$runtimeOut/tree-sitter.obj" (Join-Path $runtimeDir "lib/src/lib.c")
lib /nologo /OUT:"$runtimeOut/tree-sitter.lib" "$runtimeOut/tree-sitter.obj"
Remove-Item "$runtimeOut/tree-sitter.obj" -Force
Write-Host "built $runtimeOut/tree-sitter.lib"

foreach ($dep in Get-ChildItem (Join-Path $root "lib") -Directory -Filter "tree_sitter_*.c3l") {
    $stem = $dep.Name.Substring("tree_sitter_".Length)
    $stem = $stem.Substring(0, $stem.Length - ".c3l".Length)
    $stem = $stem.Replace("_", "-")

    if ($Grammar.Count -gt 0 -and ($Grammar -notcontains $stem)) { continue }

    $conf = Join-Path $dep.FullName "grammar.conf"
    $srcRoot = Read-GrammarConf $conf "src" "src"
    $lib = Read-GrammarConf $conf "lib" "tree-sitter-$stem"

    $export = ""
    $c3i = Get-ChildItem (Join-Path $dep.FullName "*.c3i") -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c3i) {
        $match = Select-String -Path $c3i.FullName -Pattern 'extern fn TSLanguage\*\s+(\w+)\('
        if ($match) { $export = $match.Matches[0].Groups[1].Value }
    }

    $out = Join-Path $dep.FullName "linked-libs/$Target"
    $mode = if ($Static) { "static" } else { "shared" }
    Write-Host "building $lib for $Target ($mode)"
    Build-TreeSitterLib $lib (Join-Path $dep.FullName "upstream") $srcRoot $out $export
}

Write-Host "done ($Target)"

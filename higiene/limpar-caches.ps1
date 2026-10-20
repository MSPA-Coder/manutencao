[CmdletBinding()]
param(
    [string]$RaizProjetos = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$Saida,
    [switch]$Aplicar
)

$ErrorActionPreference = 'Stop'
$raiz = (Resolve-Path -LiteralPath $RaizProjetos).Path.TrimEnd('\', '/')
if (-not $Saida) {
    $Saida = Join-Path $raiz ('CodexTemp/higiene-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$saidaAbsoluta = [IO.Path]::GetFullPath($Saida)
if (-not $saidaAbsoluta.StartsWith($raiz + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'A saída precisa ficar dentro da raiz dos projetos.'
}
New-Item -ItemType Directory -Path $saidaAbsoluta -Force | Out-Null
$registro = Join-Path $saidaAbsoluta 'caches.csv'
if (Test-Path -LiteralPath $registro) { throw 'Escolha uma saída nova para preservar o registro anterior.' }

function Ler-Git([string]$Repositorio, [string[]]$Argumentos) {
    $linhas = @(& git -c core.quotepath=false -C $Repositorio @Argumentos)
    if ($LASTEXITCODE -ne 0) { throw "Falha no Git: $Repositorio" }
    return $linhas
}

function Tem-LinkNoCaminho([string]$Caminho, [string]$Limite) {
    $atual = Get-Item -LiteralPath $Caminho -Force
    while ($null -ne $atual) {
        if ($atual.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $true }
        if ($atual.FullName -eq $Limite) { return $false }
        $atual = $atual.Parent
    }
    throw 'Caminho não alcançou o limite esperado.'
}

$resultados = foreach ($repo in Get-ChildItem -LiteralPath $raiz -Directory -Force) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo.FullName '.git'))) { continue }
    if (Tem-LinkNoCaminho $repo.FullName $raiz) { continue }
    $topo = @(Ler-Git $repo.FullName @('rev-parse', '--show-toplevel'))
    if ([IO.Path]::GetFullPath($topo[0]).TrimEnd('\', '/') -ne $repo.FullName) {
        throw "Raiz Git inesperada: $($repo.FullName)"
    }
    $ignorados = @(Ler-Git $repo.FullName @('ls-files', '--others', '--ignored', '--exclude-standard'))
    $candidatos = foreach ($rel in $ignorados) {
        # Ambientes e dependências pertencem ao runtime; não limpar por dentro.
        if ($rel -match '(^|/)(\.git|CodexTemp|\.venv[^/]*|venv[^/]*|env|ENV|env\.bak|node_modules|\.secrets|\.certs|backups|instance|media|uploads|logs|staticfiles|dist|build|release)(/|$)') { continue }
        if ($rel -match '^(?<cache>.*?(?:^|/)(?:__pycache__|\.pytest_cache|\.ruff_cache|\.mypy_cache))/') {
            $Matches.cache
        }
    }
    foreach ($rel in @($candidatos | Sort-Object -Unique)) {
        $alvo = [IO.Path]::GetFullPath((Join-Path $repo.FullName $rel))
        if (-not $alvo.StartsWith($repo.FullName + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Cache fora do repositório: $alvo"
        }
        if (-not (Test-Path -LiteralPath $alvo -PathType Container)) { continue }
        if (Tem-LinkNoCaminho $alvo $raiz) { throw "Link na árvore do cache: $alvo" }
        $itens = @(Get-ChildItem -LiteralPath $alvo -Recurse -Force)
        if (@($itens | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count) {
            throw "Link dentro do cache: $alvo"
        }
        $rastreados = @(Ler-Git $repo.FullName @('ls-files', '--cached', '--', $rel))
        $naoIgnorados = @(Ler-Git $repo.FullName @('ls-files', '--others', '--exclude-standard', '--', $rel))
        if ($rastreados.Count -or $naoIgnorados.Count) { throw "Cache contém arquivos protegidos: $alvo" }
        $arquivos = @($itens | Where-Object {-not $_.PSIsContainer})
        $linha = [pscustomobject]@{
            projeto=$repo.Name; caminho=$alvo; arquivos=$arquivos.Count
            bytes=[long](($arquivos | Measure-Object Length -Sum).Sum)
            acao=$(if ($Aplicar) {'removido'} else {'simulacao'})
        }
        if ($Aplicar) { Remove-Item -LiteralPath $alvo -Recurse -Force }
        $linha | Export-Csv -LiteralPath $registro -NoTypeInformation -Append -Encoding utf8
        $linha
    }
}
if (-not $resultados) { Write-Output 'Nenhum cache descartável encontrado.' }
else { $resultados | Format-Table projeto,caminho,arquivos,bytes,acao -AutoSize }

param(
    [string]$RaizProjetos = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$Saida,
    [string[]]$Projetos = @('SharedAuth', 'FinancasMCP', 'BackupRestore', 'Site_Mp-solucoes', 'MegaSena', 'ConfortoTermico', 'ControleRendaVariavel', 'ControleBancario')
)

$ErrorActionPreference = 'Stop'
if (-not $Saida) {
    $Saida = Join-Path $RaizProjetos ('CodexTemp\validacao-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$Saida = [System.IO.Path]::GetFullPath($Saida)
New-Item -ItemType Directory -Force -Path $Saida | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'cobertura.py') -Destination (Join-Path $Saida 'coverage_runner.py')

# Ferramenta externa à aplicação, instalada somente por um contêiner.
# O mesmo coletor é montado somente para leitura em cada imagem de qualidade.
if (-not (Test-Path -LiteralPath (Join-Path $Saida 'coverage-tool\coverage\__init__.py'))) {
    & docker run --rm --mount "type=bind,source=$Saida,target=/evidence" python:3.15-slim `
        python -m pip install --no-cache-dir --target /evidence/coverage-tool coverage==7.16.2
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível preparar a instrumentação Docker.' }
}

$configuracoes = @{
    SharedAuth = @{ Fontes = 'sharedauth'; Comando = 'ruff check . && python /validation/coverage_runner.py' }
    FinancasMCP = @{ Fontes = 'financas_mcp'; Comando = 'ruff check . && python /validation/coverage_runner.py' }
    BackupRestore = @{ Fontes = '/workspace'; Comando = 'python /validation/coverage_runner.py' }
    'Site_Mp-solucoes' = @{ Fontes = 'institucional'; Comando = 'ruff check . && ruff format --check . && python /validation/coverage_runner.py' }
    MegaSena = @{ Fontes = 'app'; Ambiente = '.env.docker'; Comando = 'ruff check . && mypy && python /validation/coverage_runner.py' }
    ConfortoTermico = @{ Fontes = 'app'; Ambiente = '.env.docker'; Comando = 'ruff check . && mypy && python /validation/coverage_runner.py' }
    ControleRendaVariavel = @{ Fontes = 'app'; Comando = 'ruff check . && mypy && python /validation/coverage_runner.py' }
    ControleBancario = @{ Fontes = 'accounts,bank_statements,banking,core,dashboard,financeiro,management,reports,transactions'; Ambiente = '.env.docker'; Comando = 'ruff check . && mypy && python /validation/coverage_runner.py' }
}

$falhas = @()
foreach ($projeto in $Projetos) {
    if (-not $configuracoes.ContainsKey($projeto)) { throw "Projeto desconhecido: $projeto" }
    $configuracao = $configuracoes[$projeto]
    $pasta = Join-Path $RaizProjetos $projeto
    $argumentos = @('compose')
    if ($configuracao.Ambiente) { $argumentos += @('--env-file', $configuracao.Ambiente) }
    $argumentos += @('-f', 'compose.yaml', '--profile', 'quality', 'run', '--build', '--rm')
    if ($projeto -in @('SharedAuth', 'BackupRestore', 'Site_Mp-solucoes')) { $argumentos += '--no-deps' }
    $argumentos += @(
        '-e', 'PYTHONPATH=/validation/coverage-tool',
        '-e', "VALIDATION_PROJECT=$projeto", '-e', "VALIDATION_SOURCES=$($configuracao.Fontes)",
        '-v', "${Saida}:/validation:ro", '-v', "${Saida}:/evidence",
        'quality', 'sh', '-ec', $configuracao.Comando
    )
    # Dois pytest-django simultâneos criam/derrubam o mesmo test_<banco>.
    # Serialize as rodadas deste script por projeto; projetos distintos seguem livres.
    $mutex = [System.Threading.Mutex]::new($false, "Local\CodexValidation-$projeto")
    $obteveTrava = $false
    try { $obteveTrava = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $obteveTrava = $true }
    if (-not $obteveTrava) {
        $mutex.Dispose()
        throw "Já há uma validação em execução para $projeto. Aguarde sua conclusão."
    }
    Push-Location -LiteralPath $pasta
    try {
        $log = Join-Path $Saida "$projeto-coverage.log"
        & docker @argumentos *> $log
        $codigo = $LASTEXITCODE
        $identidade = @{
            projeto = $projeto
            commit = (& git rev-parse HEAD)
            alteracoes = @(& git status --short)
            argumentos_docker = $argumentos
            codigo_saida = $codigo
        }
        $identidade | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Saida "$projeto-execucao.json") -Encoding utf8
        Write-Output "$projeto : código $codigo; evidência em $log"
        Get-Content -LiteralPath $log -Tail 26
        if ($codigo -ne 0) { $falhas += $projeto }
    } finally {
        Pop-Location
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}
if ($falhas.Count) { throw "Validação reprovada: $($falhas -join ', ')" }

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

function Write-Step([string]$Text) {
  Write-Host ""
  Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Require-Command([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Не найдена программа '$Name'."
  }
}

Write-Host "Публикация интерактивной презентации" -ForegroundColor Green
Write-Host "Скрипт не сохраняет секрет Supabase в GitHub."

Require-Command "git"
Require-Command "gh"
Require-Command "npx.cmd"

Write-Step "1. Проверка входа в GitHub"
& gh auth status
if ($LASTEXITCODE -ne 0) {
  throw "Сначала войдите в GitHub: gh auth login --hostname github.com --git-protocol https --web --clipboard"
}

$repositoryName = Read-Host "Название публичного репозитория [gamification-live]"
if ([string]::IsNullOrWhiteSpace($repositoryName)) { $repositoryName = "gamification-live" }
if ($repositoryName -notmatch '^[A-Za-z0-9._-]+$') {
  throw "Название репозитория содержит недопустимые символы."
}

$origin = (& git remote get-url origin 2>$null)
if ([string]::IsNullOrWhiteSpace($origin)) {
  Write-Host "Создаю публичный репозиторий и отправляю локальные файлы..."
  & gh repo create $repositoryName --public --source . --remote origin --push --description "Interactive presentation about gamification"
  if ($LASTEXITCODE -ne 0) { throw "Не удалось создать репозиторий GitHub." }
} else {
  Write-Host "Репозиторий уже подключен: $origin"
  & git push -u origin main
  if ($LASTEXITCODE -ne 0) { throw "Не удалось отправить файлы в GitHub." }
}

$repository = (& gh repo view --json nameWithOwner --jq .nameWithOwner).Trim()
if ([string]::IsNullOrWhiteSpace($repository)) { throw "Не удалось определить адрес репозитория." }

& gh api "repos/$repository/pages" *> $null
if ($LASTEXITCODE -ne 0) {
  $pagesBody = @{ build_type = "legacy"; source = @{ branch = "main"; path = "/" } } | ConvertTo-Json -Compress
  $pagesBody | & gh api --method POST "repos/$repository/pages" --input - *> $null
  if ($LASTEXITCODE -ne 0) {
    throw "Не удалось включить GitHub Pages. Включите Settings → Pages → Deploy from a branch → main → /(root)."
  }
}
Write-Host "GitHub Pages включен."

Write-Step "2. Подключение Supabase"
Write-Host "До продолжения создайте бесплатный проект: https://database.new"
Write-Host "Дождитесь статуса Project is ready."
Read-Host "Нажмите Enter, когда проект готов"

& npx.cmd --yes supabase@latest projects list *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Сейчас Supabase попросит войти в аккаунт или вставить Personal Access Token."
  & npx.cmd --yes supabase@latest login
  if ($LASTEXITCODE -ne 0) { throw "Вход в Supabase не завершён." }
}

$projectRef = Read-Host "Project ref из Supabase (Settings → General → Reference ID)"
if ($projectRef -notmatch '^[a-z0-9]{10,32}$') { throw "Project ref выглядит неверно." }

& npx.cmd --yes supabase@latest link --project-ref $projectRef
if ($LASTEXITCODE -ne 0) { throw "Не удалось подключить проект Supabase." }

Write-Host "Проверяю миграцию..."
& npx.cmd --yes supabase@latest db push --dry-run
if ($LASTEXITCODE -ne 0) { throw "Проверка базы данных не прошла." }

Write-Host "Создаю таблицы и серверную защиту таймаута..."
& npx.cmd --yes supabase@latest db push
if ($LASTEXITCODE -ne 0) { throw "Не удалось применить миграцию базы данных." }

$presenterToken = ([guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N"))
& npx.cmd --yes supabase@latest secrets set "PRESENTER_TOKEN=$presenterToken" --project-ref $projectRef
if ($LASTEXITCODE -ne 0) { throw "Не удалось сохранить код ведущей." }

Write-Host "Публикую серверную функцию..."
& npx.cmd --yes supabase@latest functions deploy presentation-api --no-verify-jwt --project-ref $projectRef --use-api
if ($LASTEXITCODE -ne 0) { throw "Не удалось опубликовать серверную функцию." }

$publishableKey = Read-Host "Publishable key из Supabase (кнопка Connect → Publishable key)"
if ([string]::IsNullOrWhiteSpace($publishableKey)) { throw "Publishable key не указан." }

$projectUrl = "https://$projectRef.supabase.co"
$config = @"
window.PRESENTATION_CONFIG = {
  syncEnabled: true,
  supabaseUrl: "$projectUrl",
  supabasePublishableKey: "$publishableKey",
  defaultRoomId: "gamification-live"
};
"@
Set-Content -LiteralPath (Join-Path $PSScriptRoot "presentation-config.js") -Value $config -Encoding utf8
Set-Content -LiteralPath (Join-Path $PSScriptRoot "presenter-code.txt") -Value $presenterToken -Encoding utf8

Write-Step "3. Финальная публикация"
& git add presentation-config.js
& git commit -m "Enable live presentation"
if ($LASTEXITCODE -ne 0) { throw "Не удалось сохранить публичную конфигурацию." }
& git push
if ($LASTEXITCODE -ne 0) { throw "Не удалось отправить финальную конфигурацию." }

$parts = $repository.Split('/')
$owner = $parts[0]
$repo = $parts[1]
$baseUrl = "https://$owner.github.io/$repo/"
$audienceUrl = "${baseUrl}?room=gamification-live"
$presenterUrl = "${baseUrl}?room=gamification-live&presenter=1"

Write-Host ""
Write-Host "ГОТОВО" -ForegroundColor Green
Write-Host "Для аудитории: $audienceUrl"
Write-Host "Для ведущей:   $presenterUrl"
Write-Host "Код ведущей сохранён только локально: $(Join-Path $PSScriptRoot 'presenter-code.txt')"
Write-Host "Код ведущей: $presenterToken" -ForegroundColor Yellow
Write-Host ""
Write-Host "GitHub Pages может обновляться несколько минут."

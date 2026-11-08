# ============================================================
#  Unique-Video.ps1
#  Уникализация MP4-видео через FFmpeg:
#   - чистка метаданных (все теги и главы)
#   - микро-изменение музыки (питч) и громкости
#   - микро-изменение картинки (яркость/контраст/сатурация)
#   - микро-изменение скорости видео+аудио
#   - рамка (поверх краёв "drawbox" или снаружи "pad")
#   - несколько копий на выходе из каждого входного файла
#
#  Запуск без параметров  -> интерактивный мастер настройки
#  Запуск с параметрами   -> режим командной строки (см. -Help)
#
#  Требуется: ffmpeg / ffprobe в PATH
# ============================================================

[CmdletBinding()]
param(
    [string]$Path,                       # файл или папка с .mp4
    [string]$OutDir = "output",          # папка вывода
    [int]$Count = 1,                     # копий на каждый входной файл
    [ValidateSet('drawbox','pad','none')]
    [string]$BorderMode = 'drawbox',     # тип рамки
    [int]$BorderWidth = 4,               # толщина рамки, px
    [string]$BorderColor = 'black',      # цвет рамки (black, white, 0x808080...)
    [double]$Pitch = 0,                  # фикс. питч (0 = случайно из диапазона)
    [double]$PitchMin = 0.97,            # мин. случайный питч
    [double]$PitchMax = 1.03,            # макс. случайный питч
    [double]$Volume = 1.0,               # громкость аудио
    [double]$Brightness = 2,             # фикс. яркость (2 = случайно)
    [double]$Contrast = 0,               # фикс. контраст
    [double]$Saturation = 0,             # фикс. сатурация
    [double]$EqJitter = 0.03,            # случайный разброс яркости/контраста/сатурации
    [double]$Speed = 0,                  # фикс. скорость (0 = случайно из диапазона)
    [double]$SpeedMin = 0.99,            # мин. случайная скорость
    [double]$SpeedMax = 1.01,            # макс. случайная скорость
    [int]$CRF = 18,                      # качество x264 (меньше = лучше)
    [string]$Preset = 'medium',          # пресет x264
    [string]$Suffix = '_uniq',           # суффикс имён файлов
    [string]$Tags = '',                  # доп. теги "key=val,key2=val2"
    [switch]$RandomTag,                  # вписать случайный comment=uid:... в каждый файл
    [switch]$DryRun,                     # показать команды ffmpeg, ничего не делать
    [switch]$Recurse,                    # искать mp4 во вложенных папках
    [int]$Seed = -1,                     # seed ГПСЧ (-1 = случайный)
    [switch]$Help                        # справка
)

$ErrorActionPreference = 'Stop'

# ---------- справка ----------
if ($Help -or ($PSBoundParameters.Count -eq 1 -and $Help)) {
    Write-Host @"
Unique-Video.ps1 — уникализация MP4 (метаданные + музыка + картинка + рамка)

Запуск БЕЗ параметров открывает интерактивный мастер настройки.
Все параметры можно задать и через CLI:

  -Path <строка>          файл или папка с .mp4
  -OutDir <строка>        папка вывода (по умолч. 'output')
  -Count <int>            сколько уникальных копий сделать из каждого файла
  -BorderMode <...>       drawbox (рамка поверх, разрешение прежнее) | pad (снаружи) | none
  -BorderWidth <int>      толщина рамки в пикселях
  -BorderColor <строка>   цвет (black, white, red, 0xRRGGBB)
  -Pitch <double>         фикс. питч, напр. 0.98 (0 = случайный)
  -PitchMin/-PitchMax     диапазон случайного питча (0.97..1.03)
  -Volume <double>        громкость аудио (1.0 = без изменений)
  -Brightness <double>    фикс. яркость (-1..1, 2 = случайный разброс)
  -Contrast/-Saturation   фикс. контраст/сатурация (0 = случайный разброс)
  -EqJitter <double>      случайный разброс картинки (0 = выкл.)
  -Speed <double>         фикс. скорость, напр. 1.02 (0 = случайный)
  -SpeedMin/-SpeedMax     диапазон случайной скорости (0.99..1.01)
  -CRF <int>              качество кодирования (18 по умолч.)
  -Preset <строка>        пресет x264: ultrafast..placebo
  -Suffix <строка>        суффикс имени файла
  -Tags "title=X"         записать свои теги после чистки
  -RandomTag              вписать случайный comment=uid:XXXX в каждый файл
  -DryRun                 показать команды ffmpeg без выполнения
  -Recurse                искать .mp4 во вложенных папках
  -Seed <int>             фиксировать случайность (повторяемый результат)
  -Help                   эта справка

Запуск БЕЗ параметров: спросит режим — 1) АВТО (средние настройки, сразу
обработка, без вопросов) или 2) ВРУЧНУЮ (пошаговый мастер).

Примеры:
  Unique-Video.bat                                    # выбор режима: АВТО или вручную
  Unique-Video.bat -Count 10                          # CLI: 10 копий, без вопросов
  .\Unique-Video.ps1 -Path .\vid.mp4 -Count 3         # 3 уникальные копии
  .\Unique-Video.ps1 -Pitch 0.97 -BorderMode pad -DryRun
"@ -ForegroundColor Cyan
    return
}

# ---------- вспомогательные функции ----------
function Write-Title([string]$t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }
function Read-Line([string]$prompt, [string]$default) {
    $v = Read-Host "$prompt [$default]"
    if ([string]::IsNullOrWhiteSpace($v)) { return $default }
    $v = $v.Trim()
    if ($v.Length -ge 2 -and (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'")))) {
        $v = $v.Substring(1, $v.Length - 2).Trim()
    }
    return $v
}
function Read-Number([string]$prompt, [double]$default, [double]$min, [double]$max) {
    while ($true) {
        $v = Read-Line $prompt ([string]$default)
        $d = 0.0
        if (-not [double]::TryParse($v, [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
            Write-Host "  Введите число." -ForegroundColor Red; continue
        }
        if ($d -lt $min -or $d -gt $max) {
            Write-Host "  Значение должно быть от $min до $max." -ForegroundColor Red; continue
        }
        return $d
    }
}
function Read-Int([string]$prompt, [int]$default, [int]$min, [int]$max) {
    while ($true) {
        $v = Read-Line $prompt ([string]$default)
        $d = 0
        if (-not [int]::TryParse($v, [ref]$d)) { Write-Host "  Введите целое число." -ForegroundColor Red; continue }
        if ($d -lt $min -or $d -gt $max) { Write-Host "  Допустимо от $min до $max." -ForegroundColor Red; continue }
        return $d
    }
}
function Read-Choice([string]$prompt, [string[]]$options, [int]$default) {
    Write-Host $prompt
    for ($i = 0; $i -lt $options.Count; $i++) {
        $mark = if ($i -eq $default) { '>' } else { ' ' }
        Write-Host ("  {0} {1}. {2}" -f $mark, ($i + 1), $options[$i])
    }
    while ($true) {
        $v = Read-Host "Выбор 1-$($options.Count) [Enter = $($default + 1)]" 
        if ([string]::IsNullOrWhiteSpace($v)) { return $default }
        $n = 0
        if ([int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le $options.Count) { return $n - 1 }
        Write-Host "  Неверный выбор." -ForegroundColor Red
    }
}
function Read-YesNo([string]$prompt, [bool]$default) {
    $def = if ($default) { 'Y' } else { 'N' }
    while ($true) {
        $v = Read-Host "$prompt [Y/N, Enter=$def]"
        if ([string]::IsNullOrWhiteSpace($v)) { return $default }
        if ($v -match '^(y|да|yes)$') { return $true }
        if ($v -match '^(n|нет|no)$') { return $false }
        Write-Host "  Ответьте Y или N." -ForegroundColor Red
    }
}
function Get-Param([hashtable]$h, [string]$k, $default) {
    if ($null -ne $h[$k]) { return $h[$k] } else { return $default }
}

# ---------- выбор режима при запуске без параметров ----------
$Interactive = $false
if ($PSBoundParameters.Count -eq 0) {
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "  УНИК-ВИДЕО — уникализация MP4               " -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. АВТО     — без вопросов, средние настройки, сразу обработка"
    Write-Host "  2. ВРУЧНУЮ  — пошаговая настройка всех параметров"
    Write-Host ""
    while ($true) {
        $v = Read-Host "Режим (1/2) [Enter = 1]"
        if ([string]::IsNullOrWhiteSpace($v)) { $Interactive = $false; break }
        if ($v -eq '1') { $Interactive = $false; break }
        if ($v -eq '2') { $Interactive = $true; break }
        Write-Host "  Введите 1 или 2." -ForegroundColor Red
    }
    Write-Host ""
}

# ---------- АВТО-режим: без вопросов, средние настройки ----------
if (-not $Interactive -and $PSBoundParameters.Count -eq 0) {
    Write-Host "== АВТО-РЕЖИМ ==" -ForegroundColor Cyan
    Write-Host "Папка: $(if ($Path) { $Path } else { (Get-Location).Path })"
    Write-Host "Копий/файл: $Count | Рамка: drawbox 4px | Питч: 0.97-1.03 | Скорость: 0.99-1.01 | Цвет: +-0.03`n"
    if (-not $RandomTag) { $RandomTag = $true }   # АВТО всегда вписывает случайный comment
}

# ---------- интерактивный мастер ----------
if ($Interactive) {
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "  УНИК-ВИДЕО — мастер уникализации MP4        " -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan

    # 1. Источник
    $p = Read-Line "Путь к файлу или папке с .mp4 [Enter = текущая папка]" ""
    if ($p) { $Path = $p }
    $Recurse = Read-YesNo "Искать файлы во вложенных папках?" $false

    # 2. Кол-во копий
    $Count = Read-Int "Сколько уникальных копий делать с КАЖДОГО файла" 1 1 100

    # 3. Рамка
    Write-Title "Рамка"
    $bm = Read-Choice "Тип рамки:" @('Поверх краёв (разрешение не меняется)', 'Снаружи (добавит размер к разрешению)', 'Без рамки') 0
    $BorderMode = @('drawbox','pad','none')[$bm]
    if ($BorderMode -ne 'none') {
        $BorderWidth = [int](Read-Number "Толщина рамки, px" 4 1 200)
        $BorderColor = Read-Line "Цвет рамки (black/white/red/0xRRGGBB)" "black"
    } else { $BorderWidth = 0 }

    # 4. Музыка
    Write-Title "Музыка (аудио)"
    $pm = Read-Choice "Питч:" @('Случайный (каждой копии свой)', 'Задать вручную', 'Без изменения') 0
    if ($pm -eq 0) {
        $PitchMin = Read-Number "Мин. питч" $PitchMin 0.5 2
        $PitchMax = Read-Number "Макс. питч" $PitchMax $PitchMin 2; $Pitch = 0
    } elseif ($pm -eq 1) { $Pitch = Read-Number "Питч (0.9 = ниже, 1.1 = выше)" 1.0 0.5 2 }
    else { $Pitch = 1.0 }
    $Volume = Read-Number "Громкость (1.0 = без изменений)" 1.0 0.1 2

    # 5. Скорость
    Write-Title "Скорость видео и звука"
    $sm = Read-Choice "Скорость:" @('Случайная (незаметно, +-1-2%)', 'Задать вручную', 'Без изменения') 0
    if ($sm -eq 0) {
        $SpeedMin = Read-Number "Мин. скорость" $SpeedMin 0.5 2
        $SpeedMax = Read-Number "Макс. скорость" $SpeedMax $SpeedMin 2; $Speed = 0
    } elseif ($sm -eq 1) { $Speed = Read-Number "Скорость (1.02 = на 2% быстрее)" 1.0 0.5 2 }
    else { $Speed = 1.0 }

    # 6. Картинка
    Write-Title "Картинка"
    $em = Read-Choice "Цветокоррекция:" @('Случайная микро-правка (яркость/контраст/сатурация)', 'Задать вручную', 'Без изменения') 0
    if ($em -eq 0) { $EqJitter = Read-Number "Сила разброса (+-)" 0.03 0.001 0.5; $Brightness = 2; $Contrast = 0; $Saturation = 0 }
    elseif ($em -eq 1) {
        $EqJitter = 0
        $Brightness = Read-Number "Яркость (-0.3..0.3)" 0.0 -1 1
        $Contrast = Read-Number "Контраст (0.9..1.1)" 1.0 0 3
        $Saturation = Read-Number "Сатурация (0.9..1.1)" 1.0 0 3
    } else { $EqJitter = 0; $Brightness = 0; $Contrast = 1.0; $Saturation = 1.0 }

    # 7. Кодирование
    Write-Title "Кодирование"
    $CRF = [int](Read-Number "CRF (14=почти без потерь, 28=плохо)" $CRF 10 35)
    $Preset = Read-Line "Пресет x264 (ultrafast..medium..slow)" $Preset

    # 8. Метаданные
    Write-Title "Метаданные"
    Write-Host "Все теги и главы будут удалены всегда." -ForegroundColor DarkGray
    $RandomTag = Read-YesNo "Вписать случайный 'comment' в каждый файл (доп. уникализация)?" $false
    $t = Read-Line "Свои теги 'key=val,key=val' [Enter = нет]" ""
    if ($t) { $Tags = $t }

    # 9. Вывод
    Write-Title "Вывод"
    $o = Read-Line "Папка вывода" $OutDir; $OutDir = $o
    $sfx = Read-Line "Суффикс имён файлов" $Suffix; $Suffix = $sfx
    $Seed = [int](Read-Number "Seed случайности (Enter = случайный, число = повторяемо)" -1 -1 999999999)
    $DryRun = Read-YesNo "Тестовый прогон (показать команды ffmpeg, ничего не делать)?" $false

    # Подтверждение
    Write-Host "`n---------- СВОДКА ----------" -ForegroundColor Yellow
    Write-Host "Файлы:      $(if ($Path) { $Path } else { 'текущая папка (*.mp4)' })"
    Write-Host "Копий/файл: $Count"
    Write-Host "Рамка:      $BorderMode" $(if ($BorderMode -ne 'none') { "($BorderWidth px, $BorderColor)" })
    Write-Host "Питч:       $(if ($Pitch -gt 0) { $Pitch } elseif ($Pitch -eq 1) { 'выкл' } else { "$PitchMin..$PitchMax (случайно)" })"
    Write-Host "Громкость:  $Volume"
    Write-Host "Скорость:   $(if ($Speed -gt 0) { $Speed } elseif ($Speed -eq 1) { 'выкл' } else { "$SpeedMin..$SpeedMax (случайно)" })"
    Write-Host "Картинка:   $(if ($EqJitter -gt 0) { "случайно +-$EqJitter" } elseif ($Brightness -ne 0 -or $Contrast -ne 1 -or $Saturation -ne 1) { "b=$Brightness c=$Contrast s=$Saturation" } else { 'выкл' })"
    Write-Host "Кодирование: libx264 CRF=$CRF preset=$Preset"
    Write-Host "Метаданные: чистка + $(if ($RandomTag) { 'случайный comment' } else { 'без comment' })"
    Write-Host "Вывод:      $OutDir (суффикс '$Suffix')"
    Write-Host "----------------------------" -ForegroundColor Yellow
    if (-not (Read-YesNo "Запустить обработку?" $true)) { Write-Host "Отменено." ; return }
}

# ---------- проверка окружения ----------
foreach ($exe in @('ffmpeg', 'ffprobe')) {
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
        Write-Error "$exe не найден в PATH. Установите FFmpeg и добавьте в PATH."; exit 1
    }
}

# ---------- сбор файлов ----------
if ($Path) {
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) {
        if ($Recurse) {
            $files = @(Get-ChildItem -LiteralPath $Path -Filter *.mp4 -File -Recurse | Where-Object { $_.Extension -eq '.mp4' })
        } else {
            $files = @(Get-ChildItem -LiteralPath $Path -Filter *.mp4 -File | Where-Object { $_.Extension -eq '.mp4' })
        }
    } else { $files = @($item) }
} else {
    $files = @(Get-ChildItem -LiteralPath (Get-Location) -Filter *.mp4 -File)
}
if ($files.Count -eq 0) { Write-Error "MP4-файлы не найдены."; exit 1 }

if ($Seed -ge 0) { Get-Random -SetSeed $Seed }

if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$OutDirResolved = (Get-Item -LiteralPath $OutDir).FullName

# ---------- генерация случайных значений ----------
function New-Rand([double]$min, [double]$max) { return (Get-Random -Minimum $min -Maximum $max) }
function Round3([double]$v) { return [math]::Round($v, 3) }
function Fmt([double]$v) { return $v.ToString('0.####', [System.Globalization.CultureInfo]::InvariantCulture) }

function New-Settings {
    $s = @{
        Pitch      = 1.0
        Speed      = 1.0
        Brightness = 0.0
        Contrast   = 1.0
        Saturation = 1.0
        UseEq      = $false
    }
    # питч: >0 фикс; Min==Max → это значение; иначе случайно из диапазона
    if ($Pitch -gt 0) { $s.Pitch = $Pitch }
    elseif ($PitchMin -eq $PitchMax) { $s.Pitch = $PitchMin }
    else { $s.Pitch = Round3 (New-Rand ([math]::Min($PitchMin,$PitchMax)) ([math]::Max($PitchMin,$PitchMax))) }
    # скорость: аналогично
    if ($Speed -gt 0) { $s.Speed = $Speed }
    elseif ($SpeedMin -eq $SpeedMax) { $s.Speed = $SpeedMin }
    else { $s.Speed = Round3 (New-Rand ([math]::Min($SpeedMin,$SpeedMax)) ([math]::Max($SpeedMin,$SpeedMax))) }
    # Brightness=2 — служебный сентинел «не задано»; Contrast/Saturation=0 — тоже сентинелы
    $eqExplicit = ($Brightness -ne 2) -or ($Contrast -ne 0) -or ($Saturation -ne 0)
    if ($EqJitter -gt 0) {
        $s.UseEq = $true
        $s.Brightness = Round3 (New-Rand (-$EqJitter) $EqJitter)
        $s.Contrast   = Round3 (1.0 + (New-Rand (-$EqJitter) $EqJitter))
        $s.Saturation = Round3 (1.0 + (New-Rand (-$EqJitter) $EqJitter))
    } elseif ($eqExplicit) {
        $s.UseEq = $true
        $s.Brightness = $Brightness; $s.Contrast = $Contrast; $s.Saturation = $Saturation
    }
    return $s
}

# ---------- построение аргументов ffmpeg ----------
function Build-Args([string]$inFile, [string]$outFile, [hashtable]$s, [bool]$hasAudio, [int]$sampleRate, [int]$vWidth, [int]$vHeight) {
    $fa = @('-y', '-hide_banner', '-loglevel', 'error', '-stats')
    $fa += @('-i', $inFile)
    $fa += @('-map', '0:v:0', '-map', '0:a:0?')
    $fa += @('-map_metadata', '-1', '-map_chapters', '-1')
    $fa += @('-fflags', '+bitexact', '-flags:v', '+bitexact', '-flags:a', '+bitexact')

    # --- видео ---
    $vf = @()
    if ($s.UseEq) { $vf += "eq=brightness=$($s.Brightness):contrast=$($s.Contrast):saturation=$($s.Saturation)" }
    if ($s.Speed -ne 1.0) { $vf += "setpts=PTS/$($s.Speed)" }
    if ($BorderMode -eq 'drawbox') { $vf += "drawbox=x=0:y=0:w=iw:h=ih:color=${BorderColor}:t=$BorderWidth" }
    if ($BorderMode -eq 'pad')     { $vf += "pad=ceil((iw+2*${BorderWidth})/2)*2:ceil((ih+2*${BorderWidth})/2)*2:(ow-iw)/2:(oh-ih)/2:color=$BorderColor" }
    # нечётные размеры несовместимы с yuv420p — добиваем 1px чёрного края
    if ($BorderMode -ne 'pad' -and (($vWidth % 2) -ne 0 -or ($vHeight % 2) -ne 0)) {
        $vf += "pad=ceil(iw/2)*2:ceil(ih/2)*2:0:0:color=black"
    }

    if ($vf.Count -gt 0) {
        $fa += @('-c:v', 'libx264', '-crf', "$CRF", '-preset', $Preset, '-pix_fmt', 'yuv420p', '-vf', ($vf -join ','))
    } else {
        $fa += @('-c:v', 'copy')
    }

    # --- аудио ---
    if ($hasAudio) {
        $af = @()
        if ($s.Pitch -ne 1.0) {
            $srp = [math]::Round($sampleRate * $s.Pitch)
            $af += "asetrate=$srp"
            $af += "aresample=$sampleRate"
            $af += "atempo=$([math]::Round(1.0 / $s.Pitch, 4))"
        }
        if ($s.Speed -ne 1.0) { $af += "atempo=$($s.Speed)" }
        if ($af.Count -gt 0 -or $Volume -ne 1.0) {
            if ($Volume -ne 1.0) { $af += "volume=$Volume" }
            $fa += @('-c:a', 'aac', '-b:a', '192k', '-ar', "$sampleRate", '-af', ($af -join ','))
        } else {
            $fa += @('-c:a', 'copy')
        }
        $fa += '-shortest'
    }

    # --- теги ---
    $meta = @()
    if ($Tags) { foreach ($t in ($Tags -split '\s*,\s*')) { $meta += @('-metadata', $t) } }
    if ($RandomTag) { $meta += @('-metadata', ("comment=uid:{0:X8}" -f (Get-Random -Maximum 0x7FFFFFFF))) }
    if ($meta.Count -gt 0) { $fa += $meta }

    $fa += @('-movflags', '+faststart', '-sn', '-dn', $outFile)
    return $fa
}

# ---------- обработка ----------
$results = @()
$idx = 0
$total = $files.Count * $Count
$failed = 0

Write-Host "`nФайлов к обработке: $($files.Count), копий каждого: $Count (всего $total)" -ForegroundColor Green
if ($DryRun) { Write-Host "РЕЖИМ DRYRUN — команды будут только показаны.`n" -ForegroundColor Yellow }

foreach ($f in $files) {
    # длительность и наличие аудио
    $probe = & ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 -- "$($f.FullName)" 2>$null
    $hasAudio = ($probe -contains 'audio')
    $sampleRate = 44100
    if ($hasAudio) {
        $sr = & ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 -- "$($f.FullName)" 2>$null
        if ($sr -match '^\d+$') { $sampleRate = [int]$sr }
    }
    # размеры кадра (для выравнивания под yuv420p)
    $vWidth = 0; $vHeight = 0
    $dims = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 -- "$($f.FullName)" 2>$null
    if ($dims -match '^(\d+),(\d+)') { $vWidth = [int]$Matches[1]; $vHeight = [int]$Matches[2] }

    for ($c = 1; $c -le $Count; $c++) {
        $idx++
        $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
        $outName = "$base$Suffix$('{0:D2}' -f $c).mp4"
        $outPath = Join-Path $OutDirResolved $outName
        $n = 1
        while (Test-Path -LiteralPath $outPath) {
            $n++
            $outName = "$base$Suffix$('{0:D2}' -f $c)_v$n.mp4"
            $outPath = Join-Path $OutDirResolved $outName
        }

        $s = New-Settings
        $argList = Build-Args -inFile $f.FullName -outFile $outPath -s $s -hasAudio $hasAudio -sampleRate $sampleRate -vWidth $vWidth -vHeight $vHeight

        $info = "  питч=$($s.Pitch) скорость=$($s.Speed)"
        if ($s.UseEq) { $info += " | ярк=$($s.Brightness) контр=$($s.Contrast) сат=$($s.Saturation)" }
        Write-Host $info -ForegroundColor DarkGray

        if ($DryRun) {
            Write-Host "  ffmpeg $($argList -join ' ')" -ForegroundColor DarkGray
            $results += [pscustomobject]@{ input=$f.Name; output=$outName; pitch=(Fmt $s.Pitch); speed=(Fmt $s.Speed); brightness=(Fmt $s.Brightness); contrast=(Fmt $s.Contrast); saturation=(Fmt $s.Saturation); border="$BorderMode/$BorderWidth"; status='DRYRUN' }
            continue
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        & ffmpeg @argList
        if ($LASTEXITCODE -eq 0) {
            $sw.Stop()
            Write-Host ("  OK за {0:N1} сек" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
            $results += [pscustomobject]@{ input=$f.Name; output=$outName; pitch=(Fmt $s.Pitch); speed=(Fmt $s.Speed); brightness=(Fmt $s.Brightness); contrast=(Fmt $s.Contrast); saturation=(Fmt $s.Saturation); border="$BorderMode/$BorderWidth"; status='OK' }
        } else {
            $sw.Stop()
            Write-Host "  ОШИБКА ffmpeg (код $LASTEXITCODE)" -ForegroundColor Red
            $failed++
            $results += [pscustomobject]@{ input=$f.Name; output=$outName; pitch=(Fmt $s.Pitch); speed=(Fmt $s.Speed); brightness=(Fmt $s.Brightness); contrast=(Fmt $s.Contrast); saturation=(Fmt $s.Saturation); border="$BorderMode/$BorderWidth"; status='FAIL' }
        }
    }
}

# журнал
if (-not $DryRun) {
    $log = Join-Path $OutDirResolved ("uniquelog_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $results | Export-Csv -LiteralPath $log -NoTypeInformation -Encoding UTF8
    Write-Host "`nЖурнал: $log"
}

Write-Host "`nГотово. Успешно: $($results | Where-Object { $_.status -in 'OK' } | Measure-Object | Select-Object -ExpandProperty Count) / $total" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
exit $(if ($failed -gt 0) { 1 } else { 0 })

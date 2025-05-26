Write-Host "=== Markdown图片处理器 v0.1.0 - 发行版准备工具 ===" -ForegroundColor Cyan
Write-Host ""

# 设置版本号
$version = "v0.1.0"
$releaseDir = "secure-release"
$outputDir = "github-release"

# 检查构建文件是否存在
if (-not (Test-Path "$releaseDir\MarkdownImageProcessor.exe")) {
    Write-Host "错误: 未找到构建文件，请先运行构建脚本" -ForegroundColor Red
    Write-Host "请运行: powershell -ExecutionPolicy Bypass -File 'build-secure-simple.ps1'" -ForegroundColor Yellow
    exit 1
}

Write-Host "准备 $version 发行版文件..." -ForegroundColor Green
Write-Host ""

# 创建发行版目录
if (Test-Path $outputDir) {
    Remove-Item $outputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

# 定义需要复制的文件列表
$requiredFiles = @(
    "MarkdownImageProcessor.exe",
    "MarkdownImageProcessor.dll", 
    "MarkdownImageProcessor.runtimeconfig.json",
    "MarkdownImageProcessor.deps.json"
)

# 复制指定的程序文件
Write-Host "复制程序文件..." -ForegroundColor Yellow
foreach ($file in $requiredFiles) {
    $sourcePath = "$releaseDir\$file"
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath -Destination $outputDir
        Write-Host "  ✓ $file" -ForegroundColor Green
    } else {
        Write-Host "  ✗ 警告: 未找到 $file" -ForegroundColor Red
    }
}

# 创建用户指南
Write-Host "创建用户指南..." -ForegroundColor Yellow
$userGuide = @"
# Markdown图片处理器 v0.1.0 使用指南

## 快速开始

1. **系统要求**
   - Windows 7/8/10/11
   - .NET 6.0 Runtime（如未安装，Windows会自动提示下载）

2. **运行程序**
   - 双击 MarkdownImageProcessor.exe
   - 选择包含Markdown文件的文件夹
   - 点击"开始处理"按钮

3. **如果遇到安全提示**
   - Windows SmartScreen: 点击"更多信息" → "仍要运行"
   - 杀毒软件拦截: 选择"信任"或"允许运行"

## 安全声明

本软件是100%安全的开源应用程序：
- 无病毒、无恶意代码
- 不收集任何个人信息
- 仅在本地处理文件
- 开源代码可审查

## 功能特性

- 处理Markdown文件中的图片引用
- 下载网络图片到本地assets文件夹
- 自动更新图片路径引用
- 实时进度显示
- 详细日志记录

## 故障排除

如果程序被杀毒软件误报：
1. 将程序添加到杀毒软件白名单
2. 重新启动程序

更多帮助请访问：https://github.com/your-username/markdown-image-processor

---
版本: $version
发布日期: $(Get-Date -Format 'yyyy-MM-dd')
许可证: MIT License
"@

# 使用.NET方法写入UTF8编码的文件
[System.IO.File]::WriteAllText("$outputDir\User-Guide.txt", $userGuide, [System.Text.Encoding]::UTF8)

# 统计文件信息
$files = Get-ChildItem $outputDir -File
$totalSize = ($files | Measure-Object -Property Length -Sum).Sum
$fileSizeKB = [math]::Round($totalSize / 1KB, 2)

Write-Host ""
Write-Host "发行版准备完成!" -ForegroundColor Green
Write-Host "输出目录: $outputDir" -ForegroundColor Cyan
Write-Host "文件数量: $($files.Count)" -ForegroundColor Gray
Write-Host "总大小: $fileSizeKB KB" -ForegroundColor Gray

Write-Host ""
Write-Host "发行版文件列表:" -ForegroundColor Yellow
foreach ($file in $files) {
    $size = [math]::Round($file.Length / 1KB, 2)
    Write-Host "  $($file.Name) ($size KB)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "GitHub Release 准备步骤:" -ForegroundColor Yellow
Write-Host "1. 压缩 $outputDir 目录为 markdown-image-processor-$version.zip" -ForegroundColor Gray
Write-Host "2. 在GitHub创建新的Release" -ForegroundColor Gray
Write-Host "3. 上传压缩包作为发行版附件" -ForegroundColor Gray
Write-Host "4. 添加发行说明" -ForegroundColor Gray

Write-Host ""
$compress = Read-Host "现在创建ZIP压缩包? (y/n)"
if ($compress -eq "y" -or $compress -eq "Y" -or $compress -eq "") {
    $zipPath = "markdown-image-processor-$version.zip"
    
    # 删除已存在的压缩包
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    
    # 创建压缩包
    Compress-Archive -Path "$outputDir\*" -DestinationPath $zipPath -Force
    
    $zipSize = [math]::Round((Get-Item $zipPath).Length / 1KB, 2)
    Write-Host ""
    Write-Host "✓ 压缩包创建成功: $zipPath ($zipSize KB)" -ForegroundColor Green
    Write-Host "此文件可直接上传到GitHub Release" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "完成!" -ForegroundColor Green 
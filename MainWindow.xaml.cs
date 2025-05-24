using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using System.Windows.Threading;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Media;
using System.Net;

namespace MarkdownImageProcessor
{
    /// <summary>
    /// MainWindow.xaml 的交互逻辑
    /// </summary>
    public partial class MainWindow : Window
    {
        private bool _isProcessing = false;
        private string _selectedPath = string.Empty;
        private readonly Dictionary<string, string> _fileRenameMap = new();
        private readonly HashSet<string> _shownErrors = new();
        private static readonly HttpClient httpClient = new();

        /// <summary>
        /// 初始化主窗口
        /// </summary>
        public MainWindow()
        {
            InitializeComponent();
            InitializeApplication();
        }

        /// <summary>
        /// 初始化应用程序设置
        /// </summary>
        private void InitializeApplication()
        {
            // 设置HTTP客户端
            httpClient.DefaultRequestHeaders.Clear();
            httpClient.DefaultRequestHeaders.Add("User-Agent", 
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
            httpClient.DefaultRequestHeaders.Add("Accept", 
                "image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8");
            httpClient.DefaultRequestHeaders.Add("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8");
            httpClient.DefaultRequestHeaders.Add("Accept-Encoding", "gzip, deflate, br");
            httpClient.DefaultRequestHeaders.Add("Cache-Control", "no-cache");
            httpClient.DefaultRequestHeaders.Add("Pragma", "no-cache");
            httpClient.Timeout = TimeSpan.FromSeconds(60); // 增加超时时间到60秒
            
            // 忽略SSL证书错误（仅用于开发测试）
            ServicePointManager.ServerCertificateValidationCallback = 
                (sender, certificate, chain, sslPolicyErrors) => true;
        }

        /// <summary>
        /// 浏览按钮点击事件
        /// </summary>
        private void BrowseButton_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new System.Windows.Forms.FolderBrowserDialog()
            {
                Description = "选择包含Markdown文件的目录",
                UseDescriptionForTitle = true,
                ShowNewFolderButton = false
            };

            if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
            {
                _selectedPath = dialog.SelectedPath;
                txtTargetPath.Text = _selectedPath;
                btnProcess.IsEnabled = true;
                UpdateStatus("已选择目录: " + _selectedPath);
                AppendLog($"选择的目录: {_selectedPath}", LogLevel.Info);
            }
        }

        /// <summary>
        /// 处理按钮点击事件
        /// </summary>
        private async void ProcessButton_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrEmpty(_selectedPath))
            {
                MessageBox.Show("请先选择要处理的目录！", "提示", 
                    MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            if (!Directory.Exists(_selectedPath))
            {
                MessageBox.Show("选择的目录不存在！", "错误", 
                    MessageBoxButton.OK, MessageBoxImage.Error);
                return;
            }

            await StartProcessing();
        }

        /// <summary>
        /// 清空日志按钮点击事件
        /// </summary>
        private void ClearButton_Click(object sender, RoutedEventArgs e)
        {
            txtLog.Text = "日志已清空，等待处理...";
            _shownErrors.Clear();
            UpdateStatus("就绪");
        }

        /// <summary>
        /// 开始处理流程
        /// </summary>
        private async Task StartProcessing()
        {
            if (_isProcessing) return;

            _isProcessing = true;
            btnProcess.IsEnabled = false;
            btnBrowse.IsEnabled = false;
            progressBar.Visibility = Visibility.Visible;
            progressBar.IsIndeterminate = false;
            progressBar.Value = 0;

            try
            {
                UpdateStatus("正在处理...");
                AppendLog("开始处理Markdown文件图片...", LogLevel.Info);
                AppendLog($"目标目录: {_selectedPath}", LogLevel.Info);

                // 清空重命名映射和错误记录
                _fileRenameMap.Clear();
                _shownErrors.Clear();

                await Task.Run(async () => await ProcessMarkdownFiles());

                AppendLog("\n" + "=".PadRight(50, '='), LogLevel.Success);
                AppendLog("🎉 处理完成！所有Markdown文件图片已成功处理", LogLevel.Success);
                AppendLog("=".PadRight(50, '='), LogLevel.Success);
                UpdateStatus("✅ 处理完成");
                
                // 移除弹窗提示，改为在日志中着重显示
                AppendLog("\n✨ 任务已完成，请查看上方日志了解详细信息", LogLevel.Success);
            }
            catch (Exception ex)
            {
                var errorMsg = $"❌ 处理过程中发生错误: {ex.Message}";
                AppendLog(errorMsg, LogLevel.Error);
                UpdateStatus("❌ 处理失败");
                
                // 只在严重错误时显示弹窗
                if (!_shownErrors.Contains(ex.Message))
                {
                    _shownErrors.Add(ex.Message);
                    Dispatcher.Invoke(() => MessageBox.Show(errorMsg, "错误", 
                        MessageBoxButton.OK, MessageBoxImage.Error));
                }
            }
            finally
            {
                _isProcessing = false;
                Dispatcher.Invoke(() => {
                    btnProcess.IsEnabled = true;
                    btnBrowse.IsEnabled = true;
                    progressBar.Visibility = Visibility.Hidden;
                    progressBar.Value = 0;
                });
            }
        }

        /// <summary>
        /// 处理Markdown文件的主要逻辑
        /// </summary>
        private async Task ProcessMarkdownFiles()
        {
            try
            {
                // 第一步：备份assets文件夹
                AppendLog("\n=== 第一步：备份assets文件夹 ===", LogLevel.Step);
                Dispatcher.Invoke(() => progressBar.Value = 10);
                var backupInfo = BackupAssetsFolder(_selectedPath);

                // 第二步：如果有备份，更新Markdown文件中的图片路径引用
                if (!string.IsNullOrEmpty(backupInfo.BackupDir))
                {
                    AppendLog("\n=== 第二步：更新Markdown文件中的图片引用路径 ===", LogLevel.Step);
                    Dispatcher.Invoke(() => progressBar.Value = 20);
                    UpdateMarkdownImagePaths(_selectedPath, backupInfo.RelativeFolderName);

                    // 第三步：将备份文件夹中的图片复制回assets文件夹
                    AppendLog("\n=== 第三步：恢复备份图片到assets文件夹 ===", LogLevel.Step);
                    Dispatcher.Invoke(() => progressBar.Value = 30);
                    RestoreImagesFromBackup(backupInfo.BackupDir, backupInfo.AssetsDir);
                }

                // 第四步：处理所有Markdown文件中的图片
                AppendLog("\n=== 第四步：处理Markdown文件中的图片 ===", LogLevel.Step);
                var mdFiles = Directory.GetFiles(_selectedPath, "*.md");
                int totalProcessed = 0;
                
                // 计算进度条的起始和结束值
                double startProgress = 40;
                double endProgress = 80;
                double progressRange = endProgress - startProgress;

                for (int i = 0; i < mdFiles.Length; i++)
                {
                    var mdFile = mdFiles[i];
                    AppendLog($"📄 正在处理文件 ({i + 1}/{mdFiles.Length}): {Path.GetFileName(mdFile)}", LogLevel.Info);
                    
                    // 更新进度条
                    double currentProgress = startProgress + (progressRange * (i + 1) / mdFiles.Length);
                    Dispatcher.Invoke(() => progressBar.Value = currentProgress);
                    
                    var processed = await ProcessMarkdownFile(mdFile, backupInfo.AssetsDir, backupInfo.RelativeFolderName);
                    totalProcessed += processed;
                }

                // 第五步：最终更新所有引用备份文件夹的图片路径
                if (!string.IsNullOrEmpty(backupInfo.BackupDir))
                {
                    AppendLog("\n=== 第五步：最终更新备份文件夹引用 ===", LogLevel.Step);
                    Dispatcher.Invoke(() => progressBar.Value = 90);
                    UpdateBackupReferences(_selectedPath, backupInfo.RelativeFolderName);
                }

                // 完成进度
                Dispatcher.Invoke(() => progressBar.Value = 100);

                // 输出处理结果统计
                AppendLog($"\n📊 处理统计信息:", LogLevel.Success);
                AppendLog($"   📁 处理的Markdown文件数量: {mdFiles.Length}", LogLevel.Success);
                AppendLog($"   🖼️ 处理的图片数量: {totalProcessed}", LogLevel.Success);
                if (!string.IsNullOrEmpty(backupInfo.BackupDir))
                {
                    AppendLog($"   📦 备份文件夹: {backupInfo.RelativeFolderName}", LogLevel.Success);
                }
                AppendLog($"   📂 Assets文件夹: {Path.GetFileName(backupInfo.AssetsDir)}", LogLevel.Success);
            }
            catch (Exception ex)
            {
                AppendLog($"❌ 处理失败: {ex.Message}", LogLevel.Error);
                throw;
            }
        }

        /// <summary>
        /// 备份assets文件夹信息结构
        /// </summary>
        private struct BackupInfo
        {
            public string? BackupDir { get; set; }
            public string AssetsDir { get; set; }
            public string? RelativeFolderName { get; set; }
        }

        /// <summary>
        /// 备份现有的assets文件夹
        /// </summary>
        private BackupInfo BackupAssetsFolder(string targetDir)
        {
            var assetsDir = Path.Combine(targetDir, "assets");
            var backupFolderName = "assets_bak_" + DateTime.Now.ToString("yyyyMMdd");
            var backupDir = Path.Combine(targetDir, backupFolderName);

            var result = new BackupInfo
            {
                BackupDir = null,
                AssetsDir = assetsDir,
                RelativeFolderName = null
            };

            if (Directory.Exists(assetsDir))
            {
                // 确保备份文件夹名称唯一
                var counter = 1;
                var originalBackupDir = backupDir;
                while (Directory.Exists(backupDir))
                {
                    backupDir = $"{originalBackupDir}_{counter}";
                    counter++;
                }

                // 创建备份文件夹并移动文件
                Directory.CreateDirectory(backupDir);
                AppendLog($"创建备份文件夹: {backupDir}", LogLevel.Info);

                // 移动所有文件到备份文件夹
                var files = Directory.GetFiles(assetsDir);
                foreach (var file in files)
                {
                    var fileName = Path.GetFileName(file);
                    var destPath = Path.Combine(backupDir, fileName);
                    File.Move(file, destPath);
                }

                AppendLog("已将assets文件夹内容移动到备份文件夹", LogLevel.Info);

                result.BackupDir = backupDir;
                result.RelativeFolderName = Path.GetFileName(backupDir);
            }
            else
            {
                // 创建新的assets文件夹
                Directory.CreateDirectory(assetsDir);
                AppendLog($"创建assets文件夹: {assetsDir}", LogLevel.Info);
            }

            return result;
        }

        /// <summary>
        /// 更新Markdown文件中的图片路径引用
        /// </summary>
        private void UpdateMarkdownImagePaths(string targetDir, string? relativeFolderName)
        {
            if (string.IsNullOrEmpty(relativeFolderName)) return;
            
            var mdFiles = Directory.GetFiles(targetDir, "*.md");

            foreach (var mdFile in mdFiles)
            {
                var content = File.ReadAllText(mdFile, Encoding.UTF8);

                // 匹配并替换图片路径：![alt](assets/xxx) -> ![alt](backup_folder/xxx)
                var pattern = @"!\[(.*?)\]\(assets/(.*?)\)";
                var replacement = $"![$1]({relativeFolderName}/$2)";
                var newContent = Regex.Replace(content, pattern, replacement);

                if (content != newContent)
                {
                    File.WriteAllText(mdFile, newContent, Encoding.UTF8);
                    AppendLog($"已更新Markdown文件中的图片引用路径: {Path.GetFileName(mdFile)}", LogLevel.Info);
                }
            }
        }

        /// <summary>
        /// 将备份文件夹中的图片复制回assets文件夹
        /// </summary>
        private void RestoreImagesFromBackup(string backupDir, string assetsDir)
        {
            AppendLog("将备份文件夹中的图片复制到assets文件夹...", LogLevel.Info);
            var backupImages = Directory.GetFiles(backupDir);

            foreach (var img in backupImages)
            {
                var imgName = Path.GetFileName(img);
                var uniqueImgName = GetUniqueFileName(assetsDir, imgName, img);
                var targetPath = Path.Combine(assetsDir, uniqueImgName);

                // 记录文件重命名映射关系
                _fileRenameMap[imgName] = uniqueImgName;

                if (imgName == uniqueImgName)
                {
                    if (!File.Exists(targetPath))
                    {
                        File.Copy(img, targetPath);
                        AppendLog($"已复制图片: {imgName} 到 assets 文件夹", LogLevel.Info);
                    }
                    else
                    {
                        AppendLog($"文件已存在且内容相同，跳过复制: {imgName}", LogLevel.Warning);
                    }
                }
                else
                {
                    File.Copy(img, targetPath);
                    AppendLog($"已复制图片（重命名）: {imgName} -> {uniqueImgName} 到 assets 文件夹", LogLevel.Info);
                }
            }
        }

        /// <summary>
        /// 处理单个Markdown文件中的所有图片
        /// </summary>
        private async Task<int> ProcessMarkdownFile(string mdFilePath, string assetsDir, string? backupRelativeName)
        {
            var dir = Path.GetDirectoryName(mdFilePath);
            var fileName = Path.GetFileName(mdFilePath);

            // 确保assets文件夹存在
            if (!Directory.Exists(assetsDir))
            {
                Directory.CreateDirectory(assetsDir);
            }

            var content = File.ReadAllText(mdFilePath, Encoding.UTF8);

            // 匹配所有图片：![alt](url) 格式
            var imgPattern = @"!\[(.*?)\]\((.*?)\)";
            var matches = Regex.Matches(content, imgPattern);

            var replaceMap = new Dictionary<string, string>();

            foreach (Match match in matches)
            {
                var imgUrl = match.Groups[2].Value;

                // 处理备份文件夹中的图片引用
                if (!string.IsNullOrEmpty(backupRelativeName) && 
                    Regex.IsMatch(imgUrl, $@"^{Regex.Escape(backupRelativeName)}/(.*?)$"))
                {
                    var regexMatch = Regex.Match(imgUrl, $@"^{Regex.Escape(backupRelativeName)}/(.*?)$");
                    var originalImgName = regexMatch.Groups[1].Value;

                    var actualImgName = _fileRenameMap.ContainsKey(originalImgName) 
                        ? _fileRenameMap[originalImgName] 
                        : originalImgName;

                    var backupAssetsPath = $"assets/{actualImgName}";
                    var oldStr = match.Value;
                    var newStr = oldStr.Replace(imgUrl, backupAssetsPath);
                    replaceMap[oldStr] = newStr;
                    continue;
                }

                // 跳过已经指向assets的图片
                if (imgUrl.StartsWith("assets/"))
                {
                    continue;
                }

                // 处理图片文件名
                var imgName = Path.GetFileName(imgUrl.Split('?')[0]);
                if (string.IsNullOrEmpty(imgName))
                {
                    imgName = $"image_{Guid.NewGuid().ToString().Substring(0, 8)}.jpg";
                }

                string? processedAssetsPath = null;

                if (imgUrl.StartsWith("http://") || imgUrl.StartsWith("https://"))
                {
                    // 处理网络图片
                    processedAssetsPath = await ProcessNetworkImage(imgUrl, imgName, assetsDir);
                }
                else
                {
                    // 处理本地图片
                    processedAssetsPath = ProcessLocalImage(imgUrl, imgName, assetsDir, dir ?? string.Empty);
                }

                // 如果处理成功，记录替换信息
                if (!string.IsNullOrEmpty(processedAssetsPath))
                {
                    var oldStr = match.Value;
                    var newStr = oldStr.Replace(imgUrl, processedAssetsPath);
                    replaceMap[oldStr] = newStr;
                }
            }

            // 统一替换所有图片路径
            if (replaceMap.Count > 0)
            {
                var newContent = content;
                foreach (var kvp in replaceMap)
                {
                    newContent = newContent.Replace(kvp.Key, kvp.Value);
                }

                File.WriteAllText(mdFilePath, newContent, Encoding.UTF8);
                AppendLog($"处理完成: {fileName} (更新了 {replaceMap.Count} 个图片路径)", LogLevel.Success);
            }
            else
            {
                AppendLog($"处理完成: {fileName} (没有需要更新的图片路径)", LogLevel.Warning);
            }

            return replaceMap.Count;
        }

        /// <summary>
        /// 处理网络图片（改进版本，包含重试机制和更好的错误处理）
        /// </summary>
        private async Task<string?> ProcessNetworkImage(string imageUrl, string imageName, string assetsDir)
        {
            const int maxRetries = 3;
            var tempFile = Path.GetTempFileName();
            var tempFileWithExt = tempFile + Path.GetExtension(imageName);

            for (int attempt = 1; attempt <= maxRetries; attempt++)
            {
                try
                {
                    AppendLog($"正在下载图片 (尝试 {attempt}/{maxRetries}): {imageUrl}", LogLevel.Info);

                    // 创建HTTP请求消息，允许自定义请求头
                    using var request = new HttpRequestMessage(HttpMethod.Get, imageUrl);
                    
                    // 为特定域名添加Referer头
                    var uri = new Uri(imageUrl);
                    request.Headers.Add("Referer", $"{uri.Scheme}://{uri.Host}/");
                    
                    // 发送请求
                    using var response = await httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
                    
                    // 检查响应状态
                    if (!response.IsSuccessStatusCode)
                    {
                        throw new HttpRequestException($"HTTP {(int)response.StatusCode} {response.StatusCode}: {response.ReasonPhrase}");
                    }

                    // 检查内容类型
                    var contentType = response.Content.Headers.ContentType?.MediaType;
                    if (!string.IsNullOrEmpty(contentType) && !contentType.StartsWith("image/"))
                    {
                        AppendLog($"警告: 响应内容类型不是图片: {contentType}", LogLevel.Warning);
                    }

                    // 获取文件大小
                    var contentLength = response.Content.Headers.ContentLength;
                    if (contentLength.HasValue)
                    {
                        AppendLog($"图片大小: {contentLength.Value / 1024.0:F1} KB", LogLevel.Info);
                        
                        // 检查文件大小是否合理（小于50MB）
                        if (contentLength.Value > 50 * 1024 * 1024)
                        {
                            throw new InvalidOperationException($"图片文件过大: {contentLength.Value / 1024.0 / 1024.0:F1} MB");
                        }
                    }

                    // 下载到临时文件
                    await using var responseStream = await response.Content.ReadAsStreamAsync();
                    await using var fileStream = File.Create(tempFileWithExt);
                    
                    // 如果有内容长度，显示下载进度
                    if (contentLength.HasValue)
                    {
                        var buffer = new byte[8192];
                        long totalBytesRead = 0;
                        int bytesRead;
                        
                        while ((bytesRead = await responseStream.ReadAsync(buffer, 0, buffer.Length)) > 0)
                        {
                            await fileStream.WriteAsync(buffer, 0, bytesRead);
                            totalBytesRead += bytesRead;
                            
                            // 每下载1MB显示一次进度
                            if (totalBytesRead % (1024 * 1024) == 0 || totalBytesRead == contentLength.Value)
                            {
                                var progress = (double)totalBytesRead / contentLength.Value * 100;
                                AppendLog($"下载进度: {progress:F1}% ({totalBytesRead / 1024.0:F1} KB / {contentLength.Value / 1024.0:F1} KB)", LogLevel.Info);
                            }
                        }
                    }
                    else
                    {
                        // 没有内容长度信息，直接复制
                        await responseStream.CopyToAsync(fileStream);
                    }

                    await fileStream.FlushAsync();
                    fileStream.Close();

                    // 验证下载的文件
                    var fileInfo = new FileInfo(tempFileWithExt);
                    if (fileInfo.Length == 0)
                    {
                        throw new InvalidOperationException("下载的文件为空");
                    }

                    AppendLog($"下载完成，文件大小: {fileInfo.Length / 1024.0:F1} KB", LogLevel.Success);

                    // 检查文件重名并生成唯一文件名
                    var uniqueImgName = GetUniqueFileName(assetsDir, imageName, tempFileWithExt);
                    var assetsPath = $"assets/{uniqueImgName}";
                    var fullAssetsPath = Path.Combine(assetsDir, uniqueImgName);

                    if (imageName == uniqueImgName)
                    {
                        if (!File.Exists(fullAssetsPath))
                        {
                            File.Move(tempFileWithExt, fullAssetsPath);
                            AppendLog($"下载图片成功: {imageUrl} -> {uniqueImgName}", LogLevel.Success);
                        }
                        else
                        {
                            AppendLog($"网络图片已存在且内容相同，跳过下载: {imageUrl}", LogLevel.Warning);
                            File.Delete(tempFileWithExt);
                        }
                    }
                    else
                    {
                        File.Move(tempFileWithExt, fullAssetsPath);
                        AppendLog($"下载图片成功（重命名）: {imageUrl} -> {uniqueImgName}", LogLevel.Success);
                    }

                    return assetsPath;
                }
                catch (TaskCanceledException ex) when (ex.InnerException is TimeoutException)
                {
                    var errorMsg = $"下载超时 (尝试 {attempt}/{maxRetries}): {imageUrl}";
                    AppendLog(errorMsg, LogLevel.Warning);
                    
                    if (attempt == maxRetries)
                    {
                        var finalError = $"下载失败: {imageUrl} - 多次尝试后仍然超时";
                        AppendLog(finalError, LogLevel.Error);
                        if (!_shownErrors.Contains(finalError))
                        {
                            _shownErrors.Add(finalError);
                        }
                        return null;
                    }
                    
                    // 等待后重试
                    await Task.Delay(2000 * attempt);
                }
                catch (HttpRequestException ex)
                {
                    var errorMsg = $"HTTP请求错误 (尝试 {attempt}/{maxRetries}): {imageUrl} - {ex.Message}";
                    AppendLog(errorMsg, LogLevel.Warning);
                    
                    if (attempt == maxRetries)
                    {
                        var finalError = $"下载失败: {imageUrl} - HTTP错误: {ex.Message}";
                        AppendLog(finalError, LogLevel.Error);
                        if (!_shownErrors.Contains(finalError))
                        {
                            _shownErrors.Add(finalError);
                        }
                        return null;
                    }
                    
                    // 等待后重试
                    await Task.Delay(2000 * attempt);
                }
                catch (Exception ex)
                {
                    var errorMsg = $"下载异常 (尝试 {attempt}/{maxRetries}): {imageUrl} - {ex.Message}";
                    AppendLog(errorMsg, LogLevel.Warning);
                    
                    if (attempt == maxRetries)
                    {
                        var finalError = $"下载失败: {imageUrl} - 错误: {ex.Message}";
                        AppendLog(finalError, LogLevel.Error);
                        if (!_shownErrors.Contains(finalError))
                        {
                            _shownErrors.Add(finalError);
                        }
                        return null;
                    }
                    
                    // 等待后重试
                    await Task.Delay(2000 * attempt);
                }
                finally
                {
                    // 清理临时文件
                    if (File.Exists(tempFile)) 
                    {
                        try { File.Delete(tempFile); } catch { }
                    }
                    if (File.Exists(tempFileWithExt) && attempt == maxRetries) 
                    {
                        try { File.Delete(tempFileWithExt); } catch { }
                    }
                }
            }

            return null;
        }

        /// <summary>
        /// 处理本地图片
        /// </summary>
        private string? ProcessLocalImage(string imageUrl, string imageName, string assetsDir, string baseDir)
        {
            // 解析图片的绝对路径
            var absImgPath = Path.IsPathRooted(imageUrl) ? imageUrl : Path.Combine(baseDir, imageUrl);

            if (File.Exists(absImgPath))
            {
                // 检查文件重名并生成唯一文件名
                var uniqueImgName = GetUniqueFileName(assetsDir, imageName, absImgPath);
                var assetsPath = $"assets/{uniqueImgName}";
                var fullAssetsPath = Path.Combine(assetsDir, uniqueImgName);

                if (imageName == uniqueImgName)
                {
                    if (!File.Exists(fullAssetsPath))
                    {
                        File.Copy(absImgPath, fullAssetsPath);
                        AppendLog($"已复制本地图片: {absImgPath} -> {fullAssetsPath}", LogLevel.Success);
                    }
                    else
                    {
                        AppendLog($"本地图片已存在且内容相同，跳过复制: {absImgPath}", LogLevel.Warning);
                    }
                }
                else
                {
                    File.Copy(absImgPath, fullAssetsPath);
                    AppendLog($"已复制本地图片（重命名）: {absImgPath} -> {fullAssetsPath}", LogLevel.Success);
                }

                return assetsPath;
            }
            else
            {
                var errorMsg = $"本地图片未找到: {absImgPath}";
                AppendLog(errorMsg, LogLevel.Error);
                
                if (!_shownErrors.Contains(errorMsg))
                {
                    _shownErrors.Add(errorMsg);
                }
                
                return null;
            }
        }

        /// <summary>
        /// 生成唯一的文件名以避免文件重名冲突
        /// </summary>
        private string GetUniqueFileName(string assetsDir, string originalFileName, string? sourceFilePath = null)
        {
            var fullPath = Path.Combine(assetsDir, originalFileName);

            // 如果文件不存在，直接返回原始文件名
            if (!File.Exists(fullPath))
            {
                return originalFileName;
            }

            // 如果提供了源文件路径，比较文件内容
            if (!string.IsNullOrEmpty(sourceFilePath) && File.Exists(sourceFilePath))
            {
                try
                {
                    // 使用MD5哈希值比较文件内容
                    var existingFileHash = GetFileHash(fullPath);
                    var sourceFileHash = GetFileHash(sourceFilePath);

                    if (existingFileHash == sourceFileHash)
                    {
                        AppendLog($"文件内容相同，无需重复保存: {originalFileName}", LogLevel.Warning);
                        return originalFileName;
                    }
                    else
                    {
                        AppendLog($"文件重名但内容不同，需要重命名: {originalFileName}", LogLevel.Warning);
                    }
                }
                catch (Exception ex)
                {
                    AppendLog($"无法比较文件内容，将进行重命名: {originalFileName} - 错误: {ex.Message}", LogLevel.Warning);
                }
            }

            // 生成新的唯一文件名
            var fileExtension = Path.GetExtension(originalFileName);
            var fileNameWithoutExt = Path.GetFileNameWithoutExtension(originalFileName);

            var timestamp = DateTime.Now.ToString("HHmmssff");
            var randomNum = new Random().Next(10, 99);
            var suffix = $"{timestamp}{randomNum}";

            var newFileName = $"{fileNameWithoutExt}_{suffix}{fileExtension}";

            AppendLog($"文件重名，生成新文件名: {originalFileName} -> {newFileName}", LogLevel.Info);
            return newFileName;
        }

        /// <summary>
        /// 获取文件的MD5哈希值
        /// </summary>
        private string GetFileHash(string filePath)
        {
            using var md5 = MD5.Create();
            using var stream = File.OpenRead(filePath);
            var hashBytes = md5.ComputeHash(stream);
            return Convert.ToHexString(hashBytes);
        }

        /// <summary>
        /// 最终更新所有引用备份文件夹的图片路径
        /// </summary>
        private void UpdateBackupReferences(string targetDir, string? relativeFolderName)
        {
            if (string.IsNullOrEmpty(relativeFolderName)) return;
            
            AppendLog("更新所有引用备份文件夹的图片路径...", LogLevel.Info);
            var mdFiles = Directory.GetFiles(targetDir, "*.md");

            foreach (var mdFile in mdFiles)
            {
                var content = File.ReadAllText(mdFile, Encoding.UTF8);
                var newContent = content;

                // 匹配备份文件夹中的图片引用
                var pattern = $@"!\[(.*?)\]\({Regex.Escape(relativeFolderName)}/(.*?)\)";
                var matches = Regex.Matches(content, pattern);

                foreach (Match match in matches)
                {
                    var originalImgName = match.Groups[2].Value;

                    var actualImgName = _fileRenameMap.ContainsKey(originalImgName)
                        ? _fileRenameMap[originalImgName]
                        : originalImgName;

                    var oldStr = match.Value;
                    var altText = match.Groups[1].Value;
                    var newStr = $"![{altText}](assets/{actualImgName})";
                    newContent = newContent.Replace(oldStr, newStr);
                }

                if (content != newContent)
                {
                    File.WriteAllText(mdFile, newContent, Encoding.UTF8);
                    AppendLog($"已更新引用备份文件夹的图片路径: {Path.GetFileName(mdFile)}", LogLevel.Success);
                }
            }
        }

        /// <summary>
        /// 日志级别枚举
        /// </summary>
        private enum LogLevel
        {
            Info,
            Success,
            Warning,
            Error,
            Step
        }

        /// <summary>
        /// 追加日志信息
        /// </summary>
        private void AppendLog(string message, LogLevel level = LogLevel.Info)
        {
            Dispatcher.Invoke(() =>
            {
                var timestamp = DateTime.Now.ToString("HH:mm:ss");
                var logMessage = $"[{timestamp}] {message}\n";

                // 根据日志级别设置颜色（简化版本，WPF中需要使用Rich Text或者其他方式）
                txtLog.Text += logMessage;

                // 自动滚动到底部
                LogScrollViewer.ScrollToEnd();
            });
        }

        /// <summary>
        /// 更新状态栏信息
        /// </summary>
        private void UpdateStatus(string status)
        {
            Dispatcher.Invoke(() =>
            {
                statusText.Text = status;
            });
        }
    }
} 
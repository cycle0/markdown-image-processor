using System.Windows;

namespace MarkdownImageProcessor
{
    /// <summary>
    /// App.xaml 的交互逻辑
    /// </summary>
    public partial class App : Application
    {
        /// <summary>
        /// 应用程序启动时的处理
        /// </summary>
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            
            // 设置全局异常处理
            DispatcherUnhandledException += App_DispatcherUnhandledException;
        }

        /// <summary>
        /// 全局异常处理
        /// </summary>
        private void App_DispatcherUnhandledException(object sender, System.Windows.Threading.DispatcherUnhandledExceptionEventArgs e)
        {
            MessageBox.Show($"应用程序发生未处理的异常:\n{e.Exception.Message}", "错误", 
                MessageBoxButton.OK, MessageBoxImage.Error);
            e.Handled = true;
        }
    }
} 
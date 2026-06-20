using System;
using System.IO.Ports;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace At24c512cGui
{
    public sealed class MainWindow : Window
    {
        private readonly object serialLock = new object();
        private readonly DispatcherTimer sw4Timer;

        private SerialPort serial;
        private bool connected;
        private bool sw4Busy;

        private TextBox portBox;
        private Button btnConnect;
        private Button btnDisconnect;
        private TextBlock statusText;
        private TextBlock sw4Status;
        private CheckBox sw4Poll;
        private TextBox eeAddr;
        private TextBox eeData;
        private TextBox eeDumpLen;
        private RadioButton type256;
        private RadioButton type512;
        private TextBox logArea;
        private TextBox cmdInput;
        private TextBlock bottomStatus;

        public MainWindow(string defaultPort)
        {
            Title = "AT24C512C EEPROM Control GUI (C# WPF)";
            Width = 920;
            Height = 560;
            MinWidth = 760;
            MinHeight = 480;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Background = Brush("#FF1E1E1E");

            Content = BuildUi(defaultPort);

            sw4Timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
            sw4Timer.Tick += async (s, e) => await RefreshSw4Async();

            Closing += (s, e) =>
            {
                sw4Timer.Stop();
                DisconnectSerial();
            };

            LogWrite("AT24C512C EEPROM Control Panel ready");
            LogWrite("Select COM port and click Connect");
            type256.IsChecked = true;
        }

        private UIElement BuildUi(string defaultPort)
        {
            var root = new Grid { Margin = new Thickness(8, 6, 8, 6) };
            root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(320) });
            root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
            root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var leftScroll = new ScrollViewer
            {
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
            };
            Grid.SetColumn(leftScroll, 0);
            root.Children.Add(leftScroll);

            var left = new StackPanel { Margin = new Thickness(2, 0, 2, 0) };
            leftScroll.Content = left;

            left.Children.Add(ConnectionGroup(defaultPort));
            left.Children.Add(LedSw4Group());
            left.Children.Add(EepromGroup());
            left.Children.Add(TypeWdtSystemGroup());

            var right = new Grid();
            right.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            right.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            right.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            Grid.SetColumn(right, 2);
            root.Children.Add(right);

            logArea = new TextBox
            {
                IsReadOnly = true,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                Background = Brush("#FF0C0C0C"),
                Foreground = Brush("#FFD4D4D4"),
                BorderBrush = Brush("#FF444444"),
                FontFamily = new FontFamily("Consolas"),
                FontSize = 12,
                AcceptsReturn = true,
                AcceptsTab = true
            };
            right.Children.Add(logArea);

            var commandGrid = new Grid { Margin = new Thickness(0, 4, 0, 0) };
            commandGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            commandGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            commandGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            commandGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetRow(commandGrid, 1);
            right.Children.Add(commandGrid);

            commandGrid.Children.Add(Label("CMD:", 0));
            cmdInput = TextBox("");
            cmdInput.KeyDown += async (s, e) =>
            {
                if (e.Key == Key.Enter)
                {
                    e.Handled = true;
                    await SendRawCommandAsync();
                }
            };
            Grid.SetColumn(cmdInput, 1);
            commandGrid.Children.Add(cmdInput);

            var send = Button("Send", 55, "#FF2D5F2D");
            send.Click += async (s, e) => await SendRawCommandAsync();
            Grid.SetColumn(send, 2);
            commandGrid.Children.Add(send);

            var clear = Button("Clear", 55, "#FF333333");
            clear.Click += (s, e) => logArea.Clear();
            Grid.SetColumn(clear, 3);
            commandGrid.Children.Add(clear);

            bottomStatus = new TextBlock
            {
                Text = "Ready",
                Foreground = Brush("#FF888888"),
                Margin = new Thickness(0, 4, 0, 0)
            };
            Grid.SetRow(bottomStatus, 2);
            right.Children.Add(bottomStatus);

            return root;
        }

        private GroupBox ConnectionGroup(string defaultPort)
        {
            var stack = new StackPanel { Margin = new Thickness(3) };

            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 4) };
            row.Children.Add(new Label { Content = "Port:", Foreground = Brushes.White, Width = 40, Padding = new Thickness(0, 2, 0, 2) });
            portBox = TextBox(defaultPort);
            portBox.Width = 100;
            row.Children.Add(portBox);
            stack.Children.Add(row);

            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            btnConnect = Button("Connect", 95, "#FF2D5F2D");
            btnDisconnect = Button("Disconnect", 95, "#FF5F2D2D");
            btnDisconnect.IsEnabled = false;
            btnConnect.Click += async (s, e) => await ConnectAsync();
            btnDisconnect.Click += (s, e) =>
            {
                DisconnectSerial();
                LogWrite("Disconnected");
                SetConnectedUi(false, "Disconnected");
            };
            buttons.Children.Add(btnConnect);
            buttons.Children.Add(btnDisconnect);
            stack.Children.Add(buttons);

            statusText = new TextBlock
            {
                Text = "Disconnected",
                Foreground = Brush("#FFCCCCCC"),
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 4, 0, 0)
            };
            stack.Children.Add(statusText);

            return Group("Connection", stack);
        }

        private UIElement LedSw4Group()
        {
            var grid = new Grid { Margin = new Thickness(0, 0, 0, 4) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(6) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var ledStack = new StackPanel { Margin = new Thickness(2) };
            var ledGrid = new UniformGrid { Columns = 3, Margin = new Thickness(0, 0, 0, 3) };
            for (int i = 1; i <= 6; i++)
            {
                int led = i;
                var b = Button("L" + i, 0, "#FF333333");
                b.Height = 24;
                b.FontSize = 11;
                b.Click += async (s, e) => await ExecuteCommandAsync(led.ToString(), 400);
                ledGrid.Children.Add(b);
            }
            ledStack.Children.Add(ledGrid);

            var ledOps = new UniformGrid { Columns = 2 };
            var all = Button("All ON", 0, "#FF2D5F2D");
            all.Click += async (s, e) => await ExecuteCommandAsync("a", 400);
            var clear = Button("All OFF", 0, "#FF5F2D2D");
            clear.Click += async (s, e) => await ExecuteCommandAsync("c", 400);
            ledOps.Children.Add(all);
            ledOps.Children.Add(clear);
            ledStack.Children.Add(ledOps);
            grid.Children.Add(Group("LED", ledStack));

            var swStack = new StackPanel { Margin = new Thickness(2), VerticalAlignment = VerticalAlignment.Center };
            sw4Status = new TextBlock
            {
                Text = "---",
                FontSize = 16,
                FontWeight = FontWeights.Bold,
                Foreground = Brush("#FFAAAAAA"),
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 4, 0, 4)
            };
            swStack.Children.Add(sw4Status);
            var swRow = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            var refresh = Button("Refresh", 60, "#FF333333");
            refresh.Click += async (s, e) => await RefreshSw4Async();
            sw4Poll = new CheckBox { Content = "Auto", Foreground = Brushes.White, VerticalAlignment = VerticalAlignment.Center, FontSize = 11 };
            sw4Poll.Checked += (s, e) => sw4Timer.Start();
            sw4Poll.Unchecked += (s, e) => sw4Timer.Stop();
            swRow.Children.Add(refresh);
            swRow.Children.Add(sw4Poll);
            swStack.Children.Add(swRow);

            var swGroup = Group("SW4", swStack);
            Grid.SetColumn(swGroup, 2);
            grid.Children.Add(swGroup);
            return grid;
        }

        private GroupBox EepromGroup()
        {
            var stack = new StackPanel { Margin = new Thickness(3) };

            var row = new Grid { Margin = new Thickness(0, 0, 0, 4) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.Children.Add(Label("Addr:", 0));
            eeAddr = TextBox("0x0000");
            Grid.SetColumn(eeAddr, 1);
            row.Children.Add(eeAddr);
            row.Children.Add(Label("Data:", 2));
            eeData = TextBox("0xAB");
            Grid.SetColumn(eeData, 3);
            row.Children.Add(eeData);
            stack.Children.Add(row);

            var readWrite = new UniformGrid { Columns = 2, Margin = new Thickness(0, 0, 0, 3) };
            var read = Button("Read", 0, "#FF2D4F5F");
            read.Click += async (s, e) => await ExecuteCommandAsync("eer " + eeAddr.Text.Trim(), 500);
            var write = Button("Write", 0, "#FF4F2D5F");
            write.Click += async (s, e) => await ExecuteCommandAsync("eew " + eeAddr.Text.Trim() + " " + eeData.Text.Trim(), 600);
            readWrite.Children.Add(read);
            readWrite.Children.Add(write);
            stack.Children.Add(readWrite);

            var dumpRow = new Grid { Margin = new Thickness(0, 0, 0, 3) };
            dumpRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            dumpRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            dumpRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            dumpRow.Children.Add(Label("Len:", 0));
            eeDumpLen = TextBox("16");
            Grid.SetColumn(eeDumpLen, 1);
            dumpRow.Children.Add(eeDumpLen);
            var dump = Button("Dump", 60, "#FF333333");
            dump.Click += async (s, e) => await ExecuteCommandAsync("eedump " + eeAddr.Text.Trim() + " " + Len(), 600);
            Grid.SetColumn(dump, 2);
            dumpRow.Children.Add(dump);
            stack.Children.Add(dumpRow);

            var ops = new UniformGrid { Columns = 3 };
            var test = Button("Test", 0, "#FF333333");
            test.Click += async (s, e) =>
            {
                var resp = await ExecuteCommandAsync("eetest", 2500);
                if (resp.IndexOf("PASS", StringComparison.OrdinalIgnoreCase) >= 0) bottomStatus.Text = "EEPROM test: PASS";
                if (resp.IndexOf("FAIL", StringComparison.OrdinalIgnoreCase) >= 0) bottomStatus.Text = "EEPROM test: FAIL";
            };
            var fill = Button("Fill", 0, "#FF333333");
            fill.Click += async (s, e) => await ExecuteCommandAsync("eefill " + eeAddr.Text.Trim() + " " + Len() + " " + eeData.Text.Trim(), 600);
            var scan = Button("Scan", 0, "#FF333333");
            scan.Click += async (s, e) => await ExecuteCommandAsync("scan", 5000);
            ops.Children.Add(test);
            ops.Children.Add(fill);
            ops.Children.Add(scan);
            stack.Children.Add(ops);

            return Group("EEPROM Access", stack);
        }

        private UIElement TypeWdtSystemGroup()
        {
            var grid = new Grid { Margin = new Thickness(0, 0, 0, 4) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(6) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(6) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var typeStack = new StackPanel { Margin = new Thickness(2), VerticalAlignment = VerticalAlignment.Center };
            type256 = new RadioButton { Content = "256", Foreground = Brushes.White, GroupName = "EeType", FontSize = 11, Margin = new Thickness(0, 1, 0, 1) };
            type512 = new RadioButton { Content = "512", Foreground = Brushes.White, GroupName = "EeType", FontSize = 11, Margin = new Thickness(0, 1, 0, 1) };
            type256.Checked += async (s, e) => { if (connected) await ExecuteCommandAsync("eetype 256", 400); };
            type512.Checked += async (s, e) => { if (connected) await ExecuteCommandAsync("eetype 512", 400); };
            typeStack.Children.Add(type256);
            typeStack.Children.Add(type512);
            grid.Children.Add(Group("Type", typeStack));

            var wdt = new UniformGrid { Columns = 1, Margin = new Thickness(2) };
            AddCommandButton(wdt, "ON", "wdt on", "#FF2D5F2D");
            AddCommandButton(wdt, "PAT", "wdt pat", "#FF333333");
            AddCommandButton(wdt, "OFF", "wdt off", "#FF5F2D2D");
            var wdtGroup = Group("WDT", wdt);
            Grid.SetColumn(wdtGroup, 2);
            grid.Children.Add(wdtGroup);

            var sys = new UniformGrid { Columns = 1, Margin = new Thickness(2) };
            AddCommandButton(sys, "ID", "id", "#FF333333", 500);
            AddCommandButton(sys, "Dump", "dump", "#FF333333", 600);
            var sysGroup = Group("System", sys);
            Grid.SetColumn(sysGroup, 4);
            grid.Children.Add(sysGroup);

            return grid;
        }

        private async Task ConnectAsync()
        {
            var port = portBox.Text.Trim();
            LogWrite("Connecting to " + port + " ...");
            var ok = await Task.Run(() => ConnectSerial(port));
            if (ok)
            {
                LogWrite("Connected to " + port);
                SetConnectedUi(true, "Connected (" + port + ")");
            }
            else
            {
                LogError("Failed to connect to " + port);
                statusText.Text = "Connection failed";
            }
        }

        private bool ConnectSerial(string port)
        {
            try
            {
                var sp = new SerialPort(port, 9600, Parity.None, 8, StopBits.One);
                sp.ReadTimeout = 5000;
                sp.WriteTimeout = 5000;
                sp.Open();
                Thread.Sleep(300);
                sp.DiscardInBuffer();
                lock (serialLock)
                {
                    serial = sp;
                    connected = true;
                }
                return true;
            }
            catch
            {
                connected = false;
                return false;
            }
        }

        private void DisconnectSerial()
        {
            lock (serialLock)
            {
                if (serial != null)
                {
                    try { serial.Close(); } catch { }
                    serial.Dispose();
                    serial = null;
                }
                connected = false;
            }
        }

        private async Task<string> ExecuteCommandAsync(string cmd, int waitMs)
        {
            if (!connected)
            {
                LogError("Not connected");
                return "";
            }

            LogCommand(cmd);
            var resp = await Task.Run(() => SendCommand(cmd, waitMs));
            LogResponse(resp);
            return resp;
        }

        private string SendCommand(string cmd, int waitMs)
        {
            lock (serialLock)
            {
                if (!connected || serial == null) return "";
                try { serial.ReadExisting(); } catch { }
                serial.WriteLine(cmd);
                Thread.Sleep(waitMs);

                var response = "";
                try { response = serial.ReadExisting(); } catch { }
                var emptyCount = 0;
                while (emptyCount < 2)
                {
                    Thread.Sleep(150);
                    var chunk = "";
                    try { chunk = serial.ReadExisting(); } catch { }
                    if (!string.IsNullOrEmpty(chunk))
                    {
                        response += chunk;
                        emptyCount = 0;
                    }
                    else
                    {
                        emptyCount++;
                    }
                }

                return string.Join("\r\n", response
                    .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(x => x.Trim())
                    .Where(x => x.Length > 0 && x != cmd));
            }
        }

        private async Task RefreshSw4Async()
        {
            if (!connected || sw4Busy) return;
            sw4Busy = true;
            try
            {
                var resp = await Task.Run(() => SendCommand("s", 300));
                var val = resp.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(x => x.Trim()).LastOrDefault(x => x.Length > 0 && x != "s");

                if (val == "1")
                {
                    sw4Status.Text = "PRESSED";
                    sw4Status.Foreground = Brush("#FF4EC9B0");
                }
                else if (val == "0")
                {
                    sw4Status.Text = "RELEASED";
                    sw4Status.Foreground = Brush("#FFCCCCCC");
                }
                else if (!string.IsNullOrEmpty(val))
                {
                    sw4Status.Text = "???";
                    sw4Status.Foreground = Brush("#FFF44747");
                }
            }
            finally
            {
                sw4Busy = false;
            }
        }

        private async Task SendRawCommandAsync()
        {
            var cmd = cmdInput.Text.Trim();
            if (cmd.Length == 0) return;
            await ExecuteCommandAsync(cmd, 600);
            cmdInput.Text = "";
        }

        private void SetConnectedUi(bool isConnected, string text)
        {
            btnConnect.IsEnabled = !isConnected;
            btnDisconnect.IsEnabled = isConnected;
            statusText.Text = text;
            statusText.Foreground = isConnected ? Brush("#FF4EC9B0") : Brush("#FFCCCCCC");
        }

        private void LogCommand(string cmd)
        {
            LogWrite(">> " + cmd);
        }

        private void LogResponse(string response)
        {
            if (string.IsNullOrWhiteSpace(response)) return;
            foreach (var line in response.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
            {
                if (!string.IsNullOrWhiteSpace(line)) LogWrite("   " + line);
            }
        }

        private void LogError(string text)
        {
            LogWrite("!! " + text);
        }

        private void LogWrite(string text)
        {
            logArea.AppendText("[" + DateTime.Now.ToString("HH:mm:ss") + "] " + text + "\r\n");
            logArea.ScrollToEnd();
        }

        private string Len()
        {
            var len = eeDumpLen.Text.Trim();
            if (len.Length == 0) len = "16";
            return len;
        }

        private void AddCommandButton(Panel panel, string text, string cmd, string color, int waitMs = 400)
        {
            var b = Button(text, 0, color);
            b.Height = 22;
            b.FontSize = 10;
            b.Margin = new Thickness(0, 1, 0, 1);
            b.Click += async (s, e) => await ExecuteCommandAsync(cmd, waitMs);
            panel.Children.Add(b);
        }

        private static GroupBox Group(string header, object content)
        {
            return new GroupBox
            {
                Header = header,
                Content = content,
                Foreground = Brushes.White,
                BorderBrush = Brush("#FF444444"),
                Padding = new Thickness(4),
                Margin = new Thickness(0, 0, 0, 4)
            };
        }

        private static TextBox TextBox(string text)
        {
            return new TextBox
            {
                Text = text,
                Background = Brush("#FF333333"),
                Foreground = Brushes.White,
                BorderBrush = Brush("#FF555555"),
                Padding = new Thickness(2, 1, 2, 1),
                FontSize = 11
            };
        }

        private static Button Button(string text, double width, string color)
        {
            var b = new Button
            {
                Content = text,
                Height = 26,
                Margin = new Thickness(1),
                Background = Brush(color),
                Foreground = Brushes.White,
                FontSize = 11
            };
            if (width > 0) b.Width = width;
            return b;
        }

        private static Label Label(string text, int column)
        {
            var label = new Label
            {
                Content = text,
                Foreground = Brushes.White,
                Padding = new Thickness(0, 2, 4, 2),
                VerticalAlignment = VerticalAlignment.Center,
                FontSize = 11
            };
            Grid.SetColumn(label, column);
            return label;
        }

        private static SolidColorBrush Brush(string color)
        {
            return (SolidColorBrush)new BrushConverter().ConvertFromString(color);
        }
    }

    public static class Program
    {
        [STAThread]
        public static void Main(string[] args)
        {
            var defaultPort = args.Length > 0 ? args[0] : "COM11";
            var app = new Application();
            app.Run(new MainWindow(defaultPort));
        }
    }
}

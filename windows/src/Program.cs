namespace Banshell;

public static class Program
{
    [STAThread]
    public static void Main()
    {
        using var instanceLock = new Mutex(true, "BanshellSingleInstance", out var isFirstInstance);
        if (!isFirstInstance) return;
        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApp());
    }
}

public class TrayApp : ApplicationContext
{
    private readonly NotifyIcon trayIcon;
    private readonly Watcher watcher;
    private readonly ToolStripMenuItem statusItem;
    private readonly ToolStripMenuItem armItem;
    private readonly ToolStripMenuItem disarmItem;
    private SettingsForm? settingsForm;
    private AlarmForm? alarmForm;

    public TrayApp()
    {
        var config = BanshellConfig.Load();
        watcher = new Watcher(config);
        watcher.AlarmRequested += ShowAlarm;
        watcher.StateChanged += RefreshMenu;

        statusItem = new ToolStripMenuItem("BANSHELL — starting…") { Enabled = false };
        armItem = new ToolStripMenuItem("Arm Now", null, (_, _) => watcher.Arm());
        disarmItem = new ToolStripMenuItem("Disarm…", null, (_, _) => DisarmWithPin());

        var menu = new ContextMenuStrip();
        menu.Items.Add(statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(armItem);
        menu.Items.Add(disarmItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Settings…", null, (_, _) => ShowSettings()));
        menu.Items.Add(new ToolStripMenuItem("Test Siren (Drill)…", null, (_, _) => Drill()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit BANSHELL", null, (_, _) => Quit()));

        trayIcon = new NotifyIcon
        {
            Icon = SystemIcons.Shield,
            ContextMenuStrip = menu,
            Visible = true,
            Text = "BANSHELL",
        };
        trayIcon.DoubleClick += (_, _) => ShowSettings();

        RefreshMenu();
        if (!config.HasPin) ShowFirstRun();
    }

    private void RefreshMenu()
    {
        var config = watcher.Config;
        if (watcher.Triggered)
        {
            statusItem.Text = "BANSHELL — ALARM ACTIVE";
            trayIcon.Icon = SystemIcons.Error;
        }
        else if (watcher.Armed)
        {
            statusItem.Text = "BANSHELL — Armed";
            trayIcon.Icon = SystemIcons.Shield;
        }
        else
        {
            statusItem.Text = config.AutoArmDaily
                ? $"BANSHELL — Disarmed · arms at {config.ArmHour:D2}:{config.ArmMinute:D2}"
                : "BANSHELL — Disarmed";
            trayIcon.Icon = SystemIcons.Application;
        }
        armItem.Visible = !watcher.Armed;
        disarmItem.Visible = watcher.Armed;
        trayIcon.Text = statusItem.Text.Length <= 63 ? statusItem.Text : statusItem.Text[..63];
    }

    private void ShowAlarm(string reason)
    {
        if (alarmForm != null) return;
        alarmForm = new AlarmForm(BanshellConfig.Load(), reason);
        alarmForm.Disarmed += () =>
        {
            alarmForm = null;
            watcher.ClearTriggeredAndDisarm();
        };
        alarmForm.Show();
    }

    private void DisarmWithPin()
    {
        var config = BanshellConfig.Load();
        using var dialog = new PinDialog(true);
        dialog.Text = "Enter disarm code";
        if (dialog.ShowDialog() != DialogResult.OK) return;
        if (config.VerifyPin(dialog.CurrentPin))
            watcher.Disarm();
        else
            MessageBox.Show("Wrong code.", "BANSHELL", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }

    private void Drill()
    {
        var confirm = MessageBox.Show(
            "The real siren will sound at full volume and the screen will lock until you enter your disarm code. Fire the drill?",
            "BANSHELL Drill", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
        if (confirm == DialogResult.Yes) watcher.Drill();
    }

    private void ShowSettings()
    {
        if (settingsForm == null || settingsForm.IsDisposed)
            settingsForm = new SettingsForm(watcher);
        settingsForm.Show();
        settingsForm.Activate();
    }

    private void ShowFirstRun()
    {
        using var dialog = new PinDialog(false);
        dialog.Text = "Welcome to BANSHELL — set your disarm code";
        while (true)
        {
            if (dialog.ShowDialog() != DialogResult.OK) continue;
            if (dialog.NewPin.Length >= 4 && dialog.NewPin == dialog.ConfirmPin) break;
            MessageBox.Show("Codes must match and be at least 4 characters.", "BANSHELL",
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        var config = BanshellConfig.Load();
        config.SetPin(dialog.NewPin);
        config.Save();
        watcher.ReloadConfig(config);
        ShowSettings();
    }

    private void Quit()
    {
        if (watcher.Armed)
        {
            var config = BanshellConfig.Load();
            using var dialog = new PinDialog(true);
            dialog.Text = "BANSHELL is armed — enter code to quit";
            if (dialog.ShowDialog() != DialogResult.OK || !config.VerifyPin(dialog.CurrentPin)) return;
        }
        trayIcon.Visible = false;
        watcher.Dispose();
        Application.Exit();
    }
}

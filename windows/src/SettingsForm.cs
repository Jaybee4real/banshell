using Microsoft.Win32;

namespace Banshell;

public class SettingsForm : Form
{
    private readonly Watcher watcher;
    private BanshellConfig config;
    private readonly CheckBox autoArmBox;
    private readonly DateTimePicker timePicker;
    private readonly CheckBox motionBox;
    private readonly TrackBar sensitivityBar;
    private readonly Label sensitivityLabel;
    private readonly Label liveAccelLabel;
    private readonly CheckBox powerBox;
    private readonly CheckBox inputBox;
    private readonly NumericUpDown exitDelay;
    private readonly NumericUpDown entryDelay;
    private readonly CheckBox autostartBox;
    private readonly Label readinessLabel;
    private readonly System.Windows.Forms.Timer liveTimer;

    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public SettingsForm(Watcher watcher)
    {
        this.watcher = watcher;
        config = BanshellConfig.Load();
        Text = "BANSHELL Settings";
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        ClientSize = new Size(480, 560);
        Font = new Font("Segoe UI", 10);

        var layout = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Padding = new Padding(20),
            AutoScroll = true,
        };

        layout.Controls.Add(Section("SCHEDULE"));
        var scheduleRow = Row();
        autoArmBox = new CheckBox { Text = "Arm automatically every day at", AutoSize = true };
        autoArmBox.CheckedChanged += (_, _) => SaveFromControls();
        timePicker = new DateTimePicker
        {
            Format = DateTimePickerFormat.Time,
            ShowUpDown = true,
            Width = 100,
            CustomFormat = "HH:mm",
        };
        timePicker.Format = DateTimePickerFormat.Custom;
        timePicker.ValueChanged += (_, _) => SaveFromControls();
        scheduleRow.Controls.Add(autoArmBox);
        scheduleRow.Controls.Add(timePicker);
        layout.Controls.Add(scheduleRow);

        layout.Controls.Add(Section("TRIGGERS"));
        motionBox = new CheckBox { Text = "Motion — accelerometer", AutoSize = true };
        motionBox.CheckedChanged += (_, _) => SaveFromControls();
        layout.Controls.Add(motionBox);

        var sensitivityRow = Row();
        sensitivityRow.Controls.Add(new Label { Text = "Sensitivity:", AutoSize = true, Padding = new Padding(20, 6, 0, 0) });
        sensitivityBar = new TrackBar { Minimum = 2, Maximum = 20, Value = 6, Width = 180, TickFrequency = 2 };
        sensitivityBar.ValueChanged += (_, _) => SaveFromControls();
        sensitivityLabel = new Label { AutoSize = true, Padding = new Padding(0, 6, 0, 0) };
        liveAccelLabel = new Label { AutoSize = true, ForeColor = Color.Gray, Padding = new Padding(8, 6, 0, 0) };
        sensitivityRow.Controls.Add(sensitivityBar);
        sensitivityRow.Controls.Add(sensitivityLabel);
        sensitivityRow.Controls.Add(liveAccelLabel);
        layout.Controls.Add(sensitivityRow);

        powerBox = new CheckBox { Text = "Charger disconnected", AutoSize = true };
        powerBox.CheckedChanged += (_, _) => SaveFromControls();
        layout.Controls.Add(powerBox);

        inputBox = new CheckBox { Text = "Keyboard or mouse touched", AutoSize = true };
        inputBox.CheckedChanged += (_, _) => SaveFromControls();
        layout.Controls.Add(inputBox);

        layout.Controls.Add(Section("TIMING"));
        var timingRow = Row();
        timingRow.Controls.Add(new Label { Text = "Walk-away delay (s)", AutoSize = true, Padding = new Padding(0, 6, 0, 0) });
        exitDelay = new NumericUpDown { Minimum = 5, Maximum = 300, Width = 70 };
        exitDelay.ValueChanged += (_, _) => SaveFromControls();
        timingRow.Controls.Add(exitDelay);
        timingRow.Controls.Add(new Label { Text = "  Siren delay (s)", AutoSize = true, Padding = new Padding(0, 6, 0, 0) });
        entryDelay = new NumericUpDown { Minimum = 3, Maximum = 60, Width = 70 };
        entryDelay.ValueChanged += (_, _) => SaveFromControls();
        timingRow.Controls.Add(entryDelay);
        layout.Controls.Add(timingRow);

        layout.Controls.Add(Section("SECURITY"));
        var pinButton = new Button { Text = "Change Disarm Code…", AutoSize = true };
        pinButton.Click += (_, _) => ChangePin();
        layout.Controls.Add(pinButton);

        layout.Controls.Add(Section("STARTUP"));
        autostartBox = new CheckBox { Text = "Start BANSHELL when Windows starts", AutoSize = true };
        autostartBox.CheckedChanged += (_, _) => ApplyAutostart();
        layout.Controls.Add(autostartBox);

        layout.Controls.Add(Section("READINESS"));
        readinessLabel = new Label { AutoSize = true, MaximumSize = new Size(430, 0) };
        layout.Controls.Add(readinessLabel);

        var footer = new Label
        {
            Text = "Changes save immediately. Windows puts the machine to sleep when the lid closes " +
                   "unless you set the lid action to \"Do nothing\" in Power Options. A hard power-off " +
                   "defeats any software alarm — keep BitLocker and Find My Device on.",
            AutoSize = true,
            MaximumSize = new Size(430, 0),
            ForeColor = Color.Gray,
        };
        layout.Controls.Add(footer);

        Controls.Add(layout);
        LoadIntoControls();

        liveTimer = new System.Windows.Forms.Timer { Interval = 500 };
        liveTimer.Tick += (_, _) => UpdateLive();
        liveTimer.Start();
        FormClosed += (_, _) => liveTimer.Stop();
    }

    private static Label Section(string text) => new()
    {
        Text = text,
        AutoSize = true,
        Font = new Font("Segoe UI", 9, FontStyle.Bold),
        ForeColor = Color.DimGray,
        Padding = new Padding(0, 14, 0, 2),
    };

    private static FlowLayoutPanel Row() => new()
    {
        FlowDirection = FlowDirection.LeftToRight,
        AutoSize = true,
        WrapContents = false,
    };

    private void LoadIntoControls()
    {
        autoArmBox.Checked = config.AutoArmDaily;
        timePicker.Value = DateTime.Today.AddHours(config.ArmHour).AddMinutes(config.ArmMinute);
        motionBox.Checked = config.MotionTrigger;
        powerBox.Checked = config.PowerTrigger;
        inputBox.Checked = config.InputTrigger;
        sensitivityBar.Value = Math.Clamp((int)(config.AccelDeltaG * 100), sensitivityBar.Minimum, sensitivityBar.Maximum);
        sensitivityLabel.Text = $"{config.AccelDeltaG:F2}g";
        exitDelay.Value = Math.Clamp(config.ExitDelaySeconds, (int)exitDelay.Minimum, (int)exitDelay.Maximum);
        entryDelay.Value = Math.Clamp(config.EntryDelaySeconds, (int)entryDelay.Minimum, (int)entryDelay.Maximum);
        using var runKey = Registry.CurrentUser.OpenSubKey(RunKeyPath);
        autostartBox.Checked = runKey?.GetValue("Banshell") != null;
        UpdateLive();
    }

    private void SaveFromControls()
    {
        config.AutoArmDaily = autoArmBox.Checked;
        config.ArmHour = timePicker.Value.Hour;
        config.ArmMinute = timePicker.Value.Minute;
        config.MotionTrigger = motionBox.Checked;
        config.PowerTrigger = powerBox.Checked;
        config.InputTrigger = inputBox.Checked;
        config.AccelDeltaG = sensitivityBar.Value / 100.0;
        sensitivityLabel.Text = $"{config.AccelDeltaG:F2}g";
        config.ExitDelaySeconds = (int)exitDelay.Value;
        config.EntryDelaySeconds = (int)entryDelay.Value;
        config.Save();
        watcher.ReloadConfig(config);
    }

    private void ApplyAutostart()
    {
        using var runKey = Registry.CurrentUser.CreateSubKey(RunKeyPath);
        if (autostartBox.Checked)
            runKey.SetValue("Banshell", $"\"{Application.ExecutablePath}\"");
        else
            runKey.DeleteValue("Banshell", false);
    }

    private void UpdateLive()
    {
        liveAccelLabel.Text = watcher.AccelerometerReading is { } reading
            ? $"now: {reading.X:F2}, {reading.Y:F2}, {reading.Z:F2}"
            : "";
        readinessLabel.Text = (watcher.AccelerometerAvailable
                ? "✅ Accelerometer detected"
                : "❌ No accelerometer — motion trigger unavailable; charger + input triggers still work")
            + "\n✅ Input hooks active"
            + "\n" + (SystemInformation.PowerStatus.PowerLineStatus == PowerLineStatus.Online
                ? "🔌 On AC power" : "🔋 On battery");
    }

    private void ChangePin()
    {
        using var dialog = new PinDialog(config.HasPin);
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        if (config.HasPin && !config.VerifyPin(dialog.CurrentPin))
        {
            MessageBox.Show(this, "Current code is wrong.", "BANSHELL", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }
        if (dialog.NewPin.Length < 4)
        {
            MessageBox.Show(this, "New code must be at least 4 characters.", "BANSHELL", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }
        if (dialog.NewPin != dialog.ConfirmPin)
        {
            MessageBox.Show(this, "Codes do not match.", "BANSHELL", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }
        config.SetPin(dialog.NewPin);
        config.Save();
        watcher.ReloadConfig(config);
    }
}

public class PinDialog : Form
{
    private readonly TextBox currentBox;
    private readonly TextBox newBox;
    private readonly TextBox confirmBox;

    public string CurrentPin => currentBox.Text;
    public string NewPin => newBox.Text;
    public string ConfirmPin => confirmBox.Text;

    public PinDialog(bool requireCurrent)
    {
        Text = "Change Disarm Code";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(320, 200);
        StartPosition = FormStartPosition.CenterParent;

        currentBox = new TextBox { PasswordChar = '●', Width = 260, Location = new Point(30, 20), PlaceholderText = "Current code" };
        newBox = new TextBox { PasswordChar = '●', Width = 260, Location = new Point(30, 60), PlaceholderText = "New code (min 4 chars)" };
        confirmBox = new TextBox { PasswordChar = '●', Width = 260, Location = new Point(30, 100), PlaceholderText = "Confirm new code" };
        currentBox.Visible = requireCurrent;

        var okButton = new Button { Text = "Save", DialogResult = DialogResult.OK, Location = new Point(140, 150) };
        var cancelButton = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel, Location = new Point(225, 150) };
        AcceptButton = okButton;
        CancelButton = cancelButton;

        Controls.AddRange(new Control[] { currentBox, newBox, confirmBox, okButton, cancelButton });
    }
}

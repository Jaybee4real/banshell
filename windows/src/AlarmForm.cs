namespace Banshell;

public class AlarmForm : Form
{
    private readonly BanshellConfig config;
    private readonly Label reasonLabel;
    private readonly Label countdownLabel;
    private readonly TextBox pinBox;
    private readonly System.Windows.Forms.Timer countdownTimer;
    private readonly System.Windows.Forms.Timer enforcerTimer;
    private readonly System.Windows.Forms.Timer focusTimer;
    private DateTime? entryDeadline;
    private float? savedVolume;
    private bool disarmed;

    public event Action? Disarmed;

    public AlarmForm(BanshellConfig config, string reason)
    {
        this.config = config;
        FormBorderStyle = FormBorderStyle.None;
        WindowState = FormWindowState.Maximized;
        TopMost = true;
        BackColor = Color.Black;
        ShowInTaskbar = false;
        ControlBox = false;

        var title = new Label
        {
            Text = "🚨  BANSHELL  🚨",
            Font = new Font("Segoe UI", 42, FontStyle.Bold),
            ForeColor = Color.Red,
            AutoSize = false,
            TextAlign = ContentAlignment.MiddleCenter,
            Dock = DockStyle.Top,
            Height = 140,
            Padding = new Padding(0, 60, 0, 0),
        };

        reasonLabel = new Label
        {
            Text = reason.ToUpperInvariant(),
            Font = new Font("Consolas", 18, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize = false,
            TextAlign = ContentAlignment.MiddleCenter,
            Dock = DockStyle.Top,
            Height = 60,
        };

        countdownLabel = new Label
        {
            Font = new Font("Consolas", 22, FontStyle.Bold),
            ForeColor = Color.Yellow,
            AutoSize = false,
            TextAlign = ContentAlignment.MiddleCenter,
            Dock = DockStyle.Top,
            Height = 60,
        };

        pinBox = new TextBox
        {
            PasswordChar = '●',
            Font = new Font("Consolas", 22, FontStyle.Bold),
            TextAlign = HorizontalAlignment.Center,
            Width = 320,
            PlaceholderText = "ENTER CODE",
        };
        pinBox.KeyDown += (_, args) =>
        {
            if (args.KeyCode == Keys.Enter) SubmitPin();
        };

        var pinHost = new Panel { Dock = DockStyle.Top, Height = 80 };
        pinHost.Controls.Add(pinBox);
        pinHost.Resize += (_, _) => pinBox.Location = new Point((pinHost.Width - pinBox.Width) / 2, 20);

        var hint = new Label
        {
            Text = "Enter disarm code and press Enter",
            Font = new Font("Segoe UI", 12),
            ForeColor = Color.Gray,
            AutoSize = false,
            TextAlign = ContentAlignment.MiddleCenter,
            Dock = DockStyle.Top,
            Height = 40,
        };

        Controls.Add(hint);
        Controls.Add(pinHost);
        Controls.Add(countdownLabel);
        Controls.Add(reasonLabel);
        Controls.Add(title);

        savedVolume = VolumeControl.ReadVolume();
        VolumeControl.SetVolume(0.7f);
        SirenAudio.PlayBeeps();
        entryDeadline = DateTime.Now.AddSeconds(config.EntryDelaySeconds);

        countdownTimer = new System.Windows.Forms.Timer { Interval = 250 };
        countdownTimer.Tick += (_, _) => TickCountdown();
        countdownTimer.Start();

        enforcerTimer = new System.Windows.Forms.Timer { Interval = 150 };
        enforcerTimer.Tick += (_, _) => VolumeControl.SetVolume(1.0f);

        focusTimer = new System.Windows.Forms.Timer { Interval = 1000 };
        focusTimer.Tick += (_, _) =>
        {
            TopMost = true;
            if (Form.ActiveForm != this) Activate();
            if (!pinBox.Focused)
            {
                pinBox.Focus();
                pinBox.SelectionStart = pinBox.TextLength;
                pinBox.SelectionLength = 0;
            }
        };
        focusTimer.Start();

        Shown += (_, _) => pinBox.Focus();
        FormClosing += (_, args) =>
        {
            if (!disarmed) args.Cancel = true;
        };
    }

    private void TickCountdown()
    {
        if (entryDeadline is not { } deadline)
        {
            countdownLabel.Text = "⚠  SIREN ACTIVE  ⚠";
            return;
        }
        var remaining = (deadline - DateTime.Now).TotalSeconds;
        if (remaining <= 0)
        {
            entryDeadline = null;
            SirenAudio.PlaySiren();
            enforcerTimer.Start();
            countdownLabel.Text = "⚠  SIREN ACTIVE  ⚠";
        }
        else
        {
            countdownLabel.Text = $"SIREN IN {Math.Ceiling(remaining):F0}";
        }
    }

    private void SubmitPin()
    {
        var attempt = pinBox.Text;
        pinBox.Text = "";
        if (!config.VerifyPin(attempt))
        {
            reasonLabel.Text = "WRONG CODE";
            return;
        }
        disarmed = true;
        countdownTimer.Stop();
        enforcerTimer.Stop();
        focusTimer.Stop();
        SirenAudio.Stop();
        if (savedVolume is { } volume) VolumeControl.SetVolume(volume);
        Disarmed?.Invoke();
        Close();
    }
}

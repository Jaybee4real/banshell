namespace Banshell;

// Covers one non-primary monitor while the alarm (or its countdown) is up, so the
// desktop is never visible on a second screen. The card and PIN stay on AlarmForm.
public class BlackoutForm : Form
{
    private readonly Panel inner;

    public BlackoutForm(Rectangle bounds)
    {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Bounds = bounds;
        TopMost = true;
        BackColor = Color.FromArgb(90, 10, 10);
        ShowInTaskbar = false;
        ControlBox = false;

        inner = new Panel { Dock = DockStyle.Fill, BackColor = Color.Black, Margin = Padding.Empty };
        Padding = new Padding(16);
        Controls.Add(inner);

        FormClosing += (_, args) =>
        {
            if (!AllowClose) args.Cancel = true;
        };
    }

    public bool AllowClose { get; set; }

    public void SetPulse(bool on)
    {
        BackColor = on ? Color.FromArgb(230, 30, 30) : Color.FromArgb(90, 10, 10);
    }

    public void CloseForReal()
    {
        AllowClose = true;
        Close();
    }
}

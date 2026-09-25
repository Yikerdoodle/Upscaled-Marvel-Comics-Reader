using System;
using System.Drawing;
using System.Windows.Forms;

// Small always-on-top notice for the "press F11 when you're ready" step.
// It's shown right after "marvel0 " is typed into the browser's address
// bar, so it must NEVER take keyboard focus - otherwise the next thing you
// type would go into this window instead of the browser. Hence
// ShowWithoutActivation + WS_EX_NOACTIVATE, and no taskbar button.
public class TVModePrompt : Form {
    private const int WS_EX_TOPMOST = 0x00000008;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_NOACTIVATE = 0x08000000;

    private static readonly Color Background = Color.FromArgb(28, 28, 32);
    private static readonly Color Border = Color.FromArgb(64, 64, 72);
    private static readonly Color MarvelRed = Color.FromArgb(236, 29, 36);
    private static readonly Color BodyText = Color.FromArgb(215, 215, 222);
    private static readonly Color Muted = Color.FromArgb(150, 150, 160);

    public TVModePrompt(string heading, string body) {
        SuspendLayout();

        var accent = new Panel {
            BackColor = MarvelRed,
            Location = new Point(0, 0),
            Size = new Size(5, 122)
        };
        var title = new Label {
            Text = heading,
            Font = new Font("Segoe UI Semibold", 11F),
            ForeColor = Color.White,
            Location = new Point(20, 12),
            Size = new Size(330, 24)
        };
        var text = new Label {
            Text = body,
            Font = new Font("Segoe UI", 9.5F),
            ForeColor = BodyText,
            Location = new Point(20, 40),
            Size = new Size(356, 72)
        };
        var close = new Label {
            Text = ((char)0xD7).ToString(),
            Font = new Font("Segoe UI", 13F),
            ForeColor = Muted,
            Location = new Point(364, 4),
            Size = new Size(24, 26),
            TextAlign = ContentAlignment.MiddleCenter,
            Cursor = Cursors.Hand
        };
        close.Click += (s, e) => Close();
        close.MouseEnter += (s, e) => close.ForeColor = Color.White;
        close.MouseLeave += (s, e) => close.ForeColor = Muted;

        Controls.Add(accent);
        Controls.Add(title);
        Controls.Add(text);
        Controls.Add(close);

        AutoScaleDimensions = new SizeF(96F, 96F);
        AutoScaleMode = AutoScaleMode.Dpi;
        BackColor = Background;
        ClientSize = new Size(392, 122);
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        Text = "Marvel Comics - 4K TV Mode";

        ResumeLayout(false);
    }

    protected override bool ShowWithoutActivation {
        get { return true; }
    }

    protected override CreateParams CreateParams {
        get {
            var cp = base.CreateParams;
            cp.ExStyle |= WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
            return cp;
        }
    }

    // Bottom-right of the laptop screen, just above the taskbar near the
    // "4K" tray icon - clear of the browser's address bar at the top.
    // Positioned in OnLoad because DPI autoscaling has resized the form by
    // then, so Width/Height are the real on-screen size.
    protected override void OnLoad(EventArgs e) {
        base.OnLoad(e);
        Rectangle area = Screen.PrimaryScreen.WorkingArea;
        int margin;
        using (Graphics g = CreateGraphics()) { margin = (int)Math.Round(16 * g.DpiX / 96f); }
        Location = new Point(area.Right - Width - margin, area.Bottom - Height - margin);
    }

    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        using (var pen = new Pen(Border)) {
            e.Graphics.DrawRectangle(pen, 0, 0, ClientSize.Width - 1, ClientSize.Height - 1);
        }
    }
}

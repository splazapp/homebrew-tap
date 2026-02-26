class ClaudecodeNotification < Formula
  desc "Native macOS notifications for Claude Code with click-to-return"
  homepage "https://github.com/splazapp/claude-code-notification"
  url "https://github.com/splazapp/claude-code-notification/archive/refs/tags/v2.1.tar.gz"
  sha256 "a42b44097462862d0997cffa338ec26bebdd4ca6d1072c51e6a90bb65e69d511"
  license "MIT"

  depends_on :macos
  depends_on macos: :ventura

  def install
    # Build universal binary (arm64 + x86_64)
    system "bash", "build.sh"

    # Install hook script and .app bundle to libexec
    libexec.install "claudecode-notification.sh"
    libexec.install "dist/ClaudeCodeNotification.app"
    chmod 0755, libexec/"claudecode-notification.sh"

    # Create setup script that registers hooks in ~/.claude/settings.json
    (bin/"claudecode-notification-setup").write <<~BASH
      #!/bin/bash
      # Register ClaudeCodeNotification hooks in Claude Code settings
      set -euo pipefail

      SETTINGS_FILE="$HOME/.claude/settings.json"
      HOOK_CMD="#{opt_libexec}/claudecode-notification.sh"

      /usr/bin/python3 - "$SETTINGS_FILE" "$HOOK_CMD" << 'PYTHON'
      import json, sys, os

      settings_path = sys.argv[1]
      hook_cmd = sys.argv[2]

      if os.path.exists(settings_path):
          with open(settings_path, 'r') as f:
              settings = json.load(f)
      else:
          os.makedirs(os.path.dirname(settings_path), exist_ok=True)
          settings = {}

      hooks = settings.setdefault("hooks", {})

      for old_pattern in ["claudecode-tap", "claudecode-notification"]:
          for event in list(hooks.keys()):
              entries = hooks[event]
              if isinstance(entries, list):
                  for entry in entries:
                      if isinstance(entry, dict) and "hooks" in entry:
                          entry["hooks"] = [
                              h for h in entry["hooks"]
                              if not (isinstance(h, dict) and old_pattern in h.get("command", ""))
                          ]
                  hooks[event] = [e for e in entries if e.get("hooks")]
                  if not hooks[event]:
                      del hooks[event]

      for event in ["UserPromptSubmit", "Stop", "Notification"]:
          hook_entry = {
              "hooks": [{
                  "type": "command",
                  "command": f"{hook_cmd} {event}"
              }]
          }
          existing = hooks.get(event, [])
          already = any(
              hook_cmd in h.get("command", "")
              for entry in existing if isinstance(entry, dict)
              for h in entry.get("hooks", []) if isinstance(h, dict)
          )
          if not already:
              existing.append(hook_entry)
          hooks[event] = existing

      settings["hooks"] = hooks

      with open(settings_path, 'w') as f:
          json.dump(settings, f, indent=2, ensure_ascii=False)
          f.write('\\n')

      print("Hooks registered in " + settings_path)
      PYTHON

      echo ""
      echo "Done! On first notification, macOS will ask for permission — click Allow."
    BASH
    chmod 0755, bin/"claudecode-notification-setup"
  end

  def post_install
    # Attempt to register hooks automatically (may fail in sandbox)
    system bin/"claudecode-notification-setup"
  rescue => e
    opoo "Auto-registration failed (#{e.message}). Run manually: claudecode-notification-setup"
  end

  def caveats
    <<~EOS
      To register Claude Code hooks, run:
        claudecode-notification-setup

      On first notification, macOS will ask for permission — click Allow.

      To uninstall completely, also remove hooks from ~/.claude/settings.json:
        python3 -c "
      import json; p='$HOME/.claude/settings.json'; s=json.load(open(p))
      [s['hooks'].pop(e) for e in list(s.get('hooks',{})) if not [s['hooks'][e].remove(x) for x in s['hooks'][e] if any('claudecode-notification' in h.get('command','') for h in x.get('hooks',[]))]]
      json.dump(s,open(p,'w'),indent=2,ensure_ascii=False)"
    EOS
  end

  test do
    assert_predicate libexec/"ClaudeCodeNotification.app/Contents/MacOS/claudecode-notification", :exist?
    assert_predicate libexec/"claudecode-notification.sh", :executable?
  end
end

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
  end

  def post_install
    # Register hooks in ~/.claude/settings.json
    settings_file = File.expand_path("~/.claude/settings.json")

    hook_cmd = opt_libexec/"claudecode-notification.sh"

    system "/usr/bin/python3", "-c", <<~PYTHON
      import json, sys, os

      settings_path = "#{settings_file}"
      hook_cmd = "#{hook_cmd}"

      # Load existing settings or create new
      if os.path.exists(settings_path):
          with open(settings_path, 'r') as f:
              settings = json.load(f)
      else:
          os.makedirs(os.path.dirname(settings_path), exist_ok=True)
          settings = {}

      hooks = settings.setdefault("hooks", {})

      # Remove old claudecode-tap / claudecode-notification hooks
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

      # Add new hooks
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
    PYTHON
  end

  def caveats
    <<~EOS
      Claude Code hooks have been registered in ~/.claude/settings.json

      On first notification, macOS will ask for permission — click Allow.

      To uninstall completely, also remove the hook entries from:
        ~/.claude/settings.json

      Or run this one-liner to clean up:
        python3 -c "
      import json
      p = '$HOME/.claude/settings.json'
      s = json.load(open(p))
      for e in list(s.get('hooks', {})):
          s['hooks'][e] = [x for x in s['hooks'][e] if not any('claudecode-notification' in h.get('command','') for h in x.get('hooks',[]))]
          if not s['hooks'][e]: del s['hooks'][e]
      json.dump(s, open(p,'w'), indent=2, ensure_ascii=False)
      "
    EOS
  end

  test do
    assert_predicate libexec/"ClaudeCodeNotification.app/Contents/MacOS/claudecode-notification", :exist?
    assert_predicate libexec/"claudecode-notification.sh", :executable?
  end
end

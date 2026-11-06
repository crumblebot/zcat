class Zcat < Formula
  desc "Terminal-aware cat with Tree-sitter highlighting and Markdown rendering"
  homepage "https://github.com/crumblebot/zcat"
  license "MIT"

  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/crumblebot/zcat/releases/download/v0.1.2/zcat-0.1.2-aarch64-macos.tar.gz"
      sha256 "22d71f6a2a5e0dda13b1cef2283fcf91de34a76a56095f1241466bcb4b5a5c72"
    else
      url "https://github.com/crumblebot/zcat/releases/download/v0.1.2/zcat-0.1.2-x86_64-macos.tar.gz"
      sha256 "cb41ad35f9d67e54134e8651bec36dbc4f7b18027bf10054f2e58cf00350f781"
    end
  else
    url "https://github.com/crumblebot/zcat/releases/download/v0.1.2/zcat-0.1.2-x86_64-linux.tar.gz"
    sha256 "8fd0c1b9e01328acfe2d5d2980d8c130aba0231d6555adcaff19728980897d11"
  end

  on_macos do
    depends_on macos: :sequoia
  end

  on_linux do
    depends_on arch: :x86_64
  end

  def install
    bin.install "bin/zc"
    pkgshare.install "licenses", "THIRD_PARTY.md", "LICENSE"
  end

  def caveats
    <<~EOS
      Run zc to view files. The project and formula are named zcat;
      no zcat or zcat-view command is installed.
    EOS
  end

  test do
    assert_equal "zc 0.1.2\n", shell_output("#{bin}/zc --version")
    assert_match "Usage: zc", shell_output("#{bin}/zc --help")
    raw = "cat bytes\x00\xff\n".b
    assert_equal raw, pipe_output("#{bin}/zc --plain", raw).b

    (testpath/"table.md").write <<~MARKDOWN
      | Path | Contents |
      | :--- | ---: |
      | apps/web/ | Web client |
    MARKDOWN
    output = shell_output("#{bin}/zc -m --color=never --width 60 #{testpath}/table.md")
    assert_match "│ Path", output
    assert_match "apps/web/", output
    assert_match "Web client", output
    refute_match "---", output
    assert output.lines.all? { |line| line.chomp.length <= 60 }

    output = pipe_output("#{bin}/zc --color=always -l zig", "const answer = 42;\n")
    assert_match "\e[", output
    assert_path_exists pkgshare/"licenses"
    refute_path_exists bin/"zcat"
    refute_path_exists bin/"zcat-view"
  end
end

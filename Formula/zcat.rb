class Zcat < Formula
  desc "Terminal-aware cat with code highlighting, Markdown, and images"
  homepage "https://github.com/crumblebot/zcat"
  license "MIT"

  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/crumblebot/zcat/releases/download/v0.2.0/zcat-0.2.0-aarch64-macos.tar.gz"
      sha256 "f3713e7a41ebe7b474267ad95da503adbea2553f0bfc878ce0341785e03470ed"
    else
      url "https://github.com/crumblebot/zcat/releases/download/v0.2.0/zcat-0.2.0-x86_64-macos.tar.gz"
      sha256 "39b7a638506b7ba67afa5aa165b9882b01b329b627092f571a153066da1502be"
    end
  else
    url "https://github.com/crumblebot/zcat/releases/download/v0.2.0/zcat-0.2.0-x86_64-linux.tar.gz"
    sha256 "075612f760cdc5aa4142eff6bd6aa722f7d1389edba18e743d0d2a7afd3b4c93"
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
    assert_equal "zc 0.2.0\n", shell_output("#{bin}/zc --version")
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
    assert_match "stdin [zig]", output
    assert_match "     1  ", output

    # Generated 1x1 red PNG; explicit Kitty mode also works without a TTY.
    png = ["89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489" \
           "0000000d49444154789c63f8cfc0f01f00050001ff89993d1d0000000049454e44ae426082"].pack("H*")
    (testpath/"red.png").binwrite png
    output = shell_output("#{bin}/zc --images=kitty #{testpath}/red.png")
    assert_match "\e_Ga=T,t=d,f=32,s=1,v=1", output
    assert_match "/wAA/w==", output
    assert_path_exists pkgshare/"licenses"
    refute_path_exists bin/"zcat"
    refute_path_exists bin/"zcat-view"
  end
end

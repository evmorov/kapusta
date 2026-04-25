require "fileutils"
(-> do
  tmp_dir = File.expand_path("tmp", Dir.pwd)
  path = File.join(tmp_dir, "file-io-example.txt")
  body = "Ada\nLin"
  begin
    FileUtils.mkdir_p(tmp_dir)
    File.write(path, body)
    p(File.read(path))
    p(File.readlines(path).length)
  ensure
    FileUtils.rm_f(path)
  end
end).call

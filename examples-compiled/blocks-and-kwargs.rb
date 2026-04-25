require "fileutils"
(-> do
    tmp_dir = File.expand_path("tmp", Dir.pwd)
  path = File.join(tmp_dir, "blocks-and-kwargs.txt")
  begin
    FileUtils.mkdir_p(tmp_dir)
    File.open(path, "w", **{:encoding => "UTF-8"}, &proc do |io|
      io.write("Ada\nLin\n")
    end)
    File.open(path, "r", **{:encoding => "UTF-8"}, &proc do |io|
      (-> do
          content = io.read
        p(content.strip)
        p(content.lines.length)
      end).call
    end)
  ensure
    FileUtils.rm_f(path)
  end
end).call

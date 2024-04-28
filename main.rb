require "bundler"
require "find"
require "fileutils"
require "sqlite3"
require "rtesseract"

BASE_PATH = Pathname.new(ENV["XDG_DATA_HOME"] || File.join(Dir.home, ".local/share"))
APP_DATA_PATH = BASE_PATH.join("image-search-demo")
DB_FILENAME = "index.db".freeze

class FileIndex
  def initialize
    FileUtils.mkdir_p APP_DATA_PATH
    @db = SQLite3::Database.new APP_DATA_PATH.join(DB_FILENAME)
    load_schema!
  end

  def all_files
    @db.execute("SELECT path, fulltext FROM scanned_files").flat_map { |row| {path: row[0], fulltext: row[1]} }
  end

  def search(q)
    @db.execute("SELECT path FROM scanned_files WHERE lower(fulltext) LIKE '%' || lower(:query) || '%'",
      {query: q}).flatten
  end

  def index_result(path, text)
    @db.execute "INSERT INTO scanned_files (path, fulltext) VALUES (:path, :fulltext) ON CONFLICT(path) DO UPDATE SET fulltext=:fulltext",
      {path:, fulltext: text}
  end

  private

  def load_schema!
    @db.execute <<~SQL
      CREATE TABLE IF NOT EXISTS scanned_files (
        id INT PRIMARY KEY,
        path VARCHAR UNIQUE,
        fulltext TEXT
      );
    SQL
  end
end

def scan_folder(folder:, file_index:)
  Find.find(folder) do |filepath|
    # TODO: better filtering of filetypes we want to scan
    next unless filepath.to_s.end_with?("jpg", "png")

    fulltext = extract_text(filepath)

    if fulltext.empty?
      puts "No text found for #{filepath}"
    else
      file_index.index_result(filepath, fulltext)
    end
  end
end

def extract_text(filepath)
  RTesseract.new(filepath).to_s
end

def open_file(filepath)
  system %(nohup xdg-open "#{filepath}" &> /dev/null &disown)
end

file_index = FileIndex.new

verb = ARGV[0]

case verb
when "index"
  new_path = ARGV[1] || "samples"

  scan_folder(folder: new_path, file_index:)
when "search", "f", "s"
  q = ARGV[1]

  results = file_index.search(q)

  puts results
when "pluck", "plucky", "pl"
  q = ARGV[1]

  result = file_index.search(q).first

  open_file(result)
when "list", "ls"
  puts file_index.all_files
else
  puts "what even is #{verb}"
end

class Gwyfile
  attr_accessor :name, :gwyobjects
  def initialize(path)
    fin = File.open(path, 'rb').read
    puts "filesize: #{fin.size}"
    raise "File header didn't seem like a gwy file" unless fin[0..3] == 'GWYP'

    # Start parsing GwyObjects
    ptr = 0
    while ptr < fin.size-1
      name = fin.slice!(0, fin.index("\0")+1).chomp
      ptr = fin.slice!(0,4).unpack1("L")
      puts "1st container: #{name}"
      puts "size: #{ptr}"
      puts "remaining fin: #{fin.size}"
      ptr = fin.size
    end

  end
end

# Deserialize Gwyobject into Hash
class GwyObject
  attr_accessor :components
  def initialize(serialized)
  end
end
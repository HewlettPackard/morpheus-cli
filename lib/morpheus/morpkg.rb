require 'zip'

module Morpheus

  # A module for building .morpkg files
  module Morpkg

    # parse the manifest json data for a package source directory
    def self.parse_package_manifest(source_directory)
      source_directory = File.expand_path(source_directory)
      manifest_filename = File.join(source_directory, "package-manifest.json")
      if !File.exist?(manifest_filename)
        raise "Package manifest file not found: #{manifest_filename}"
      end
      manifest = JSON.parse(File.read(manifest_filename))
      return manifest
    end

    # write a .morpkg file for a package source directory
    # validates manifest data
    # default outfile is code-version.morpkg
    # returns outfile (filename) or raises exception
    def self.build_package(source_directory, outfile=nil, do_overwrite=false)
      source_directory = File.expand_path(source_directory)
      manifest = self.parse_package_manifest(source_directory)
      code = manifest["code"]
      version = manifest["version"]
      org = manifest["org"] || manifest["organization"]
      type = manifest["type"]
      if code.nil? || code.empty?
        raise "Package manifest data missing: code"
      end
      if version.nil? || version.empty?
        raise "Package manifest data missing: version"
      end
      # if org.nil? || org.empty?
      #   raise "Package manifest data missing: org"
      # end
      # if type.nil? || type.empty?
      #   raise "Package manifest data missing: type"
      # end
      if outfile.nil? || outfile.empty?
        # outfile = "#{orig_dir}/#{type}-#{code}-#{version}.morpkg"
        # outfile = File.join(File.dirname(source_directory), "#{type}-#{code}-#{version}.morpkg")
        outfile = File.join(File.dirname(source_directory), "#{code}-#{version}.morpkg")
      elsif File.directory?(outfile)
        outfile = File.join(outfile, "#{code}-#{version}.morpkg")
      end
      if Dir.exist?(outfile)
        raise "Invalid package target. #{outfile} is the name of an existing directory."
      end
      if File.exist?(outfile)
        if do_overwrite
          # don't delete, just overwrite.
          # File.delete(outfile)
        else
          raise "Invalid package target. File already exists: #{outfile}"
        end
      end
      # build directories if needed
      if !Dir.exist?(File.dirname(outfile))
        Dir.mkdir(File.dirname(outfile))
      end

      # write the .morpkg file and return filename
      zf = ZipFileGenerator.new(source_directory, outfile)
      zf.write()
      
      return outfile
    end

    # This is a simple example which uses rubyzip to
    # recursively generate a zip file from the contents of
    # a specified directory. The directory itself is not
    # included in the archive, rather just its contents.
    #
    # Usage:
    #   directoryToZip = "/tmp/input"
    #   outputFile = "/tmp/out.zip"
    #   zf = ZipFileGenerator.new(directoryToZip, outputFile)
    #   zf.write()
    class ZipFileGenerator

      # Initialize with the directory to zip and the location of the output archive.
      def initialize(inputDir, outputFile)
        @inputDir = inputDir
        @outputFile = outputFile
      end

      # Zip the input directory.
      def write()
        entries = Dir.entries(@inputDir); entries.delete("."); entries.delete("..")
        io = Zip::File.open(@outputFile, create: true);
        writeEntries(entries, "", io)
        io.close();
      end

      # A helper method to make the recursion work.
      private
      def writeEntries(entries, path, io)

        entries.each { |e|
          zipFilePath = path == "" ? e : File.join(path, e)
          diskFilePath = File.join(@inputDir, zipFilePath)
          puts "Deflating " + diskFilePath # remove me
          if  File.directory?(diskFilePath)
            io.mkdir(zipFilePath)
            subdir =Dir.entries(diskFilePath); subdir.delete("."); subdir.delete("..")
            writeEntries(subdir, zipFilePath, io)
          else
            io.get_output_stream(zipFilePath) { |f| f.puts(File.open(diskFilePath, "rb").read())}
          end
        }
      end

    end

  end
end

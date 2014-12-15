#
# Copyright 2014 Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module Omnibus
  class Packager::Docker < Packager::Base
    id :docker

    setup do
      # Copy the full-stack installer into our scratch directory, accounting for
      # any excluded files.
      #
      # /opt/hamlet => /tmp/daj29013/opt/hamlet
      destination = File.join(staging_dir, project.install_dir)
      FileSyncer.sync(project.install_dir, destination, exclude: exclusions)

      # Copy over any user-specified extra package files.
      #
      # Files retain their relative paths inside the scratch directory, so
      # we need to grab the dirname of the file, create that directory, and
      # then copy the file into that directory.
      #
      # extra_package_file '/path/to/foo.txt' #=> /tmp/scratch/path/to/foo.txt
      project.extra_package_files.each do |file|
        parent      = File.dirname(file)
        destination = File.join(staging_dir, parent)

        create_directory(destination)
        copy_file(file, destination)
      end

    end

    build do

      # Create the docker image
      create_docker_image
    end

    #
    # @!group DSL methods
    # --------------------------------------------------

    #
    # Set or return the vendor who made this package.
    #
    # @example
    #   vendor "Seth Vargo <sethvargo@gmail.com>"
    #
    # @param [String] val
    #   the vendor who make this package
    #
    # @return [String]
    #   the vendor who make this package
    #
    def vendor(val = NULL)
      if null?(val)
        @vendor || 'Omnibus <omnibus@getchef.com>'
      else
        unless val.is_a?(String)
          raise InvalidValue.new(:vendor, 'be a String')
        end

        @vendor = val
      end
    end
    expose :vendor

    #
    # Set or return the license for this package.
    #
    # @example
    #   license "Apache 2.0"
    #
    # @param [String] val
    #   the license for this package
    #
    # @return [String]
    #   the license for this package
    #
    def license(val = NULL)
      if null?(val)
        @license || 'unknown'
      else
        unless val.is_a?(String)
          raise InvalidValue.new(:license, 'be a String')
        end

        @license = val
      end
    end
    expose :license

    #
    # Set or return the priority for this package.
    #
    # @example
    #   priority "extra"
    #
    # @param [String] val
    #   the priority for this package
    #
    # @return [String]
    #   the priority for this package
    #
    def priority(val = NULL)
      if null?(val)
        @priority || 'extra'
      else
        unless val.is_a?(String)
          raise InvalidValue.new(:priority, 'be a String')
        end

        @priority = val
      end
    end
    expose :priority

    #
    # Set or return the section for this package.
    #
    # @example
    #   section "databases"
    #
    # @param [String] val
    #   the section for this package
    #
    # @return [String]
    #   the section for this package
    #
    def section(val = NULL)
      if null?(val)
        @section || 'misc'
      else
        unless val.is_a?(String)
          raise InvalidValue.new(:section, 'be a String')
        end

        @section = val
      end
    end
    expose :section

    #
    # @!endgroup
    # --------------------------------------------------

    #
    # The name of the package to create. Note, this does **not** include the
    # extension.
    #
    def package_name
      "#{safe_base_package_name}_#{safe_version}-#{safe_build_iteration}_#{safe_architecture}.tar.gz"
    end

    #
    # Render a control file in +#{debian_dir}/control+ using the supplied ERB
    # template.
    #
    # @return [void]
    #
    def write_docker_file
      render_template(resource_path('Dockerfile.erb'),
        destination: File.join(staging_dir, 'Dockerfile')
      )
    end

    #
    # Create the +.deb+ file, compressing at gzip level 9. The use of the
    # +fakeroot+ command is required so that the package is owned by
    # +root:root+, but the build user does not need to have sudo permissions.
    #
    # @return [void]
    #
    def create_docker_image
      log.info(log_key) { "Creating docker image .tar.gz" }

      # Execute the build command
      Dir.chdir(Config.package_dir) do
        shellout!("fakeroot docker build  -t gdurham/notifier:0.1.0 #{staging_dir}/Dockerfile > #{package_name}")
      end
    end

    #
    # Return the Debian-ready base package name, converting any invalid characters to
    # dashes (+-+).
    #
    # @return [String]
    #
    def safe_base_package_name
      if project.package_name =~ /\A[a-z0-9\.\+\-]+\z/
        project.package_name.dup
      else
        converted = project.package_name.downcase.gsub(/[^a-z0-9\.\+\-]+/, '-')

        log.warn(log_key) do
          "The `name' compontent of Debian package names can only include " \
          "lower case alphabetical characters (a-z), numbers (0-9), dots (.), " \
          "plus signs (+), and dashes (-). Converting `#{project.package_name}' to " \
          "`#{converted}'."
        end

        converted
      end
    end

    #
    # This is actually just the regular build_iteration, but it felt lonely
    # among all the other +safe_*+ methods.
    #
    # @return [String]
    #
    def safe_build_iteration
      project.build_iteration
    end

    #
    # Return the Debian-ready version, replacing all dashes (+-+) with tildes
    # (+~+) and converting any invalid characters to underscores (+_+).
    #
    # @return [String]
    #
    def safe_version
      version = project.build_version.dup

      if version =~ /\-/
        converted = version.gsub('-', '~')

        log.warn(log_key) do
          "Dashes hold special significance in the Debian package versions. " \
          "Versions that contain a dash and should be considered an earlier " \
          "version (e.g. pre-releases) may actually be ordered as later " \
          "(e.g. 12.0.0-rc.6 > 12.0.0). We'll work around this by replacing " \
          "dashes (-) with tildes (~). Converting `#{project.build_version}' " \
          "to `#{converted}'."
        end

        version = converted
      end

      if version =~ /\A[a-zA-Z0-9\.\+\:\~]+\z/
        version
      else
        converted = version.gsub(/[^a-zA-Z0-9\.\+\:\~]+/, '_')

        log.warn(log_key) do
          "The `version' component of Debian package names can only include " \
          "alphabetical characters (a-z, A-Z), numbers (0-9), dots (.), " \
          "plus signs (+), dashes (-), tildes (~) and colons (:). Converting " \
          "`#{project.build_version}' to `#{converted}'."
        end

        converted
      end
    end

    #
    # Debian does not follow the standards when naming 64-bit packages.
    #
    # @return [String]
    #
    def safe_architecture
      case Ohai['kernel']['machine']
      when 'x86_64'
        'amd64'
      when 'i686'
        'i386'
      when 'armv6l'
        if Ohai['platform'] == 'raspbian'
          'armhf'
        else
          'armv6l'
        end
      else
        Ohai['kernel']['machine']
      end
    end
  end
end

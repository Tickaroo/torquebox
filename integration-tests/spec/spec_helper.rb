require 'torquespec'
require 'fileutils'
require 'rbconfig'
require 'torquebox-rake-support'

$: << File.dirname( __FILE__ )

MUTABLE_APP_BASE_PATH  = File.join( File.dirname( __FILE__ ), '..', 'target', 'apps' )
TESTING_ON_WINDOWS = ( java.lang::System.getProperty( "os.name" ) =~ /windows/i )
SLIM_DISTRO = java.lang::System.getProperty( "org.torquebox.slim_distro" ) == "true"

def jboss_home
  if SLIM_DISTRO
    File.expand_path( File.join( File.dirname( __FILE__ ), '..', 'target', 'integ-dist', 'jboss' ) )
  else
    Dir.glob( File.join( File.dirname( __FILE__ ), '..', 'target', 'integ-dist', 'jboss-eap-6*' ) ).first
  end
end

def jruby_home
  if SLIM_DISTRO
    File.expand_path( File.join( File.dirname( __FILE__ ), '..', 'target', 'integ-dist', 'jruby' ) )
  else
    File.join( Dir.glob( File.join( File.dirname( __FILE__ ), '..', 'target', 'integ-dist', 'jboss-eap-6*' ) ).first, 'jruby' )
  end
end
java.lang::System.setProperty( 'jruby.home', jruby_home )

def jboss_log_dir
  File.join( jboss_home, 'standalone', 'log' )
end

TorqueSpec.local {
  require 'spec_helper_integ'
}

TorqueSpec.configure do |config|
  config.jboss_home = jboss_home
  config.jvm_args = "-Xms256m -Xmx1024m -XX:MaxPermSize=384m -XX:NewRatio=8 -XX:+UseParallelGC -XX:+UseParallelOldGC -XX:SoftRefLRUPolicyMSPerMB=100 -Djruby.home=#{config.jruby_home} -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -Xloggc:#{File.join( jboss_log_dir, 'gc.log' )} -Djava.net.preferIPv4Stack=true -Djboss.modules.system.pkgs=$JBOSS_MODULES_SYSTEM_PKGS -Djava.awt.headless=true"
  config.max_heap = java.lang::System.getProperty( 'max.heap' )
  config.lazy = java.lang::System.getProperty( 'jboss.lazy' ) == "true"
  config.jvm_args += " -Dgem.path=default"
  #config.jvm_args += " -Xrunjdwp:transport=dt_socket,address=8787,server=y,suspend=y"
  config.knob_root = File.expand_path( File.join( File.dirname( __FILE__ ), '..', 'target', 'knobs' ) )
  config.spec_dir = File.dirname( __FILE__ )

  if java.lang::System.getProperty( "integ.debug" ) == "true"
    config.jvm_args += " -Xrunjdwp:transport=dt_socket,address=8787,server=y,suspend=y"
  end
end
FileUtils.mkdir_p(TorqueSpec.knob_root) unless File.exist?(TorqueSpec.knob_root)
FileUtils.mkdir_p( jboss_log_dir ) unless File.exist?( jboss_log_dir )

module TorqueSpec
  module AS7
    def start_command
      ENV['JAVA_OPTS'] = "#{TorqueSpec.jvm_args} -Djboss.home.dir=\"#{TorqueSpec.jboss_home}\""
      script_suffix = TESTING_ON_WINDOWS ? "bat" : "sh"
      boot_script = "standalone.#{script_suffix}"
      server_config = SLIM_DISTRO ? "standalone.xml" : "torquebox-full.xml"
      "\"#{TorqueSpec.jboss_home}/bin/#{boot_script}\" --server-config=#{server_config}"
    end
  end

  module Domain
    def start_command
      ENV['JAVA_OPTS'] = "#{TorqueSpec.jvm_args} -Djboss.home.dir=\"#{TorqueSpec.jboss_home}\""
      script_suffix = TESTING_ON_WINDOWS ? "bat" : "sh"
      boot_script = "domain.#{script_suffix}"
      server_config = SLIM_DISTRO ? "domain.xml" : "torquebox-full.xml"
      "\"#{TorqueSpec.jboss_home}/bin/#{boot_script}\" --domain-config=#{server_config}"
    end

    def ready?
      host = host_controller[1]
      host["server"].size > 1
    rescue
      false
    end
  end
end

def mutable_app(path)
  full_path = File.join( MUTABLE_APP_BASE_PATH, path )
  dest_path = File.dirname( full_path )
  FileUtils.rm_rf( full_path )
  FileUtils.mkdir_p( dest_path )
  FileUtils.cp_r( File.join( File.dirname( __FILE__ ), '..', 'apps', path ), dest_path )
end

def jruby_binary
  bin = File.expand_path( File.join( jruby_home, 'bin', 'jruby' ) )
  bin << ".exe" if TESTING_ON_WINDOWS
  bin
end

def integ_jruby_launcher
  File.expand_path( File.join( File.dirname( __FILE__ ), 'integ_jruby_launcher.rb' ) )
end

def integ_jruby(command)
  ENV['JAVA_OPTS'] = '-XX:+TieredCompilation -XX:TieredStopAtLevel=1'
  jruby_version = case RUBY_VERSION
                  when /^1\.8\./ then ' --1.8'
                  when /^1\.9\./ then ' --1.9'
                  when /^2\.0\./ then ' --2.0'
                  end
  full_command = %Q{#{jruby_binary} #{jruby_version} #{integ_jruby_launcher} "#{command}"}
  full_command << " 2>&1" unless TESTING_ON_WINDOWS
  `#{full_command}`
end

def normalize_path(path)
    path = path.slice(0..0).downcase + path.slice(1..-1) if TESTING_ON_WINDOWS
    File.expand_path(path.strip)
end

def assert_paths_are_equal(actual, expected) 
  normalize_path(actual).should eql(normalize_path(expected))
end

def wait_for_condition(timeout, interval, condition)
  start_time = Time.now
  while (Time.now - start_time < timeout) do
    value = yield
    return value if condition.call(value)
    sleep(interval)
  end
  nil
end

# JRuby 1.7.0 has a bug where two threads can deadlock if the thread
# finishing normally and the thread being killed happened to get
# interleaved. This impacts the DRb implemention in 1.8 mode so
# workaround that by waiting a bit before killing any alive threads.
#
# See https://gist.github.com/02c60ec8a42d445acffa
if RUBY_VERSION < '1.9' && JRUBY_VERSION > '1.7'
  require 'drb'
  require 'thread'
  module DRb
    class DRbServer
      def kill_sub_thread
        Thread.new do
          grp = ThreadGroup.new
          grp.add(Thread.current)
          list = @grp.list
          while list.size > 0
            list.each do |th|
              wait_count = 0
              while wait_count < 5
                sleep 0.1 if th.alive?
                wait_count += 1
              end
              th.kill if th.alive?
            end
            list = @grp.list
          end
        end
      end
    end
  end
end

# JRuby 1.6.7.2 in 1.9 mode has a bug where it needs ObjectSpace for
# DRb to work. So, we swipe JRuby master's implementation and patch
# things up.
if RUBY_VERSION > '1.9' && JRUBY_VERSION < '1.7'
  require 'drb'
  require 'weakref'
  module DRb
    class DRbIdConv
      # Convert an object reference id to an object.
      #
      # This implementation looks up the reference id in the local object
      # space and returns the object it refers to.
      def to_obj(ref)
        _get(ref)
      end

      # Convert an object into a reference id.
      #
      # This implementation returns the object's __id__ in the local
      # object space.
      def to_id(obj)
        obj.nil? ? nil : _put(obj)
      end

      def _clean
        dead = []
        id2ref.each {|id,weakref| dead << id unless weakref.weakref_alive?}
        dead.each {|id| id2ref.delete(id)}
      end

      def _put(obj)
        _clean
        id2ref[obj.__id__] = WeakRef.new(obj)
        obj.__id__
      end

      def _get(id)
        weakref = id2ref[id]
        if weakref
          result = weakref.__getobj__ rescue nil
          if result
            return result
          else
            id2ref.delete id
          end
        end
        nil
      end

      def id2ref
        @id2ref ||= {}
      end
      private :_clean, :_put, :_get, :id2ref
    end
  end
end

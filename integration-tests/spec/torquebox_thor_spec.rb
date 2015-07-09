require 'spec_helper'
require 'fileutils'

describe "torquebox thor utility tests" do

  before(:all) do
    ENV['TORQUEBOX_HOME'] = File.join(File.dirname(__FILE__), '..', 'target', 'integ-dist')
    ENV['JBOSS_HOME'] = jboss_home
  end

  describe "torquebox archive" do

    it "should archive an app from the root" do
      Dir.chdir( root_dir ) do
        tb('archive')
        File.exist?("#{root_dir}/basic.knob").should == true
        FileUtils.rm_rf("#{root_dir}/basic.knob")
      end
    end

    it "should archive an app with a root specified" do
      tb("archive #{root_dir}")
      File.exist?('basic.knob').should == true
      FileUtils.rm_rf('basic.knob')
    end

    it "should archive and deploy an app from the root" do
      Dir.chdir( root_dir ) do
        check_deployment("archive --deploy", 'basic', '.knob')
        File.exist?("#{root_dir}/basic.knob").should == true
        FileUtils.rm_rf "#{root_dir}/basic.knob"
        check_undeployment('undeploy', 'basic', '.knob')
      end
    end

    it "should archive and deploy an app with a root specified" do
      check_deployment("archive #{root_dir} --deploy", 'basic', '.knob')
      File.exist?('basic.knob').should == true
      FileUtils.rm_rf('basic.knob')
      Dir.chdir( root_dir ) do
        check_undeployment("undeploy", 'basic', '.knob')
      end
    end

    it "should precompile assets" do
      # Remove Gemfile.lock since varying Rake versions may get picked
      # up during integ runs and bundler will complain during asset
      # compilation
      FileUtils.rm_rf(File.join(root_dir, 'Gemfile.lock'))
      assets_dir = File.join(root_dir, 'public', 'assets')
      File.exist?(File.join(assets_dir, 'application.css')).should == false
      File.exist?(File.join(assets_dir, 'application.js')).should == false
      begin
        archive_output = tb("archive #{root_dir} --precompile-assets")
        File.exist?('basic.knob').should == true
        File.exist?(File.join(assets_dir, 'application.css')).should == true
        File.exist?(File.join(assets_dir, 'application.js')).should == true
        knob_files = `jar -tf basic.knob`
        knob_files.should include('public/assets/application.css')
        knob_files.should include('public/assets/application.js')
      rescue Exception => ex
        puts archive_output
        raise ex
      ensure
        FileUtils.rm_rf('basic.knob')
        FileUtils.rm_rf(File.join(root_dir, 'public', 'assets'))
      end
    end

    it "should package gems" do
      pending "rubygems fix for bundle package of default gems"
      gem_version = RUBY_VERSION[0..2]
      # 2.0 gems get installed into 1.9 for whatever reason
      gem_version = '1.9' if gem_version == '2.0'
      bundle_dir = File.join(root_dir, 'vendor', 'bundle', 'jruby')
      FileUtils.rm_rf(bundle_dir)
      begin
        tb("archive #{root_dir} --package-gems --package-without assets")
        Dir.glob("#{bundle_dir}/#{gem_version}/*").should_not be_empty
        knob_files = `jar -tf basic.knob`
        knob_files.should include("vendor/bundle/jruby/#{gem_version}/gems/torquebox")
        knob_files.should_not include("vendor/bundle/jruby/#{gem_version}/gems/uglifier")
        knob_files.should_not include('vendor/cache')
      ensure
        FileUtils.rm_rf('basic.knob')
        FileUtils.rm_rf(bundle_dir)
        FileUtils.rm_rf(File.join(root_dir, 'vendor', 'cache'))
      end
    end

    it "should exclude files" do
      begin
        tb("archive #{root_dir} --exclude public/404.html config/.+ .+file")
        knob_files = `jar -tf basic.knob`
        knob_files.should include('README')
        knob_files.should_not include('Rakefile')
        knob_files.should_not include('Gemfile')
        knob_files.should include('public/500.html')
        knob_files.should_not include('public/404.html')
        knob_files.should_not include('config/application.rb')
        knob_files.should_not include('config/environments/production.rb')
      ensure
        FileUtils.rm_rf('basic.knob')
      end
    end

  end

  describe "torquebox deploy" do

    it "should deploy a basic app" do
      Dir.chdir( root_dir ) do
        check_deployment "deploy"
        check_undeployment "undeploy"
      end
    end

    it "should deploy an app with a name specified on the command line" do
      Dir.chdir( root_dir ) do
        check_deployment( "deploy --name=foobedoo", 'foobedoo' )
        check_undeployment( "undeploy --name=foobedoo", 'foobedoo')
      end
    end

    it "should deploy an app with a context path specified on the command line" do
      Dir.chdir( root_dir ) do
        check_deployment 'deploy --context_path=/leftorium'
        contents = File.read("#{TorqueBox::DeployUtils.deploy_dir}/basic-knob.yml")
        contents.should match(/context: ['"]?\/leftorium['"]?/)
        check_undeployment 'undeploy'
      end
    end

    it "should deploy an app with an environment specified on the command line" do
      Dir.chdir( root_dir ) do
        check_deployment 'deploy --env=production'
        contents = File.read("#{TorqueBox::DeployUtils.deploy_dir}/basic-knob.yml")
        contents.should include('production')
        check_undeployment 'undeploy'
      end
    end

    it "should deploy an app with a root specified on the command line" do
      check_deployment "deploy #{root_dir}"
      Dir.chdir( root_dir ) do
        check_undeployment "undeploy"
      end
    end

  end

  # Disabled on Windows because it pops up a cmd.exe dialog that must
  # be manually closed on the CI machine for the test to continue.
  unless TESTING_ON_WINDOWS
    describe "torquebox run" do
      it "should pass JVM options specified on the command line" do
        output = tb( 'run -J \"-Xmx384m -Dmy.property=value\" --extra \"\--version\"' )
        output.should match( /\s+JAVA_OPTS: .* -Xmx384m -Dmy\.property=value/ )
      end
    end
  end

  describe "torquebox rails" do
    before(:all) do
      ruby = org.jruby.Ruby.new_instance
      @rails_3_version = ruby.evalScriptlet <<-EOS
        ENV.delete('GEM_HOME')
        ENV.delete('GEM_PATH')
        gem('rails', '~> 3.2')
        require 'rails'
        Rails::VERSION::STRING
      EOS
    end

    before(:each) do
      ENV['RAILS_VERSION'] = @rails_3_version
      @app_dir = File.join( File.dirname( __FILE__ ), '..', 'target', 'apps', 'torquebox_thor_spec_app' )
    end

    after(:each) do
      ENV['RAILS_VERSION'] = nil
      FileUtils.rm_rf( @app_dir )
    end

    it "should create the app and its directory" do
      tb( "rails #{@app_dir} --skip-bundle" )
      check_app_dir
    end

    it "should create the app even if its directory already exists" do
      FileUtils.mkdir_p( @app_dir )
      Dir.chdir( @app_dir ) do
        tb( 'rails --skip-bundle' )
      end
      check_app_dir
    end

    it "should modify the app if it already exists" do
      rails( ENV['RAILS_VERSION'], "new #{@app_dir} --skip-bundle" )
      File.exist?( File.join( @app_dir, 'Gemfile' ) ).should be_true
      File.read( File.join( @app_dir, 'Gemfile' ) ).should_not include( 'torquebox' )
      tb( "rails #{@app_dir} --skip-bundle" )
      check_app_dir
    end

    it "should modify the app in the current directory if it already exists" do
      rails( ENV['RAILS_VERSION'], "new #{@app_dir} --skip-bundle" )
      File.exist?( File.join( @app_dir, 'Gemfile' ) ).should be_true
      File.read( File.join( @app_dir, 'Gemfile' ) ).should_not include( 'torquebox' )
      Dir.chdir( @app_dir ) do
        tb( 'rails --skip-bundle' )
      end
      check_app_dir
    end

    it "should create a rails 2.3 app and its directory" do
      # 2.3 will automatically get chosen if we don't specify, and
      # this ensures things work without explicitly setting
      # RAILS_VERSION
      ENV['RAILS_VERSION'] = nil
      output = tb( "rails #{@app_dir}" )
      File.exist?( @app_dir ).should be_true
      File.exist?( File.join( @app_dir, 'config', 'environment.rb' ) ).should be_true
      contents = File.read( File.join( @app_dir, 'config', 'environment.rb' ) )
      puts output unless contents.include?( 'torquebox' )
      contents.should include( 'torquebox' )
    end

    if RUBY_VERSION >= '1.9'
      it "should create a rails 4 app and its directory" do
        ENV['RAILS_VERSION'] = '~>4.0'
        tb( "rails #{@app_dir} --skip-bundle" )
        check_app_dir
      end
    end

    def check_app_dir
      File.exist?( @app_dir ).should be_true
      File.exist?( File.join( @app_dir, 'Gemfile' ) ).should be_true
      File.read( File.join( @app_dir, 'Gemfile' ) ).should include( 'torquebox' )
    end

    def rails( version, cmd )
      if JRUBY_VERSION >= '1.7'
        version = version.sub('>', '\>')
      end
      rails_cmd = "require 'rubygems';" +
        "gem 'railties', '#{version}';" +
        "load Gem.bin_path('railties', 'rails', '#{version}');"
      puts integ_jruby("-e \\\"#{rails_cmd}\\\" #{cmd}")
    end
  end

  private

  def check_deployment(tb_command, name = 'basic', suffix = '-knob.yml')
    output = tb(tb_command)
    output.should include("Deployed: #{name}#{suffix}")
    deployment = "#{TorqueBox::DeployUtils.deploy_dir}/#{name}#{suffix}"
    dodeploy = "#{deployment}.dodeploy"
    isdeploying = "#{deployment}.isdeploying"
    deployed = "#{deployment}.deployed"
    File.exist?(deployment).should == true
    (File.exist?(dodeploy) || File.exist?(isdeploying) || File.exist?(deployed)).should == true
  end

  def check_undeployment(tb_command, name = 'basic', suffix = '-knob.yml')
    output = tb(tb_command)
    output.should include("Undeployed: #{name}#{suffix}")

    # give the AS as many as five seconds to undeploy
    5.times {
      break unless File.exist?("#{TorqueBox::DeployUtils.deploy_dir}/#{name}#{suffix}")
      puts "Waiting for undeployment..."
      sleep 1
    }

    File.exist?("#{TorqueBox::DeployUtils.deploy_dir}/#{name}#{suffix}").should == false
    File.exist?("#{TorqueBox::DeployUtils.deploy_dir}/#{name}#{suffix}.dodeploy").should == false
    output
  end

  def root_dir
    File.join( File.dirname(__FILE__), '..', 'apps', 'rails3.1', 'basic' )
  end

  def gem_dir
    dir = JRUBY_VERSION >= '1.7' ? 'shared' : '1.8'
    File.expand_path( File.join( jruby_home,  'lib', 'ruby',
                                 'gems', dir ) )
  end

  def tb(cmd)
    integ_jruby("-S torquebox #{cmd}")
  end

end

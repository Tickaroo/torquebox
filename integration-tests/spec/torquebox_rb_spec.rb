require 'spec_helper'

describe "an app using a torquebox.rb" do

  deploy( { :application => { :root => "#{File.dirname(__FILE__)}/../apps/rack/basic-torquebox-rb" },
            :environment => { 'FOO' => 'baz' } } )

  context "external tests" do
    before(:each) do
      visit "/torquebox-rb" 
    end
    
    it "should have the correct environment vars" do
      page.find("#success")[:class].should =~ /gravy/
      page.find("#success")[:class].should =~ /biscuit/
    end

    it "settings in the external descriptor should override" do
      page.find("#success")[:class].should =~ /baz/
    end

    it "should be in the correct dir" do
      page.find("#dir").text.should =~ %r{apps/rack/basic-torquebox-rb/config$}
    end


    it "should have a pool specified with a hash" do
      lambda { 
        mbean('torquebox.pools:name=foo,app=an_app_using_a_torquebox_rb') do |pool|
          pool.should_not be_nil
          pool.minimum_instances.should == 0
          pool.maximum_instances.should == 6
          pool.lazy.should == false
        end
      }.should_not raise_error()
    end
    
    it "should have a pool specified as a block" do
      lambda { 
        mbean('torquebox.pools:name=cheddar,app=an_app_using_a_torquebox_rb') do |pool|
          pool.should_not be_nil
          pool.minimum_instances.should == 0
          pool.maximum_instances.should == 6
          pool.lazy.should == true
        end
      }.should_not raise_error()
    end

    it "should have a queue we specify" do
      lambda { 
        mbean('org.hornetq:module=JMS,type=Queue,name="/queue/a-queue"')
      }.should_not raise_error()
    end

    it "should have a topic we specify" do
      lambda { 
        mbean('org.hornetq:module=JMS,type=Topic,name="/topic/a-topic"')
      }.should_not raise_error()
    end
    
    it "should not have a backgroundable queue (options_for w/a disable)" do
      lambda { 
        mbean('org.hornetq:module=JMS,type=Queue,name="/queues/torquebox/an_app_using_a_torquebox_rb/tasks/torquebox_backgroundable"')
      }.should raise_error()
    end

    it "should create a job" do
      mbean('torquebox.jobs:name=a_job,app=an_app_using_a_torquebox_rb') do |job|
        job.cron_expression.should == '*/1 * * * * ?'
        job.ruby_class_name.should == 'AJob'
      end
    end

    it "should create a processor with a hash" do
      mbean('torquebox.messaging.processors:name=/queue/another_queue/a_processor,app=an_app_using_a_torquebox_rb') do |proc|
        proc.destination_name.should == '/queue/another-queue'
        proc.concurrency.should == 2
        proc.message_selector.should == "steak = 'salad'"
        proc.xa_enabled.should == false
      end
    end

    it "should create a processor with a block" do
      mbean('torquebox.messaging.processors:name=/queue/yet_another_queue/a_processor,app=an_app_using_a_torquebox_rb') do |proc|
        proc.destination_name.should == '/queue/yet-another-queue'
        proc.concurrency.should == 2
        proc.message_selector.should == "steak = 'salad'"
        proc.xa_enabled.should == true
      end
    end

    it "should create allow a singleton processor" do
      mbean('torquebox.messaging.processors:name=/queue/singleton_queue/a_processor,app=an_app_using_a_torquebox_rb') do |proc|
        proc.destination_name.should == '/queue/singleton-queue'
        proc.concurrency.should == 1
        proc.xa_enabled.should == false
      end
    end

    it "should create a service with a hash" do
      mbean('torquebox.services:name=ham,app=an_app_using_a_torquebox_rb') do |service|
        service.ruby_class_name.should == 'AService'
      end
    end

    it "should create a service with a block" do
      mbean('torquebox.services:name=biscuit,app=an_app_using_a_torquebox_rb') do |service|
        service.ruby_class_name.should == 'AnotherService'
      end
    end

    it "should create a service with the same class as another service" do
      mbean('torquebox.services:name=another_service,app=an_app_using_a_torquebox_rb') do |service|
        service.ruby_class_name.should == 'AnotherService'
      end
    end

  end

  remote_describe "in container" do
    
    it "should have an authentication domain" do
      require 'torquebox-security'
      auth = TorqueBox::Authentication['ham']
      auth.should_not be_nil
    end

    it "should allow for multiple authentication domains" do
      require 'torquebox-security'
      auth = TorqueBox::Authentication['ham']
      auth.should_not be_nil
      auth = TorqueBox::Authentication['biscuit']
      auth.should_not be_nil
    end

    it "should pass configuration to the service" do
      response = TorqueBox::Messaging::Queue.new( '/queue/a-queue' ).receive( :timeout => 120_000 )
      response.should == :bar
    end

    it "should pass configuration to the service from a block" do
      response = TorqueBox::Messaging::Queue.new( '/queue/flavor-queue' ).receive( :timeout => 120_000 )
      response.should == 'with honey'
    end

    it "should pass configuration to the job" do
      response = TorqueBox::Messaging::Queue.new( '/queue/configured-job-queue' ).receive( :timeout => 120_000 )
      response.should == 'biscuit'
    end

    it "should set the default message encoding" do
      ENV['DEFAULT_MESSAGE_ENCODING'].should == 'marshal_base64'
    end

    it "should properly set the session timeout" do
      context = TorqueBox.fetch( 'jboss.web.deployment.default-host./torquebox-rb' )
      context.session_timeout.should == 1234
    end
  end
end

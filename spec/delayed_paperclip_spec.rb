
require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '../lib/delayed_paperclip'))

class ImageJob < Struct.new(:image_id)
  def perform
  end
end

module Delayed
  class Job
    def self.enqueue(job)
    end
  end
end

module PaperClipMock
  
  class <<self
    def included base
      base.extend ClassMethods
    end
  end
  
  module ClassMethods
    def attachment_definitions
      {@name => nil}
    end
  
    def has_attached_file(name)
      @name = name
    end
  end
end

module ActiveRecord
  class Base
    include PaperClipMock
    include DelayedPaperclip
    
    def self.after_create_callbacks
      @after_create_callbacks
    end

    def self.after_create(callback)
      @after_create_callbacks ||= []
      @after_create_callbacks << callback
    end

    def save
      self.class.after_create_callbacks.each do |callback|
        self.send(callback)
      end
      true
    end

    def self.alias_method_chain(original, topping)
    end
    
  end
end

class Image < ActiveRecord::Base
end

describe "DelayedPaperclip" do
  
  before(:each) do
    @good_dir = File.expand_path(File.join(File.dirname(__FILE__), "tmp/images")) 
    @good_class_name = "ImageJob"
    @logger = mock('logger')
    @logger.stub!(:info)
    
    Image.has_attached_file :data
    Image.delay_paperclip :tmp_dir => @good_dir, :job_class => @good_class_name
    
    @image = Image.new
    @image.stub!(:id).and_return(1)
    @image.stub!(:new_record?).and_return(false)
        
    uploaded_file = File.new(File.expand_path(File.join(File.dirname(__FILE__), "tmp/file_uploads/wurst.jpg")))
    @data = mock(Object)
    @data.stub!(:queued_for_write).and_return({:original => uploaded_file })

    @image.stub!(:data).and_return(@data)
    @image.stub!(:data_file_name).and_return("wurst.jpg")
    @image.stub(:logger).and_return(@logger)
  end
  
  # TODO: why does this one fail if its not first or in a describe block?
  it "should enqueue new job after create" do
    Delayed::Job.should_receive(:enqueue).with(an_instance_of(ImageJob))
    @image.save
  end
      
  it "should save file locally after create" do
    @image.save
    File.exist?(@image.tmp_path).should be_true
  end

  it "should stop paperclip from uploading files when saving" do
    @image.should_not_receive(:save_attached_files_without_interrupt)
    @image.save
  end
  
  it "should find attachment_name" do
    @image.attachment_name.should == :data
  end
  
  describe "validate options" do
    
    before(:all) do
      @bad_class_name = "Haha"
    end

    it "should raise exception for bad class name" do
      lambda do 
        Image.delay_paperclip(:tmp_dir => @good_dir, :job_class => @bad_class_name) 
      end \
        .should raise_error(DelayedPaperclip::InvalidOptionError, "invalid class name: #{@bad_class_name}")
    end
    
  end
  
  after(:all) do
   Dir.new("#{@good_dir}").each do |file|
     FileUtils.rm("#{@good_dir}/#{file}") unless file =~ /\A\./
   end
  end
  
end
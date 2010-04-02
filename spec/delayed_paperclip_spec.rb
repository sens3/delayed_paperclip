require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '../lib/delayed_paperclip'))

class PostImageJob < Struct.new(:image_id)
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
    
    def self.define_callbacks(*args)
    end
    
    attr_accessor :pending
    
    def pending?
      true
    end
    
    def callback(arg)
    end
    
    def self.alias_method_chain(original, topping)
    end
    
  end
end

class Post < ActiveRecord::Base
end

describe "DelayedPaperclip" do
  
  before(:each) do
    @good_dir = File.expand_path(File.join(File.dirname(__FILE__), "tmp/images")) 
    @good_class_name = "PostImageJob"
    @logger = mock('logger')
    @logger.stub!(:info)
    @logger.stub!(:error)
    
    Post.has_attached_file :image
    Post.delay_paperclip :tmp_dir => @good_dir, :job_class => @good_class_name
    
    @post = Post.new
    @post.stub!(:pending=)
    @post.stub!(:id).and_return(1)
    @post.stub!(:new_record?).and_return(false)
    
    # the file that was uploaded by the user
    @uploaded_file_path = File.expand_path(File.join(File.dirname(__FILE__), "files/wurst.jpg"))
    uploaded_file = File.new(@uploaded_file_path)
    
    @queued = {:original => uploaded_file }
    @queued.stub!(:[]=)
    
    @attachment = mock(Object)
    @attachment.stub!(:reprocess!).and_return(true)
    @attachment.stub!(:queued_for_write).and_return(@queued)

    @post.stub!(:image).and_return(@attachment)
    @post.stub!(:image_file_name).and_return("wurst.jpg")
    @post.stub(:logger).and_return(@logger)
  end
  
  # TODO: why does this one fail if its not first or in a describe block?

  it "should enqueue new job after create" do
    Delayed::Job.should_receive(:enqueue).with(an_instance_of(PostImageJob))
    @post.save
  end
    
  it "should save file locally after create" do
    @post.save
    File.exist?(@post.tmp_path).should be_true
  end

  it "should stop paperclip from uploading files when saving" do
    @post.should_not_receive(:save_attached_files_without_interrupt)
    @post.save
  end
  
  it "should find attachment_name" do
    @post.attachment_name.should == :image
  end
  
  describe "looking up tmp path" do
    
    it "should raise error if object is not saved yet" do
      @post.stub!(:new_record?).and_return(true)
      lambda { @post.tmp_path }.should raise_error("Cant use tmp_path for unsaved object")
    end
    
    it "should construct tmp path" do
      @post.tmp_path.should == "#{@good_dir}/Post-1-image-wurst.jpg"
    end
    
  end
  
  describe "performing job" do
    
    before do
      @tmp_path = '/the-file'
      @post.stub!(:tmp_path).and_return(@tmp_path)
      @file = mock('file')
      @file.stub!(:close)
      @file.stub!(:read)
      @file.stub!(:write)
      File.stub!(:open).and_yield(@file)
      File.stub!(:delete)
    end
    
    it "should open the tmp file" do
      File.should_receive(:open).with(@tmp_path)
      @post.perform
    end
  
    it "should mark object as not pending" do
      @post.should_receive(:pending=).with(false)
      @post.perform
    end
    
    it "should assign the tmp file to the paperclip variable" do
      @queued.should_receive(:[]=).with(:original, @file)
      @post.perform
    end
    
    it "should trigger paperclips re-processing" do
      @attachment.should_receive(:reprocess!)
      @post.perform
    end
    
    it "should save the object" do
      @post.should_receive(:save)
      @post.perform
    end
    
    describe "when successful" do
      
      before do
        @attachment.stub!(:reprocess!).and_return(true)
        @post.stub!(:save).and_return(true)
      end
      
      it "should delete tmp file" do
        File.should_receive(:delete).with(@tmp_path)
        @post.perform
      end
    end
  end
  
  describe "validate options" do
    
    before(:all) do
      @bad_class_name = "Haha"
    end

    it "should raise exception for bad class name" do
      lambda do 
        Post.delay_paperclip(:tmp_dir => @good_dir, :job_class => @bad_class_name) 
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